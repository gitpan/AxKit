package Apache::AxKit::Language::NotXSLT;

# $Id: NotXSLT.pm,v 1.2 2000/05/02 10:32:05 matt Exp $

use strict;
use vars qw($VERSION $PREFIX $cache $parser);

$VERSION = '0.04';

use Apache;
use Apache::Constants;
use Apache::File;
use XML::XPath;
use XML::XPath::XMLParser;

sub handler {
	my $r = shift;
	
	my ($xmlfile, $stylesheet) = @_;
	

#	warn "In NotXSLT with $xmlfile and $stylesheet\n";

	$r->content_type("text/html");
	$r->content_encoding("utf-8");
	
	my $source_finder = XML::XPath->new;
	
	$parser ||= XML::XPath::XMLParser->new;
	
	my $source_tree;
	
	my $mtime = -M $r->finfo;
	
	if (exists $cache->{$xmlfile} && 
			$cache->{$xmlfile}{mtime} <= $mtime) {
		$source_tree = $cache->{$xmlfile}{tree};
	}
	else {
		eval {
			$source_tree = $parser->parsefile($xmlfile);
		};
		if ($@) {
			warn "Parse of '$xmlfile' failed with $@";
			return DECLINED; # ???
		}
		$cache->{$xmlfile}{mtime} = $mtime;
		$cache->{$xmlfile}{tree} = $source_tree;
	}
	
	my $template_tree;
	
	$mtime = -M $stylesheet;
	
	if (exists $cache->{$stylesheet} &&
			$cache->{$stylesheet}{mtime} <= $mtime) {
		$template_tree = $cache->{$stylesheet}{tree}
	}
	else {
		eval {
			$template_tree = $parser->parsefile($stylesheet);
		};
		if ($@) {
			warn "Parse of stylesheet '$stylesheet' failed with $@";
			return DECLINED; # ???
		}
		$cache->{$stylesheet}{mtime} = $mtime;
		$cache->{$stylesheet}{tree} = $template_tree;
	}
	
	my $root_node;
	
	# get namespace prefix for template
	# here we search through all children of the root node
	# because there could be comments or PI's here.
	# The root node MUST contain a xmlns:<prefix>="..."
	ROOT:
	foreach my $node (@{$template_tree->[node_children]}) {
		if (ref($node) eq 'element') {
			# root node!
			$root_node = $node;
			foreach my $ns (@{$node->[node_namespaces]}) {
				if ($ns->[node_expanded] eq 'http://sergeant.org/notxslt') {
					$PREFIX = $ns->[node_prefix];
					last ROOT;
				}
			}
			warn "Not a template file - no namespace declaration matching\nhttp://sergeant.org/notxslt in file '$stylesheet'\n";
			return DECLINED;
		}
	}
	
	$r->send_http_header;
	
	unless ($r->header_only) {
		my $string = parse($source_finder, $source_tree, $root_node);
		$r->print($string);
	}
	
	return OK;
	
}

