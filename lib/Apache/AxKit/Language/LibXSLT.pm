# $Id: LibXSLT.pm,v 1.13 2002/06/04 07:52:17 matts Exp $

package Apache::AxKit::Language::LibXSLT;

use strict;
use vars qw/@ISA $VERSION %DEPENDS/;
use XML::LibXSLT 1.30;
use XML::LibXML;
use Apache;
use Apache::Request;
use Apache::AxKit::Language;
use Apache::AxKit::Provider;
use File::Basename qw(dirname);

@ISA = 'Apache::AxKit::Language';

$VERSION = 1.0; # this fixes a CPAN.pm bug. Bah!

my %style_cache;

sub reset_depends {
    %DEPENDS = ();
}

sub add_depends {
    $DEPENDS{shift()}++;
}

sub get_depends {
    return keys %DEPENDS;
}

sub handler {
    my $class = shift;
    my ($r, $xml, $style, $last_in_chain) = @_;
    
    my ($xmlstring, $xml_doc);
    
    AxKit::Debug(7, "[LibXSLT] getting the XML");
    
    if (my $dom = $r->pnotes('dom_tree')) {
        $xml_doc = $dom;
        delete $r->pnotes()->{'dom_tree'};
    }
    else {
        $xmlstring = $r->pnotes('xml_string');
    }
    
    my $parser = XML::LibXML->new();
    $parser->expand_entities(1);
    local $XML::LibXML::match_cb = \&match_uri;
    local $XML::LibXML::open_cb = \&open_content_uri;
    local $XML::LibXML::read_cb = \&read_uri;
    local $XML::LibXML::close_cb = \&close_uri;

    if (!$xml_doc && !$xmlstring) {
        eval {
            my $fh = $xml->get_fh();
            $xml_doc = $parser->parse_fh($fh, $r->uri());
        };
        if ($@) {
            $xmlstring = ${$xml->get_strref()};
            $xml_doc = $parser->parse_string($xmlstring, $r->uri());
        }
    } 
    elsif ($xmlstring) {
        $xml_doc = $parser->parse_string($xmlstring, $r->uri());
    }

    $xml_doc->process_xinclude();
    
    AxKit::Debug(7, "[LibXSLT] parsing stylesheet");

    my $stylesheet;
    my $cache = $style_cache{$style->key()};
    if ($cache && !$style->has_changed($cache->{mtime}) && ref($cache->{depends}) eq 'ARRAY') {
        AxKit::Debug(8, "[LibXSLT] checking if stylesheet is cached");
        my $changed = 0;
        DEPENDS:
        foreach my $depends (@{ $cache->{depends} }) {
            my $p = Apache::AxKit::Provider->new_style_provider($r, key => $depends);
            if ( $p->has_changed( $cache->{mtime} ) ) {
                $changed = 1;
                last DEPENDS;
            }
        }
        if (!$changed) {
            AxKit::Debug(7, "[LibXSLT] stylesheet cached");
            $stylesheet = $style_cache{$style->key()}{style};
        }
    }
    
    if (!$stylesheet || ref($stylesheet) ne 'XML::LibXSLT::Stylesheet') {
        my $style_doc;
        reset_depends();
        my $style_uri = $style->apache_request->uri();
        AxKit::Debug(7, "[LibXSLT] parsing stylesheet $style_uri");
        eval {
            my $fh = $style->get_fh();
            $style_doc = $parser->parse_fh($fh, $style_uri);
        };
        if ($@) {
            my $stylestring = $style->get_strref();
            $style_doc = $parser->parse_string($$stylestring, $style_uri);
        }
        
        local $XML::LibXML::open_cb = \&open_stylesheet_uri;
        
        $stylesheet = XML::LibXSLT->parse_stylesheet($style_doc);
        
        $style_cache{$style->key()} = 
                { style => $stylesheet, mtime => time, depends => [ get_depends() ] };
    }

    # get request form/querystring parameters
    my @params = fixup_params($class->get_params($r));

    AxKit::Debug(7, "[LibXSLT] performing transformation");

    my $results = $stylesheet->transform($xml_doc, @params);
    
    if ($last_in_chain && $XML::LibXSLT::VERSION >= 1.03) {
        my $encoding = $stylesheet->output_encoding;
        my $type = $stylesheet->media_type;
        $r->content_type("$type; charset=$encoding");
    }

    $stylesheet->output_fh($results, $r) if $last_in_chain;

    $r->pnotes('dom_tree', $results);

#         warn "LibXSLT returned $output \n";
#         print $stylesheet->output_string($results);
    return Apache::Constants::OK;

}

sub fixup_params {
    my @results;
    while (@_) {
        push @results, XML::LibXSLT::xpath_to_string(
                splice(@_, 0, 2)
                );
    }
    return @results;
}

sub match_uri {
    my $uri = shift;
    AxKit::Debug(8, "LibXSLT match_uri: $uri");
    return 1 if $uri =~ /^axkit:/;
    return $uri !~ /^\w+:/; # only handle URI's without a scheme
}

sub open_content_uri {
    my $uri = shift || './';
    AxKit::Debug(8, "LibXSLT open_content_uri: $uri");
    
    if ($uri =~ /^axkit:/) {
        return AxKit::get_axkit_uri($uri);
    }
    
    # create a subrequest, so we get the right AxKit::Cfg for the URI
    my $apache = AxKit::Apache->request;
    my $sub = $apache->lookup_uri($uri);
    local $AxKit::Cfg = Apache::AxKit::ConfigReader->new($sub);
    
    my $provider = Apache::AxKit::Provider->new_content_provider($sub);
    
    add_depends($provider->key());
    my $str = $provider->get_strref;
    
    undef $provider;
    undef $apache;
    undef $sub;
    
    return $$str;
}

sub open_stylesheet_uri {
    my $uri = shift || './';
    AxKit::Debug(8, "LibXSLT open_stylesheet_uri: $uri");
    
    if ($uri =~ /^axkit:/) {
        return AxKit::get_axkit_uri($uri);
    }
    
    # create a subrequest, so we get the right AxKit::Cfg for the URI
    my $apache = AxKit::Apache->request;
    my $sub = $apache->lookup_uri($uri);
    local $AxKit::Cfg = Apache::AxKit::ConfigReader->new($sub);
    
    my $provider = Apache::AxKit::Provider->new_style_provider($sub);
    
    add_depends($provider->key());
    my $str = $provider->get_strref;
    
    undef $provider;
    undef $apache;
    undef $sub;
    
    return $$str;
}

sub close_uri {
}

sub read_uri {
    return substr($_[0], 0, $_[1], "");
}

1;