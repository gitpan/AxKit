# $Id: QueryString.pm,v 1.3 2000/05/06 11:12:21 matt Exp $

package Apache::AxKit::StyleChooser::QueryString;

use strict;
use Apache::Constants;
use CGI ();

sub handler {
	my $r = shift;
	
	my $q = CGI->new();
	
	my $style = $q->param('style');
	if ($style) {
#		warn "setting notes: $style\n";
		$r->notes('preferred_style', $style);
	}
	return DECLINED;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::QueryString - Choose stylesheet using querystring

=head1 DESCRIPTION

This module lets you pick a stylesheet based on the querystring. To use
it, simply add this module to the list of PerlHandlers prior to
Apache::XMLStylesheet:

	PerlHandler Apache::AxKit::StyleChooser::QueryString \
			Apache::AxKit::StyleFinder

Then simply by referencing your xml files as follows:

	http://xml.server.com/myfile.xml?style=printable

You will recieve the alternate stylesheets with title "printable". See 
the HTML 4.0 specification for more details on stylesheet choice.

=cut
