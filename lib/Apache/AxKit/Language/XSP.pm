# $Id: XSP.pm,v 1.50 2001/06/04 13:27:31 matt Exp $

package Apache::AxKit::Language::XSP;

use strict;
use Apache::AxKit::Language;
use Apache::Request;
use Apache::AxKit::Exception;
use Apache::AxKit::Cache;
use XML::Parser;

use vars qw/@ISA/;

@ISA = ('Apache::AxKit::Language');

sub stylesheet_exists () { 0; }

sub get_mtime {
    return 30; # 30 days in the cache?
}

my $cache;

# useful for debugging - not actually used by AxKit:
# sub get_code {
#     my $filename = shift;
#  
# # cannot register - no $AxKit::Cfg...
# #    _register_me_and_others();
#     __PACKAGE__->register();
#     
#     my $package = get_package_name($filename);
#     my $parser = get_parser($package, $filename);
#     return $parser->parsefile($filename);
# }

sub handler {
    my $class = shift;
    my ($r, $xml, undef) = @_;
    
    _register_me_and_others();
    
#    warn "XSP Parse: $xmlfile\n";
    
    my $key = $xml->key();
    
    my $package = get_package_name($key);
    
    my $handler = AxKit::XSP::SAXHandler->new_handler(
            XSP_Package => $package,
            XSP_Line => $key,
            );
    my $parser = AxKit::XSP::SAXParser->new(
            provider => $xml,
            Handler => $handler,
            );
    
    local $Apache::AxKit::Language::XSP::ResNamespaces = $r->dir_config('XSPResNamespaces');
    
    my $to_eval;
    
    eval {
        if (my $dom_tree = $r->pnotes('dom_tree')) {
            AxKit::Debug(5, 'XSP: parsing dom_tree');
            $to_eval = $parser->parse($dom_tree->toString);
            delete $r->pnotes()->{'dom_tree'};
        }
        elsif (my $xmlstr = $r->pnotes('xml_string')) {
            if ($r->no_cache()
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
                    && !$xml->has_changed($cache->{$key}{mtime})
                    && defined &{"${package}::handler"}
                    )
            {
                # cached
                AxKit::Debug(5, 'XSP: xsp script cached');
            }
            else {
                AxKit::Debug(5, 'XSP: parsing fh');
                $to_eval = eval {
                    $parser->parse($xml->get_fh());
                } || $parser->parse(${ $xml->get_strref() });
                
                $cache->{$key}{mtime} = $mtime;
            }
        }
    };
    if ($@) {
        throw Apache::AxKit::Exception::Error(
                -text => "Parse of '$key' failed: $@"
                );
    }
    
    if ($to_eval) {
        undef &{"${package}::handler"};
        AxKit::Debug(5, 'Recompiling XSP script');
        AxKit::Debug(10, $to_eval);
        eval $to_eval;
        AxKit::Debug(5, 'XSP Compilation finished');
        if ($@) {
            my $line = 1;
            $to_eval =~ s/\n/"\n".++$line." "/eg;
            warn("Script:\n1 $to_eval\n");
            die "Failed to parse: $@";
        }
    }
    
    no strict 'refs';
    my $cv = \&{"$package\::handler"};
    
    my $cgi = Apache::Request->instance($r);
    
    $r->no_cache(1);
    
    my $xsp_cache = Apache::AxKit::Cache->new($r, $package);
    
    if (!$package->has_changed($xsp_cache->mtime()) && 
                !$xml->has_changed($xsp_cache->mtime())) {
        AxKit::Debug(3, "XSP results cached");
        $r->print($xsp_cache->read);
        return;
    }
    
    eval {
#        local $^W;
        $r->pnotes('dom_tree', $cv->($r, $cgi));
    };
    if ($@) {
        die "XSP Script failed: $@";
    }
    
    $xsp_cache->write( $r->pnotes('dom_tree')->toString );
}

sub register {
    my $class = shift;
    no strict 'refs';
    $class->register_taglib(${"${class}::NS"});
}

sub _register_me_and_others {
#    warn "Loading taglibs\n";
    foreach my $package ($AxKit::Cfg->XSPTaglibs()) {
#        warn "Registering taglib: $package\n";
        AxKit::load_module($package);
        $package->register();
    }
}

sub register_taglib {
    my $class = shift;
    my $namespace = shift;
    
#    warn "Register taglib: $namespace => $class\n";
    
    $Apache::AxKit::Language::XSP::tag_lib{$namespace} = $class;
}

