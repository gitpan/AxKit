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

# $Id: Scalar.pm,v 1.2 2005/07/14 18:43:35 matts Exp $

package Apache::AxKit::Provider::Scalar;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Provider');

use Apache;
use Apache::Log;
use Apache::AxKit::Exception;
use Apache::AxKit::Provider;
use AxKit;

sub new {
    my $class = shift;
    my $apache = shift;
    my $self = bless { apache => $apache }, $class;
    
    eval { $self->init(@_) };
    
    return $self;
}

sub apache_request {
    my $self = shift;
    return $self->{apache};
}

sub init {
    my $self = shift;
    $self->{data} = $_[0];
    $self->{styles} = $_[1];
    
#    warn "Scalar Provider constructed with: $self->{data}\n";
}

sub process {
    my $self = shift;
    return 1;
}

sub exists {
    my $self = shift;
    return 1;
}

sub mtime {
    my $self = shift;
    return time(); # always fresh
}

sub get_fh {
    throw Apache::AxKit::Exception::IO( -text => "Can't get fh for Scalar" );
}

sub get_strref {
    my $self = shift;
    return \$self->{data};
}

sub key {
    my $self = shift;
    return 'scalar_provider';
}

sub get_styles {
    my $self = shift;
    return $self->{styles}, [];
}

1;
