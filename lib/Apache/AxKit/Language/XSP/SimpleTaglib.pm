# $Id: SimpleTaglib.pm,v 1.7 2003/01/29 01:35:50 jwalt Exp $
# Apache::AxKit::XSP::Language::SimpleTaglib - alternate taglib helper code
package Apache::AxKit::Language::XSP::SimpleTaglib;
require 5.006;
use strict;
use Apache::AxKit::Language::XSP;
eval { require WeakRef; };
use attributes;
$Apache::AxKit::Language::XSP::SimpleTaglib::VERSION = 0.1;
@Apache::AxKit::Language::XSP::SimpleTaglib::ISA = ('Apache::AxKit::Language::XSP');

# utility functions

sub makeSingleQuoted($) { $_ = shift; s/([\\%])/\\$1/g; 'q%'.$_.'%'; }
sub _makeAttributeQuoted(@) { $_ = join(',',@_); s/([\\()])/\\\1/g; '('.$_.')'; }
sub makeVariableName($) { $_ = shift; s/[^a-zA-Z0-9]/_/g; $_; }

# perl attribute handlers

my %handlerAttributes;

use constant PLAIN => 0;
use constant EXPR => 1;
use constant EXPRORNODE => 2;
use constant NODE => 3;
use constant EXPRORNODELIST => 4;
use constant NODELIST => 5;
use constant STRUCT => 6;

# Memory leak ahead! The '&' construct may create circular references, which perl
# can't clean up. But this has only an effect if a taglib is reloaded, which shouldn't
# happen on production machines. Moreover, '&' is rather unusual.
# If you have the WeakRef module installed, this warning does not apply.
sub parseChildStructSpec {
    my ($specs, $refs) = @_;
    for my $spec ($_[0]) {
        my $result = {};
        while (length($spec)) {
            (my ($type, $token, $next) = ($spec =~ m/^([\&\@\*\$]?)([^ {}]+)(.|$)/))
                 || die("childStruct specification invalid. Parse error at: '$spec'");
            substr($spec,0,length($token)+1+($type?1:0)) = '';
            #warn("type: $type, token: $token, next: $next");
            my ($realtoken, $params);
            if ((($realtoken,$params) = ($token =~ m/^([^\(]+)((?:\([^ \)]+\))+)$/))) {
                my $i = 0;
                $token = $realtoken;
                $$result{$token}{'param'} = { map { $_ => $i++ } ($params =~ m/\(([^ )]+)\)/g) };
            }
            if ($type eq '&') {
                ($$result{$token} = $$refs{$token})
                    || die("childStruct specification invalid. '&' reference not found.");
                die("childStruct specification invalid. '&' cannot be used on '*' nodes.")
                    if ($$result{$token}{'type'} eq '*');
                die("childStruct specification invalid. '&' may only take a reference.")
                    if $$result{'param'};
                eval { WeakRef::weaken($$result{$token}) };
                return $result if (!$next || $next eq '}');
                next;
            }
            $$result{$token}{'type'} = $type || '$';
            die("childStruct specification invalid. '*' cannot be used with '{'.")
                if ($next eq '{' and $type eq '*');
            $$result{''}{'name'} = $token if ($type eq '*');
            $$result{$token}{'name'} = $token;
            return $result if (!$next || $next eq '}');
            ($$result{$token}{'sub'} = parseChildStructSpec($spec, { %$refs, $token => $$result{$token} })) || return undef if $next eq '{';
        }
        return $result;
    }
}

sub serializeChildStructSpec {
    my ($struct, $refs) = @_;
    my $result = '';
    my $first = 1;
    foreach my $token (keys %$struct) {
        next unless length($token);
        $result .= ' ' unless $first;
        undef $first;
        if (exists $$refs{$$struct{$token}}) {
            $result .= '&'.$token;
            next;
        }
        $result .= $$struct{$token}{'type'};
        $result .= $token;
        if (exists $$struct{$token}{'param'}) {
            my %keys = reverse %{$$struct{$token}{'param'}};
            $result .= '('.join(')(',@keys{0..(scalar(%keys)-1)}).')'
        }
        $result .= '{'.serializeChildStructSpec($$struct{$token}{'sub'},{ %$refs, $$struct{$token} => undef }).'}'
            if exists $$struct{$token}{'sub'};
    }
    return $result;
}

