# $Id: XMLNewsNITF.pm,v 1.2 2000/05/06 11:11:58 matt Exp $

package Apache::AxKit::Language::XMLNewsNITF;

use strict;
use vars qw/@ISA/;
use Apache::Constants;
use XMLNews::HTMLTemplate;
use Apache::AxKit::Language;

@ISA = 'Apache::AxKit::Language';

sub handler {
	my $class = shift;
	my ($r, $xmlfile, $stylefile) = @_;
	
	$r->content_type('text/html');
	$r->content_encoding('utf-8');
	
	my $template_processor = XMLNews::HTMLTemplate->new();
	
	$template_processor->readTemplate($stylefile);
	
	$template_processor->applyTemplate(*STDOUT, $xmlfile, undef);
	
	return OK;
}

1;
