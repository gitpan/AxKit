# $Id: Filter.pm,v 1.10 2001/02/16 13:39:17 matt Exp $

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
use Apache::MimeXML;
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

use vars qw/$mtime/;

$mtime = 0;

sub mtime {
    my $self = shift;
    return --$mtime; # brand new (and getting newer by the second...)
}

1;
