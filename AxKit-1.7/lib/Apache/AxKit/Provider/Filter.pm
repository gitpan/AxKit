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

# $Id: Filter.pm,v 1.2 2005/07/14 18:43:35 matts Exp $

package Apache::AxKit::Provider::Filter;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Provider::File');

# Provider for Apache::Filter
use Apache;
use Apache::Log;
use Apache::AxKit::Exception;
use Apache::AxKit::Provider;
use Apache::AxKit::Provider::File;
use AxKit;
use Apache::Constants;
use File::Basename;

# copied mostly from File provider...
sub init {
    my $self = shift;
    my (%p) = @_;
    
    if ($p{key} || $p{uri} || $p{file}) {
        return $self->SUPER::init(%p);
    }
    else {
        $self->{file} = $self->{apache}->filename();
        my ($fh, $status) = Apache->filter_register->filter_input();
        throw Apache::AxKit::Exception::Error(
                -text => "Bad filter_input status"
                ) unless $status == OK;
        $self->{filter_data} = join('', <$fh>);
    }
}

sub get_fh {
    my $self = shift;
    if ($self->{filter_data}) {
        throw Apache::AxKit::Exception::IO( 
                -text => "Can't get fh for Filter filehandle"
                );
    }
    return $self->SUPER::get_fh();
}

sub get_strref {
    my $self = shift;
    if (exists $self->{filter_data}) {
        my $data = $self->{filter_data};
        return \$data;
    }
    return $self->SUPER::get_strref();
}

sub process {
    my $self = shift;
    
    my $xmlfile = $self->{file};

    local $^W;
    # always process this resource.
    chdir(dirname($xmlfile));
    return 1;
}

sub exists {
    my $self = shift;
    return 1 if $self->{filter_data};
    return $self->SUPER::exists();
}

sub has_changed () { 1; }

sub mtime {
    my $self = shift;
    return time(); # always fresh
}

1;
