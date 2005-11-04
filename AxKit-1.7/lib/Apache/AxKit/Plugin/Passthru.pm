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

# $Id: Passthru.pm,v 1.3 2005/07/14 18:43:35 matts Exp $

package Apache::AxKit::Plugin::Passthru;

use strict;
use Apache::Constants qw(OK);

sub handler {
    my $r = shift;

    my %in = $r->args();
    if ($in{passthru}) {
        $r->notes('axkit_passthru', 1);
    }
    if ($in{passthru_type}) {
        $r->notes('axkit_passthru_type', 1);
    }
    return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::Plugin::Passthru - allow passthru=1 in querystring

=head1 SYNOPSIS

  AxAddPlugin Apache::AxKit::Plugin::Passthru

=head1 DESCRIPTION

This module allows AxKit to pass through raw XML without processing
if the request contained the option C<passthru=1> in the querystring.

Simply by referencing your xml files as follows:

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
