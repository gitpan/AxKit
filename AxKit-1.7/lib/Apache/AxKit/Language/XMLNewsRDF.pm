# Copyright 2001-2005 The Apache Software Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# $Id: XMLNewsRDF.pm,v 1.2 2005/07/14 18:43:34 matts Exp $

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
