# $Id: XSLT.pm,v 1.6 2000/05/10 21:22:19 matt Exp $

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

	$r->content_type('text/html');
	$r->content_encoding('utf-8');

	if ($r->pnotes('dom_tree')) {
		$XSLT::Parser->open_project(
			$r->pnotes('dom_tree'),
			$stylefile,
			"DOM", "FILE"
		);
	}
	elsif (my $xml = $r->notes('xml_string')) {
		$XSLT::Parser->open_project($xmlfile, $stylefile, "STRING", "FILE");
	}
	else {
		$XSLT::Parser->open_project($xmlfile, $stylefile, "FILE", "FILE");
	}

	$XSLT::Parser->process_project();
	
	if (my $dom = $r->pnotes('dom_tree')) {
		$dom->dispose;
	}

	$r->pnotes('dom_tree', $XSLT::result);

	return OK;
}

1;
