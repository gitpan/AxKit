# $Id: XSLT.pm,v 1.10 2000/05/28 07:49:05 matt Exp $

package Apache::AxKit::Language::XSLT;

use strict;
use XML::XSLT;
use Apache::Constants;
use Apache::AxKit::Language;

use vars qw/@ISA/;

@ISA = 'Apache::AxKit::Language';

sub handler {
	my $class = shift;
	my ($r, $xmlfile, $stylefile) = @_;

#	warn "Parsing stylefile '$stylefile'\n";
	my $parser = XML::XSLT->new($stylefile, "FILE");

	if (my $dom_tree = $r->pnotes('dom_tree')) {
#		warn "Parsing dom_tree: ", $dom_tree->toString, "\n";
		$parser->transform_document($dom_tree, "DOM");
	}
	elsif (my $xml = $r->notes('xml_string')) {
#		warn "Parsing string:\n$xml\n";
		$parser->transform_document($xml, "STRING");
	}
	else {
#		warn "Parsing file '$xmlfile'\n";
		$parser->transform_document($xmlfile, "FILE");
	}

	if (my $dom = $r->pnotes('dom_tree')) {
		$dom->dispose;
		delete $r->pnotes()->{'dom_tree'};
	}
	
	$r->pnotes('dom_tree', $parser->result_tree());
	
	# hack to not dispose our results tree
	delete $parser->{result};
	
	$parser->dispose();

	return OK;
}

1;
