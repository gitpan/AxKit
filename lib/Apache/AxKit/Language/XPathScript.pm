# $Id: XPathScript.pm,v 1.20 2000/06/15 10:30:56 matt Exp $

package Apache::AxKit::Language::XPathScript;

use strict;
use vars qw(@ISA $VERSION $stash);

use Apache;
use Apache::File;
use XML::XPath 0.50;
use XML::XPath::XMLParser;
use XML::XPath::Node;
use Apache::AxKit::Provider;
use Apache::AxKit::StyleProvider;
use Apache::AxKit::Language;
use Apache::AxKit::Cache;
use File::Basename;
use Cwd;
use Storable;

@ISA = 'Apache::AxKit::Language';

$VERSION = '0.05';

sub handler {
	my $class = shift;
	my ($r, $xml_provider, $style_provider) = @_;
	
	my $xp = XML::XPath->new();
	
	my $source_tree;
	
	my $parser = XML::XPath::XMLParser->new();
	
	if (my $dom = $r->pnotes('dom_tree')) {
		use XML::XPath::Builder;
		my $builder = XML::XPath::Builder->new();
		$source_tree = $dom->to_sax( Handler => $builder );
		$dom->dispose;
		delete $r->pnotes()->{'dom_tree'};
	}
	elsif (my $xml = $r->notes('xml_string')) {
#		warn "Parsing from string : $xml\n";
		$source_tree = $parser->parse($xml);
	}
	else {
		my $mtime = $xml_provider->mtime();
	
#		warn "Creating xpathstor cache\n";
		my $cache = Apache::AxKit::Cache->new($r, $r->filename(), 'xpathstor');
		my $key = $xml_provider->key();
		if (exists($stash->{$key})
				&& ($stash->{$key}{mtime} <= $mtime)) {
#			warn "Getting thawed tree\n";
			eval {
				$source_tree = Storable::thaw($cache->read());
			};
		}
		
		if (!$source_tree) {
#			warn "reparsing\n";
			my $fh = eval { $xml_provider->get_fh() };
			if ($@) {
				$source_tree = $parser->parse(${$xml_provider->get_strref()});
			}
			else {
				$source_tree = $parser->parse($fh);
			}

			$cache->write(Storable::freeze($source_tree));
			$stash->{$key}{mtime} = $mtime;
		}
	}

	$xp->set_context($source_tree);
	
	my $mtime = $style_provider->mtime();

	my $style_key = $style_provider->key();
	my $package = get_package_name($style_key);
	
#	warn "Checking stylesheet mtime: $mtime\n";
	if ($stash->{$style_key}
			&& exists($stash->{$style_key}{mtime})
			&& ($stash->{$style_key}{mtime} <= $mtime)
			&& check_inc_mtime($stash->{$style_key}{mtime}, $style_provider, $stash->{$style_key}{includes})) {
		# cached... just exec.
#		warn "Using stylesheet cache\n";
	}
	else {
		# recompile stylesheet.
#		warn "Recompiling stylesheet $style_key\n";
		compile($package, $style_provider);
		$stash->{$style_key}{mtime} = get_mtime($class, $style_provider->apache_request(), $r);
	}
	
	my $old_status = $r->status;
	
	no strict 'refs';
	my $cv = \&{"$package\::handler"};

	$Apache::AxKit::Language::XPathScript::xp = $xp;
	my $t = {};
	$Apache::AxKit::Language::XPathScript::trans = $t;
	
#	warn "Running script\n";
	local $^W;
	$cv->($r, $xp, $t);
	
#	warn "Run\n";

	$Apache::AxKit::Language::XPathScript::xp = undef;
	$Apache::AxKit::Language::XPathScript::trans = undef;
	
#	warn "Returning $old_status\n";
	return $r->status($old_status);
}

sub check_inc_mtime {
	my ($mtime, $provider, $includes) = @_;
	
	for my $inc (@$includes) {
#		warn "Checking mtime for $inc\n";
		my $old_r = $provider->apache_request();
		my $r = $old_r->lookup_file($inc);
		my $inc_provider = Apache::AxKit::StyleProvider->new($r);
		if ($inc_provider->mtime() < $mtime) {
#			warn "$inc newer (" . $inc_provider->mtime() . ") than last compile ($mtime) causing recompile\n";
			return;
		}
	}
	return 1;
}

