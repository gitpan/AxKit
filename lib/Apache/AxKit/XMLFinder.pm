# $Id: XMLFinder.pm,v 1.5 2000/05/10 21:24:05 matt Exp $

package Apache::AxKit::XMLFinder;

use strict;
use Apache::MimeXML;
use Apache::Constants;

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

This module is one of the key parts of AxKit. It detects when an XML file
is being requested using the routines in Apache::MimeXML.

=head1 SYNOPSIS

	PerlTypeHandler Apache::AxKit::XMLFinder

=cut
