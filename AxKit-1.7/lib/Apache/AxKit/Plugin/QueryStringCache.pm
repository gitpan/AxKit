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

# $Id: QueryStringCache.pm,v 1.2 2005/07/14 18:43:35 matts Exp $

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

