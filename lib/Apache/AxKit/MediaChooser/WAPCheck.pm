# $Id: WAPCheck.pm,v 1.2 2002/02/01 14:47:21 matts Exp $

package Apache::AxKit::MediaChooser::WAPCheck;

use strict;
use Apache::Constants qw(OK);

sub handler {
	my $r = shift;
	my $type;
	
#	warn "WAP Check on $ENV{HTTP_ACCEPT}\n";
#	warn " and $ENV{HTTP_USER_AGENT}\n";
	
	local $^W;
	
	if ($ENV{HTTP_ACCEPT} =~ /vnd.wap.wml/i) {
		$r->notes('preferred_media', 'handheld');
	}
	elsif (substr($ENV{HTTP_USER_AGENT},0,4) =~ 
			/(
			Noki
			| Eric
			| WapI
			| MC21 # cough spit hack ;-) (I used to work at Ericsson)
			| AUR\s
			| R380
			| UP.B
			| WinW
			| UPG1
			| upsi
			| QWAP
			| Jigs
			| Java
			| Alca
			| MITS
			| MOT-
			| My\sS
			| WAPJ
			| fetc
			| ALAV
			| Wapa
			)/x) {
#		warn "set media to handheld!\n";
		$r->notes('preferred_media', 'handheld');
	}
	
	return OK;
}

1;
