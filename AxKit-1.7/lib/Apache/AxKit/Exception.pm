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

# $Id: Exception.pm,v 1.5 2005/07/14 18:43:33 matts Exp $

package Apache::AxKit::Exception;
use Error 0.14;
@ISA = ('Error');

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    if ($AxKit::Cfg && $AxKit::Cfg->StackTrace) {
        my $i = $Error::Depth + 1;
        my ($pkg, $file, $line) = caller($i++);
        my @stacktrace;
        while ($pkg) {
            push @stacktrace, { '-package' => $pkg, '-file' => $file, '-line' => $line};
            ($pkg, $file, $line) = caller($i++);
        }
        $self->{'stacktrace'} = \@stacktrace;
    }
    
    return $self;
}

sub stacktrace_list {
    my $E = shift;
    return $E->{'stacktrace'} || [];
}

sub as_xml {
    my $E = shift;
    my $filename = shift || $E->filename;

    my $error = '<error><file>' .
            AxKit::xml_escape($filename) . '</file><msg>' .
            AxKit::xml_escape($E->{-text}) . '</msg>' .
            '<stack_trace><bt level="0">'.
            '<file>' . AxKit::xml_escape($E->{'-file'}) . '</file>' .
            '<line>' . AxKit::xml_escape($E->{'-line'}) . '</line>' .
            '</bt>';
    
    my $i = 1;
    for my $stack (@{$E->stacktrace_list}) {
        $error .= '<bt level="' . $i++ . '">' .
                '<file>' . AxKit::xml_escape($stack->{'-file'}) . '</file>' .
                '<line>' . AxKit::xml_escape($stack->{'-line'}) . '</line>' .
                '</bt>';
    }

    $error .= '</stack_trace></error>';
    return $error;
}

sub filename {
    # Overload this if you don't want to pass $r->filename to as_xml
}

use overload 'bool' => 'bool';

sub bool {
    my $E = shift;
    1;
}

sub value {
    my $E = shift;
    exists $E->{'-value'} ? $E->{'-value'} : 1;
}

package Apache::AxKit::Exception::Declined;
@ISA = ('Apache::AxKit::Exception');

package Apache::AxKit::Exception::Error;
@ISA = ('Apache::AxKit::Exception');

package Apache::AxKit::Exception::OK;
@ISA = ('Apache::AxKit::Exception');

package Apache::AxKit::Exception::Retval;
@ISA = ('Apache::AxKit::Exception');

package Apache::AxKit::Exception::IO;
@ISA = ('Apache::AxKit::Exception');

1;
