# $Id: XPathScript.pm,v 1.1 2002/01/13 20:45:11 matts Exp $

package Apache::AxKit::Language::XPathScript;

use strict;
use vars qw(@ISA $VERSION $stash );

use Apache;
use Apache::File;
use XML::XPath 1.00;
use XML::XPath::XMLParser;
use XML::XPath::Node;
use XML::XPath::NodeSet;
use XML::Parser;
use Apache::AxKit::Provider;
use Apache::AxKit::Language;
use Apache::AxKit::Cache;
use Apache::AxKit::Exception;
use Apache::AxKit::CharsetConv;

@ISA = 'Apache::AxKit::Language';

$VERSION = '0.05';

sub handler {
    my $class = shift;
    my ($r, $xml_provider, $style_provider) = @_;
    
    my $xpath = XML::XPath->new();
    
    my $source_tree;
    
    my $xml_parser = XML::Parser->new(
            ErrorContext => 2,
            Namespaces => $XML::XPath::VERSION < 1.07 ? 1 : 0,
            ParseParamEnt => 1,
            );
    
    my $parser = XML::XPath::XMLParser->new(parser => $xml_parser);
    
    local $Apache::AxKit::Language::XPathScript::local_ent_handler;
    
    if (my $entity_handler = $xml_provider->get_ext_ent_handler()) {
#        warn "XPathScript: setting entity_handler\n";
        $xml_parser->setHandlers(
                ExternEnt => $entity_handler,
                );
        $Apache::AxKit::Language::XPathScript::local_ent_handler = $entity_handler;
    }
    
    AxKit::Debug(6, "XPathScript: Getting XML Source");
    
    if (my $dom = $r->pnotes('dom_tree')) {
        # dom_tree is an XML::LibXML DOM
        $source_tree = $parser->parse($dom->toString);
        delete $r->pnotes()->{'dom_tree'};
    }
    elsif (my $xml = $r->pnotes('xml_string')) {
#        warn "Parsing from string : $xml\n";
        eval {
            $source_tree = $parser->parse($xml);
        };
        if ($@) {
            throw Apache::AxKit::Exception::Error(-text => "Parse of xml_string failed: $@");
        }
    }
    else {
        $source_tree = get_source_tree($xml_provider, $parser);
    }
    
    $xpath->set_context($source_tree);
    
    my $mtime = $style_provider->mtime();

    my $style_key = $style_provider->key();
    my $package = get_package_name($style_key);
    
    AxKit::Debug(6, "Checking stylesheet mtime: $mtime\n");
    if ($stash->{$style_key}
            && exists($stash->{$style_key}{mtime})
            && !$style_provider->has_changed($stash->{$style_key}{mtime})
            && check_inc_mtime($stash->{$style_key}{mtime}, $style_provider, $stash->{$style_key}{includes})) {
        # cached... just exec.
        AxKit::Debug(7, "Using stylesheet cache\n");
    }
    else {
        # recompile stylesheet.
        AxKit::Debug(6, "Recompiling stylesheet: $style_key\n");
        compile($package, $style_provider);
        $stash->{$style_key}{mtime} = get_mtime($class, $style_provider);
    }
    
    my $old_status = $r->status;
    
    no strict 'refs';
    my $cv = \&{"$package\::handler"};

    local $Apache::AxKit::Language::XPathScript::xp = $xpath;
    my $t = {};
    local $Apache::AxKit::Language::XPathScript::trans = $t;
    local $Apache::AxKit::Language::XPathScript::style_provider = $style_provider;
    
    AxKit::Debug(7, "Running XPathScript script\n");
    local $^W;
    eval {
        $cv->($r, $xpath, $t);
    };
    if ($@) {
        AxKit::Debug(1, "XPathScript error: $@");
        throw $@;
    }
    
    if (!$r->pnotes('xml_string') && 
        !$r->dir_config('XPSNoApplyTemplatesOnEmptyOutput')) { # no output? Try apply_templates
        print Apache::AxKit::Language::XPathScript::Toys::apply_templates();
    }
    
#    warn "Run\n";

    $Apache::AxKit::Language::XPathScript::xp = undef;
    $Apache::AxKit::Language::XPathScript::trans = undef;
    $Apache::AxKit::Language::XPathScript::style_provider = undef;
#    warn "Returning $old_status\n";
    return $r->status($old_status);
}

