# $Id: XSP.pm,v 1.23 2001/01/14 15:48:51 matt Exp $

package Apache::AxKit::Language::XSP;

use strict;
use Apache::AxKit::Language;
use Apache::Request;
use Apache::AxKit::Exception ':try';
use XML::Parser;

use vars qw/@ISA $NS/;

@ISA = ('Apache::AxKit::Language');
$NS = 'http://www.apache.org/1999/XSP/Core';

sub stylesheet_exists { 0; }

sub get_mtime {
    return 30; # 30 days in the cache?
}

sub register {
    my $class = shift;
    no strict 'refs';
    $class->register_taglib(${"${class}::NS"});
}

sub _register_me_and_others {
    warn "Loading taglibs\n";
    __PACKAGE__->register();
    
    foreach my $package ($AxKit::Cfg->XSPTaglibs()) {
        warn "Registering taglib: $package\n";
        AxKit::load_module($package);
        $package->register();
    }
}

my $cache;

# useful for debugging - not actually used by AxKit:
sub get_code {
    my $filename = shift;
 
# cannot register - no $AxKit::Cfg...
#    _register_me_and_others();
    __PACKAGE__->register();
    
    my $package = get_package_name($filename);
    my $parser = get_parser($package, $filename);
    return $parser->parsefile($filename);
}

sub handler {
    my $class = shift;
    my ($r, $xml, undef, $reparse) = @_;
    
    _register_me_and_others();
    
#    warn "XSP Parse: $xmlfile\n";
    
    my $key = $xml->key();
    
    my $package = get_package_name($key);
    my $parser = get_parser($package, $key, $xml);
    
    my $to_eval;
    
    try {
        if (my $dom_tree = $r->pnotes('dom_tree')) {
            AxKit::Debug(5, 'XSP: parsing dom_tree');
            $to_eval = $parser->parse($dom_tree->toString);
            delete $r->pnotes()->{'dom_tree'};
        }
        elsif (my $xmlstr = $r->notes('xml_string')) {
            if ($reparse || $r->no_cache()
                    || !defined &{"${package}::handler"}) {
                AxKit::Debug(5, 'XSP: parsing xml_string');
                $to_eval = $parser->parse($xmlstr);
            }
            else {
                AxKit::Debug(5, 'XSP: not reparsing xml_string (cached)');
            }
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
                AxKit::Debug(5, 'XSP: xsp script cached');
            }
            else {
                AxKit::Debug(5, 'XSP: parsing fh');
                $to_eval = try {
                    $parser->parse($xml->get_fh());
                }
                catch Error with {
                    $parser->parse(${ $xml->get_strref() });
                };
                
                $cache->{$key}{mtime} = $mtime;
            }
        }
    }
    catch Error with {
        my $err = shift;
        die "Parse of '$key' failed: $err";
    };
    
    if ($to_eval) {
        undef &{"${package}::handler"};
#        warn "Got script: $to_eval\n";
        AxKit::Debug(5, 'Recompiling XSP script');
        AxKit::Debug(10, $to_eval);
        eval $to_eval;
        if ($@) {
            my $line = 1;
            $to_eval =~ s/\n/"\n".++$line." "/eg;
            warn "Script:\n1 $to_eval\n";
            die "Failed to parse: $@";
        }
    }
    
    no strict 'refs';
    my $cv = \&{"$package\::handler"};
    
    my $cgi = Apache::Request->instance($r);
    
    $r->no_cache(1);

    try {
        local $^W;
        $r->pnotes('dom_tree', $cv->($r, $cgi));
    }
    catch Error with {
        my $err = shift;
        die "XSP Script failed: $err";
    }
    
}

sub _parse_init {
    my $e = shift;
    
    $e->{Text_Type} = '';

    $e->{XSP_Script} = join("\n", 
                "package $e->{XSP_Package};",
                "use Apache;",
                "use XML::XPath;",
                "#line 1 ".$e->{XSP_Line}."\n",
                );
}

