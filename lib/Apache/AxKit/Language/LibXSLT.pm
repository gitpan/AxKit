# $Id: LibXSLT.pm,v 1.20.2.1 2003/07/28 22:51:19 matts Exp $

package Apache::AxKit::Language::LibXSLT;

use strict;
use vars qw/@ISA $VERSION %DEPENDS/;
use XML::LibXSLT 1.30;
use XML::LibXML;
use Apache;
use Apache::Request;
use Apache::AxKit::Language;
use Apache::AxKit::Provider;
use Apache::AxKit::LibXMLSupport;
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
    local($XML::LibXML::match_cb, $XML::LibXML::open_cb,
          $XML::LibXML::read_cb, $XML::LibXML::close_cb);
    Apache::AxKit::LibXMLSupport->reset();
    warn("parser match_cb: ", $parser->match_callback);
    local $Apache::AxKit::LibXMLSupport::provider_cb = 
        sub {
            my $r = shift;
            my $provider = Apache::AxKit::Provider->new_content_provider($r);
            add_depends($provider->key());
            return $provider;
        };

    if (!$xml_doc && !$xmlstring) {
        $xml_doc = $xml->get_dom();
    } 
    elsif ($xmlstring) {
        $xml_doc = $parser->parse_string($xmlstring, $r->uri());
    }

    $xml_doc->process_xinclude();
    
    AxKit::Debug(7, "[LibXSLT] parsing stylesheet");

    my $stylesheet;
    my $cache = $style_cache{$style->key()};
    if (ref($cache) eq 'HASH' && !$style->has_changed($cache->{mtime}) && ref($cache->{depends}) eq 'ARRAY') {
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
        reset_depends();
        my $style_uri = $style->apache_request->uri();
        AxKit::Debug(7, "[LibXSLT] parsing stylesheet $style_uri");
        my $style_doc = $style->get_dom();
        
        local($XML::LibXML::match_cb, $XML::LibXML::open_cb,
            $XML::LibXML::read_cb, $XML::LibXML::close_cb);
        Apache::AxKit::LibXMLSupport->reset();
        local $Apache::AxKit::LibXMLSupport::provider_cb = 
            sub {
                my $r = shift;
                my $provider = Apache::AxKit::Provider->new_style_provider($r);
                add_depends($provider->key());
                return $provider;
            };
    
        $stylesheet = XML::LibXSLT->parse_stylesheet($style_doc);
        
        unless ($r->dir_config('AxDisableXSLTStylesheetCache')) {
            $style_cache{$style->key()} = 
                { style => $stylesheet, mtime => time, depends => [ get_depends() ] };
        }
    }

    # get request form/querystring parameters
    my @params = fixup_params($class->get_params($r));

    AxKit::Debug(7, "[LibXSLT] performing transformation");

    my $results = $stylesheet->transform($xml_doc, @params);
    
    AxKit::Debug(7, "[LibXSLT] transformation finished, creating $results");
    
    if ($last_in_chain) {
        AxKit::Debug(8, "[LibXSLT] outputting to \$r");
        if ($XML::LibXSLT::VERSION >= 1.03) {
            my $encoding = $stylesheet->output_encoding;
            my $type = $stylesheet->media_type;
            $r->content_type("$type; charset=$encoding");
        }
        $stylesheet->output_fh($results, $r);
    }

    AxKit::Debug(7, "[LibXSLT] storing results in pnotes(dom_tree) ($r)");
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

1;
