# $Id: XMLNewsNITF.pm,v 1.4 2000/06/02 13:41:50 matt Exp $

package Apache::AxKit::Language::XMLNewsNITF;

use strict;
use vars qw/@ISA/;
use Apache::Constants;
use XMLNews::HTMLTemplate;
use Apache::AxKit::Language;

@ISA = 'Apache::AxKit::Language';

sub handler {
	my $class = shift;
	my ($r, $xml, $style) = @_;
	
	my $template_processor = XMLNews::HTMLTemplate->new();
	
	$template_processor->readTemplate($style->get_fh());
	
	$template_processor->applyTemplate(*STDOUT, $xml->get_fh(), undef);
	
	return OK;
}

1;
