# $Id: XMLNewsNITF.pm,v 1.3 2000/05/19 15:47:13 matt Exp $

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
	
	my $template_processor = XMLNews::HTMLTemplate->new();
	
	$template_processor->readTemplate($stylefile);
	
	$template_processor->applyTemplate(*STDOUT, $xmlfile, undef);
	
	return OK;
}

1;
