# $Id: LibXSLT.pm,v 1.7 2001/05/29 10:19:43 matt Exp $

package Apache::AxKit::Language::LibXSLT;

use strict;
use vars qw/@ISA $CURRENT_REQUEST/;
use XML::LibXSLT 0.99;
use XML::LibXML;
use Apache;
use Apache::Request;
use Apache::AxKit::Language;
use Apache::AxKit::Provider;

@ISA = 'Apache::AxKit::Language';

sub handler {
    my $class = shift;
    my ($r, $xml, $style) = @_;
    
    $CURRENT_REQUEST = $r;

    my ($xmlstring);
    
    if (my $dom = $r->pnotes('dom_tree')) {
        $xmlstring = $dom->toString;
        delete $r->pnotes()->{'dom_tree'};
    }
    else {
        $xmlstring = $r->pnotes('xml_string');
    }
    
    if (!$xmlstring) {
        $xmlstring = eval {${$xml->get_strref()}};
        if ($@) {
            my $fh = $xml->get_fh();
            local $/;
            $xmlstring = <$fh>;
        }
    }

    my $stylestring = ${$style->get_strref()};

    my $parser = XML::LibXML->new(ext_ent_handler => \&open_uri);
    my $xslt = XML::LibXSLT->new();

    my $xml_doc = $parser->parse_string($xmlstring);
    my $style_doc = $parser->parse_string($stylestring);

    my $stylesheet = $xslt->parse_stylesheet($style_doc);


    # get request form/querystring parameters
    my @params;
    my $cgi = Apache::Request->instance($r);
    @params = map { $_ => $cgi->param($_) } $cgi->param;

    my $results = $stylesheet->transform($xml_doc, @params);
    
    if ($XML::LibXSLT::VERSION >= 1.03) {
        my $encoding = $stylesheet->output_encoding;
        my $type = $stylesheet->media_type;
        $r->content_type("$type; charset=$encoding");
    }

    $stylesheet->output_fh($results, $r);
     
    undef $CURRENT_REQUEST;
#         warn "LibXSLT returned $output \n";
#         print $stylesheet->output_string($results);
    
}

XML::LibXML->match_callback(\&match_uri);
XML::LibXML->open_callback(\&open_uri);
XML::LibXML->close_callback(\&close_uri);
XML::LibXML->read_callback(\&read_uri);

sub match_uri {
    my $uri = shift;
    warn("match: $uri\n");
    return $uri !~ /^\w+:/; # only handle URI's without a scheme
}

sub open_uri {
    my $uri = shift;
    warn("open: $uri\n");
    my $provider = Apache::AxKit::Provider->new(
            $CURRENT_REQUEST,
            uri => $uri,
            );
    my $str = $provider->get_strref;
    return $$str;
}

sub close_uri {
}

sub read_uri {
    return substr($_[0], 0, $_[1], "");
}

1;
