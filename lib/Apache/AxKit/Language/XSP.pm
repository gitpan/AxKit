# $Id: XSP.pm,v 1.7 2000/06/10 14:29:21 matt Exp $

package Apache::AxKit::Language::XSP;

use strict;
use Apache::AxKit::Language;
use Apache::AxKit::Language::XSP::SQL;
use Apache::Request;
use XML::Parser;

use vars qw/@ISA/;

@ISA = ('Apache::AxKit::Language');

sub stylesheet_exists { 0; }

sub get_mtime {
	return 30; # 30 days in the cache?
}

sub register {
    my $class = shift;
    $class->register_taglib('http://www.apache.org/1999/XSP/Core');
}

my $cache;

sub handler {
	my $class = shift;
	my ($r, $xml) = @_;
	
	$class->register();
    Apache::AxKit::Language::XSP::SQL->register();
	
#	warn "XSP Parse: $xmlfile\n";
	
	my $key = $xml->key();
	
	my $package = get_package_name($key);
	my $parser = XML::Parser->new(
			ErrorContext => 2,
			Namespaces => 1,
			XSP_Package => $package,
			);
	
	$parser->setHandlers(
			Init => \&parse_init,
			Char => \&_parse_char,
			Start => \&_parse_start,
			End => \&_parse_end,
			Final => \&parse_final,
			Proc => \&_parse_pi,
			Comment => \&_parse_comment,
			);
	
	my $to_eval;
	
	eval {
		if (my $dom_tree = $r->pnotes('dom_tree')) {
			$to_eval = $parser->parse($dom_tree->toString);
			$dom_tree->dispose;
			delete $r->pnotes()->{'dom_tree'};
		}
		elsif (my $xmlstr = $r->notes('xml_string')) {
			$to_eval = $parser->parse($xmlstr);
		}
		else {
			# check mtime.
			my $mtime = $xml->mtime();
            no strict 'refs';
			if (exists($cache->{$key})
					&& ($cache->{$key}{mtime} <= $mtime)
                    && defined &{"${package}::handler"}
					)
			{
				# cached
			}
			else {
				my $fh = eval { $xml->get_fh() };
				if ($@) {
					$to_eval = $parser->parse(${$xml->get_strref()});
				}
				else {
					$to_eval = $parser->parse($fh);
				}
				$cache->{$key}{mtime} = $mtime;
			}
		}
	};
	if ($@) {
		die "Parse of '$key' failed: $@";
	}
	
	if ($to_eval) {
		undef &{"${package}::handler"};
#		warn "Got script: $to_eval\n";
		eval $to_eval;
		if ($@) {
			warn "Script:\n$to_eval\n";
			die "Failed to parse: $@";
		}
	}
	
	no strict 'refs';
	my $cv = \&{"$package\::handler"};
	
	if (my $dom = $r->pnotes('dom_tree')) {
		$dom->dispose;
		delete $r->pnotes()->{'dom_tree'};
	}
	
	my $cgi = Apache::Request->new($r);
	
	$r->no_cache(1);

	$r->pnotes('dom_tree', 
				eval {
					local $^W;
					$cv->($r, $cgi);
				}
		);
	if ($@) {
		die "XSP Script failed: $@";
	}
	
}

sub parse_init {
	my $e = shift;

	$e->{XSP_Script} = join("\n", 
				"package $e->{XSP_Package};",
				"use Apache;",
				"use XML::DOM;",
			# need #line here...
				);
}

sub parse_final {
	my $e = shift;
	
	return $e->{XSP_Script};
}

sub _parse_char {
	my $e = shift;
	
	my $ns = $e->namespace($e->current_element) || '#default';
	
#	warn "CHAR-NS: $ns\n";
	
	if ($ns eq '#default'
			|| 
		!exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
	{
		$e->{XSP_Script} .= default_parse_char($e, @_);
	}
	else {
		no strict 'refs';
		my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
		$e->{XSP_Script} .= "${pkg}::parse_char"->($e, @_);
	}
}

sub default_parse_char {
	my ($e, $text) = @_;
	
	return '' unless $e->{XSP_User_Root};
	
	$text =~ s/\)/\\\)/g;
	
	return '{ my $text = $document->createTextNode(q(' . $text . '));' .
			'$parent->appendChild($text); }' . "\n";
}

