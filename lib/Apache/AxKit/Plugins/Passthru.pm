# $Id: Passthru.pm,v 1.4 2000/12/06 14:15:08 matt Exp $

package Apache::AxKit::Plugins::Passthru;

use strict;
use Apache::Constants;

sub handler {
    my $r = shift;

    my %in = $r->args();
    if ($in{passthru}) {
        $r->notes('axkit_passthru', 1);
    }
    return DECLINED;
}

1;
__END__

=head1 NAME

Apache::AxKit::Plugins::Passthru - allow passthru=1 in querystring

=head1 DESCRIPTION

This module allows AxKit to pass through raw XML without processing
if the request contained the option C<passthru=1> in the querystring.

Simply add this module as a handler before the main AxKit handler:

	PerlHandler Apache::AxKit::Plugins::Passthru \
			AxKit

Then simply by referencing your xml files as follows:

	http://xml.server.com/myfile.xml?passthru=1

You will recieve the raw XML in myfile.xml, rather than it being
pre-processed by AxKit.

This module is also an example of how this can be done, should you
wish to build your own passthru type module that makes the decision
to pass through based on some other parameter, such as the user agent
in use.

=cut
