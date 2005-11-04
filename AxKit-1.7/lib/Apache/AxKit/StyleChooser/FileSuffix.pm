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

# $Id: FileSuffix.pm,v 1.4 2005/07/14 18:43:35 matts Exp $

package Apache::AxKit::StyleChooser::FileSuffix;

use strict;
use Apache::Constants qw(OK);
use Apache::URI;

sub handler {
	my $r = shift;
	
	my $file = $r->filename();
	my($style) = ($file =~ m/\.(\w+?)$/);

	if ($style && $file =~ s/\.\w+?$// && -e $file) {
		$r->filename($file);
#		warn "setting notes: $style\n";
		$r->notes('preferred_style', $style);
	}
	return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::FileSuffix - Choose stylesheet using file suffix

=head1 SYNOPSIS

	PerlTypeHandler Apache::AxKit::StyleChooser::FileSuffix
	SetHandler AxKit

=head1 DESCRIPTION

This module lets you pick a stylesheet based on the filename suffix. To use
it, simply add this module to the list of PerlTypeHandlers:

	PerlTypeHandler Apache::AxKit::StyleChooser::FileSuffix
	SetHandler AxKit

Then simply by referencing your xml files as follows:

	http://xml.server.com/myfile.xml.printable

You will recieve the alternate stylesheets with title "printable". See 
the HTML 4.0 specification for more details on stylesheet choice.

Note that this installation is different from the other StyleChoosers,
because the file we're requesting here doesn't actually exist.

Thanks to Salve J. Nilsen <sjn@foo.no> for this module.

=cut