sub _parse_start {
	my $e = shift;

	my $ns = $e->namespace($_[0]) || '#default';
	
#	warn "START-NS: $ns : $_[0]\n";
	
	if ($ns eq '#default'
			|| 
		!exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
	{
		$e->{XSP_Script} .= default_parse_start($e, @_);
	}
	else {
		no strict 'refs';
		my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
		$e->{XSP_Script} .= "${pkg}::parse_start"->($e, @_);
	}
}

my %enc_attr = ( '"' => '&quot;', '<' => '&lt;', '&' => '&amp;' );
sub default_parse_start {
	my ($e, $tag, %attribs) = @_;
	
	my $code = '';
	if (!$e->{XSP_User_Root}) {
		$code .= join("\n",
				'sub handler {',
				'my ($r, $cgi) = @_;',
				'my $document = XML::DOM::Document->new();',
				'my ($parent);',
				'$parent = $document;',
				"\n",
				);
		$e->{XSP_User_Root} = $e->depth . ":$tag";
	}
	
	$code .= '{ my $elem = $document->createElement(q(' . $tag . '));' .
				'$parent->appendChild($elem); $parent = $elem; }' . "\n";
	
	for my $attr (keys %attribs) {
		$code .= '{ my $attr = $document->createAttribute(q(' . $attr . '), q(' . $attribs{$attr} . '));';
		$code .= '$parent->setAttributeNode($attr); }' . "\n";
	}
	
	return $code;
}

sub _parse_end {
	my $e = shift;

	my $ns = $e->namespace($_[0]) || '#default';
	
#	warn "END-NS: $ns\n";
	
	if ($ns eq '#default'
			|| 
		!exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
	{
		$e->{XSP_Script} .= default_parse_end($e, @_);
	}
	else {
		no strict 'refs';
		my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
		$e->{XSP_Script} .= "${pkg}::parse_end"->($e, @_);
	}
}

sub default_parse_end {
	my ($e, $tag) = @_;
	
	if ($e->{XSP_User_Root} eq $e->depth . ":$tag") {
		undef $e->{XSP_User_Root};
		return "return \$document\n}\nreturn 1;\n";
	}
	
	return '$parent = $parent->getParentNode;' . "\n";
}

sub _parse_comment {
	my $e = shift;

	my $ns = $e->namespace($e->current_element) || '#default';
			
	if ($ns eq '#default'
			|| 
		!exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
	{
		$e->{XSP_Script} .= default_parse_comment($e, @_);
	}
	else {
		no strict 'refs';
		my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
		$e->{XSP_Script} .= "${pkg}::parse_comment"->($e, @_);
	}
}

sub default_parse_comment {
	return '';
}

sub _parse_pi {
	my $e = shift;

	$e->{XSP_Script} .= '';
}

sub register_taglib {
	my $class = shift;
	my $namespace = shift;
	
#	warn "Register taglib: $namespace => $class\n";
	
	$Apache::AxKit::Language::XSP::tag_lib{$namespace} = $class;
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

	return "Apache::AxKit::Language::XSP::ROOT$filename";
}

############################################################
# Functions implementing xsp:* processing
############################################################

sub parse_char {
	my ($e, $text) = @_;

	if ($e->current_element eq 'content') {
		return '' unless $e->{XSP_User_Root};
	
		$text =~ s/\)/\\\)/g;

		return '{ my $text = $document->createTextNode(q(' . $text . '));' .
				'$parent->appendChild($text); }' . "\n";
	}
    elsif ($e->current_element() =~ /^(expr|include|structure|dtd|logic)$/) {
        return $text;
    }
    
    return '' unless $e->{XSP_User_Root};

    $text =~ s/\|/\\\|/g;	
	return ". q|$text|";
}

sub parse_start {
	my ($e, $tag, %attribs) = @_;
	
	if ($tag eq 'page') {
		if ($attribs{language} ne 'Perl') {
			die "Only Perl XSP pages supported at this time!";
		}
		local $^W;
		if ($attribs{'indent-result'} eq 'yes') {
			$e->{XSP_Indent} = 1;
		}
	}
	elsif ($tag eq 'structure') {
	}
	elsif ($tag eq 'dtd') {
	}
	elsif ($tag eq 'include') {
		return "use ";
	}
	elsif ($tag eq 'content') {
	}
	elsif ($tag eq 'logic') {
	}
	elsif ($tag eq 'element') {
		return '{ my $elem = $document->createElement(q(' . $attribs{'name'} . '));' .
				'$parent->appendChild($elem); $parent = $elem; }' . "\n";
	}
	elsif ($tag eq 'attribute') {
		return '{ my $attr = $document->createAttribute(q(' . $attribs{'name'} . '), ""';
	}
	elsif ($tag eq 'pi') {
	}
	elsif ($tag eq 'comment') {
		return '{ my $comment = $document->createComment(""';
	}
	elsif ($tag eq 'text') {
		return '{ my $text = $document->createTextNode(""';
	}
	elsif ($tag eq 'expr') {
#		warn "start Expr: CurrentEl: ", $e->current_element, "\n";
		my $ns = $e->namespace($e->current_element);
		if ($ns
				&& ($ns eq 'http://www.apache.org/1999/XSP/Core')
				&& ($e->current_element ne 'content')) {
			return '';
		}
		else {
			return '{ my $text = $document->createTextNode(do {';
		}
	}
	
	return '';
}

sub parse_end {
	my ($e, $tag) = @_;
	
	if ($tag eq 'page') {
	}
	elsif ($tag eq 'structure') {
	}
	elsif ($tag eq 'dtd') {
	}
	elsif ($tag eq 'include') {
		return ";\n";
	}
	elsif ($tag eq 'content') {
	}
	elsif ($tag eq 'logic') {
	}
	elsif ($tag eq 'element') {
		return '$parent = $parent->getParentNode;' . "\n";
	}
	elsif ($tag eq 'attribute') {
		return '); $parent->setAttributeNode($attr); }' . "\n";
	}
	elsif ($tag eq 'pi') {
	}
	elsif ($tag eq 'comment') {
		return '); $parent->appendChild($comment); }' . "\n";
	}
	elsif ($tag eq 'text') {
		return '); $parent->appendChild($text); }' . "\n";
	}
	elsif ($tag eq 'expr') {
#		warn "end Expr: CurrentEl: ", $e->current_element, "\n";
		my $ns = $e->namespace($e->current_element);
		if ($ns
				&& ($ns eq 'http://www.apache.org/1999/XSP/Core')
				&& ($e->current_element ne 'content')) {
			return '';
		}
		else {
			return '}); $parent->appendChild($text); }' . "\n";
		}
	}
	
	return '';
}

##############################################################
# XSP Utils Library - is this needed???
##############################################################

package Apache::AxKit::Language::XSP::Utils;

use vars qw/@ISA/;
use strict;
use Exporter;
@ISA = ('Exporter');

sub xspExpr {
	
}

1;
