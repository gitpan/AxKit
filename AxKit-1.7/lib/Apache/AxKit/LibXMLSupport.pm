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

# $Id: LibXMLSupport.pm,v 1.5 2005/07/14 18:43:33 matts Exp $

package Apache::AxKit::LibXMLSupport;
use strict;
use XML::LibXML 1.50;
use Apache::AxKit::Provider;

use vars qw($provider_cb);

sub reset {
    my $class = shift;
    $XML::LibXML::match_cb = \&match_uri;
    $XML::LibXML::read_cb = \&read_uri;
    $XML::LibXML::close_cb = \&close_uri;
    $XML::LibXML::open_cb = \&open_uri;
}

sub match_uri {
    my $uri = shift;
    AxKit::Debug(8, "LibXSLT match_uri: $uri");
    return 0 if $uri =~ /^(https?|ftp|file):/; # don't handle URI's supported by libxml
    return 1 if !($uri =~ /^([a-zA-Z0-9]+):/);
    return Apache::AxKit::Provider::has_protocol($1);
}

sub open_uri {
    my $uri = shift || './';
    return Apache::AxKit::Provider::get_uri($uri,AxKit::Apache->request(),$provider_cb);
}

sub close_uri {
    # do nothing
}

sub read_uri {
    return substr($_[0], 0, $_[1], "");
}

1;
__END__

=head1 NAME

Apache::AxKit::LibXMLSupport - XML::LibXML support routines

=head1 SYNOPSIS

  require Apache::AxKit::LibXMLSupport;
  Apache::AxKit::LibXMLSupport->setup_libxml();

=head1 DESCRIPTION

This module sets up some things for using XML::LibXML in AxKit. Specifically this
is to do with callbacks. All callbacks look pretty much the same in AxKit, so
this module makes them editable in one place.

=head1 API

There is just one method: C<< Apache::AxKit::LibXMLSupport->setup_libxml() >>.

You can pass a parameter, in which case it is a callback to create a provider
given a C<$r> (an Apache request object). This is so that you can create the
provider in different ways and register the fact that it was created. If you
don't provide a callback though a default one will be provided.

=cut
