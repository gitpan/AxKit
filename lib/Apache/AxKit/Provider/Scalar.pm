# $Id: Scalar.pm,v 1.3 2000/09/14 20:35:45 matt Exp $

package Apache::AxKit::Provider::Scalar;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Provider');

use Apache;
use Apache::Log;
use Apache::AxKit::Exception;
use Apache::AxKit::Provider;
use Apache::MimeXML;
use File::Basename;
use XML::Parser;
use Fcntl qw(:DEFAULT);

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

use vars qw/$mtime/;

$mtime = 0;

sub mtime {
    my $self = shift;
    return --$mtime; # brand new (and getting newer by the second...)
}

sub get_fh {
    throw Apache::AxKit::Exception::Error(-text => "Can't get fh for Scalar");
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
