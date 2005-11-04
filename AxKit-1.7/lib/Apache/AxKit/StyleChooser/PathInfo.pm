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

# $Id: PathInfo.pm,v 1.4 2005/07/14 18:43:35 matts Exp $

package Apache::AxKit::StyleChooser::PathInfo;

use strict;
use Apache::Constants qw(OK);
use Apache::URI;

sub handler {
	my $r = shift;
	
	my $style = $r->path_info();

	if ($style && $style ne '/') {
		$r->path_info('');

		my $uri = $r->uri();

		$uri =~ s/\Q$style\E$//;
		
		$r->uri($uri);
		
		my $uri2 = Apache::URI->parse($r);
		
		$r->header_out('Content-Base', $uri2->unparse);
		$r->header_out('Content-Location', $uri2->unparse);
	
		$style =~ s/^\///;
#		warn "setting notes: $style\n";
		$r->notes('preferred_style', $style);
	}
	return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::PathInfo - Choose stylesheet using PATH_INFO

=head1 SYNOPSIS

  AxAddPlugin Apache::AxKit::StyleChooser::PathInfo

=head1 DESCRIPTION

This module lets you pick a stylesheet based on the extra PATH_INFO. 
To use it, simply add this module as an AxKit plugin that 
will be run before main AxKit processing is done.

  AxAddPlugin Apache::AxKit::StyleChooser::PathInfo  

Then simply by referencing your xml files as follows:

   http://xml.server.com/myfile.xml/printable

You will recieve the alternate stylesheets with title "printable". See 
the HTML 4.0 specification for more details on stylesheet choice.

See the B<AxStyleName> AxKit configuration directive
for more information on how to setup named styles.

=head1 SEE ALSO

AxKit.

=cut

