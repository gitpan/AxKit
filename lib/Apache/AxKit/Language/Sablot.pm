# $Id: Sablot.pm,v 1.3 2000/05/10 21:21:46 matt Exp $

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

	$r->content_type('text/html');
	$r->content_encoding('utf-8');
	
	my ($xmlstring, $stylestring);
	
	if (my $dom = $r->pnotes('dom_tree')) {
		$xmlstring = $dom->toString;
	}
	else {
		$xmlstring = $r->notes('xml_string');
	}
	
	my $stylefh = Apache->gensym();
	if (open($stylefh, $stylefile)) {
		flock($stylefh, 1);
		
		local $/;
		$stylestring = <$stylefh>;
		close $stylefh;
	}
	else {
		return DECLINED;
	}
	
	if (!$xmlstring) {
		my $xmlfh = Apache->gensym();
		
		if (open($xmlfh, $xmlfile)) {
			flock($xmlfh, 1);
			
			local $/;
			$xmlstring = <$xmlfh>;
			close $xmlfh;
		}
		else {
			return DECLINED;
		}
	}
	
	my $results;
	SablotProcessStrings($stylestring, $xmlstring, $results);
		
	print $results;
	
	return OK;
}

1;
