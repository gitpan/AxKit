# $Id: Scalar.pm,v 1.6 2001/04/26 21:37:37 matt Exp $

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
