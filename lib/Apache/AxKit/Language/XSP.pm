# $Id: XSP.pm,v 1.39 2001/02/16 03:23:18 matt Exp $

package Apache::AxKit::Language::XSP;

use strict;
use Apache::AxKit::Language;
use Apache::Request;
use Apache::AxKit::Exception ':try';
use XML::Parser;

use vars qw/@ISA $NS @EXPORT_OK/;

require Exporter;

@ISA = ('Apache::AxKit::Language', 'Exporter');
$NS = 'http://apache.org/xsp/core/v1';

@EXPORT_OK = qw(start_expr expr end_expr append_to_script manage_text);

sub stylesheet_exists { 0; }

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
    my ($r, $xml, undef, $reparse) = @_;
    
    _register_me_and_others();
    
    # hack for backwards compatibility:
    $class->register_taglib("http://www.apache.org/1999/XSP/Core");
    
#    warn "XSP Parse: $xmlfile\n";
    
    my $key = $xml->key();
    
    my $package = get_package_name($key);
    my $handler = $class->new_handler(
            XSP_Package => $package,
            XSP_Line => $key,
            );
    my $parser = AxKit::XSP::SAXParser->new(
            provider => $xml,
            Handler => $handler,
            );
    
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
        AxKit::Debug(5, 'XSP Compilation finished');
        if ($@) {
            my $line = 1;
            $to_eval =~ s/\n/"\n".++$line." "/eg;
            AxKit::Debug(2, "Script:\n1 $to_eval\n");
            die "Failed to parse: $@";
        }
    }
    
    no strict 'refs';
    my $cv = \&{"$package\::handler"};
    
    my $cgi = Apache::Request->instance($r);
    
    $r->no_cache(1);

    eval {
#        local $^W;
        $r->pnotes('dom_tree', $cv->($r, $cgi));
    };
    if ($@) {
        die "XSP Script failed: $@";
    }
    
}

sub register {
    my $class = shift;
    no strict 'refs';
    $class->register_taglib(${"${class}::NS"});
}

sub _register_me_and_others {
#    warn "Loading taglibs\n";
    __PACKAGE__->register();
    
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
    
    return 1 if $Apache::AxKit::Language::XSP::tag_lib{$ns};
}

sub start_expr {
    my ($e) = @_;
    my $element = { Name => "expr",
                    NamespaceURI => $NS,
                    Attributes => [ ] };
#    warn "start_expr: $tag\n";
    $e->start_element($element);
}

# sub expr {
#     my ($e, $expression) = @_;
#     my $expr_tag = $e->generate_ns_name("expr", $NS);
#     push @{$e->{Context}}, $expr_tag;
#     main_parse_char($e, $expression);
#     pop @{$e->{Context}};
# }

sub end_expr {
    my ($e) = @_;
    my $element = { Name => "expr",
                    NamespaceURI => $NS,
                    Attributes => [ ] };
    $e->end_element($element);
}

sub append_to_script {
    my ($e, $code) = @_;
    $e->{XSP_Script} .= $code;
}

sub manage_text {
    my ($e, $set) = @_;

    my $depth = @{$e->{NodeStack}};
    if (defined($set) && $set >= 0) {
        $e->{XSP_Manage_Text}[$depth] = $set;
    }
    else {
        if (defined($set) && $set == -1) {
            # called from characters handler, rather than expr
            return $e->{XSP_Manage_Text}[$depth];
        }
        return $e->{XSP_Manage_Text}[$depth - 1];
    }
}

