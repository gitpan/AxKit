# $Id: XMLFinder.pm,v 1.2 2000/05/02 10:32:04 matt Exp $

package Apache::AxKit::XMLFinder;

use strict;
use Apache::MimeXML;
use Apache::Constants;

sub handler {
	my $r = shift;
	
	return DECLINED unless -e $r->finfo;
	return DECLINED if -d $r->finfo;
	
	if (($r->filename =~ /\.xml$/i) ||
		Apache::MimeXML::check_for_xml($r->filename)) {

		$r->notes('is_xml', 1);
		$r->handler('perl-script');

	}
	
	return DECLINED;
}

1;
