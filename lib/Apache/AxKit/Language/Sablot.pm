# $Id: Sablot.pm,v 1.6 2000/05/28 07:49:05 matt Exp $

package Apache::AxKit::Language::Sablot;

use strict;
use vars qw/@ISA/;
use XML::Sablotron ':all';
use Apache::Constants;
use Apache;
use Apache::AxKit::Language;

@ISA = 'Apache::AxKit::Language';

sub handler {
	my $class = shift;
	my ($r, $xmlfile, $stylefile) = @_;

	my ($xmlstring);
	
	if (my $dom = $r->pnotes('dom_tree')) {
		$xmlstring = $dom->toString;
	}
	else {
		$xmlstring = $r->notes('xml_string');
	}
	
	my $results = '--';
	my $retcode;

	if ($xmlstring) {
		$retcode = SablotProcess("file://$stylefile", "arg:/b", "arg:/c",
				undef, ["b", $xmlstring], $results);
	}
	else {
		$retcode = SablotProcess("file://$stylefile", "file://$xmlfile", "arg:/c",
				undef, [], $results);
	}
	
	if ($retcode) {
		warn "Sablotron failed to process XML file '$xmlfile'\n";
		return DECLINED;
	}
	
	if (my $dom = $r->pnotes('dom_tree')) {
		$dom->dispose;
		delete $r->pnotes()->{'dom_tree'};
	}
	
	print $results;
	
	return OK;
}

1;
