# $Id: XMLFinder.pm,v 1.15 2000/06/22 11:39:53 matt Exp $

package Apache::AxKit::XMLFinder;

use strict;
use Apache::MimeXML;
use Apache::Constants;

die "************* THIS MODULE IS DEPRECATED ****************\nSee perldoc AxKit now\n";

sub handler {
	my $r = shift;
	
	return DECLINED unless $r->is_main;
	return DECLINED unless -e $r->finfo;
	return DECLINED if -d $r->finfo;
	
	if (($r->filename =~ /\.xml$/i) ||
		$r->notes('xml_string') ||
		Apache::MimeXML::check_for_xml($r->filename)) {

		$r->notes('is_xml', 1);
		$r->handler('perl-script');

	}
	
	return DECLINED;
}

1;
__END__

=head1 NAME

Apache::AxKit::XMLFinder - Detects XML files

=head1 DESCRIPTION

This module is deprecated to the point of no longer working. Please
see L<AxKit> instead.

=cut
