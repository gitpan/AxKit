# $Id: FileSuffix.pm,v 1.3 2002/07/30 10:33:42 jwalt Exp $

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
