# $Id: Passthru.pm,v 1.3 2000/09/10 15:04:29 matt Exp $

package Apache::AxKit::Plugins::Passthru;

use strict;
use Apache::Constants;
use Apache::Request;

sub handler {
	my $r = Apache::Request->new(shift);
	
	my $passthru = $r->param('passthru');
	if ($passthru) {
#		warn "Setting passthru\n";
		$r->notes('axkit_passthru', 1);
	}
	return DECLINED;
}

1;
