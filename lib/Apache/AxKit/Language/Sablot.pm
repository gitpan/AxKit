# $Id: Sablot.pm,v 1.8 2000/06/02 13:41:50 matt Exp $

package Apache::AxKit::Language::Sablot;

use strict;
use vars qw/@ISA/;
use XML::Sablotron ':all';
use Apache;
use Apache::AxKit::Language;

@ISA = 'Apache::AxKit::Language';

sub handler {
	my $class = shift;
	my ($r, $xml, $style) = @_;

	my ($xmlstring);
	
	if (my $dom = $r->pnotes('dom_tree')) {
		$xmlstring = $dom->toString;
		$dom->dispose;
		delete $r->pnotes()->{'dom_tree'};
	}
	else {
		$xmlstring = $r->notes('xml_string');
	}
	
	if (!$xmlstring) {
		$xmlstring = eval {${$xml->get_strref()}};
		if ($@) {
			my $fh = $xml->get_fh();
			local $/;
			$xmlstring = <$fh>;
		}
	}
	
	my $stylestring = eval {${$style->get_strref()}};
	
	my $results = '--';
	my $retcode;

	$retcode = SablotProcess("arg:/a", "arg:/b", "arg:/c",
				undef, ["a", $stylestring, "b", $xmlstring], $results);
	
	if ($retcode) {
		die "Sablotron failed to process XML file";
	}
	
	print $results;
}

1;
