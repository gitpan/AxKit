# $Id: QueryString.pm,v 1.7 2001/04/30 21:13:48 matt Exp $

package Apache::AxKit::StyleChooser::QueryString;

use strict;
use Apache::Constants;

sub handler {
	my $r = shift;
	
	my %in = $r->args();
	if ($in{style}) {
		$r->notes('preferred_style', $in{style});
	}
	return DECLINED;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::QueryString - Choose stylesheet using querystring

=head1 SYNOPSIS

	PerlHandler Apache::AxKit::StyleChooser::QueryString \
			AxKit

=head1 DESCRIPTION

This module lets you pick a stylesheet based on the querystring. To use
it, simply add this module to the list of PerlHandlers prior to
the main AxKit handler:

	PerlHandler Apache::AxKit::StyleChooser::QueryString \
			AxKit

Then simply by referencing your xml files as follows:

	http://xml.server.com/myfile.xml?style=printable

You will recieve the alternate stylesheets with title "printable". See 
the HTML 4.0 specification for more details on stylesheet choice.

=cut
