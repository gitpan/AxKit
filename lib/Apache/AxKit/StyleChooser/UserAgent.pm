# $Id: UserAgent.pm,v 1.1 2000/09/21 12:18:12 matt Exp $

package Apache::AxKit::StyleChooser::UserAgent;

use strict;
use vars qw($VERSION);

$VERSION = '0.01';

use Apache::Constants;

# edit this to your taste. The format is ['token', 'string_to_find']
# We preferred a LOL over a hash to be sure we find "MSIE" and "Opera"
# before "Mozilla" since since all present "Mozilla" in the UA string

# TODO: Get this from PerlSetVar directive instead...
my @UAMap = (['lynx', 'Lynx'],
             ['explorer', 'MSIE'],
             ['opera', 'Opera'],
             ['netscape', 'Mozilla']);

sub handler {
    my $r = shift;

#    warn "checking UA: $ENV{HTTP_USER_AGENT}\n";

    UA: foreach my $ua (@UAMap) {
        if ($ENV{HTTP_USER_AGENT} =~ /$ua->[1]/g) {
#            warn "found UA $ua->[1], setting 'preferred_style' to $ua->[0]\n";
            $r->notes('preferred_style', $ua->[0]);
            last UA;
        }
    }

    return DECLINED;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::UserAgent - Choose stylesheets based on the user agent.

=head1 SYNOPSIS

    PerlHandler Apache::AxKit::StyleChooser::UserAgent \
                AxKit

=head1 DESCRIPTION

This module sets the internal preferred style based on the user agent
string presented by the connecting client.

By default, the following styles will be set based on the UA:

=over 4

=item lynx

=item explorer

=item opera

=item netscape

=back

However, it is very likely that you will want to customize this for
your particular situation. At this point, the only way to customize the
UA to style mapping is to crack open the module and edit it on your
own. Future releases may provide a friendlier interface.

Remember, use the B<title> attribute in your stylesheet PI to define a
matching style.

=head1 AUTHOR

Kip Hampton, kip@hampton.ws

=head1 SEE ALSO

AxKit.

=cut
