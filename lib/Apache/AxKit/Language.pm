# $Id: Language.pm,v 1.3 2000/05/19 15:46:44 matt Exp $

package Apache::AxKit::Language;

use strict;
use Apache::Constants;

sub handler {
	my $class = shift;
	my ($r, $xmlfile, $stylefile) = @_;
	
	return DECLINED;
}

sub get_mtime {
	my $class = shift;
	my $stylefile = shift;
#	warn "get_mtime called on $stylefile\n";
	return -M $stylefile;
}

sub stylesheet_exists { 1; }

1;
__END__

=head1 NAME

Apache::AxKit::Language - base class for all processors

=head1 DESCRIPTION

This base class principally provides the get_mtime function for
determining the modification time of the stylesheet. Other modules
are free to override this function - possibly to provide facilities
for determining the minimum mtime of an XML-based stylesheet that includes
external entities.

=cut
