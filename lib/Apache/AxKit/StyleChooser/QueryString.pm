# $Id: QueryString.pm,v 1.4 2002/12/23 13:45:19 matts Exp $

package Apache::AxKit::StyleChooser::QueryString;

use strict;
use Apache::Constants qw(OK);

sub handler {
    my $r = shift;
    
    my %in = $r->args();
    my $key = $r->dir_config('AxStyleChooserQueryStringKey') || 'style';
    
    if ($in{$key}) {
        $r->notes('preferred_style', $in{$key});
    }
    return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleChooser::QueryString - Choose stylesheet using querystring

=head1 SYNOPSIS

  AxAddPlugin Apache::AxKit::StyleChooser::QueryString

=head1 DESCRIPTION

This module lets you pick a stylesheet based on the querystring. 
To use it, simply add this module as an AxKit plugin that 
will be run before main AxKit processing is done.

  AxAddPlugin Apache::AxKit::StyleChooser::QueryString

By default, the key name of the name/value pair is 'style'.
This can be changed by setting the variable AxStyleChooserQueryStringKey
in your httpd.conf:

  PerlSetVar AxStyleChooserQueryStringKey mystyle

Then simply by referencing your xml files as follows:

  http://xml.server.com/myfile.xml?style=printable
  
or

  http://xml.server.com/myfile.xml?mystyle=printable

respectively - you will recieve the alternate stylesheets with title
"printable". See the HTML 4.0 specification for more details on
stylesheet choice.

See the B<AxStyleName> AxKit configuration directive
for more information on how to setup named styles.

=head1 SEE ALSO

AxKit

=cut