sub extract {
	my ($provider) = @_;
	
	my $contents;
	
#	warn "Extracting\n";
	my $fh = eval { $provider->get_fh() };
	if ($@) {
#		warn "Get from strref\n";
		$contents = ${$provider->get_strref()};
	}
	else {
#		warn "get from fh\n";
		local $/;
		$contents = <$fh>;
	}
	
#	warn "extracting $contents\n";
	
	my $key = $provider->key();
	$stash->{$key}{includes} = [];
	
	my $script;
	
	my $line = 1;
	
	while ($contents =~ /\G(.*?)(<!--\#include|<%=?)/gcs) {
		my ($text, $type) = ($1, $2);
		$line += $text =~ tr/\n//;
		$text =~ s/\|/\\\|/g;
		$script .= "print q|$text|;";
		$script .= "\n#line $line $key\n";
		if ($type eq '<%=') {
			$contents =~ /\G(.*?)%>/gcs || die "No terminating '%>' after line $line ($key)";
			my $perl = $1;
			$script .= "print( $perl );\n";
			$line += $perl =~ tr/\n//;
		}
		elsif ($type eq '<!--#include') {
			my %params;
			while ($contents =~ /\G(\s+(\w+)\s*=\s*(["'])([^\3]*?)\3|\s*-->)/gcs) {
				last if $1 eq '-->';
				$params{$2} = $4;
			}
			
			if (!$params{file}) {
				die "No matching file attribute in #include at line $line ($key)";
			}
			
			$script .= include_file($params{file}, $provider);
		}
		else {
			$contents =~ /\G(.*?)%>/gcs || die "No terminating '%>' after line $line ($key)";
			my $perl = $1;
			$script .= $perl;
			$line += $perl =~ tr/\n//;
		}
	}
	
	if ($contents =~ /\G(.*)/gcs) {
		my ($text) = ($1);
		$text =~ s/\|/\\\|/g;
		$script .= "print q|$text|;";
	}
	
	return $script;
}

sub compile {
	my ($package, $provider) = @_;
	
	my $script = extract($provider);
	
	my $eval = join('',
			'package ',
			$package,
			'; use Apache qw(exit);',
			'use XML::XPath::Node;',
			'Apache::AxKit::Language::XPathScript::Toys->import;',
			'sub handler {',
			'my ($r, $xp, $t) = @_;',
			"\n#line 1 " . $provider->key() . "\n",
			$script,
			"\n}",
			);
	
	local $^W;
	
#	warn "Recompiling $filename\n";
#	warn "Compiling script:\n$eval\n";
	eval $eval;
	if ($@) {
		die $@;
	}
}

sub include_file {
	my ($filename, $provider) = @_;

	# return if already included
	my $key = $provider->key();
	return '' if grep {$_ eq $filename} @{$stash->{$key}{includes}};
	
	push @{$stash->{$key}{includes}}, $filename;
	
	my $r = eval {$provider->apache_request()->lookup_file($filename);};
	my $inc_provider = Apache::AxKit::StyleProvider->new($r);
	return extract($inc_provider);
}

sub get_mtime {
	my $class = shift;
	my ($request, $r) = @_;
#	warn "get_mtime\n";
	my $provider = Apache::AxKit::StyleProvider->new($request);
	my $mtime = $provider->mtime();
	my $filename = $provider->key();
#	warn "mtime: $filename = $mtime\n";
	if (!$stash->{$filename}) {
		# compile stylesheet
		compile(get_package_name($filename), $provider);
	
		$stash->{$filename}{mtime} = $mtime;
		return 0;
	}

	for my $inc (@{$stash->{$filename}{includes}}) {
		my $r = $provider->apache_request()->lookup_file($inc);
		my $inc_provider = Apache::AxKit::StyleProvider->new($r);
#		warn "Checking mtime of $inc\n";
		if ($inc_provider->mtime() < $mtime) {
			$mtime = $inc_provider->mtime();
		}
	}
	
#	warn "returning $mtime\n";
	return $mtime;
}

sub get_package_name {
	my $filename = shift;
	# Escape everything into valid perl identifiers
	$filename =~ s/([^A-Za-z0-9_\/])/sprintf("_%2x",unpack("C",$1))/eg;

	# second pass cares for slashes and words starting with a digit
	$filename =~ s{
				  (/+)       # directory
				  (\d?)      # package's first character
				 }[
				   "::" . (length $2 ? sprintf("_%2x",unpack("C",$2)) : "")
				  ]egx;

	return "Apache::AxKit::Language::XPathScript::ROOT$filename";
}

{
	package Apache::AxKit::Language::XPathScript::Toys;
	
	use XML::XPath::Node;

	use vars '@ISA', '@EXPORT';
	use Exporter;
	@ISA = ('Exporter');
	@EXPORT = ('findnodes', 
				'findvalue',
				'findvalues',
				'findnodes_as_string',
				'apply_templates',
				'matches',
			);

	sub findnodes {
		$Apache::AxKit::Language::XPathScript::xp->findnodes(@_);
	}

	sub findvalue {
		$Apache::AxKit::Language::XPathScript::xp->findvalue(@_);
	}
	
	sub findvalues {
		my @nodes = findnodes(@_);
		map { findvalue('.', $_) } @nodes;
	}

	sub findnodes_as_string {
		$Apache::AxKit::Language::XPathScript::xp->findnodes_as_string(@_);
	}
	
	sub matches {
		$Apache::AxKit::Language::XPathScript::xp->matches(@_);
	}
	
	sub apply_templates (;$@) {
		unless (@_) {
			return apply_templates(findnodes('/'));
		}
		
		my ($arg1, @args) = @_;

		if (!ref($arg1)) {
			# called with a path to find
#			warn "apply_templates with path '$arg1'\n";
			return apply_templates(findnodes($arg1, @args));
		}
		
		my $retval = '';
		if ($arg1->isa('XML::XPath::NodeSet')) {
			foreach my $node ($arg1->get_nodelist) {
				$retval .= translate_node($node);
			}
		}
		else {
			$retval .= translate_node($arg1);
			foreach my $node (@args) {
				$retval .= translate_node($node);
			}
		}
		
		return $retval;
	}
	
	sub _apply_templates {
		my @nodes = @_;
		
		my $retval = '';
		foreach my $node (@nodes) {
			$retval .= translate_node($node);
		}
		
		return $retval;
	}
	
	sub translate_node {
		my $node = shift;
		
		local $^W;
				
		my $translations = $Apache::AxKit::Language::XPathScript::trans;
		
		if ($node->getNodeType != ELEMENT_NODE) {
			return $node->toString;
		}
		
#		warn "translate_node: ", $node->getName, "\n";
		
		my $node_name = $node->getName;
		my $trans = $translations->{$node_name};

		if (!$trans) {
			$node_name = '*';
			$trans = $translations->{$node_name};
		}
		
		if (!$trans) {
			return start_tag($node) . 
					_apply_templates(@{$node->getChildNodes}) .
					end_tag($node);
		}
		
		local $^W;
		
		my $dokids = 1;

		my $t = {};
		if ($trans->{testcode}) {
#			warn "Evalling testcode\n";
			my $result = $trans->{testcode}->($node, $t);
			if ($result == 0) {
				# don't process anything.
				return;
			}
			if ($result == -1) {
				# -1 means don't do children.
				$dokids = 0;
			}
		}
		
		local $translations->{$node_name};
		# copy old values in
		%{$translations->{$node_name}} = %$trans;
		
		if (%$t) {
			foreach my $key (keys %$t) {
				$translations->{$node_name}{$key} = $t->{$key};
			}
			$trans = $translations->{$node_name};
		}
		
		# default: process children too.
		my $pre = $trans->{pre} . 
				($trans->{showtag} ? start_tag($node) : '') .
				$trans->{prechildren};
		
		my $post = $trans->{postchildren} .
				($trans->{showtag} ? end_tag($node) : '') .
				$trans->{post};
		
		if ($dokids) {
			my $middle = '';
			for my $kid ($node->getChildNodes()) {
				if ($kid->isElementNode) {
					$middle .= $trans->{prechild} .
							_apply_templates($kid) .
							$trans->{postchild};
				}
				else {
					$middle .= _apply_templates($kid);
				}
			}
			return $pre . $middle . $post;
		}
		
		return $pre . $post;
	}
	
	sub start_tag {
		my ($node) = @_;
		
		return '' unless $node->getName;
		
		my $string = "<" . $node->getName;
		
		foreach my $ns ($node->getNamespaceNodes) {
			$string .= $ns->toString;
		}
		
		foreach my $attr (@{$node->getAttributeNodes}) {
			$string .= $attr->toString;
		}

		$string .= ">";
		
		return $string;
	}
	
	sub end_tag {
		my ($node) = @_;
		
		return '' unless $node->getName;
		
		return "</" . $node->getName . ">";
	}

	1;
}

1;
__END__

=head1 NAME

Apache::AxKit::Language::XPathScript - An XML Stylesheet Language

=head1 SYNOPSIS

  AxAddStyleMap "application/x-xpathscript => \
		Apache::AxKit::Language::XPathScript"

=head1 DESCRIPTION

This documentation has been removed. The definitive reference for 
XPathScript is now at http://xml.sergeant.org/axkit/xpathscript/guide.dkb
in DocBook format.

=cut
