# Copyright 2001-2005 The Apache Software Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# $Id: UserAgent.pm,v 1.5 2005/07/14 18:43:35 matts Exp $

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

#    warn "checking UA: ", $r->header_in('User-Agent'), "\n";

    UA: foreach my $ua (@UAMap) {
        if ($r->header_in('User-Agent') =~ /$ua->[1]/g) {
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
    
    AxAddPlugin Apache::AxKit::StyleChooser::UserAgent

    PerlSetVar AxUAStyleMap "lynx     => Lynx,\
                             explorer => MSIE,\
                             opera    => Opera,\
                             netscape => Mozilla"

=head1 DESCRIPTION

This module sets the internal preferred style based on the user agent
string presented by the connecting client.
To use it, simply add this module as an AxKit plugin that 
will be run before main AxKit processing is done.

  AxAddPlugin Apache::AxKit::StyleChooser::UserAgent

See the B<AxStyleName> AxKit configuration directive
for more information on how to setup named styles.

=head1 AUTHOR

Kip Hampton, khampton@totalcinema.com

=head1 SEE ALSO

AxKit.

=cut