sub MODIFY_CODE_ATTRIBUTES {
    my ($pkg,$sub,@attr) = @_;
    my @rest;
    $handlerAttributes{$sub} ||= {};
    my $handlerAttributes = $handlerAttributes{$sub};
    foreach my $a (@attr) {
        #warn("attr: $a");
        my ($attr,$param) = ($a =~ m/([^(]*)(?:\((.*)\))?$/);
        $param = eval "q($param)";
        my @param = split(/,/,$param);

        if ($attr eq 'expr') {
            $$handlerAttributes{'result'} = EXPR;
        } elsif ($attr eq 'node') {
            $$handlerAttributes{'result'} = NODE;
            $$handlerAttributes{'nodename'} = $param[0] || 'value';
        } elsif ($attr eq 'exprOrNode') {
            $$handlerAttributes{'result'} = EXPRORNODE;
            $$handlerAttributes{'nodename'} = $param[0] || 'value';
            $$handlerAttributes{'resultparam'} = $param[1] || 'as';
            $$handlerAttributes{'resultnode'} = $param[2] || 'node';
        } elsif ($attr eq 'nodelist') {
            $$handlerAttributes{'result'} = NODELIST;
            $$handlerAttributes{'nodename'} = $param[0] || 'value';
        } elsif ($attr eq 'exprOrNodelist') {
            $$handlerAttributes{'result'} = EXPRORNODELIST;
            $$handlerAttributes{'nodename'} = $param[0] || 'value';
            $$handlerAttributes{'resultparam'} = $param[1] || 'as';
            $$handlerAttributes{'resultnode'} = $param[2] || 'node';
        } elsif ($attr eq 'struct') {
            $$handlerAttributes{'result'} = STRUCT;
            $$handlerAttributes{'namespace'} = $param[0];
        } elsif ($attr eq 'nodeAttr') {
            my %namespace;
            while (@param > 1) {
                my ($ns, $prefix, $name) = parse_namespace($param[0]);
                $namespace{$prefix} = $ns if $ns and $prefix;
                $param[0] = "{$namespace{$prefix}}$prefix:$name" if $prefix;
                $$handlerAttributes{'resultattr'}{$param[0]} = $param[1];
                shift @param; shift @param;
            }
        } elsif ($attr eq 'attrib') {
            foreach my $param (@param) {
                $$handlerAttributes{'attribs'}{$param} = undef;
            }
        } elsif ($attr eq 'child') {
            foreach my $param (@param) {
                $$handlerAttributes{'children'}{$param} = undef;
            }
        } elsif ($attr eq 'attribOrChild') {
            foreach my $param (@param) {
                $$handlerAttributes{'attribs'}{$param} = undef;
                $$handlerAttributes{'children'}{$param} = undef;
            }
        } elsif ($attr eq 'childStruct') {
            my $spec = $param[0];
            #warn("parsing $spec");
            $spec =~ s/\s+/ /g;
            $spec =~ s/ ?([{}]) ?/$1/g;
            $$handlerAttributes{'struct'} = parseChildStructSpec($spec,{});
            #warn("parsed $param[0], got ".serializeChildStructSpec($$handlerAttributes{'struct'}));
            die("childStruct parse error") unless $$handlerAttributes{'struct'};
        } elsif ($attr eq 'keepWhitespace') {
            $$handlerAttributes{'keepWS'} = 1;
        } elsif ($attr eq 'captureContent') {
            $$handlerAttributes{'capture'} = 1;
        } else {
            push @rest, $a;
        }
    }
    return @rest;
}

sub FETCH_CODE_ATTRIBUTES {
    my ($pkg,$sub) = @_;
    my @attr;
    my $handlerAttributes = $handlerAttributes{$sub};
    if (exists $$handlerAttributes{'result'}) {
        if ($$handlerAttributes{'result'} == NODELIST) {
            push @attr, 'nodelist'._makeAttributeQuoted($$handlerAttributes{'nodename'});
        } elsif ($$handlerAttributes{'result'} == EXPRORNODELIST) {
            push @attr, 'exprOrNodelist'._makeAttributeQuoted($$handlerAttributes{'nodename'},$$handlerAttributes{'resultparam'},$$handlerAttributes{'resultnode'});
        } elsif ($$handlerAttributes{'result'} == NODE) {
            push @attr, 'node'._makeAttributeQuoted($$handlerAttributes{'nodename'});
        } elsif ($$handlerAttributes{'result'} == EXPRORNODE) {
            push @attr, 'exprOrNode'._makeAttributeQuoted($$handlerAttributes{'nodename'},$$handlerAttributes{'resultparam'},$$handlerAttributes{'resultnode'});
        } elsif ($$handlerAttributes{'result'} == EXPR) {
            push @attr, 'expr';
        } elsif ($$handlerAttributes{'result'} == STRUCT) {
            push @attr, 'struct';
            $attr[-1] .= _makeAttributeQuoted($$handlerAttributes{'namespace'})
              if defined $$handlerAttributes{'namespace'};
        }
    }
    push @attr, 'nodeAttr'._makeAttributeQuoted(%{$$handlerAttributes{'resultattr'}}) if $$handlerAttributes{'resultattr'};
    push @attr, 'keepWhitespace' if $$handlerAttributes{'keepWS'};
    push @attr, 'captureContent' if $$handlerAttributes{'capture'};

    push @attr, 'childStruct'._makeAttributeQuoted(serializeChildStructSpec($$handlerAttributes{'struct'},{}))
        if ($$handlerAttributes{'struct'});

    my (@attribs, @children, @both);
    foreach my $param (keys %{$$handlerAttributes{'attribs'}}) {
        if (exists $$handlerAttributes{'children'}{$param}) {
            push @both, $param;
        } else {
            push @attribs, $param;
        }
    }
    foreach my $param (keys %{$$handlerAttributes{'children'}}) {
        if (!exists $$handlerAttributes{'attribs'}{$param}) {
            push @children, $param;
        }
    }
    push @attr, 'attrib'._makeAttributeQuoted(@attribs) if @attribs;
    push @attr, 'child'._makeAttributeQuoted(@children) if @children;
    push @attr, 'attribOrChild'._makeAttributeQuoted(@both) if @both;
    return @attr;
}

sub import {
    my $pkg = caller;
    #warn("making $pkg a SimpleTaglib");
    {
        no strict 'refs';
        *{$pkg.'::Handlers::MODIFY_CODE_ATTRIBUTES'} = \&MODIFY_CODE_ATTRIBUTES;
        *{$pkg.'::Handlers::FETCH_CODE_ATTRIBUTES'} = \&FETCH_CODE_ATTRIBUTES;
        push @{$pkg.'::ISA'}, 'Apache::AxKit::Language::XSP::SimpleTaglib';

    }
    return undef;
}

# companions to start_expr

sub start_expr {
    my $e = shift;
    my $cur = $e->{Current_Element};
    my $rc = $e->start_expr(@_);
    $e->{Current_Element} = $cur;
    return $rc;
}

sub start_elem {
    my ($e, $nodename, $attribs, $default_prefix, $default_ns) = @_;
    my($ns, $prefix, $name) = parse_namespace($nodename);
    #$prefix = $e->generate_nsprefix($ns) if $ns and not $prefix;
    if (not defined $ns and not defined $prefix) {
        $ns = $default_ns; $prefix = $default_prefix;
    }
    $name = $prefix.':'.$name if $prefix;
    if ($ns) {
        $e->append_to_script('{ my $elem = $document->createElementNS('.makeSingleQuoted($ns).','.makeSingleQuoted($name).');');
    }
    else {
        $e->append_to_script('{ my $elem = $document->createElement('.makeSingleQuoted($name).');');
    }
    $e->append_to_script('$parent->appendChild($elem); $parent = $elem; }' . "\n");
    if ($attribs) {
        while (my ($key, $value) = each %$attribs) {
            start_attr($e, $key); $e->append_to_script('.'.$value); end_attr($e);
        }
    }
    $e->manage_text(0);
}

sub end_elem {
    my ($e) = @_;
    $e->append_to_script('$parent = $parent->getParentNode;'."\n");
}

sub start_attr {
    my ($e, $attrname, $default_prefix, $default_ns) = @_;
    my($ns, $prefix, $name) = parse_namespace($attrname);
    #$prefix = $e->generate_nsprefix($ns) if $ns and not $prefix;
    if (not defined $ns and not defined $prefix) {
        $ns = $default_ns; $prefix = $default_prefix;
    }
    $name = $prefix.':'.$name if $prefix;

    if ($ns and defined $prefix) {
        $e->append_to_script('$parent->setAttributeNS('.makeSingleQuoted($ns).','.makeSingleQuoted($name).', ""');
    }
    else {
        $e->append_to_script('$parent->setAttribute('.makeSingleQuoted($name).', ""');
    }
    $e->manage_text(0);
}

sub end_attr {
    my ($e) = @_;
    $e->append_to_script(');'."\n");
}

# global variables
# FIXME - put into $e (are we allowed to?)

my %structStack = ();
my %frame = ();
my @globalframe = ();
my $structStack;

# generic tag handler subs

sub set_attribOrChild_value__open {
    my ($e, $tag) = @_;
    $globalframe[0]{'capture'} = 1;
    return '$attr_'.makeVariableName($tag).' = ""';
}

sub set_attribOrChild_value : keepWhitespace {
    return '; ';
}

sub set_childStruct_value__open {
    my ($e, $tag, %attribs) = @_;
    my $var = '$_{'.makeSingleQuoted($tag).'}';
    if ($$structStack[0][0]{'param'} && exists $$structStack[0][0]{'param'}{$tag}) {
        $e->append_to_script('.do { $param_'.$$structStack[0][0]{'param'}{$tag}.' = ""');
        $globalframe[0]{'capture'} = 1;
        return '';
    }
    my $desc = $$structStack[0][0]{'sub'}{$tag};
    unshift @{$$structStack[0]},$desc;
    if ($$desc{'param'}) {
        $e->append_to_script("{ \n");
        foreach my $key (keys %{$$desc{'param'}}) {
            $_ = $$desc{'param'}{$key};
            $e->append_to_script("my \$param_$_; ");
            $e->append_to_script("\$param_$_ = ".makeSingleQuoted($attribs{$key}).'; ')
                if exists $attribs{$key};
        }
        $e->append_to_script('local ($_) = ""; ');
        $var = '$_';
    }
    if ($$desc{'type'} eq '@') {
        $e->append_to_script("$var ||= []; push \@{$var}, ");
    } else {
        $e->append_to_script("$var = ");
    }
    if ($$desc{'sub'}) {
        $e->append_to_script('do {');
        $e->append_to_script('local (%_) = (); ');
        foreach my $attrib (keys %attribs) {
            next if $$desc{'sub'}{$attrib}{'type'} eq '%';
            $e->append_to_script('$_{'.makeSingleQuoted($attrib).'} = ');
            $e->append_to_script('[ ') if $$desc{'sub'}{$attrib}{'type'} eq '@';
            $e->append_to_script(makeSingleQuoted($attribs{$attrib}));
            $e->append_to_script(' ]') if $$desc{'sub'}{$attrib}{'type'} eq '@';
            $e->append_to_script('; ');
        }
        my $textname = $$desc{'sub'}{''}{'name'};
        if ($textname) {
            $e->append_to_script(' $_{'.makeSingleQuoted($textname).'} = ""');
            $globalframe[0]{'capture'} = 1;
        }
    } else {
        $e->append_to_script('""');
        $globalframe[0]{'capture'} = 1;
    }
    return '';
}

sub set_childStruct_value {
    my ($e, $tag) = @_;
    if ($$structStack[0][0]{'param'} && exists $$structStack[0][0]{'param'}{$tag}) {
        $e->append_to_script('; }');
        return '';
    }
    my $desc = $$structStack[0][0];
    shift @{$$structStack[0]};
    if ($$desc{'sub'}) {
        $e->append_to_script(' \%_; }; ');
    }
    if ($$desc{'param'}) {
        my $var = '$_{'.makeSingleQuoted($tag).'}';
        for (0..(scalar(%{$$desc{'param'}})-1)) {
            $var .= "{\$param_$_}";
        }
        if ($$desc{'type'} eq '@') {
            $e->append_to_script("$var ||= []; push \@{$var}, \@{\$_};");
        } else {
            $e->append_to_script("$var = \$_;");
        }
        $e->append_to_script(" }\n");
    }
    return '';
}

# code called from compiled XSP scripts
sub parse_namespace {
    local( $_ ) = shift;

    # These forms will return ns and prefix as follows:
    # *1.  {ns}prefix:name => ns specified, prefix specified (fully specified)
    # *2a. {ns}name        => ns specified, prefix undefined (generate prefix)
    #  2b. {ns}:name       => ns specified, prefix undefined (generate prefix)
    # *3a. prefix:name     => ns undefined, prefix specified (lookup ns)
    #  3b. {}prefix:name   => ns undefined, prefix specified (lookup ns)
    # *4a. {}name          => ns is '',     prefix is ''     (no ns)
    #  4b. {}:name         => ns is '',     prefix is ''     (no ns)
    #  4c. :name           => ns is '',     prefix is ''     (no ns)
    # *5.  name            => ns undefined, prefix undefined (default ns)
    # The canonical forms are starred.
    # (Note that neither a ns of '0' nor a prefix of '0' is allowed;
    # they will be treated as empty strings.)

    # The following tests can be used:
    # if $ns and $prefix                         => fully specified
    # if $ns and not $prefix                     => generate prefix
    # if not $ns and $prefix                     => lookup ns
    # if not $ns and defined $ns                 => no ns
    # if not defined $ns and not defined $prefix => default ns

    # This pattern match will almost give the desired results:
    my ($ns, $prefix, $name) = m/^(?:{(.*)})? (?:([^:]*):)? (.*)$/x;

    # These cases are fine with the pattern match:
    # 1.  {ns}prefix:name => ns specified, prefix specified
    # 2a. {ns}name        => ns specified, prefix undefined
    # 3a. prefix:name     => ns undefined, prefix specified
    # 4b. {}:name         => ns is '',     prefix is ''
    # 5.  name            => ns undefined, prefix undefined

    # These cases need to be adjusted:

    # 2b. {ns}:name       => ns specified, prefix ''        <= actual result
    # 2b. {ns}:name       => ns specified, prefix undefined <= desired result
    $prefix = undef if $ns and not $prefix;

    # 3b. {}prefix:name   => ns '',        prefix specified <= actual result
    # 3b. {}prefix:name   => ns undefined, prefix specified <= desired result
    $ns = undef if not $ns and $prefix;

    # 4a. {}name,         => ns is '',     prefix undefined <= actual result
    # 4a. {}name,         => ns is '',     prefix is ''     <= desired result
    $prefix = '' if not $prefix and defined $ns and $ns eq '';

    # 4c. :name           => ns undefined, prefix is ''     <= actual result
    # 4c. :name           => ns is '',     prefix is ''     <= desired result
    $ns = '' if not $ns and defined $prefix and $prefix eq '';

    ($ns, $prefix, $name);
}

sub _lookup_prefix {
    my ($ns, $namespaces) = @_;
    my $i = 0;
    foreach my $namespace (@$namespaces) {
        my ($nsprefix, $nsuri) = @$namespace;
        ++$i;
        next unless $nsuri eq $ns;
        #$nsprefix = "stlns$i" if $nsprefix eq '' and $nsuri ne '';
        return $nsprefix;
    }
    #return "stlns$i";
    return "";
}

sub _lookup_ns {
    my ($prefix, $namespaces) = @_;
    $prefix ||= '';
    my $i = 0;
    foreach my $namespace (@$namespaces) {
        my ($nsprefix, $nsuri) = @$namespace;
        #++$i;
        next unless $nsprefix eq $prefix;
        #$nsprefix = "stlns$i" if $nsprefix eq '' and $nsuri ne '';
        return wantarray ? ($nsuri, $nsprefix) : $nsuri;
    }
    my ($nsprefix, $nsuri) = @{$namespaces->[-1]}; # default namespace
    return wantarray ? ($nsuri, $nsprefix) : $nsuri;
}


sub xmlize {
    my ($document, $parent, $namespaces, @data) = @_;
    foreach my $data (@data) {
        if (UNIVERSAL::isa($data,'XML::LibXML::Document')) {
            $data = $data->getDocumentElement();
        }
        if (UNIVERSAL::isa($data,'XML::LibXML::Node')) {
            $document->importNode($data);
            $parent->appendChild($data);
            next;
        }
        die 'data is not a hash ref or DOM fragment!' unless ref($data) eq 'HASH';
        while (my ($key, $val) = each %$data) {
            my $outer_namespaces_added = 0;
            if (substr($key,0,1) eq '@') {
                $key = substr($key,1);
                die 'attribute value is not a simple scalar!' if ref($val);
                next if $key =~ m/^xmlns(?::|$)/; # already processed these
                my ($ns, $prefix, $name) = parse_namespace($key);
                #$prefix = _lookup_prefix($ns, $namespaces) if $ns and not $prefix;
                $ns = _lookup_ns($prefix, $namespaces) if not $ns and $prefix;
                $name = $prefix.':'.$name if $prefix;
                if ($ns and $prefix) {
                    $parent->setAttributeNS($ns,$name,$val);
                } else {
                    $parent->setAttribute($name,$val);
                }
                next;
            }

            my ($ns, $prefix, $name) = parse_namespace($key);
            $prefix = _lookup_prefix($ns, $namespaces) if $ns and not $prefix;
            if (defined $ns) {
                unshift @$namespaces, [ $prefix => $ns ];
                $outer_namespaces_added++;
            }
            my @data = ref($val) eq 'ARRAY'? @$val:$val;
            foreach my $data (@data) {
                my $namespaces_added = 0;
                if (ref($data) and ref($data) eq 'HASH') {
                    # search for namespace declarations in attributes
                    while (my ($key, $val) = each %$data) {
                        if ($key =~ m/^\@xmlns(?::|$)(.*)/) {
                            unshift @$namespaces, [ $1 => $val ];
                            $namespaces_added++;
                        }
                    }
                }

                my $elem;
                if (length($key)) {
                    my($nsuri, $nsprefix, $local) = ($ns, $prefix, $name);
                    ($nsuri, $nsprefix) = _lookup_ns($nsprefix, $namespaces) if not defined $nsuri;
                    $local = $nsprefix.':'.$local if $nsprefix;
                    if ($nsuri) {
                        $elem = $document->createElementNS($nsuri,$local);
                    } else {
                        $elem = $document->createElement($local);
                    }
                    $parent->appendChild($elem);
                } else {
                    $elem = $parent;
                }

                if (ref($data)) {
                    xmlize($document, $elem, $namespaces, $data);
                } else {
                    my $tn = $document->createTextNode($data);
                    $elem->appendChild($tn);
                }
                splice(@$namespaces, 0, $namespaces_added) if $namespaces_added; # remove added namespaces
            }
            splice(@$namespaces, 0, $outer_namespaces_added) if $outer_namespaces_added; # remove added namespaces
        }
    }
}

# event handlers

sub characters {
    my ($e, $node) = @_;
    my $text = $node->{'Data'};
    if ($globalframe[0]{'ignoreWS'}) {
        $text =~ s/^\s*//;
        $text =~ s/\s*$//;
    }
    return '' if $text eq '';
    return '.'.makeSingleQuoted($text);
}

sub start_element
{
    my ($e, $element) = @_;
    my %attribs = map { $_->{'Name'} => $_->{'Value'} } @{$element->{'Attributes'}};
    my $tag = $element->{'Name'};
    #warn("Element: ".join(",",map { "$_ => ".$$element{$_} } keys %$element));
    my $ns = $element->{'NamespaceURI'};
    my $frame = ($frame{$ns} ||= []);
    $structStack = ($structStack{$ns} ||= []);
    my $pkg = $Apache::AxKit::Language::XSP::tag_lib{$ns}."::Handlers";
    my ($sub, $subOpen);
    my $attribs = {};
    #warn("full struct: ".serializeChildStructSpec($$structStack[0][$#{$$structStack[0]}]{'sub'})) if $$structStack[0];
    #warn("current node: ".$$structStack[0][0]{'name'}) if $$structStack[0];
    #warn("rest struct: ".serializeChildStructSpec($$structStack[0][0]{'sub'})) if $$structStack[0];
    if ($$structStack[0][0]{'param'} && exists $$structStack[0][0]{'param'}{$tag}) {
        $sub = \&set_childStruct_value;
        $subOpen = \&set_childStruct_value__open;
    } elsif ($$structStack[0][0]{'sub'} && exists $$structStack[0][0]{'sub'}{$tag}) {
        if ($$structStack[0][0]{'sub'}{$tag}{'sub'}) {
            foreach my $key (keys %{$$structStack[0][0]{'sub'}{$tag}{'sub'}}) {
                $$attribs{$key} = $attribs{$key} if exists $attribs{$key};
            }
        }
        if ($$structStack[0][0]{'sub'}{$tag}{'param'}) {
            foreach my $key (keys %{$$structStack[0][0]{'sub'}{$tag}{'param'}}) {
                $$attribs{$key} = $attribs{$key} if exists $attribs{$key};
            }
        }
        $sub = \&set_childStruct_value;
        $subOpen = \&set_childStruct_value__open;
    } else {
        for my $i (0..$#{$frame}) {
            if (exists $$frame[$i]{'vars'}{$tag}) {
                #warn("variable: $tag");
                $sub = \&set_attribOrChild_value;
                $subOpen = \&set_attribOrChild_value__open;
                last;
            }
        }
        if (!$sub) {
            my @backframes = (reverse(map{ ${$_}{'name'} } @{$frame}),$tag);
            #warn("frames: ".@$frame.", backframes: ".join(",",@backframes));
            while (@backframes) {
                my $longtag = join('___', @backframes);
                shift @backframes;
                #warn("checking for $longtag");
                if ($sub = $pkg->can(makeVariableName($longtag))) {
                    $subOpen = $pkg->can(makeVariableName($longtag)."__open");
                    last;
                }
            }
        }
    }
    die "invalid tag: $tag (namespace: $ns, package $pkg, parents ".join(", ",map{ ${$_}{'name'} } @{$frame}).")" unless $sub;

    my $handlerAttributes = $handlerAttributes{$sub};

    if ($$handlerAttributes{'result'} == STRUCT || !$$handlerAttributes{'result'} ||
        $$handlerAttributes{'result'} == NODELIST ||
        ($$handlerAttributes{'result'} == EXPRORNODELIST &&
         $attribs{$$handlerAttributes{'resultparam'}} eq
         $$handlerAttributes{'resultnode'})) {

        # FIXME: this can give problems with non-SimpleTaglib-taglib interaction
        # it must autodetect whether to use '.do' or not like xsp:expr, but as
        # that one doesn't work reliably neither, it probably doesn't make any
        # difference
        $e->append_to_script('.') if ($globalframe[0]{'capture'});
        $e->append_to_script('do { ');

    } elsif ($$handlerAttributes{'result'} == NODE ||
        ($$handlerAttributes{'result'} == EXPRORNODE
        && $attribs{$$handlerAttributes{'resultparam'}} eq
        $$handlerAttributes{'resultnode'})) {

        $e->append_to_script('.') if ($globalframe[0]{'capture'});
        $e->append_to_script('do { ');
        start_elem($e,$$handlerAttributes{'nodename'},$$handlerAttributes{'resultattr'},$element->{'Prefix'},$ns);
        start_expr($e,$tag);
    } else {
        $e->append_to_script('.') if ($globalframe[0]{'capture'} && $element->{Parent}->{Name} =~ /^(.*:)?(logic|expr)$/);
        start_expr($e,$tag);
    }

    foreach my $attrib (keys %{$$handlerAttributes{'attribs'}}) {
        $$attribs{$attrib} = $attribs{$attrib}
            unless exists $$handlerAttributes{'children'}{$attrib};
    }
    $$attribs{$$handlerAttributes{'resultparam'}} = $attribs{$$handlerAttributes{'resultparam'}}
        if $$handlerAttributes{'resultparam'};

    unshift @{$frame}, {};
    unshift @globalframe,{};
    $$frame[0]{'attribs'} = $attribs;
    $globalframe[0]{'ignoreWS'} = !$$handlerAttributes{'keepWS'};
    $globalframe[0]{'capture'} = $$handlerAttributes{'capture'};
    $globalframe[0]{'pkg'} = $pkg;
    $globalframe[0]{'ns'} = $pkg;
    $$frame[0]{'name'} = $tag;
    $$frame[0]{'sub'} = $sub;
    if ($$handlerAttributes{'struct'}) {
        unshift @{$structStack}, [{ 'sub' => $$handlerAttributes{'struct'}, 'name' => $tag }];
        $$frame[0]{'struct'} = 1;
        $e->append_to_script('local(%_) = (); ');
    }

    $e->append_to_script('my ($attr_'.join(', $attr_',map { makeVariableName($_) } keys %{$$handlerAttributes{'children'}}).'); ')
        if $$handlerAttributes{'children'} && %{$$handlerAttributes{'children'}};
    foreach my $var (keys %{$$handlerAttributes{'children'}}) {
        next unless exists $attribs{$var};
        $e->append_to_script('$attr_'.makeVariableName($var).' = '.makeSingleQuoted($attribs{$var}).'; ');
    }
    $$frame[0]{'vars'} = $$handlerAttributes{'children'};

    $e->append_to_script($subOpen->($e,$tag,%$attribs)) if $subOpen;

    if ($$handlerAttributes{'capture'}) {
        $e->append_to_script('local($_) = ""');
        $e->{'Current_Element'}->{'SimpleTaglib_SavedNS'} = $e->{'Current_Element'}->{'NamespaceURI'};
        $e->{'Current_Element'}->{'NamespaceURI'} = $ns;
    }

    return '';
}

sub end_element {
    my ($e, $element) = @_;

    my $tag = $element->{'Name'};
    my $ns = $element->{'NamespaceURI'};
    my $frame = $frame{$ns};
    $structStack = $structStack{$ns};
    my $pkg = $Apache::AxKit::Language::XSP::tag_lib{$ns}."::Handlers";
    my $longtag;
    my $sub = $$frame[0]{'sub'};
    die "invalid closing tag: $tag (namespace: $ns, package $pkg, sub ".makeVariableName($tag).")" unless $sub;
    my $handlerAttributes = $handlerAttributes{$sub};

    if ($globalframe[0]{'capture'}) {
        $e->append_to_script('; ');
    }

    if ($$handlerAttributes{'result'}) {
        $e->append_to_script(' my @_res = do {');
    }

    my $attribs = $$frame[0]{'attribs'};
    shift @{$structStack} if $$frame[0]{'struct'};
    shift @{$frame};
    shift @globalframe;
    $e->append_to_script($sub->($e, $tag, %{$attribs}));

    if (defined $e->{'Current_Element'}->{'SimpleTaglib_SavedNS'}) {
        $e->{'Current_Element'}->{'NamespaceURI'} = $e->{'Current_Element'}->{'SimpleTaglib_SavedNS'};
        delete $e->{'Current_Element'}->{'SimpleTaglib_SavedNS'};
    }

    if ($$handlerAttributes{'result'} == NODELIST ||
        ($$handlerAttributes{'result'} == EXPRORNODELIST
         && $$attribs{$$handlerAttributes{'resultparam'}} eq
         $$handlerAttributes{'resultnode'})) {

        $e->append_to_script('}; foreach my $_res (@_res) {');
        start_elem($e,$$handlerAttributes{'nodename'},$$handlerAttributes{'resultattr'},$element->{'Prefix'},$ns);
        start_expr($e,$$handlerAttributes{'nodename'});
        $e->append_to_script('$_res');
        $e->end_expr();
        end_elem($e);
        $e->append_to_script("} ");
        $e->append_to_script('""; ') if ($globalframe[0]{'capture'});
        $e->append_to_script("};\n");
    } elsif ($$handlerAttributes{'result'} == NODE ||
        ($$handlerAttributes{'result'} == EXPRORNODE
         && $$attribs{$$handlerAttributes{'resultparam'}} eq
         $$handlerAttributes{'resultnode'})) {

        $e->append_to_script('}; ');
        $e->append_to_script('join("",@_res);');
        $e->end_expr($tag);
        end_elem($e);
        if ($globalframe[0]{'capture'}) {
            $e->append_to_script("\"\"; }\n");
        } else {
            $e->append_to_script(" };\n");
        }
    } elsif ($$handlerAttributes{'result'} == STRUCT) {
        $e->append_to_script('}; ');
        my ($nsuri, $nsprefix);
        if (not $$handlerAttributes{'namespace'}) {
            $nsuri = $ns;
            $nsprefix = $element->{'Prefix'};
        }
        elsif ($$handlerAttributes{'namespace'} =~ m/^{(.*)}([^:]*):?$/) {
            # "{ns}prefix:", "{ns}prefix", "{ns}:", "{ns}", "{}:", "{}"
            ($nsuri, $nsprefix) = ($1, $2);
            $nsprefix = '' unless $nsuri; # assume "{}prefix" meant "{}"
            #$nsprefix = $e->generate_nsprefix($nsuri) if $nsuri and not $nsprefix;
        }
        else {
            # "ns", '""', "''"
            $nsuri = $$handlerAttributes{'namespace'};
            $nsuri = '' if $nsuri eq '""' or $nsuri eq "''";
            #$nsprefix = $e->generate_nsprefix($nsuri) if $nsuri;
            $nsprefix = '';
        }
        if (Apache::AxKit::Language::XSP::is_xsp_namespace($element->{'Parent'}->{'NamespaceURI'})) {
            if (!$e->manage_text() || $element->{'Parent'}->{'Name'} =~ /^(.*:)?content$/) {
                $e->append_to_script('Apache::AxKit::Language::XSP::SimpleTaglib::xmlize($document,$parent,[['.makeSingleQuoted($nsprefix).'=>'.makeSingleQuoted($nsuri).']],@_res); ');
            } else {
                $e->append_to_script('eval{if (wantarray) { @_res; } else { join("",@_res); }}');
            }
        } else {
            $e->append_to_script('Apache::AxKit::Language::XSP::SimpleTaglib::xmlize($document,$parent,[['.makeSingleQuoted($nsprefix).'=>'.makeSingleQuoted($nsuri).']],@_res); ');
        }
        if ($globalframe[0]{'capture'}) {
            $e->append_to_script("\"\"; }\n");
        } else {
            $e->append_to_script(" };\n");
        }
    } elsif ($$handlerAttributes{'result'}) {
        $e->append_to_script('}; eval{if (wantarray) { @_res; } else { join("",@_res); }} ');
        $e->end_expr();
    } else {
        if ($globalframe[0]{'capture'}) {
            $e->append_to_script("\"\"; }\n");
        } else {
            $e->append_to_script(" };\n");
        }
    }
    #warn('script len: '.length($e->{XSP_Script}).', end tag: '.$tag);
    return '';
}

1;

__END__

=pod

=head1 NAME

Apache::AxKit::XSP::Language::SimpleTaglib - alternate XSP taglib helper

=head1 SYNOPSIS

    package Your::XSP::Package;
    use Apache::AxKit::Language::XSP::SimpleTaglib;

    ... more initialization stuff, start_document handler, utility functions, whatever
	you like, but no parse_start/end handler needed - if in doubt, just leave empty ...

    package Your::XSP::Package::Handlers;

    sub some_tag : attrib(id) attribOrChild(some-param) node(result) keepWhitespace {
        my ($e, $tag, %attr) = @_;
        return 'do_something($attr_some_param,'.$attr{'id'}.');';
    }


=head1 DESCRIPTION

This taglib helper allows you to easily write tag handlers with most of the common
behaviours needed. It manages all 'Design Patterns' from the XSP man page plus
several other useful tag styles.

=head2 Simple handler subs

A tag "<yourNS:foo>" will trigger a call to sub "foo" during the closing tag event.
What happens in between can be configured in many ways
using Perl function attributes. In the rare cases where some action has to happen during
the opening tag event, you may provide a sub "foo__open" (double underscore)
which will be called at the appropriate time. Usually you would only do that for 'if'-
style tags which enclose some block of code.

It is important to understand that your tag handler is called during the XSP parse stage,
when the XSP script is being constructed. Therefore, it is the responsibility of the
handler to return a I<Perl code fragment> to be appended to the XSP script, as shown
above. Contrast this behaviour to TaglibHelper, where the handler is called when the XSP
script is being run, and it returns I<data> to be included in the XML output.

=head2 Context sensitive handler subs

A sub named "foo___bar" (triple underscore) gets called on the following XML input:
"<yourNS:foo><yourNS:bar/></yourNS:foo>". Handler subs may have any nesting depth.
The rule for opening tag handlers applies here as well. The sub name must represent the
exact tag hierarchy (within your namespace).

=head2 Names, parameters, return values

Names for subs and variables get created by replacing any non-alphanumeric characters in the
original tag or attribute to underscores. For example, 'get-id' becomes 'get_id'.

The called subs get passed 3 parameters: The parser object, the tag name, and an
attribute hash. This hash only contains XML attributes declared using the 'attrib()' Perl
function attribute. (Try not to confuse these two meanings of 'attribute' - unfortunately
XML and Perl both call them that way.) The other declared parameters get converted into
local variables with prefix 'attr_', or, in the case of 'childStruct', converted into the
'%_' hash. These local variables are only available inside your code fragment which
becomes part of the XSP script, unlike the attribute hash which is passed directly to
your handler as the third parameter.

If a sub has an output attribute ('node', 'expr', etc.), the code fragment will be run
in list context. If necessary, returned lists get converted to scalars by joining them
without separation. Code fragments from plain subs (without an output attribute) inherit
their context and have their return value left unmodified.

=head2 Precedence

If more than one handler matches a tag, the following rules determine which one is chosen.
Remember, though, that only tags in your namespace are considered.

=over 4

=item 1.

If the innermost tag has a 'childStruct' spec which matches, the internal childStruct
handler takes precedence.

=item 2.

Otherwise, if any surrounding tag has a matching 'child' or 'attribOrChild'
attribute, the internal handler for the innermost matching tag gets chosen.

=item 3.

Otherwise, the handler sub with the deepest tag hierarchy gets called.

=back

=head2 Utility functions

Apache::AxKit::Language::XSP contains a few handy utility subs to help build your code fragment:

=over 4

=item start_elem, end_elem, start_attr, end_attr

these create elements and attributes
in the output document. Call them just like you call start_expr and end_expr.

=item makeSingleQuoted

given a scalar as input, it returns a scalar which yields
the exact input value when evaluated; handy when using unknown text as-is in code fragments.

=item makeVariableName

creates a valid, readable perl identifier from arbitrary input text.
The return values might overlap.

=back

=head1 PERL ATTRIBUTES

Perl function attributes are used to define how XML output should be generated from your
code fragment and how XML input should be presented to your handler.  Note that
parameters to attributes get handled as if 'q()' enclosed them (explicit quote marks are
not needed). Furthermore, commas separate parameters (except for childStruct), so a
parameter cannot contain a comma.

=head2 Output attributes

Choose none or one of these to select output behaviour.

=head3 C<expr>

Makes this tag behave like an '<xsp:expr>' tag, creating text nodes or inline text as appropriate.
Choose this if you create plain text which may be used everywhere, including inside code. This
attribute has no parameters.

=head3 C<node(name)>

Makes this tag create an XML node named C<name>. The tag encloses all content as well as the
results of the handler sub.
Choose this if you want to create one XML node with all your output.

=head3 C<nodelist(name)>

Makes this tag create a list of XML nodes named C<name>. The tag(s) do not enclose content nodes,
which become preceding siblings of the generated nodes. The return value gets converted to a
node list by enclosing each element with an XML node named C<name>.
Choose this if you want to create a list of uniform XML nodes with all your output.

=head3 C<exprOrNode(name,attrname,attrvalue)>

Makes this tag behave described under either 'node()' or 'expr', depending on the value of
XML attribute C<attrname>. If that value matches C<attrvalue>, it will work like 'node()',
otherwise it will work like 'expr'. C<attrname> defaults to 'as', C<attrvalue> defaults to
'node', thus leaving out both parameters means that 'as="node"' will select 'node()' behaviour.
Choose this if you want to let the XSP author decide what to generate.

=head3 C<exprOrNodelist(name,attrname,attrvalue)>

Like exprOrNode, selecting between 'expr' and 'nodelist()' behaviour.

=head3 C<struct>

Makes this tag create a more complex XML fragment. You may return a single hashref or an array
of hashrefs, which get converted into an XML structure. Each hash element may contain a scalar,
which gets converted into an XML tag with the key as name and the value as content. Alternatively,
an element may contain an arrayref, which means that an XML tag encloses each single array element.
Finally, you may use hashrefs in place of scalars to create substructures. To create attributes on
tags, use a hashref that contain the attribute names prefixed by '@'. A '' (empty
string) as key denotes the text contents of that node.

You can also use a XML::LibXML::Document or XML::LibXML::Node object in place of a hashref. You
can, for example, simply return an XML::LibXML::Document object and it gets inserted at the current
location. You may also return an array of documents/nodes, and you may even mix plain hashrefs
with DOM objects as you desire.

In an expression context, passes on the unmodified return value.

=head2 Other output attributes

These may appear more than once and modify output behaviour.

=head3 C<nodeAttr(name,expr,...)>

Adds an XML attribute named C<name> to all generated nodes. C<expr> gets evaluated at run time.
Evaluation happens once for each generated node. Of course, this tag only makes sense with
'node()' type handlers.

=head2 Input attributes

These tags specify how input gets handled. Most may appear more than once, if that makes sense.

=head3 C<attrib(name,...)>

Declares C<name> as a (non-mandatory) XML attribute. All attributes declared this way get
passed to your handler sub in the attribute hash (the third argument to your handler).

=head3 C<child(name,...)>

Declares a child tag C<name>. It always lies within the same namespace as the taglib itself. The
contents of the tag, if any, get saved in a local variable named $attr_C<name> and made
available to your code fragment. If the child tag appears more than once, the last value
overrides any previous value.

=head3 C<attribOrChild(name,...)>

Declares an attribute or child tag named C<name>. A variable is created just like for 'child()',
containing the attribute or child tag contents. If both appear, the contents of the child tag take
precedence.

=head3 C<keepWhitespace>

Makes this tag preserve contained whitespace.

=head3 C<captureContent>

Makes this tag store the enclosed content in '$_' for later retrieval in your code fragment instead
of adding it to the enclosing element. Non-text nodes will not work as expected.

=head3 C<childStruct(spec)>

Marks this tag to take a complex XML fragment as input. The resulting data structure is available
as %_ in your code fragment. Whitespace is always preserved.

C<spec> has the following syntax:

=over 4

=item 1.

A C<spec> consists of a list of tag names, separated by whitespace (not commas!).

=item 2.

Tags may appear in any order.

=item 3.

A tag name prefixed by '@' may appear more than once in the XML document. A tag
name prefixed by '$' or without any prefix may only appear once.

=item 4.

If a '{' follows a tag name, that tag has child tags. A valid C<spec> and a
closing '}' must follow.

=item 5.

A tag name prefixed by '*' does not indicate an input tag but specifies the name
for the text contents of the surrounding tag in the resulting data structure. Such a tag name may
not bear a '{...}' block.

=item 6.

Any tag without child tags may also appear as attribute of the parent tag.

=item 7.

A tag name followed by one or more parameter specs in parentheses means a hash
gets created with the value of the corresponding attribute (or child tag) as key. This usage does
not forbid appending a '{...}' block, which would result in a nested hash.

=item 8.

A tag name prefixed by '&' denotes a recursive structure. The tag name must appear
as the name of one of the surrounding '{...}'-blocks. The innermost matching block gets chosen.

=back

Example:

Given the following handler sub:

    set_permission : childStruct(add{@permission{$type *name} $target $comment(lang)(day)} remove{@permission{$type *name} $target})

and the following XML as input:

    <set-permission>
        <add>
            <permission type="user">
                foo
            </permission>
            <permission>
                <type>group</type>
                bar
            </permission>
            <target>/test.html</target>
            <comment lang="en" day="Sun">Test entry</comment>
            <comment lang="en" day="Wed">Test entry 2</comment>
            <comment><lang>de</lang>Testeintrag</comment>
        </add>
        <remove target="/test2.html">
            <permission type="user">
                baz
            </permission>
        </remove>
    </set-permission>

then the local variable '%_' will be made available to your code fragment (returned by
your set_permission handler sub).  It will be initialized like this:

    %_ = (
        add => {
            permission => [
                { type => "user", name => 'foo' },
                { type => "group", name => 'bar' },
            ],
            target => '/test.html',
            comment => {
                'en' => { 'Sun' => 'Test entry', 'Wed' => 'Test entry 2' },
                'de' => { '' => 'Testeintrag' },
            }
        },
        remove => {
            permission => [
                { type => "user", name => 'baz' },
            ],
            target => '/test2.html',
        },
    );


=head1 XML NAMESPACES

By default, all output element nodes are placed in the same namespace
as the tag library.  To specify a different namespace or no namespace,
the desired namespace can be placed within curly braces before the
node name in an output attribute:

  {namespaceURI}name

To specify a prefix, place it after the namespace:

  {namespaceURI}prefix:name

For example, to create an XML node named C<otherNS:name> and associate
the prefix 'otherNS' with the namespace 'http://mydomain/NS/other/v1':

  node({http://mydomain/NS/other/v1}otherNS:name)

To create an XML node with no namespace, use an empty namespace:

  node({}name)

This notation for specifying namespaces can also be used in the
C<struct> output attribute.  Alternatively, the standard "xmlns" XML
attribute may be used to specify namespaces.  For example, the
following are equivalent:

  sub sample_struct : struct {
    return "{ '{http://mydomain/NS/other/v1}otherNS:name' => 'value' }";
  }

  sub sample_struct : struct {
    return q{{
        'otherNS:name' =>
        { '@xmlns:otherNS' => 'http://mydomain/NS/other/v1',
          '' => 'value' }
    }};
  }

Namespace scoping in the hashref is patterned after XML documents.
You may refer to previously declared namespaces by using the same
prefix, and you may override previously declared namespaces with new
declarations (either with the curly-braced notation or by using
"xmlns" XML attributes).

To specify a default namespace for all unqualified node names in the
hashref, state it as a parameter to the C<struct> output attribute:

  struct(namespaceURI)

You may also specify a prefix:

  struct({namespaceURI}prefix)

For example, the following is equivalent to the previous example:

  sub sample_struct : struct({http://mydomain/NS/other/v1}otherNS) {
    return "{ 'name' => 'value' }";
  }

To turn off the default namespace for all node names, use an empty
namespace:

  sub sample_struct : struct({}) {
    return "{ 'name' => 'value' }";
  }

By default, XML attributes created with the C<nodeAttr> output
attribute are not in a namespace.  The curly-braced notation can be
used to specify a namespace.  For example:

  nodeAttr({http://www.w3.org/TR/REC-html40}html:href,'http://www.axkit.org/')

If you are specifying more than one attribute in the same namespace,
you can refer to previously declared namespaces by using the same
prefix:

  nodeAttr({http://www.w3.org/TR/REC-html40}html:href,'http://www.axkit.org/',html:class,'link')

A prefix is required to associate a namespace with an attribute. Default namespaces
(those without a prefix) do not apply to attributes and are ignored.


=head1 EXAMPLES

Refer to the Demo tag libraries included in the AxKit distribution and look at the source
code of AxKit::XSP::Sessions and AxKit::XSP::Auth for full-featured examples.

=head1 BUGS AND HINTS

=head2 Miscellaneous

Because of the use of perl attributes, SimpleTaglib will only work with Perl 5.6.0 or later.
This software is already tested quite well and works for a number of simple and complex
taglibs. Still, you may have to experiment with the attribute declarations, as the differences
can be quite subtle but decide between 'it works' and 'it doesn't'. XSP can be quite fragile if
you start using heavy trickery.

If some tags don't work as expected, try surrounding the offending tag with
<xsp:content>, this is a common gotcha (but correct and intended). If you find yourself needing
<xsp:expr> around a tag, please contact the author, as that is probably a bug.

If you use the '&' flag of childStruct and are reloading your taglib through Apache::StatINC or
a similar method, consider installing the 'WeakRef' module from CPAN to prevent memory leaks. If
you never use '&' or don't reload the taglib in the running server, this is not necessary.

TODO: to be fixed: childStruct currently does not allow hash keys to be child nodes, they must be attributes of their
parent node. For example, given childStruct(text(lang)), this is valid: <text lang="en">foo</text>
but this is not: <text><lang>en</lang>foo</text>

=head2 Request-time handler

TODO: This shall be enhanced in a future release.

If you pine for the TaglibHelper-style handlers that get called at request time, and you
do not need the flexibility of custom-generated code fragments provided by SimpleTaglib,
you can define a subroutine in your tag library to be called at request time instead of
at parse time.  Just place a call to your subroutine inside the code fragment returned by
your handler.  You can even pass it some request-time variables such as $r and $cgi.  For
example,

    package Your::XSP::Package;
    use Apache::AxKit::Language::XSP::SimpleTaglib;

    sub some_tag {
	my($r, $cgi, $some_param) = @_;
	# define code here to be run at request time
    }

    package Your::XSP::Package::Handlers;

    sub some_tag : attribOrChild(some-param) node(result) {
        'Your::XSP::Package::some_tag($r,$cgi,$attr_some_param);';
    }

=head2 Using attrib and childStruct together

TODO: to be fixed.

You may need a list-valued parameter to be specified by XML child tags for your tag
handler, but you also want the option that a single value can be passed in as an XML
attribute.  For example:

  <yourNS:some_tag>
    <yourNS:format>XML</yourNS:format>
    <yourNS:format>HTML</yourNS:format>
    <yourNS:format>PDF</yourNS:format>
  </yourNS:some_tag>

  <yourNS:some_tag format="XML"/>

The 'attribOrChild' Perl attribute will not suffice here because the child tag overwrites
the previous value each time instead of creating a list (format will be set to 'PDF').
What you need is a combination of 'attrib' and 'childStruct':

    sub some_tag : attrib(format) childStruct(@format) node(result) {
	my ($e, $tag, %attr) = @_;
	my $code = '';
	if ( defined $attr{format} ) {
	    my $quoted = Apache::AxKit::Language::XSP::makeSingleQuoted($attr{format});
	    $code .= '$_{format} = ' . $quoted . ' unless defined $_{format};';
	}
        $code .= 'Your::XSP::Package::some_tag($r,$cgi,%_);';
	$code;
    }

This technique can be generalized to support any number of parameters.  In your handler,
iterate over the '%attr' hash (defined by 'attrib') and merge the values into the '%_'
hash (defined by 'childStruct') inside your code fragment.  Remember that parameters
defined in the childStruct attribute are separated by spaces, not commas.

    sub some_tag : attrib(format,option) childStruct(@format @option) node(result) {
	my ($e, $tag, %attr) = @_;
        my $code = '';
	while ( my($key, $value) = each %attr ) {
	    next unless defined $value;
	    $value = Apache::AxKit::Language::XSP::makeSingleQuoted($value);
	    $code .= "\$_{'_$key'} = $value unless defined \$_{'_$key'};\n"
	}
        $code .= 'Your::XSP::Package::some_tag($r,$cgi,%_);';
	$code;
    }

=head1 AUTHOR

Jörg Walter <jwalt@cpan.org>

=head1 COPYRIGHT

All rights reserved. This program is free software; you can redistribute it and/or
modify it under the same terms as AxKit itself.

=head1 SEE ALSO

AxKit, Apache::AxKit::Language::XSP, Apache::AxKit::Language::XSP::TaglibHelper

=cut
