# $Id: QueryStringCache.pm,v 1.1 2002/01/13 20:45:12 matts Exp $

package Apache::AxKit::Plugin::QueryStringCache;
use strict;

use Apache::Constants qw(OK);

sub handler {
    my $r = shift;
    $r->notes('axkit_cache_extra', $r->notes('axkit_cache_extra') . $r->args);
    return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::Plugin::QueryStringCache - Cache based on QS

=head1 SYNOPSIS

  SetHandler axkit
  AxAddPlugin Apache::AxKit::Plugin::QueryStringCache

=head1 DESCRIPTION

By default AxKit does not change it's cache file with a change
in querystring, which can lead to some pretty unexpected behaviour
(and also a number of frequently asked questions). In order
to get around this, use this plugin.

=cut

