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

# $Id: Language.pm,v 1.5 2005/07/14 18:43:33 matts Exp $

package Apache::AxKit::Language;

use strict;
use Apache::Constants;

sub handler {
	my $class = shift;
	my ($r, $xml, $style) = @_;
	
	die "Need to subclass handler() method";
}

sub get_mtime {
	my $class = shift;
	my $provider = shift;
	return $provider->mtime();
}

sub stylesheet_exists { 1; }

sub get_params {
    my $class = shift;
    my $r = shift;

    my @xslt_params;
    if (!$r->notes('disable_xslt_params')) {
        my $cgi = Apache::Request->instance($r);
        @xslt_params = map { $_ => AxKit::ToUTF8(($cgi->param($_))[0]) } $cgi->param;
        if (ref($r->pnotes('extra_xslt_params')) eq 'ARRAY') {
            push @xslt_params, @{$r->pnotes('extra_xslt_params')};
        }
        elsif (ref($r->pnotes('extra_xslt_params')) eq 'CODE') {
            $r->pnotes('extra_xslt_params')->($r, $cgi, \@xslt_params);
        }
        elsif (ref($r->pnotes('extra_xslt_params')) eq 'HASH') {
            push @xslt_params, %{$r->pnotes('extra_xslt_params')};
        }
    }
    return @xslt_params;
}

1;
__END__

=head1 NAME

Apache::AxKit::Language - base class for all processors

=head1 DESCRIPTION

This base class principally provides the get_mtime function for
determining the modification time of the stylesheet. Other modules
are free to override this function - possibly to provide facilities
for determining the minimum mtime of an XML-based stylesheet that includes
external entities.

=cut
