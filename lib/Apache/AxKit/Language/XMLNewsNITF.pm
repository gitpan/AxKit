# $Id: XMLNewsNITF.pm,v 1.1 2002/01/13 20:45:11 matts Exp $

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
	
	$template_processor->applyTemplate($r, $xml->get_fh(), undef);
	
	return OK;
}

1;