sub current_element {
    my $e = shift;
    my $tag = $e->{NodeStack}[-1]{Name};
    $tag =~ s/^(.*:)//;
    return $tag;
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

sub new_handler {
    my ($type, %self) = @_; 
    return bless \%self, $type;
}

sub start_document {
    my $e = shift;
    
    $e->{XSP_Script} = join("\n", 
                "package $e->{XSP_Package};",
                "use Apache;",
                "use XML::XPath;",
                "#line 1 ".$e->{XSP_Line}."\n",
                );
    
    foreach my $ns (keys %Apache::AxKit::Language::XSP::tag_lib) {
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{$ns};
        if (my $sub = $pkg->can("parse_init")) {
            $e->{XSP_Script} .= $sub->($e);
        }
    }
}

sub end_document {
    my $e = shift;
    
    foreach my $ns (keys %Apache::AxKit::Language::XSP::tag_lib) {
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{$ns};
        if (my $sub = $pkg->can("parse_final")) {
            $e->{XSP_Script} .= $sub->($e);
        }
    }

    $e->{XSP_Script} .= "return \$document\n}\n";
    
    return $e->{XSP_Script};
}

sub start_element {
    my $e = shift;
    my $element = shift;

    my $ns = $element->{NamespaceURI};
    
#    warn "START-NS: $ns : $element->{Name}\n";
    
    my @attribs;
    
    for my $attr (@{$element->{Attributes}}) {
        if ($attr->{Name} eq 'xmlns') {
            unless (is_xsp_namespace($attr->{Value})) {
                $e->{Current_NS}{'#default'} = $attr->{Value};
            }
        }
        elsif ($attr->{Name} =~ /^xmlns:(.*)$/) {
            my $prefix = $1;
            unless (is_xsp_namespace($attr->{Value})) {
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
        $e->{XSP_Script} .= default_parse_start($e, $element);
    }
    else {
#        local $^W;
        my $tag = $element->{Name};
        $tag =~ s/^(.*)://; # strip prefix
        my $prefix = $1;
        my %attribs;
        for my $attr (@{$element->{Attributes}}) {
            $attr->{Name} =~ s/^\Q$prefix\E://;
            $attribs{$attr->{Name}} = $attr->{Value};
        }
        $e->manage_text(1); # set default for xsp tags
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        if (my $sub = $pkg->can("parse_start")) {
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
        $e->{XSP_Script} .= default_parse_end($e, $element);
    }
    else {
#        local $^W;
        my $tag = $element->{Name};
        $tag =~ s/^(.*)://; # strip prefix
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        if (my $sub = $pkg->can("parse_end")) {
            $e->{XSP_Script} .= $sub->($e, $tag);
        }
    }
}

sub characters {
    my $e = shift;
    my $text = shift;
    my $ns = $e->{NodeStack}->[-1]->{NamespaceURI};
    
#    warn "CHAR-NS: $ns\n";
    
    if (!defined($ns) || 
        !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns }) ||
        !$e->manage_text(-1))
    {
        $e->{XSP_Script} .= default_parse_char($e, $text->{Data});
    }
    else {
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        if (my $sub = $pkg->can("parse_char")) {
            $e->{XSP_Script} .= $sub->($e, $text->{Data});
        }
    }
}

sub comment {
    my $e = shift;
    my $comment = shift;

    my $ns = $e->{NodeStack}->[-1]->{NamespaceURI};
                
    if (!defined($ns) || 
        !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
    {
        $e->{XSP_Script} .= default_parse_comment($e, $comment);
    }
    else {
#        local $^W;
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        if (my $sub = $pkg->can("parse_comment")) {
            $e->{XSP_Script} .= $sub->($e, $comment);
        }
    }
}

sub processing_instruction {
    my $e = shift;
    my $pi = shift;

    my $ns = $e->{NodeStack}->[-1]->{NamespaceURI};
    
    if (!defined($ns) || 
        !exists($Apache::AxKit::Language::XSP::tag_lib{ $ns })) 
    {
        $e->{XSP_Script} .= default_parse_pi($e, $pi);
    }
    else {
#        local $^W;
        my $pkg = $Apache::AxKit::Language::XSP::tag_lib{ $ns };
        if (my $sub = $pkg->can("parse_pi")) {
            $e->{XSP_Script} .= $sub->($e, $pi);
        }
    }
}

############################################################
## Default (non-xsp-namespace) handlers
############################################################

sub default_parse_start {
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

sub default_parse_end {
    my ($e, $element) = @_;
    
    $e->{Current_NS} = pop @{ $e->{NS_Stack} };
    
    return '$parent = $parent->getParentNode;' . "\n";
}

sub default_parse_char {
    my ($e, $text) = @_;
    
    return '' unless $e->{XSP_User_Root}; # should not happen!
    
    if (!$e->{XSP_Indent}) {
        return '' unless $text =~ /\S/;
    }
    
    $text =~ s/\|/\\\|/g;
    
    return '{ my $text = XML::XPath::Node::Text->new(q|' . $text . '|);' .
            '$parent->appendChild($text, 1); }' . "\n";
}

sub default_parse_comment {
    return '';
}

sub default_parse_pi {
    return '';
}

############################################################
# Functions implementing xsp:* processing
############################################################

sub parse_init {
    return "#initialize xsp namespace\n";
}

sub parse_final {
}

sub parse_comment {
    return '';
}

sub parse_pi {
    return '';
}

sub parse_char {
    my ($e, $text) = @_;

    local $^W;
    
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
    elsif ($e->current_element() =~ /^(attribute|comment)$/) {
        $text =~ s/\|/\\\|/g;    
        return ". q|$text|";
    }
    
#    return '' unless $e->{XSP_User_Root};
    
    return $text;
}

sub parse_start {
    my ($e, $tag, %attribs) = @_;
    
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
        $e->manage_text(0);
        return '{ my $elem = XML::XPath::Node::Element->new(q(' . $attribs{'name'} . '));' .
                '$parent->appendChild($elem, 1); $parent = $elem; }' . "\n";
    }
    elsif ($tag eq 'attribute') {
        return '{ my $attr = XML::XPath::Node::Attribute->new(q|' . $attribs{'name'} . '|, ""';
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
#        warn "expr: -2 = {", $e->{NodeStack}[-2]{NamespaceURI}, "}", $e->{NodeStack}[-2]{Name}, "\n";
        if (Apache::AxKit::Language::XSP::is_xsp_namespace($e->{NodeStack}[-2]{NamespaceURI})) {
            if (!$e->manage_text() || $e->{NodeStack}[-2]{Name} =~ /^(.*:)?content$/) {
                return <<'EOT';
{
    my $text = XML::XPath::Node::Text->new(do {
EOT
            }
            elsif ($e->{NodeStack}[-2]{Name} =~ /^(.*:)?logic$/) {
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
    elsif ($tag eq 'pi') {
    }
    elsif ($tag eq 'comment') {
        return '); $parent->appendChild($comment, 1); }' . "\n";
    }
    elsif ($tag eq 'text') {
        return '); $parent->appendChild($text, 1); }' . "\n";
    }
    elsif ($tag eq 'expr') {
        if (Apache::AxKit::Language::XSP::is_xsp_namespace($e->{NodeStack}[-2]{NamespaceURI})) {
            if (!$e->manage_text() || $e->{NodeStack}[-2]{Name} =~ /^(.*:)?content$/) {
                return <<'EOT';
});
    $parent->appendChild($text, 1); 
}
EOT
            }
            elsif ($e->{NodeStack}[-2]{Name} =~ /^(.*:)?logic$/) {
                return '}';
            }
        }
        else {
            return <<'EOT';
});
    $parent->appendChild($text, 1); 
}
EOT
        }
        return '}';
    }
    
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
    $self->{Handler}{NodeStack} = [ ];

    return $parser->parse($thing);
}

sub _handle_init {
    my ($self, $expat) = @_;

    my $document = { };
    push @{ $self->{Handler}{NodeStack} }, $document;
    $self->{Handler}->start_document( $document );
}

sub _handle_final {
    my ($self, $expat) = @_;

    my $document = pop @{ $self->{Handler}{NodeStack} };
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
                    Attributes => [ @attributes ] };

    push @{ $self->{Handler}{NodeStack} }, $element;
    $self->{Handler}->start_element( $element );
}

sub _handle_end {
    my $self = shift;

    my $element = $self->{Handler}{NodeStack}[-1];
    my $results = $self->{Handler}->end_element( $element );
    pop @{ $self->{InScopeNamespaceStack} };
    pop @{ $self->{Handler}{NodeStack} };
    return $results;
}

sub _handle_char {
    my ($self, $expat, $string) = @_;

    my $characters = { Data => $string };
    $self->{Handler}->characters( $characters );
}

sub _handle_comment {
    my ($self, $expat, $data) = @_;

    my $comment = { Data => $data };
    $self->{Handler}->comment( $comment );
}

sub _handle_proc {
    my ($self, $expat, $target, $data) = @_;

    my $pi = {  Target => $target,
                Data => $data };
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

1;

__END__
=pod

=head1 NAME

Apache::AxKit::Language::XSP - eXtensible Server Pages

=head1 DESCRIPTION

XSP implements a tag-based dynamic language that allows you to develop
your own tags, examples include sendmail and sql taglibs.

=head1 DESIGN PATTERNS

Writing your own taglibs can be tricky, because you're using an event
based API to write out Perl code. These patterns represent the things
you may want to achieve when authoring a tag library.

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