sub is_xsp_namespace {
    my ($ns) = @_;
    
    # a uri of the form "res:perl/<spec>" turns into an implicit loading of
    # the module indicated by <spec> (after slashes are turned into
    # double-colons). an example uri is "res:perl/My/Cool/Module".
    if ($Apache::AxKit::Language::XSP::ResNamespaces && $ns =~ m/^res:perl\/(.*)$/) {
       my $package = $1;
       $package =~ s/\//::/g;
       AxKit::load_module($package);
       $package->register();
    }
    
    return 1 if $Apache::AxKit::Language::XSP::tag_lib{$ns};
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
# SAX Handler code
############################################################

package AxKit::XSP::SAXHandler;

sub new_handler {
    my ($type, %self) = @_; 
    return bless \%self, $type;
}

sub start_expr {
    my ($e) = @_;
    my $element = { Name => "expr",
                    NamespaceURI => $AxKit::XSP::Core::NS,
                    Attributes => [ ],
                    Parent => $e->{Current_Element}->{Parent},
#                    OldParent => $e->{Current_Element},
            };
#    warn "start_expr: $e->{Current_Element}->{Name}\n";
    $e->start_element($element);
}

sub end_expr {
    my ($e) = @_;
    my $parent = $e->{Current_Element}->{Parent};
    my $element = { Name => "expr",
                    NamespaceURI => $AxKit::XSP::Core::NS,
                    Attributes => [ ],
                    Parent => $parent,
            };
#    warn "end_expr: $parent->{Name}\n";
    $e->end_element($element);
}

sub append_to_script {
    my ($e, $code) = @_;
    $e->{XSP_Script} .= $code;
}

sub manage_text {
    my ($e, $set, $go_back) = @_;
    
    $go_back ||= 0;

    my $depth = $e->depth();
    if (defined($set) && $set >= 0) {
        $e->{XSP_Manage_Text}[$depth - $go_back] = $set;
    }
    else {
        if (defined($set) && $set == -1) {
            # called from characters handler, rather than expr
            return $e->{XSP_Manage_Text}[$depth];
        }
        return $e->{XSP_Manage_Text}[$depth - 1];
    }
}

sub depth {
    my ($e) = @_;
    my $element = $e->{Current_Element};
    
    my $depth = 0;
    while ($element = $element->{Parent}) {
        $depth++;
    }
    
    return $depth;
}

sub current_element {
    my $e = shift;
    my $tag = $e->{Current_Element}{Name};
    $tag =~ s/^(.*:)//;
    return $tag;
}

sub start_document {
    my $e = shift;
    
    $e->{XSP_Script} = join("\n", 
                "package $e->{XSP_Package}; \@$e->{XSP_Package}::ISA = ('Apache::AxKit::Language::XSP::Page');",
                "#line 2 ".$e->{XSP_Line}."\n",
                "use Apache;",
                "use XML::XPath;",
                );
    
    foreach my $ns (keys %Apache::AxKit::Language::XSP::tag_lib) {
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{$ns};
        my $sub;
        if (($sub = $pkg->can("start_document")) && ($sub != \&start_document)) {
            $e->{XSP_Script} .= $sub->($e);
        }
        elsif ($sub = $pkg->can("parse_init")) {
            $e->{XSP_Script} .= $sub->($e);
        }
    }
}

sub end_document {
    my $e = shift;
    
    foreach my $ns (keys %Apache::AxKit::Language::XSP::tag_lib) {
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{$ns};
        my $sub;
        if (($sub = $pkg->can("end_document")) && ($sub != \&end_document)) {
            $e->{XSP_Script} .= $sub->($e);
        }
        elsif ($sub = $pkg->can("parse_final")) {
            $e->{XSP_Script} .= $sub->($e);
        }
    }

    $e->{XSP_Script} .= "return \$document\n}\n";
    
    return $e->{XSP_Script};
}

sub start_element {
    my $e = shift;
    my $element = shift;
    
    $element->{Parent} ||= $e->{Current_Element};
    
    $e->{Current_Element} = $element;

    my $ns = $element->{NamespaceURI};
    
#    warn "START-NS: $ns : $element->{Name}\n";
    
    my @attribs;
    
    for my $attr (@{$element->{Attributes}}) {
        if ($attr->{Name} eq 'xmlns') {
            unless (Apache::AxKit::Language::XSP::is_xsp_namespace($attr->{Value})) {
                $e->{Current_NS}{'#default'} = $attr->{Value};
            }
        }
        elsif ($attr->{Name} =~ /^xmlns:(.*)$/) {
            my $prefix = $1;
            unless (Apache::AxKit::Language::XSP::is_xsp_namespace($attr->{Value})) {
                $e->{Current_NS}{$prefix} = $attr->{Value};
            }
        }
        else {
            push @attribs, $attr;
        }
    }
    
    $element->{Attributes} = \@attribs;
    
    if (!defined($ns) || 
        !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
    {
        $e->manage_text(0); # set default for non-xsp tags
        $e->{XSP_Script} .= AxKit::XSP::DefaultHandler::start_element($e, $element);
    }
    else {
#        local $^W;
        $element->{Name} =~ s/^(.*)://;
        my $prefix = $1;
        my $tag = $element->{Name};
        my %attribs;
        # this is probably a bad hack to turn xsp:name="value" into name="value"
        for my $attr (@{$element->{Attributes}}) {
            $attr->{Name} =~ s/^\Q$prefix\E://;
            $attribs{$attr->{Name}} = $attr->{Value};
        }
        $e->manage_text(1); # set default for xsp tags
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        my $sub;
        if (($sub = $pkg->can("start_element")) && ($sub != \&start_element)) {
            $e->{XSP_Script} .= $sub->($e, $element);
        }
        elsif ($sub = $pkg->can("parse_start")) {
            $e->{XSP_Script} .= $sub->($e, $tag, %attribs);
        }
    }
}

sub end_element {
    my $e = shift;
    my $element = shift;

    my $ns = $element->{NamespaceURI};
    
#    warn "END-NS: $ns : $_[0]\n";
    
    if (!defined($ns) || 
        !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
    {
        $e->{XSP_Script} .= AxKit::XSP::DefaultHandler::end_element($e, $element);
    }
    else {
#        local $^W;
        $element->{Name} =~ s/^(.*)://;
        my $tag = $element->{Name};
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        my $sub;
        if (($sub = $pkg->can("end_element")) && ($sub != \&end_element)) {
            $e->{XSP_Script} .= $sub->($e, $element);
        }
        elsif ($sub = $pkg->can("parse_end")) {
            $e->{XSP_Script} .= $sub->($e, $tag);
        }
    }
    
    $e->{Current_Element} = $element->{Parent} || $e->{Current_Element}->{Parent};
}

sub characters {
    my $e = shift;
    my $text = shift;
    my $ns = $e->{Current_Element}->{NamespaceURI};
    
#    warn "CHAR-NS: $ns\n";
    
    if (!defined($ns) || 
        !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns }) ||
        !$e->manage_text(-1))
    {
        $e->{XSP_Script} .= AxKit::XSP::DefaultHandler::characters($e, $text);
    }
    else {
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        my $sub;
        if (($sub = $pkg->can("characters")) && ($sub != \&characters)) {
            $e->{XSP_Script} .= $sub->($e, $text);
        }
        elsif ($sub = $pkg->can("parse_char")) {
            $e->{XSP_Script} .= $sub->($e, $text->{Data});
        }
    }
}

sub comment {
    my $e = shift;
    my $comment = shift;

    my $ns = $e->{Current_Element}->{NamespaceURI};
                
    if (!defined($ns) || 
        !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
    {
        $e->{XSP_Script} .= AxKit::XSP::DefaultHandler::comment($e, $comment);
    }
    else {
#        local $^W;
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        my $sub;
        if (($sub = $pkg->can("comment")) && ($sub != \&comment)) {
            $e->{XSP_Script} .= $sub->($e, $comment);
        }
        elsif ($sub = $pkg->can("parse_comment")) {
            $e->{XSP_Script} .= $sub->($e, $comment);
        }
    }
}

sub processing_instruction {
    my $e = shift;
    my $pi = shift;

    my $ns = $e->{Current_Element}->{NamespaceURI};
    
    if (!defined($ns) || 
        !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
    {
        $e->{XSP_Script} .= AxKit::XSP::DefaultHandler::processing_instruction($e, $pi);
    }
    else {
#        local $^W;
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        my $sub;
        if (($sub = $pkg->can("processing_instruction")) && ($sub != \&processing_instruction)) {
            $e->{XSP_Script} .= $sub->($e, $pi);
        }
        elsif ($sub = $pkg->can("parse_pi")) {
            $e->{XSP_Script} .= $sub->($e, $pi);
        }
    }
}

############################################################
# Functions implementing xsp:* processing
############################################################

package AxKit::XSP::Core;

use vars qw/@ISA $NS/;

@ISA = ('Apache::AxKit::Language::XSP');

$NS = 'http://apache.org/xsp/core/v1';

__PACKAGE__->register();

# hack for backwards compatibility:
__PACKAGE__->register_taglib("http://www.apache.org/1999/XSP/Core");


sub start_document {
    return "#initialize xsp namespace\n";
}

sub end_document {
    return '';
}

sub comment {
    return '';
}

sub processing_instruction {
    return '';
}

sub characters {
    my ($e, $node) = @_;

    local $^W;
    
    my $text = $node->{Data};
    
#     Ricardo writes: "<xsp:expr> produces either an [object]
# _expression_ (not necessarily a String) or a character event depending
# on context. When  <xsp:expr> is enclosed in another XSP tag (except
# <xsp:content>), it's replaced by the code it contains. Otherwise it
# should be treated as a text node and, therefore, coerced to String to be
# output through a characters SAX event."

    if ($e->current_element() =~ /^(content)$/) {
        $text =~ s/\|/\\\|/g;

        return <<"EOT";
{
    my \$text = XML::XPath::Node::Text->new(q|$text|);
    \$parent->appendChild(\$text, 1); 
}
EOT
    }
    elsif ($e->current_element() =~ /^(attribute|comment|name)$/) {
        return '' if ($e->current_element() eq 'attribute' && !$e->{attrib_seen_name});
        $text =~ s/^\s*//; $text =~ s/\s*$//;
        $text =~ s/\|/\\\|/g;    
        return ". q|$text|";
    }
    
#    return '' unless $e->{XSP_User_Root};
    
    return $text;
}

sub start_element {
    my ($e, $node) = @_;
    
    my ($tag, %attribs);
    
    $tag = $node->{Name};
    
    foreach my $attrib (@{$node->{Attributes}}) {
        $attribs{$attrib->{Name}} = $attrib->{Value};
    }
    
    if ($tag eq 'page') {
        if ($attribs{language} && lc($attribs{language}) ne 'perl') {
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
        if (my $name = $attribs{name}) {
            $e->manage_text(0);
            return '{ my $elem = XML::XPath::Node::Element->new(q(' . $name . '));' .
                    '$parent->appendChild($elem, 1); $parent = $elem; }' . "\n";
        }
    }
    elsif ($tag eq 'attribute') {
        if (my $name = $attribs{name}) {
            $e->{attrib_seen_name} = 1;
            return '{ my $attr = XML::XPath::Node::Attribute->new(q|' . $name . '|, ""';
        }
        $e->{attrib_seen_name} = 0;
    }
    elsif ($tag eq 'name') {
        return '{ my $name = ""';
    }
    elsif ($tag eq 'pi') {
    }
    elsif ($tag eq 'comment') {
        return '{ my $comment = XML::XPath::Node::Comment->new(""';
    }
    elsif ($tag eq 'text') {
        return '{ my $text = XML::XPath::Node::Text->new(""';
    }
    elsif ($tag eq 'expr') {
#        warn "expr: -2 = {", $node->{Parent}->{NamespaceURI}, "}", $node->{Parent}->{Name}, "\n";
        if (Apache::AxKit::Language::XSP::is_xsp_namespace($node->{Parent}->{NamespaceURI})) {
            if (!$e->manage_text() || $node->{Parent}->{Name} =~ /^(.*:)?content$/) {
                return <<'EOT';
{
    my $text = XML::XPath::Node::Text->new(do {
EOT
            }
            elsif ($node->{Parent}->{Name} =~ /^(.*:)?(logic|expr)$/) {
                return 'do {';
            }
        }
        else {
            return <<'EOT';
{
    my $text = XML::XPath::Node::Text->new(do {
EOT
        }
        
        return '. do {';
#        warn "start Expr: CurrentEl: ", $e->current_element, "\n";
    }
    
    return '';
}

sub end_element {
    my ($e, $node) = @_;
    
    my $tag = $node->{Name};
    
    if ($tag eq 'page') {
    }
    elsif ($tag eq 'structure') {
    }
    elsif ($tag eq 'dtd') {
    }
    elsif ($tag eq 'include') {
        return ";\n";
    }
    elsif ($tag eq 'import') {
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
        return '); $parent->appendAttribute($attr, 1); }' . "\n";
    }
    elsif ($tag eq 'name') {
        if ($node->{Parent}->{Name} =~ /^(.*:)?element$/) {
            $e->manage_text(0, 1);
            return '; my $elem = XML::XPath::Node::Element->new($name);' .
                    '$parent->appendChild($elem, 1); $parent = $elem; }' . "\n";
        }
        elsif ($node->{Parent}->{Name} =~ /^(.*:)?attribute$/) {
            $e->{attrib_seen_name} = 1;
            return '; my $attr = XML::XPath::Node::Attribute->new($name, ""';
        }
        else {
            die "xsp:name parent node: $node->{Parent}->{Name} not valid";
        }
    }
    elsif ($tag eq 'pi') {
    }
    elsif ($tag eq 'comment') {
        return '); $parent->appendChild($comment, 1); }' . "\n";
    }
    elsif ($tag eq 'text') {
        return '); $parent->appendChild($text, 1); }' . "\n";
    }
    elsif ($tag eq 'expr') {
#        warn "expr: -2 = {", $node->{Parent}->{NamespaceURI}, "}", $node->{Parent}->{Name}, "\n";
        if (Apache::AxKit::Language::XSP::is_xsp_namespace($node->{Parent}->{NamespaceURI})) {
            if (!$e->manage_text() || $node->{Parent}->{Name} =~ /^(.*:)?content$/) {
                return <<'EOT';
}); # xsp tag
    $parent->appendChild($text, 1); 
}
EOT
            }
            elsif ($node->{Parent}->{Name} =~ /^(.*:)?(logic|expr)$/) {
                return '}';
            }
        }
        else {
            return <<'EOT';
}); # non xsp tag
    $parent->appendChild($text, 1); 
}
EOT
        }
        return '}';
    }
    
    return '';
}

1;

############################################################
## Default (non-xsp-namespace) handlers
############################################################

package AxKit::XSP::DefaultHandler;

sub start_element {
    my ($e, $node) = @_;
    
    if (!$e->{XSP_User_Root}) {
        $e->{XSP_Script} .= join("\n",
                'sub handler {',
                'my ($r, $cgi) = @_;',
                'my $document = XML::XPath::Node::Element->new();',
                'my ($parent);',
                '$parent = $document;',
                "\n",
                );
        $e->{XSP_User_Root} = 1;
    }
    
    my $code = '{ my $elem = XML::XPath::Node::Element->new(q(' . $node->{Name} . '));' .
                '$parent->appendChild($elem, 1); $parent = $elem; }' . "\n";
    
    for my $attr (@{$node->{Attributes}}) {
        $code .= '{ my $attr = XML::XPath::Node::Attribute->new(q(' . $attr->{Name} . '), q(' . $attr->{Value} . '));';
        $code .= '$parent->appendAttribute($attr, 1); }' . "\n";
    }

    for my $ns (keys %{$e->{Current_NS}}) {
        $code .= '{ my $ns = XML::XPath::Node::Namespace->new(q(' . $ns .'), q(' .
                $e->{Current_NS}{$ns} . '));';
        $code .= '$parent->appendNamespace($ns); }' . "\n";
    }
    
    push @{ $e->{NS_Stack} },
         { %{ $e->{Current_NS} } };
    
    $e->{Current_NS} = {};
    
    return $code;
}

sub end_element {
    my ($e, $element) = @_;
    
    $e->{Current_NS} = pop @{ $e->{NS_Stack} };
    
    return '$parent = $parent->getParentNode;' . "\n";
}

sub characters {
    my ($e, $node) = @_;
    
    my $text = $node->{Data};
    
    return '' unless $e->{XSP_User_Root}; # should not happen!
    
    if (!$e->{XSP_Indent}) {
        return '' unless $text =~ /\S/;
    }
    
    $text =~ s/\|/\\\|/g;
    
    return '{ my $text = XML::XPath::Node::Text->new(q|' . $text . '|);' .
            '$parent->appendChild($text, 1); }' . "\n";
}

sub comment {
    return '';
}

sub processing_instruction {
    return '';
}

1;

######################################################
## SAXParser - almost verbatim copy of Ken MacLeod's
##             SAX2 stuff.
######################################################

package AxKit::XSP::SAXParser;

use vars qw/$xmlns_ns/;

$xmlns_ns = "http://www.w3.org/2000/xmlns/";

sub new {
    my ($type, %self) = @_; 
    return bless \%self, $type;
}

sub parse {
    my ($self, $thing) = @_;

    my $parser = XML::Parser->new( Handlers => {
	Init => sub { $self->_handle_init(@_) },
	Final => sub { $self->_handle_final(@_) },
	Start => sub { $self->_handle_start(@_) },
	End => sub { $self->_handle_end(@_) },
	Char => sub { $self->_handle_char(@_) },
	Comment => sub { $self->_handle_comment(@_) },
	Proc => sub { $self->_handle_proc(@_) },
    } );
    
    if ($self->{provider}) {
        if (my $ext_ent_handler = $self->{provider}->get_ext_ent_handler()) {
            $parser->setHandlers(ExternEnt => $ext_ent_handler);
        }
    }

    $self->{InScopeNamespaceStack} = [ { '_Default' => undef,
				         'xmlns' => $xmlns_ns } ];
    $self->{NodeStack} = [ ];

    return $parser->parse($thing);
}

sub _handle_init {
    my ($self, $expat) = @_;

    my $document = { Parent => undef };
    push @{ $self->{NodeStack} }, $document;
    $self->{Handler}->start_document( $document );
}

sub _handle_final {
    my ($self, $expat) = @_;

    my $document = pop @{ $self->{NodeStack} };
    return $self->{Handler}->end_document( $document );
}

sub _handle_start {
    my $self = shift; my $expat = shift; my $element_name = shift;

    push @{ $self->{InScopeNamespaceStack} },
         { %{ $self->{InScopeNamespaceStack}[-1] } };
    $self->_scan_namespaces(@_);

    my @attributes;
    for (my $ii = 0; $ii < $#_; $ii += 2) {
	my ($name, $value) = ($_[$ii], $_[$ii+1]);
	my $namespace = $self->_namespace($name);
	push @attributes, { Name => $name,
                            Value => $value,
                            NamespaceURI => $namespace };
    }

    my $namespace = $self->_namespace($element_name);
    my $element = { Name => $element_name,
                    NamespaceURI => $namespace,
                    Attributes => [ @attributes ],
                    Parent => $self->{NodeStack}[-1] };

    push @{ $self->{NodeStack} }, $element;
    $self->{Handler}->start_element( $element );
}

sub _handle_end {
    my $self = shift;

    pop @{ $self->{InScopeNamespaceStack} };
    my $element = pop @{ $self->{NodeStack} };
    my $results = $self->{Handler}->end_element( $element );
    return $results;
}

sub _handle_char {
    my ($self, $expat, $string) = @_;

    my $characters = { Data => $string, Parent => $self->{NodeStack}[-1] };
    $self->{Handler}->characters( $characters );
}

sub _handle_comment {
    my ($self, $expat, $data) = @_;

    my $comment = { Data => $data, Parent => $self->{NodeStack}[-1] };
    $self->{Handler}->comment( $comment );
}

sub _handle_proc {
    my ($self, $expat, $target, $data) = @_;

    my $pi = {  Target => $target,
                Data => $data,
                Parent => $self->{NodeStack}[-1] };
    $self->{Handler}->processing_instruction( $pi );
}

sub _scan_namespaces {
    my ($self, %attributes) = @_;

    while (my ($attr_name, $value) = each %attributes) {
	if ($attr_name eq 'xmlns') {
	    $self->{InScopeNamespaceStack}[-1]{'_Default'} = $value;
	} elsif ($attr_name =~ /^xmlns:(.*)$/) {
	    my $prefix = $1;
	    $self->{InScopeNamespaceStack}[-1]{$prefix} = $value;
	}
    }
}

sub _namespace {
    my ($self, $name) = @_;

    my ($prefix, $localname) = split(/:/, $name);
    if (!defined($localname)) {
	if ($prefix eq 'xmlns') {
	    return undef;
	} else {
	    return $self->{InScopeNamespaceStack}[-1]{'_Default'};
	}
    } else {
	return $self->{InScopeNamespaceStack}[-1]{$prefix};
    }
}

############################################################
# Base page class
############################################################

package Apache::AxKit::Language::XSP::Page;

sub has_changed {
    my $class = shift;
    my $mtime = shift;
    return 1;
}

1;

__END__
=pod

=head1 NAME

Apache::AxKit::Language::XSP - eXtensible Server Pages

=head1 SYNOPSIS

  <xsp:page
    xmlns:xsp="http://apache.org/xsp/core/v1">

    <xsp:structure>
        <xsp:import>Time::Object</xsp:import>
    </xsp:structure>

    <page>
        <title>XSP Test</title>
        <para>
        Hello World!
        </para>
        <para>
        Good 
        <xsp:logic>
        if (localtime->hour >= 12) {
            <xsp:content>Afternoon</xsp:content>
        }
        else {
            <xsp:content>Morning</xsp:content>
        }
        </xsp:logic>
        </para>
    </page>
    
  </xsp:page>

=head1 DESCRIPTION

XSP implements a tag-based dynamic language that allows you to develop
your own tags, examples include sendmail and sql taglibs. It is AxKit's
way of providing an environment for dynamic pages. XSP is originally part
of the Apache Cocoon project, and so you will see some Apache namespaces
used in XSP.

=head1 Tag Reference

=head2 C<<xsp:page>>

This is the top level element, although it does not have to be. AxKit's
XSP implementation can process XSP pages even if the top level element
is not there, provided you use one of the standard AxKit ways to turn
on XSP processing for that page. See L<AxKit>.

The attribute C<language="Perl"> can be present, to mandate the language.
This is useful if you expect people might mistakenly try and use this
page on a Cocoon system. The default value of this attribute is "Perl".

XSP normally swallows all whitespace in your output. If you don't like
this feature, or it creates invalid output, then you can add the
attribute: C<indent-result="yes">

=head2 C<<xsp:structure>>

  parent: <xsp:page>

This element appears at the root level of your page before any non-XSP
tags. It defines page-global "things" in the C<<xsp:logic>> and
C<<xsp:import>> tags.

=head2 C<<xsp:import>>

  parent: <xsp:structure>

Use this tag for including modules into your code, for example:

  <xsp:structure>
    <xsp:import>DBI</xsp:import>
  </xsp:structure>

=head2 C<<xsp:logic>>

  parent: <xsp:structure>, any

The C<<xsp:logic>> tag introduces some Perl code into your page.

As a child of C<<xsp:structure>>, this element allows you to define
page global variables, or functions that get used in the page. Placing
functions in here allows you to get around the Apache::Registry
closures problem (see the mod_perl guide at http://perl.apache.org/guide
for details).

Elsewhere the perl code contained within the tags is executed on every
view of the XSP page.

B<Warning:> Be careful - the Perl code contained within this tag is still
subject to XML's validity constraints. Most notably to Perl code is that
the & and < characters must be escaped into &amp; and &lt; respectively.
You can get around this to some extent by using CDATA sections. This is
especially relevant if you happen to think something like this will work:

  <xsp:logic>
    if ($some_condition) {
      print "<para>Condition True!</para>";
    }
    else {
      print "<para>Condition False!</para>";
    }
  </xsp:logic>

The correct way to write that is simply:

  <xsp:logic>
    if ($some_condition) {
      <para>Condition True!</para>
    }
    else {
      <para>Condition False!</para>
    }
  </xsp:logic>

The reason is that XSP intrinsically knows about XML!

=head2 C<<xsp:content>>

  parent: <xsp:logic>

This tag allows you to temporarily "break out" of logic sections to generate
some XML text to go in the output. Using something similar to the above
example, but without the surrounding C<<para>> tag, we have:

  <xsp:logic>
    if ($some_condition) {
      <xsp:content>Condition True!</xsp:content>
    }
    else {
      <xsp:content>Condition False!</xsp:content>
    }
  </xsp:logic>

=head2 C<<xsp:element>>

This tag generates an element of name equal to the value in the attribute
C<name>. Alternatively you can use a child element C<<xsp:name>> to specify
the name of the element. Text contents of the C<<xsp:element>> are created
as text node children of the new element.

=head2 C<<xsp:attribute>>

Generates an attribute. The name of the attribute can either be specified
in the C<name="..."> attribute, or via a child element C<<xsp:name>>. The
value of the attribute is the text contents of the tag.

=head2 C<<xsp:comment>>

Normally XML comments are stripped from the output. So to add one back in
you can use the C<<xsp:comment>> tag. The contents of the tag are the
value of the comment.

=head2 C<<xsp:text>>

Create a plain text node. The contents of the tag are the text node to be
generated. This is useful when you wish to just generate a text node while
in an C<<xsp:logic>> section.

=head2 C<<xsp:expr>>

This is probably the most useful, and most important (and also the most
complex) tag. An expression is some perl code that executes, and the results
of which are added to the output. Exactly how the results are added to the
output depends very much on context.

The default method for output for an expression is as a text node. So for
example:

  <p>
  It is now: <xsp:expr>localtime</xsp:expr>
  </p>

Will generate a text node containing the time.

If the expression is contained within an XSP namespaces, that is either a
tag in the xsp:* namespace, or a tag implementing a tag library, then an
expression generally does not create a text node, but instead is simply
wrapped in a Perl C<do {}> block, and added to the perl script. However,
there are anti-cases to this. For example if the expression is within
a C<<xsp:content>> tag, then a text node is created.

Needless to say, in every case, C<<xsp:expr>> should just "do the right
thing". If it doesn't, then something (either a taglib or XSP.pm itself)
is broken and you should report a bug.

=head1 DESIGN PATTERNS

Writing your own taglibs can be tricky, because you're using an event
based API to write out Perl code. You may want to take a look at the
Apache::AxKit::Language::XSP::TaglibHelper module, which comes with
AxKit and allows you to easily publish a taglib without writing
XML event code.

These patterns represent the things you may want to achieve when 
authoring a tag library "from scratch".

B<1. Your tag is a wrapper around other things.>

Example:

  <mail:sendmail>...</mail:sendmail>

Solution:

Start a new block, so that you can store lexical variables, and declare
any variables relevant to your tag:

in parse_start:

  if ($tag eq 'sendmail') {
    return '{ my ($to, $from, $sender);';
  }

Often it will also be relevant to execute that code when you see the end
tag:

in parse_end:

  if ($tag eq 'sendmail') {
    return 'Mail::Sendmail::sendmail( 
            to => $to, 
            from => $from, 
            sender => $sender 
            ); }';
  }

Note there the closing of that original opening block.

B<2. Your tag indicates a parameter for a surrounding taglib.>

Example:

  <mail:to>...</mail:to>

Solution:

Having declared the variable as above, you simply set it to the empty
string, with no semi-colon:

in parse_start:

  if ($tag eq 'to') {
    return '$to = ""';
  }

Then in parse_char:

sub parse_char {
  my ($e, $text) = @_;
  $text =~ s/^\s*//;
  $text =~ s/\s*$//;

  return '' unless $text;

  $text =~ s/\|/\\\|/g;
  return ". q|$text|";
}

Note there's no semi-colon at the end of all this, so we add that:

in parse_end:

  if ($tag eq 'to') {
    return ';';
  }

All of this black magic allows other taglibs to set the thing in that
variable using expressions.

B<3. You want your tag to return a scalar (string) that does the right thing
depending on context. For example, generates a Text node in one place or
generates a scalar in another context.>

Solution:

use start_expr(), append_to_script(), end_expr().

Example:

  <example:get-datetime format="%Y-%m-%d %H:%M:%S"/>

in parse_start:

  if ($tag eq 'get-datetime') {
    start_expr($e, $tag); # creates a new { ... } block
    my $local_format = lc($attribs{format}) || '%a, %d %b %Y %H:%M:%S %z';
    return 'my ($format); $format = q|' . $local_format . '|;';
  }

in parse_end:

  if ($tag eq 'get-datetime') {
    append_to_script($e, 'use Time::Object; localtime->strftime($format);');
    end_expr($e);
    return '';
  }

Explanation:

This is more complex than the first 2 examples, so it warrants some 
explanation. I'll go through it step by step.

  start_expr(...)

This tells XSP that this really generates a <xsp:expr> tag. Now we don't
really generate that tag, we just execute the handler for it. So what
happens is the <xsp:expr> handler gets called, and it looks to see what
the current calling context is. If its supposed to generate a text node,
it generates some code to do that. If its supposed to generate a scalar, it
does that too. Ultimately both generate a do {} block, so we'll summarise 
that by saying the code now becomes:

  do {

(the end of the block is generated by end_expr()).

Now the next step (ignoring the simple gathering of the format variable), is
a return, which appends more code onto the generated perl script, so we
get:

  do {
    my ($format); $format = q|%a, %d %b %Y %H:%M:%S %z|;

Now we immediately receive an end_expr, because this is an empty element
(we'll see why we formatted it this way in #5 below). The first thing we
get is:

  append_to_script($e, 'use Time::Object; localtime->strftime($format);');

This does exactly what it says, and the script becomes:

  do {
    my ($format); $format = q|%a, %d %b %Y %H:%M:%S %z|;
    use Time::Object; localtime->strftime($format);

Finally, we call:

  end_expr($e);

which closes the do {} block, leaving us with:

  do {
    my ($format); $format = q|%a, %d %b %Y %H:%M:%S %z|;
    use Time::Object; localtime->strftime($format);
  }

Now if you execute that in Perl, you'll see the do {} returns the last
statement executed, which is the C<localtime->strftime()> bit there,
thus doing exactly what we wanted.

Note that start_expr, end_expr and append_to_script aren't exported
by default, so you need to do:

  use Apache::AxKit::Language::XSP 
        qw(start_expr end_expr append_to_script);

B<4. Your tag can take as an option either an attribute, or a child tag.>

Example:

  <util:include-uri uri="http://server/foo"/>

or

  <util:include-uri>
    <util:uri><xsp:expr>$some_uri</xsp:expr></util:uri>
  </util:include-uri>

Solution:

There are several parts to this. The simplest is to ensure that whitespace
is ignored. We have that dealt with in the example parse_char above. Next
we need to handle that variable. Do this by starting a new block with the
tag, and setting up the variable:

in parse_start:

  if ($tag eq 'include-uri') {
    my $code = '{ my ($uri);';
    if ($attribs{uri}) {
      $code .= '$uri = q|' . $attribs{uri} . '|;';
    }
    return $code;
  }

Now if we don't have the attribute, we can expect it to come in the 
C<<util:uri>> tag:

in parse_start:

  if ($tag eq 'uri') {
    return '$uri = ""'; # note the empty string!
  }

Now you can see that we're not explicitly setting C<$uri>, that's because the
parse_char we wrote above handles it by returning '. q|$text|'. And if we
have a C<<xsp:expr>> in there, that's handled automagically too.

Now we just need to wrap things up in the end handlers:

in parse_end:

  if ($tag eq 'uri') {
    return ';';
  }
  if ($tag eq 'include-uri') {
    return 'Taglib::include_uri($uri); # execute the code
            } # close the block
    ';
  }

B<5. You want to return a scalar that does the right thing in context, but
also can take a parameter as an attribute I<or> a child tag.>

Example:

  <esql:get-column column="user_id"/>

vs

  <esql:get-column>
    <esql:column><xsp:expr>$some_column</xsp:expr></esql:column>
  </esql:get-column>

Solution:

This is a combination of patterns 3 and 4. What we need to do is change
#3 to simply allow our variable to be added as in #4 above:

in parse_start:

  if ($tag eq 'get-column') {
    start_expr($e, $tag);
    my $code = 'my ($col);'
    if ($attribs{col}) {
      $code .= '$col = q|' . $attribs{col} . '|;';
    }
    return $code;
  }
  if ($tag eq 'column') {
    return '$col = ""';
  }

in parse_end:

  if ($tag eq 'column') {
    return ';';
  }
  if ($tag eq 'get-column') {
    append_to_script($e, 'Full::Package::get_column($col)');
    end_expr($e);
    return '';
  }

B<6. You have a conditional tag>

Example:

  <esql:no-results>
    No results!
  </esql:no-results>

Solution:

The problem here is that taglibs normally recieve character/text events
so that they can manage variables. With a conditional tag, you want
character events to be handled by the core XSP and generate text events.
So we have a switch for that:

  if ($tag eq 'no-results') {
    $e->manage_text(0);
    return 'if (AxKit::XSP::ESQL::get_count() == 0) {';
  }

Turning off manage_text with a zero simply ensures that immediate children
text nodes of this tag don't fire text events to the tag library, but
instead get handled by XSP core, thus creating text nodes (and doing
the right thing, generally).

=head1 <xsp:expr> (and start_expr, end_expr) Notes

B<Do not> consider adding in the 'do {' ... '}' bits yourself. Always
leave this to the start_expr, and end_expr functions. This is because the
implementation could change, and you really don't know better than
the underlying XSP implementation. You have been warned.

=cut
