# $Id: FileSuffix.pm,v 1.3 2000/05/03 15:46:56 matt Exp $

package Apache::AxKit::StyleChooser::FileSuffix;

use strict;
use Apache::Constants;
use Apache::URI;

########
## This needs fixing, it probably won't work...
## The XMLFinder will return false, not set the handler to perl-script
## and so this handler will never get called.
########

sub handler {
	my $r = shift;
	
	my $file = $r->filename();
	
	if ($style && $style =~ s/\.(\w+?)$// && -e $style) {
		my $type = $1;
		$r->filename($style);
#		warn "setting notes: $style\n";
		$r->notes('preferred_style', $type);
	}
	return DECLINED;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::FileSuffix - Choose stylesheet using file suffix

=head1 DESCRIPTION

This module lets you pick a stylesheet based on the filename suffix. To use
it, simply add this module to the list of PerlTypeHandlers prior to
Apache::AxKit::XMLFinder:

	PerlTypeHandler Apache::AxKit::StyleChooser::FileSuffix \
			Apache::AxKit::XMLFinder

Then simply by referencing your xml files as follows:

	http://xml.server.com/myfile.xml.printable

You will recieve the alternate stylesheets with title "printable". See 
the HTML 4.0 specification for more details on stylesheet choice.

Note that this installation is different from the other StyleChoosers,
because the file we're requesting here doesn't actually exist.

(Thanks to Salve J. Nilsen for this module, who I couldn't thank directly
because his mail came to me From: "sjn@localhost.localdomain")

=cut