sub get_source_tree {
    my ($provider, $parser) = @_;
    my $source_tree;
    AxKit::Debug(7, "XPathScript: reparsing file");
    eval {
        my $fh = $provider->get_fh();
        # warn("parsing FH $fh with parser $parser\n");
        local $/;
        my $contents = <$fh>;
        # warn("FH contains: $contents\n");
        $source_tree = $parser->parse($contents);
        # warn("Parse completed\n");
        close($fh);
    };
    if ($@) {
        # warn("parse_fh failed\n");
        $source_tree = $parser->parse(${ $provider->get_strref() });
    }

    # warn("get_source_tree = $source_tree\n");
    return $source_tree;
}

sub check_inc_mtime {
    my ($mtime, $provider, $includes) = @_;
    
    for my $inc (@$includes) {
#        warn "Checking mtime for $inc\n";
        my $inc_provider = Apache::AxKit::Provider->new(
                AxKit::Apache->request, 
                uri => $inc,
                rel => $provider,
                );
        if ($inc_provider->has_changed($mtime)) {
#            warn "$inc newer (" . $inc_provider->mtime() . ") than last compile ($mtime) causing recompile\n";
            return;
        }
    }
    return 1;
}

sub extract {
    my ($provider,$scalar_output) = @_;
    
    my $contents;
    eval { 
        my $fh = $provider->get_fh();
        local $/;
        $contents = <$fh>;
    };
    if ($@) {
        $contents = ${ $provider->get_strref() };
    }
    
    my $r = AxKit::Apache->request();
    if (my $charset = $r->dir_config('XPathScriptCharset')) {
        
        AxKit::Debug(8, "XPS: got charset: $charset");
        
        my $map = Apache::AxKit::CharsetConv->new($charset, "utf-8") || die "No such charset: $charset";
        $contents = $map->convert($contents);
    }
    
    my $key = $provider->key();
    $stash->{$key}{includes} = [];
    
    AxKit::Debug(10, "XPathScript: extracting from '$key' contents: $contents\n");
    
    my $script;
    
    my $line = 1;
    
    while ($contents =~ /\G(.*?)(<!--\#include|<%=?)/gcs) {
        my ($text, $type) = ($1, $2);
        $line += $text =~ tr/\n//;
        $text =~ s/\|/\\\|/g;
        if($scalar_output) {
            $script .= "\$__OUTPUT.=q|$text|;";
        } else {
            $script .= "print q|$text|;";
        }
        $script .= "\n#line $line $key\n";
        if ($type eq '<%=') {
            $contents =~ /\G(.*?)%>/gcs || die "No terminating '%>' after line $line ($key)";
            my $perl = $1;
            if(!$scalar_output) {
                $script .= "print(do { $perl });\n";
            } else {
                $script .= "\$__OUTPUT.=join('',(do { $perl }));\n";
            }
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
            
            AxKit::Debug(10, "About to include file $params{file}");
            $script .= include_file($params{file}, $provider, $scalar_output);
            AxKit::Debug(10, "include done");
        }
        else {
            $contents =~ /\G(.*?)%>/gcs || die "No terminating '%>' after line $line ($key)";
            my $perl = $1;
            $perl =~ s/;?$/;/s; # add on ; if its missing. As in <% $foo = 'Hello' %>
            $script .= $perl;
            $line += $perl =~ tr/\n//;
        }
    }
    
    if ($contents =~ /\G(.*)/gcs) {
        my ($text) = ($1);
        $text =~ s/\|/\\\|/g;
        if ($scalar_output) {
            $script .= "\$__OUTPUT.=q|$text|;";
        } else {
            $script .= "print q|$text|;";
        }
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
    
    AxKit::Debug(10, "Compiling script:\n$eval\n");
    eval $eval;
    if ($@) {
        AxKit::Debug(1, "Compilation failed: $@");
        throw $@;
    }
}

sub include_file {
    my ($filename, $provider, $script_output) = @_;

    # return if already included
    my $key = $provider->key();
    return '' if grep {$_ eq $filename} @{$stash->{$key}{includes}};
    
    push @{$stash->{$key}{includes}}, $filename;
    
    my $inc_provider = Apache::AxKit::Provider->new(
            AxKit::Apache->request,
            uri => $filename,
            rel => $provider,
            );
    
    return extract($inc_provider, $script_output);
}

sub XML::XPath::Function::document {
    # warn "Document function called\n";
    return unless $Apache::AxKit::Language::XPathScript::local_ent_handler;
    my $self = shift;
    my ($node, @params) = @_;
    die "document: Function takes 1 parameter\n" unless @params == 1;

    my $xml_parser = XML::Parser->new(
            ErrorContext => 2,
            Namespaces => $XML::XPath::VERSION < 1.07 ? 1 : 0,
            # ParseParamEnt => 1,
            );

    my $parser = XML::XPath::XMLParser->new(parser => $xml_parser);

    my $results = XML::XPath::NodeSet->new();
    my $uri = $params[0];
    my $newdoc;
    if ($uri =~ /^\w\w+:/) { # assume it's scheme://foo uri
        eval {
            # warn "Trying to parse $params[0]\n";
            $newdoc = $parser->parse(
                    $Apache::AxKit::Language::XPathScript::local_ent_handler->(
                        undef, undef, $uri
                    )
                );
            # warn "Parsed OK into $newdoc\n";
        };
        if (my $E = $@) {
            if ($E->isa('Apache::AxKit::Exception::IO')) {
                AxKit::Debug(2, $E);
            }
            else {
                throw Apache::AxKit::Exception::Error(-text => "Parse of '$uri' failed: $E");
            };
        }
    }
    else {
        # warn("Parsing local: $uri\n");
        my $provider = Apache::AxKit::Provider->new(
                    AxKit::Apache->request, 
                    uri => $uri,
                );
        $newdoc = get_source_tree($provider, $parser);
    }

    $results->push($newdoc) if $newdoc;
    return $results;
}

sub get_mtime {
    my $class = shift;
    my ($provider) = @_;
#    warn "get_mtime\n";
    my $mtime = $provider->mtime();
    my $filename = $provider->key();
#    warn "mtime: $filename = $mtime\n";
    if (!$stash->{$filename}) {
        # compile stylesheet
        compile(get_package_name($filename), $provider);
    
        $stash->{$filename}{mtime} = $mtime;
        return 0;
    }

    for my $inc (@{$stash->{$filename}{includes}}) {
        my $inc_provider = Apache::AxKit::Provider->new(
                AxKit::Apache->request, 
                uri => $inc,
                rel => $provider,
                );
        
#        warn "Checking mtime of $inc\n";
        if ($inc_provider->has_changed($mtime)) {
            $mtime = $inc_provider->mtime();
        }
    }
    
#    warn "returning $mtime\n";
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
    use Apache::AxKit::Exception;

    use vars '@ISA', '@EXPORT';
    use Exporter;
    @ISA = ('Exporter');
    @EXPORT = qw(
            findnodes 
            findvalue
            findvalues
            findnodes_as_string
            apply_templates
            matches
            set_namespace
            import_template
            DO_SELF_AND_KIDS
            DO_SELF_ONLY
            DO_NOT_PROCESS
            );
    
    sub DO_SELF_AND_KIDS () { return 1; }
    sub DO_SELF_ONLY () { return -1; }
    sub DO_NOT_PROCESS () { return 0; }
    sub MAX_DEPTH () { return 32; }
    
    sub import_template {
        my ($filename, $local_changes) = @_;
        my ($script) = Apache::AxKit::Language::XPathScript::include_file($filename,$Apache::AxKit::Language::XPathScript::style_provider, 1);
        # changes may be local to this imported template, or global (default).
        my ($setup_t);
        if ($local_changes) {
            $setup_t = 'local $Apache::AxKit::Language::XPathScript::trans = clone($Apache::AxKit::Language::XPathScript::trans);';
        }
        
        $script = join('',
                     'use strict;',
                     'sub { ',
                     'my ($node, $real_local_t) = @_;',
                     'local $Apache::AxKit::Language::XPathScript::xp = $node;',
                     $setup_t,
                     'my ($t) = $Apache::AxKit::Language::XPathScript::trans;',
                     'my ($__OUTPUT);',
                     $script,';',
                     '$real_local_t->{pre} = $__OUTPUT;',
                     'return -1;',
                     '}');
        return eval($script);
    }

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
    
    sub set_namespace {
        eval {
            $Apache::AxKit::Language::XPathScript::xp->set_namespace(@_);
        };
        if ($@) {
            AxKit::Debug(3, "set_namespace failed: $@");
        }
    }
    
    # quieten warnings when compiling this module
    sub apply_templates (;$@);
    
    sub apply_templates (;$@) {
        unless (@_) {
            return apply_templates(findnodes('/'));
        }
        
        my ($arg1, @args) = @_;

        if (!ref($arg1)) {
            # called with a path to find
#            warn "apply_templates with path '$arg1'\n";
            $arg1 = findnodes($arg1, @args);
#            return apply_templates($nodes);
        }
        
        my $retval = '';
        if (ref($arg1) eq "HASH") {
#            warn "apply_templates with a hash\n";
            local $Apache::AxKit::Language::XPathScript::trans = $arg1;
            return apply_templates(@args);
        } 
        elsif ($arg1->isa('XML::XPath::NodeSet')) {
#            warn "apply_templates with a NodeSet\n";
            foreach my $node ($arg1->get_nodelist) {
                $retval .= translate_node($node);
            }
        }
        else {
#            warn "apply_templates with a list of " , 1 + @args, " nodes? : ", ref($arg1), "\n";
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
        
        if ($node->isTextNode) {
            my $trans = $translations->{'text()'};
            if (!$trans) { return $node->toString; }
            if (my $code = $trans->{testcode}) {
                my $t = {};
                my $retval = $code->($node, $t);
                if ($retval && %$t) {
                    foreach my $tkey (keys %$t) {
                        $trans->{$tkey} = $t->{$tkey};
                    }
                }
            }
            return $trans->{pre} . $node->toString . $trans->{post};
        }

        if (!$node->isElementNode) {
            # don't output top-level PI's
            if ($node->isPINode) {
                my $retstring = eval {
                    if ($node->getParentNode->getParentNode) {
                        return $node->toString;
                    }
                    return '';
                };
                
                return $retstring || '';
            }
            return $node->toString;
        }
        
#        warn "translate_node: ", $node->getName, "\n";
        
        my $node_name = $node->getName;

        my $trans = $translations->{$node_name};

        if (!$trans) {
            $node_name = '*';
            $trans = $translations->{$node_name};
        }
        
        if (!$trans) {
#            warn "Default trans\n";
            if (my @children = $node->getChildNodes) {
                return start_tag($node) . 
                    _apply_templates(@children) .
                    end_tag($node);
            }
            else {
                return empty_tag($node);
            }
        }
        
        local $^W;
        
        my $dokids = 1;
        my $search;
       my $testcode_output = 0;
        my $t = {};
        if ($trans->{testcode}) {
#            warn "eval testcode\n";
           $testcode_output = 1;
            my $result;
            my $testcode = $trans->{testcode};
            my $depth = 0;
            while (1) {
                $result = $testcode->($node, $t);
#                warn "Testcode returned: $result\n";
                if (defined($t->{testcode}) &&
                      ref($t->{testcode}) eq "CODE") {
                    if ($depth++ > MAX_DEPTH) {
                        die "Max Depth of ", MAX_DEPTH, " reached on testcode eval!";
                    }
                    $testcode = $t->{testcode};
                    $t = {};
                } else {
                    last;
                }
            }
            
#            warn "Here with $result\n";
            

            if ($result =~ /\D/) {
                $dokids = 0;
                $search = $result;
            }
            elsif ($result == DO_NOT_PROCESS) {
                # don't process anything.
                return;
            }
            elsif ($result == DO_SELF_ONLY) {
                # -1 means don't do children.
                $dokids = 0;
            }
            elsif ($result == DO_SELF_AND_KIDS) {
                # do kids
            }
#            warn "Here with dokids => $dokids, search => $search\n";
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
        my $pre = interpolate($node, $trans->{pre}, $testcode_output) . 
                ($trans->{showtag} ? start_tag($node) : '') .
                interpolate($node, $trans->{prechildren}, $testcode_output);
        
        my $post = interpolate($node, $trans->{postchildren}, $testcode_output) .
                ($trans->{showtag} ? end_tag($node) : '') .
                interpolate($node, $trans->{post}, $testcode_output);
        
        if ($dokids) {
            my $middle = '';
            for my $kid ($node->getChildNodes()) {
                if ($kid->isElementNode) {
                    $middle .= interpolate($node, $trans->{prechild}) .
                            _apply_templates($kid) .
                            interpolate($node, $trans->{postchild});
                }
                else {
                    $middle .= _apply_templates($kid);
                }
            }
            return $pre . $middle . $post;
        }
        elsif ($search) {
            my $middle = '';
            for my $kid (findnodes($search, $node)) {
                if ($kid->isElementNode) {
                    $middle .= interpolate($node, $trans->{prechild}) .
                            _apply_templates($kid) .
                            interpolate($node, $trans->{postchild});
                }
                else {
                    $middle .= _apply_templates($kid);
                }
            }
            return $pre . $middle . $post;
        }
        else {
            return $pre . $post;
        }
    }
    
    sub start_tag {
        my ($node) = @_;
        
        my $name = $node->getName;
        return '' unless $name;
        
        my $string = "<" . $name;
        
        foreach my $ns ($node->getNamespaceNodes) {
            $string .= $ns->toString;
        }
        
        foreach my $attr ($node->getAttributeNodes) {
            $string .= $attr->toString;
        }

        $string .= ">";
        
        return $string;
    }
    
    sub end_tag {
        my ($node) = @_;
        
        if (my $name = $node->getName) {
            return "</" . $name . ">";
        }
        else {
            return '';
        }
    }
    
    sub empty_tag {
        my ($node) = @_;
        
        my $name = $node->getName;
        return '' unless $name;
        
        my $string = "<" . $name;
        
        foreach my $ns ($node->getNamespaceNodes) {
            $string .= $ns->toString;
        }
        
        foreach my $attr ($node->getAttributeNodes) {
            $string .= $attr->toString;
        }

        $string .= " />";
        
        return $string;
    }        
    
    sub interpolate {
        my ($node, $string, $ignore) = @_;
        return $string if $XPathScript::DoNotInterpolate || $ignore;
        return $string unless AxKit::Apache->request->dir_config('AxXPSInterpolate');
        my $new = '';
        while ($string =~ m/\G(.*?)\{(.+?)\}/gcs) {
            my ($pre, $path) = ($1, $2);
            $new .= $pre;
            $new .= $node->findvalue($path);
        }
        $string =~ /\G(.*)/gcs;
        $new .= $1 if defined $1;
        return $new;
    }

    # make a clone, but copy subs.
    sub clone {
        my ($a) = @_;
        my ($b);
        if (ref($a) eq "HASH") {
            $b = {};
            foreach my $key (keys(%$a)) {        
                my ($copy) = clone($a->{$key});
                $b->{$key} = $copy;
            }
        }
        else {
            # copy as is
            $b = $a;
        }
        return $b;
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
XPathScript is now at http://axkit.org/docs/xpathscript/guide.dkb
in DocBook format.

=cut
