# $Id: PathInfo.pm,v 1.2 2002/02/01 14:45:07 matts Exp $

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

	PerlHandler Apache::AxKit::StyleChooser::PathInfo \
			AxKit

=head1 DESCRIPTION

This module lets you pick a stylesheet based on the extra PATH_INFO. To use
it, simply add this module to the list of PerlHandlers prior to
AxKit:

	PerlHandler Apache::AxKit::StyleChooser::PathInfo \
			AxKit

Then simply by referencing your xml files as follows:

	http://xml.server.com/myfile.xml/printable

You will recieve the alternate stylesheets with title "printable". See 
the HTML 4.0 specification for more details on stylesheet choice.

=cut