sub _parse_final {
    my $e = shift;
    
    return $e->{XSP_Script};
}

sub _parse_char {
    my $e = shift;
    my $ns = $e->namespace($e->current_element) || '#default';
    
#    warn "CHAR-NS: $ns\n";
    
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
    
    $text =~ s/\|/\\\|/g;
    
    return '{ my $text = XML::XPath::Node::Text->new(q|' . $text . '|);' .
            '$parent->appendChild($text, 1); }' . "\n";
}

sub _parse_start {
    my $e = shift;

    my $ns = $e->namespace($_[0]) || '#default';
            
#    warn "START-NS: $ns : $_[0]\n";
    
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
                'my $document = XML::XPath::Node::Element->new();',
                'my ($parent);',
                '$parent = $document;',
                "\n",
                );
        $e->{XSP_User_Root} = $e->depth . ":$tag";
    }
    
    $code .= '{ my $elem = XML::XPath::Node::Element->new(q(' . $tag . '));' .
                '$parent->appendChild($elem, 1); $parent = $elem; }' . "\n";
    
    for my $attr (keys %attribs) {
        $code .= '{ my $attr = XML::XPath::Node::Attribute->new(q(' . $attr . '), q(' . $attribs{$attr} . '));';
        $code .= '$parent->appendAttribute($attr, 1); }' . "\n";
    }
    
    return $code;
}

