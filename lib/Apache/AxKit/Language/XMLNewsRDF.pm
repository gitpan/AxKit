# $Id: XMLNewsRDF.pm,v 1.5 2000/08/06 12:15:18 matt Exp $

package Apache::AxKit::Language::XMLNewsRDF;

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
	
	$template_processor->applyTemplate($r, undef, $xml->get_fh());
	
	return OK;
}

1;
