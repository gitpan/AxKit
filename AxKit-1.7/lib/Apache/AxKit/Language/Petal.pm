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

# $Id: Petal.pm,v 1.2 2005/07/14 18:43:34 matts Exp $

package Apache::AxKit::Language::Petal;

use strict;
use vars qw/@ISA $VERSION/;
use Petal;
use Apache;
use Apache::Request;
use Apache::AxKit::Language;
use Apache::AxKit::Provider;
use XML::Simple;

@ISA = 'Apache::AxKit::Language';

$VERSION = 1.0; # this fixes a CPAN.pm bug. Bah!

sub handler {
    my $class = shift;
    my ($r, $xml, $style, $last_in_chain) = @_;
    
    my $xmlstring;
    
    AxKit::Debug(7, "[Petal] getting the XML");
    
    if (my $dom = $r->pnotes('dom_tree')) {
        $xmlstring = $dom->toString;
        delete $r->pnotes()->{'dom_tree'};
    }
    else {
        $xmlstring = $r->pnotes('xml_string');
    }
    
    # Setup petal variables
    local $Petal::INPUT = 'XML';
    local $Petal::OUTPUT = $last_in_chain ? 'XHTML' : 'XML';
    local $Petal::DISK_CACHE = 1;
    local $Petal::MEMORY_CACHE = 1;
    
    AxKit::Debug(7, "[Petal] parsing stylesheet");
    my $stylesheet = Petal->new(file => ugh);
    
    AxKit::Debug(7, "[Petal] parsing input");
    my $hash = XMLin($xmlstring, forcearray => 1);
    
    AxKit::Debug(7, "[Petal] performing transformation");
    $r->print( $stylesheet->process($hash) );
    
    return Apache::Constants::OK;
}

1;