sub _parse_end {
    my $e = shift;

    my $ns = $e->namespace($_[0]) || '#default';
    
#    warn "END-NS: $ns\n";
    
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
            
    if (defined $e->{XSP_Text}) {
        if ($ns eq '#default'
                || 
            !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
        {
            $e->{XSP_Script} .= default_parse_char($e, $e->{XSP_Text});
        }
        else {
            no strict 'refs';
            my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
            $e->{XSP_Script} .= "${pkg}::parse_char"->($e, $e->{XSP_Text});
        }
        undef $e->{XSP_Text};
    }
        
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

    my $ns = $e->namespace($e->current_element) || '#default';
            
    if (defined $e->{XSP_Text}) {
        if ($ns eq '#default'
                || 
            !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
        {
            $e->{XSP_Script} .= default_parse_char($e, $e->{XSP_Text});
        }
        else {
            no strict 'refs';
            my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
            $e->{XSP_Script} .= "${pkg}::parse_char"->($e, $e->{XSP_Text});
        }
        undef $e->{XSP_Text};
    }
        
    $e->{XSP_Script} .= '';
}

sub register_taglib {
    my $class = shift;
    my $namespace = shift;
    
#    warn "Register taglib: $namespace => $class\n";
    
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

sub get_parser {
    my ($package, $key, $provider) = @_;
    
    my $parser = XML::Parser->new(
            ErrorContext => 2,
            Namespaces => 1,
            ParseParamEnt => 1,
            XSP_Package => $package,
            XSP_Line => $key,
            );
    
    if ($provider) {
        if (my $ext_ent_handler = $provider->get_ext_ent_handler()) {
            $parser->setHandlers(ExternEnt => $ext_ent_handler);
        }
    }
    
    $parser->setHandlers(
            Init => \&_parse_init,
            Char => \&_parse_char,
            Start => \&_parse_start,
            End => \&_parse_end,
            Final => \&_parse_final,
            Proc => \&_parse_pi,
            Comment => \&_parse_comment,
            );
    
    return $parser;
}

############################################################
# Functions implementing xsp:* processing
############################################################

sub parse_char {
    my ($e, $text) = @_;

    local $^W;
    
#     Ricardo writes: "<xsp:expr> produces either an [object]
# _expression_ (not necessarily a String) or a character event depending
# on context. When  <xsp:expr> is enclosed in another XSP tag (except
# <xsp:content>), it's replaced by the code it contains. Otherwise it
# should be treated as a text node and, therefore, coerced to String to be
# output through a characters SAX event."

    if ($e->{Text_Type} eq 'node') {
        $text =~ s/\|/\\\|/g;

        return '{ my $last = $parent->getLastChild;
                 if ($last && $last->isTextNode) {
                     $last->appendText(q|' . $text . '|);
                 }
                 else {
                     my $text = XML::XPath::Node::Text->new(q|' . $text . '|);
                     $parent->appendChild($text, 1); 
                 }
                }' . "\n";
    }
    elsif ($e->{Text_Type} eq 'expr') {
        return ". do { $text }";
    }
    elsif ($e->{Text_Type} eq 'quote') {
        $text =~ s/\|/\\\|/g;    
        return ". q|$text|";
    }
    
    return '' unless $e->{XSP_User_Root};
    
    return $text;
}

sub parse_start {
    my ($e, $tag, %attribs) = @_;
    
    if ($tag eq 'page') {
        if (lc($attribs{language}) ne 'perl') {
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
        return "warn \"xsp:include is deprecated\"; use ";
    }
    elsif ($tag eq 'content') {
    }
    elsif ($tag eq 'logic') {
    }
    elsif ($tag eq 'import') {
        return "use ";
    }
    elsif ($tag eq 'element') {
        return '{ my $elem = XML::XPath::Node::Element->new(q(' . $attribs{'name'} . '));' .
                '$parent->appendChild($elem, 1); $parent = $elem; }' . "\n";
    }
    elsif ($tag eq 'attribute') {
        $e->{Text_Type} = 'quote';
        return '{ my $attr = XML::XPath::Node::Attribute->new(q(' . $attribs{'name'} . '), ""';
    }
    elsif ($tag eq 'pi') {
    }
    elsif ($tag eq 'comment') {
        $e->{Text_Type} = 'quote';
        return '{ my $comment = XML::XPath::Node::Comment->new(""';
    }
    elsif ($tag eq 'text') {
        $e->{Text_Type} = 'quote';
        return '{ my $text = XML::XPath::Node::Text->new(""';
    }
    elsif ($tag eq 'expr') {
        $e->{Text_Type} = 'expr';
        if ($e->namespace(($e->context())[-2]) eq $NS) {
            if (($e->context())[-2] eq 'content') {
                $e->{Text_Type} = 'node';
            }
        }
        else {
            return '{ my $text = XML::XPath::Node::Text->new(""';
        }
#        warn "start Expr: CurrentEl: ", $e->current_element, "\n";
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
        $e->{Text_Type} = '';
    }
    elsif ($tag eq 'include') {
        $e->{Text_Type} = '';
        return ";\n";
    }
    elsif ($tag eq 'import') {
        $e->{Text_Type} = '';
        return ";\n";
    }
    elsif ($tag eq 'content') {
        $e->{Text_Type} = '';
    }
    elsif ($tag eq 'logic') {
        $e->{Text_Type} = '';
    }
    elsif ($tag eq 'element') {
        return '$parent = $parent->getParentNode;' . "\n";
    }
    elsif ($tag eq 'attribute') {
        $e->{Text_Type} = '';
        return '); $parent->appendAttribute($attr, 1); }' . "\n";
    }
    elsif ($tag eq 'pi') {
    }
    elsif ($tag eq 'comment') {
        $e->{Text_Type} = '';
        return '); $parent->appendChild($comment, 1); }' . "\n";
    }
    elsif ($tag eq 'text') {
        $e->{Text_Type} = '';
        return '); $parent->appendChild($text, 1); }' . "\n";
    }
    elsif ($tag eq 'expr') {
        $e->{Text_Type} = '';
        if ($e->namespace(($e->context())[-2]) ne $NS) {
            return '); $parent->appendChild($text, 1); }' . "\n";
        }
#        warn "end Expr: CurrentEl: ", $e->current_element, "\n";
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
