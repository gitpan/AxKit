# $Id: Passthru.pm,v 1.7 2001/04/30 21:13:48 matt Exp $

package Apache::AxKit::Plugins::Passthru;

use strict;
use Apache::Constants;

sub handler {
    my $r = shift;

    my %in = $r->args();
    if ($in{passthru}) {
        $r->notes('axkit_passthru', 1);
    }
    if ($in{passthru_type}) {
        $r->notes('axkit_passthru_type', 1);
    }
    return DECLINED;
}

1;
__END__

=head1 NAME

Apache::AxKit::Plugins::Passthru - allow passthru=1 in querystring

=head1 SYNOPSIS

	PerlHandler Apache::AxKit::Plugins::Passthru \
			AxKit

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

A second function of this module is to allow the content-type of
the requested file to be passed through unchanged. AxKit's default
output content-type is "text/html; charset=utf-8". By enabling
this plugin and requesting a file as:

    http://xml.server.com/myfile.xml?passthru_type=1

Then the file's content type (as set by the Apache AddType option),
will be used rather than any values set during the processing of the
file.

=cut
