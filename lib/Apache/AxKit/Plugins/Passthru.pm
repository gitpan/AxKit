# $Id: Passthru.pm,v 1.2 2000/05/08 13:10:41 matt Exp $

package Apache::AxKit::Plugins::Passthru;

use strict;
use Apache::Constants;
use CGI ();

sub handler {
	my $r = shift;
	
	my $q = CGI->new();
	
	my $passthru = $q->param('passthru');
	if ($passthru) {
#		warn "Setting passthru\n";
		$r->notes('axkit_passthru', 1);
	}
	return DECLINED;
}

1;
