# $Id: WAPCheck.pm,v 1.3 2003/02/07 16:21:44 matts Exp $

package Apache::AxKit::MediaChooser::WAPCheck;

use strict;
use Apache::Constants qw(OK);

sub handler {
	my $r = shift;
	my $type;
	
        my $accept = $r->header_in('Accept') || '';
        my $ua = $r->header_in('User-Agent') || '';
	AxKit::Debug(3, "WAP Check on '$accept' and '$ua'");
	
	local $^W;
	
	if ($accept =~ /vnd.wap.wml/i) {
		$r->notes('preferred_media', 'handheld');
	}
	elsif (substr($ua,0,4) =~ 
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
		AxKit::Debug(3, "set media to handheld!");
		$r->notes('preferred_media', 'handheld');
	}
	
	return OK;
}

1;

__END__

=head1 NAME

Apache::AxKit::MediaChooser::WAPCheck - WAP device media chooser

=head1 SYNOPSIS

  AxAddPlugin Apache::AxKit::MediaChooser::WAPCheck

=head1 DESCRIPTION

This module sets the preferred media type in AxKit to B<handheld> if
it detects that a WAP device made the request. This way you can specify
different stylesheets for WAP devices automatically.

The selection is performed either based on the C<Accept> header being
sent, or based on the C<User-Agent> header (see the source code for
a list of the supported user agent strings).

=cut

