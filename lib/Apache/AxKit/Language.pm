# $Id: Language.pm,v 1.4 2000/06/02 13:41:48 matt Exp $

package Apache::AxKit::Language;

use strict;
use Apache::Constants;

sub handler {
	my $class = shift;
	my ($r, $xml, $style) = @_;
	
	die "Need to subclass handler() method";
}

sub get_mtime {
	my $class = shift;
	my $provider = shift;
	return $provider->mtime();
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
