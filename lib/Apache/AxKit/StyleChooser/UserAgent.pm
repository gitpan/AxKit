# $Id: UserAgent.pm,v 1.2 2002/02/01 14:45:07 matts Exp $

package Apache::AxKit::StyleChooser::UserAgent;

use strict;
use vars qw($VERSION);

$VERSION = '0.01';

use Apache::Constants qw(OK);

sub handler {
    my $r = shift;
    my @UAMap;
    my @aoh = split /\s*,\s*/, $r->dir_config('AxUAStyleMap');
    foreach (@aoh) {
        push (@UAMap, [ split /\s*=>\s*/, $_ ]);
    }

#    warn "checking UA: $ENV{HTTP_USER_AGENT}\n";

    UA: foreach my $ua (@UAMap) {
        if ($ENV{HTTP_USER_AGENT} =~ /$ua->[1]/g) {
#            warn "found UA $ua->[1], setting 'preferred_style' to $ua->[0]\n";
            $r->notes('preferred_style', $ua->[0]);
            last UA;
        }
    }

    return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::UserAgent - Choose stylesheets based on the user agent.

=head1 SYNOPSIS

    In your .conf or .htaccess file(s):
    
    PerlHandler Apache::AxKit::StyleChooser::UserAgent \
                AxKit

    PerlSetVar AxUAStyleMap "lynx     => Lynx,\
                             explorer => MSIE,\
                             opera    => Opera,\
                             netscape => Mozilla"

=head1 DESCRIPTION

This module sets the internal preferred style based on the user agent
string presented by the connecting client.

Remember, use the B<title> attribute in your stylesheet PI to define a
matching style.

=head1 AUTHOR

Kip Hampton, khampton@totalcinema.com

=head1 SEE ALSO

AxKit.

=cut