sub parse_style {
	my $data = shift;
	my $style;
	while ($data =~ /\G\s*$XML::XPath::Parser::NCName\s*=\s*(["'])([^\2<]*?)\2/gco) {
		my ($attr, $val) = ($1, $3);
		$style->{$attr} = $val;
	}
	
	if (!exists($style->{href}) || !exists($style->{type})) {
		warn "Incorrect <?xml-stylesheet?> processing instruction\n";
		return;
	}
	
	return $style;
}

sub escape {
	my $text = shift;
	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&quot;/g;
	$text =~ s/'/&apos;/g;
	return $text;
}

sub parse {
	my ($xp, $context, $node) = @_;
	
	# examine node
	
	my $string;
	
#	print "Node type is ", ref($node), "\n";
	for (ref($node)) {
		if ($_ eq 'element') {
			local $^W;
			if ($node->[node_prefix] eq $PREFIX) {
				$string .= process_template_node($xp, $context, $node);
			}
			else {
				# gather attributes
				my @attribs;
				$string .= "<" . $node->[node_name];
				foreach my $attr (@{$node->[node_attribs]}) {
					$string .= " " . $attr->[node_key] . '="' . escape($attr->[node_value]) . '"';
				}
				
				if (@{$node->[node_children]}) {
					$string .= ">";
					# process children
					foreach my $n (@{$node->[node_children]}) {
						$string .= parse($xp, $context, $n);
					}
					$string .= "</" . $node->[node_name] . ">";
				}
				else {
					$string .= "/>";
				}
			}
		}
		elsif ($_ eq 'text') {
			$string .= $node->[node_text];
#			$string .= escape($node->[node_text]);
		}
		elsif ($_ eq 'comment') {
			# ignore comments for now.
			# print STDERR $node->[node_comment], "\n";
		}
	}
	
	return $string;
}

sub process_template_node {
	my ($xp, $context, $node) = @_;

	my $string;
	
	if ($node->[node_name] eq "$PREFIX:select") {
		# find match in $xp, and output.
		my $match;
		foreach my $attrib (@{$node->[node_attribs]}) {
			if ($attrib->[node_key] eq 'match') {
				$match = $attrib->[node_value];
			}
		}
		
		die "No 'match' attribute on $PREFIX:select element" unless $match;
		
		my $results = $xp->find($match, $context);
		
		die "Match '$match' failed!\n" unless defined $results;
		
		if ($results->isa('XML::XPath::NodeSet')) {
			foreach my $result ($results->get_nodelist) {
				$string .= XML::XPath::XMLParser::as_string($result);
#				$string .= escape(XML::XPath::XMLParser::as_string($result));
			}
		}
		else {
			$string .= $results->value;
#			$string .= escape($results->value);
		}
	}
	elsif ($node->[node_name] eq "$PREFIX:for-each") {
		# find match, get matching nodes, loop over matching nodes
		my $match;
		foreach my $attrib (@{$node->[node_attribs]}) {
			if ($attrib->[node_key] eq 'match') {
				$match = $attrib->[node_value];
			}
		}
		
		die "No 'match' attribute on $PREFIX:for-each element" unless $match;
		
		my $results = $xp->find($match, $context);
		
		if ($results->isa('XML::XPath::NodeSet')) {
			foreach my $result ($results->get_nodelist) {
				foreach my $kid (@{$node->[node_children]}) {
					$string .= parse($xp, $result, $kid);
				}
			}
		}
		else {
			die "$PREFIX:for-each match doesn't match a set of nodes";
		}
	}
	elsif ($node->[node_name] eq "$PREFIX:exec") {
		# find match and ignore results.
		my $match;
		foreach my $attrib (@{$node->[node_attribs]}) {
			if ($attrib->[node_key] eq 'match') {
				$match = $attrib->[node_value];
			}
		}
		
		die "No 'match' attribute on $PREFIX:exec element" unless $match;
		
		my $results = $xp->find($match, $context);
	}
	elsif ($node->[node_name] eq "$PREFIX:verbatim") {
		my $match;
		foreach my $attrib (@{$node->[node_attribs]}) {
			if ($attrib->[node_key] eq 'match') {
				$match = $attrib->[node_value];
			}
		}
		
		die "No 'match' attribute on $PREFIX:verbatim element" unless $match;
		
		my $results = $xp->find($match, $context);
		
		if ($results->isa('XML::XPath::NodeSet')) {
			foreach my $node ($results->get_nodelist) {
				if (ref($node) eq 'element') {
					$string .= "<" . $node->[node_name];
					foreach my $attr (@{$node->[node_attribs]}) {
						$string .= " " . $attr->[node_key] . '="' . escape($attr->[node_value]) . '"';
					}

					if (@{$node->[node_children]}) {
						$string .= ">";
						# process children
						foreach my $n (@{$node->[node_children]}) {
							$string .= parse($xp, $context, $n);
						}
						$string .= "</" . $node->[node_name] . ">";
					}
					else {
						$string .= "/>";
					}
				}
				elsif (ref($node) eq 'text') {
					$string .= $node->[node_text];
#					$string .= escape($node->[node_text]);
				}
			}
		}
		else {
			die "$PREFIX:verbatim match doesn't match a set of nodes";
		}
	}
	
	return $string;
}

{
	
	# here we add some functions to the XPath function library.

	package XML::XPath::Function;
	
	use XML::XPath::Literal;

	# why oh why wasn't set_var implemented in the first place???
	sub set_var {
		my $self = shift;
		my ($node, @params) = @_;
		if (@params != 2) {
			die "Usage: set_var('name', value)\n";
		}
		$self->{pp}->set_var($params[0], $params[1]);
	}
	
	# and the same goes for sprintf!
	# (I think the excuse there is "Java doesn't have sprintf". Bah!)
	sub sprintf {
		my $self = shift;
		my ($node, @params) = @_;
		if (!@params) {
			die "Usage: sprintf(Literal [, args]*)\n";
		}
		
		my @vals = map("$_", @params);
		my $format = shift @vals;
		my $val = CORE::sprintf($format, @vals);
		return XML::XPath::Literal->new($val);
	}
	
}


1;
__END__

=head1 NAME

Apache::AxKit::Language::NotXSLT - Matt's non-xslt template processor

=head1 SYNOPSIS

  PerlTypeHandler Apache::AxKit::XMLFinder
  PerlHandler Apache::AxKit::StyleFinder
  PerlSetVar StylesheetMap "application/x-notxslt => \
		Apache::AxKit::Language::NotXSLT"

=head1 DESCRIPTION

This module implements an XML template system that looks a bit like
XSLT, but isn't. Hence the name. It uses XML::XPath, and should be
fast enough to use on small web sites dynamically, rather than using
static transformation.

=head1 AUTHOR

Matt Sergeant, matt@sergeant.org

=head1 SEE ALSO

XML::XPath(1).

=cut

# $Log: NotXSLT.pm,v $
# Revision 1.2  2000/05/02 10:32:05  matt
# Rename to AxKit
#
