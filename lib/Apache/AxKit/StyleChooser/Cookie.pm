# $Id: Cookie.pm,v 1.4 2002/12/23 13:45:19 matts Exp $

package Apache::AxKit::StyleChooser::Cookie;

use strict;
use Apache::Constants qw(OK);
use Apache::Cookie;

use vars qw($VERSION);

$VERSION = '0.01';

sub handler {
    my $r = shift;
    my $key = $r->dir_config('AxStyleChooserCookieKey') ||
                'axkit_preferred_style';
    my $oreo = Apache::Cookie->fetch; # if dougm can call a cookie method "bake". . .
    if ( defined $oreo->{$key} ) {
        $r->notes('preferred_style', $oreo->{$key}->value);
    }

    return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::Cookie - Choose stylesheets based on a browser cookie

=head1 SYNOPSIS

    AxAddPlugin Apache::AxKit::StyleChooser::Cookie

=head1 DESCRIPTION

This module checks for the presence of a cookie named 'axkit_preferred_style' 
and sets the preferred style accordingly. 

The name of the cookie can be changed by setting the variable
C<AxStyleChooserCookieKey> in your httpd.conf:

  PerlSetVar AxStyleChooserCookieKey mystyle

Once set, this module will check for the presence of the cookie named
'mystyle' instead of the cookie named 'axkit_preferred_style'.

To use the module, simply add this module as an AxKit plugin that 
will be run before main AxKit processing is done.

  AxAddPlugin Apache::AxKit::StyleChooser::Cookie

See the B<AxStyleName> AxKit configuration directive
for more information on how to setup named style.

=head1 AUTHOR

Kip Hampton, kip@hampton.ws

=head1 SEE ALSO

AxKit.

=cut
