# $Id: Filter.pm,v 1.8 2001/01/02 11:25:59 matt Exp $

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

# copied mostly from File provider...
sub init {
    my $self = shift;
    my (%p) = @_;
    
    if ($p{uri} and $p{uri} =~ s|^file:(//)?||) {
        $p{file} = delete $p{uri};
    }
    
    if ($p{uri}) {
        my $r = $p{rel} ? $p{rel}->apache_request() : $self->apache_request();
        
        AxKit::Debug(8, "Filter Provider looking up uri $p{uri}");
        
        $self->{apache} = $r->lookup_uri($p{uri});
        $self->{file} = $self->{apache}->filename();
        
        AxKit::Debug(8, "Filter Provider set filename to $self->{file}");
        
        my $fh = Apache->gensym();
        open($fh, $self->{file}) || throw Apache::AxKit::Exception::Declined(
                reason => "Cannot open file: $self->{file}"
                );
        flock $fh, 1; # shared (read) lock
        $self->{fh} = $fh;
    }
    elsif ($p{file}) {
        my $r = $p{rel} ? $p{rel}->apache_request() : $self->apache_request();
        
        AxKit::Debug(8, "Filter Provider looking up file $p{file}");

        $self->{apache} = $r->lookup_file($p{file});
        $self->{file} = $self->{apache}->filename();
        
        AxKit::Debug(8, "Filter Provider set filename to $self->{file}");
        
        my $fh = Apache->gensym();
        open($fh, $self->{file}) || throw Apache::AxKit::Exception::Declined(
                reason => "Cannot open file: $self->{file}"
                );
        flock $fh, 1; # shared (read) lock
        $self->{fh} = $fh;
    }
    else {
        $self->{file} = $self->{apache}->filename();
        my ($fh, $status) = Apache->filter_register->filter_input();
        throw Apache::AxKit::Exception::Error(
                -text => "Bad filter_input status"
                ) unless $status == OK;
        $self->{fh} = $fh;
        $self->{data} = join('', <$fh>);
    }
}

sub get_fh {
    throw Apache::AxKit::Exception::IO( 
            -text => "Can't get fh for Filter filehandle"
            );
}

sub get_strref {
    my $self = shift;
    if (my $data = $self->{data}) {
        return \$data;
    }
    my $fh = $self->{fh};
#    warn "About to read from fh: $fh\n";
#    seek($fh, 0, 0);
    my $str = join('', <$fh>);
#    warn "Got: $str\n";
    return \$str;
}

use vars qw/$mtime/;

$mtime = 0;

sub mtime {
    my $self = shift;
    return --$mtime; # brand new (and getting newer by the second...)
}

1;
