# $Id: Cookie.pm,v 1.2 2002/02/01 14:45:07 matts Exp $

package Apache::AxKit::StyleChooser::Cookie;

use strict;
use Apache::Constants qw(OK);
use Apache::Cookie;

use vars qw($VERSION);

$VERSION = '0.01';

sub handler {
    my $r = shift;
    my $oreo = Apache::Cookie->fetch; # if dougm can call a cookie method "bake". . .
    if ( defined $oreo->{'axkit_preferred_style'} ) {
        $r->notes('preferred_style', $oreo->{'axkit_preferred_style'}->value);
    }

    return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::Cookie - Choose stylesheets based on a browser cookie

=head1 SYNOPSIS

    PerlHandler Apache::AxKit::StyleChooser::Cookie \
                AxKit

=head1 DESCRIPTION

This module checks for the presence of a cookie named
'axkit_preferred_style' and sets the preferred style accordingly.

Remember, use the B<title> attribute in your stylesheet PI to define a
matching style.

=head1 AUTHOR

Kip Hampton, kip@hampton.ws

=head1 SEE ALSO

AxKit.

=cut
