# $Id: XSLT.pm,v 1.2 2000/05/02 10:32:05 matt Exp $

package Apache::AxKit::Language::XSLT;

use strict;
use XML::XSLT;
use Apache::Constants;

sub handler {
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
	else {
		$XSLT::Parser->open_project($xmlfile, $stylefile);
	}

	$XSLT::Parser->process_project();

	$r->pnotes('dom_tree', $XSLT::results);

	return OK;
}

1;
