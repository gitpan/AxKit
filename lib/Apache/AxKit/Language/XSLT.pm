# $Id: XSLT.pm,v 1.14 2001/01/14 13:05:35 matt Exp $

package Apache::AxKit::Language::XSLT;

use strict;
use XML::XSLT;
use Apache::AxKit::Language;

use vars qw/@ISA/;

@ISA = 'Apache::AxKit::Language';

sub handler {
    my $class = shift;
    my ($r, $xml, $style) = @_;

#    warn "Parsing stylefile '$stylefile'\n";
    my $parser = XML::XSLT->new($style->get_strref(), "STRING");

    if (my $dom_tree = $r->pnotes('dom_tree')) {
#        warn "Parsing dom_tree: ", $dom_tree->toString, "\n";
        my $xml_string = $dom_tree->toString;
        delete $r->pnotes()->{'dom_tree'};
        $parser->transform_document($xml_string, "STRING");
    }
    elsif (my $xmlstr = $r->notes('xml_string')) {
#        warn "Parsing string:\n$xml\n";
        $parser->transform_document($xmlstr, "STRING");
    }
    else {
#        warn "Parsing file '$xmlfile'\n";
        $parser->transform_document($xml->get_strref(), "STRING");
    }

    $r->notes('xml_string', $parser->result_tree()->toString);
    
    $parser->dispose();
}

1;
