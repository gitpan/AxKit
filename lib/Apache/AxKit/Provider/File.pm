# $Id: File.pm,v 1.28 2001/05/12 10:09:48 matt Exp $

package Apache::AxKit::Provider::File;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Provider');

use Apache;
use Apache::Log;
use Apache::Constants qw(HTTP_OK);
use Apache::AxKit::Exception;
use Apache::AxKit::Provider;
use Apache::MimeXML;
use AxKit;
use File::Basename;
use Fcntl qw(O_RDONLY LOCK_SH);

sub init {
    my $self = shift;
    my (%p) = @_;

    if ($p{key}) {
        $self->{file} = $p{key};
        return;
    }
    
    if ($p{uri} and $p{uri} =~ s|^file:(//)?||) {
        $p{file} = delete $p{uri};
    }
    
    if ($p{uri}) {
        my $r = $p{rel} ? $p{rel}->apache_request() : $self->apache_request();
        
        AxKit::Debug(8, "File Provider looking up" . ($p{rel} ? " relative" : "") . " uri $p{uri}");

        $self->{apache} = $r->lookup_uri($p{uri});
        my $status = $self->{apache}->status();
        if ($status != HTTP_OK) {
            throw Apache::AxKit::Exception::Error(-text => "Subrequest failed with status: " . $status);
        }
        $self->{file} = $self->{apache}->filename();
        
        AxKit::Debug(8, "File Provider set filename to $self->{file}");
    }
    elsif ($p{file}) {
        my $r = $p{rel} ? $p{rel}->apache_request() : $self->apache_request();
        
        AxKit::Debug(8, "File Provider looking up file $p{file}");

        $self->{apache} = $r->lookup_uri($p{file});
        $self->{file} = $self->{apache}->filename();
        
        AxKit::Debug(8, "File Provider set filename to $self->{file}");
    }
    else {
        $self->{file} = $self->{apache}->filename();
    }
}

sub key {
    my $self = shift;
    return $self->{file};
}

sub exists {
    my $self = shift;
    return $self->{file_exists} if exists $self->{file_exists};
    if (-e $self->{file}) {
        if (-r _ ) {
            $self->{file_exists} = 1;
            return 1;
        }
        else {
            AxKit::Debug(2, "'$self->{file}' not readable");
            return;
        }
    }
    return;
}

sub process {
    my $self = shift;
    
    my $xmlfile = $self->{file};
    
    unless ($self->exists()) {
        throw Apache::AxKit::Exception::Declined(
                reason => "file '$xmlfile' does not exist or is not readable"
                );
    }
    
    if (-d $xmlfile) {
        throw Apache::AxKit::Exception::Declined(
                reason => "'$xmlfile' is a directory"
                );
    }
    
    local $^W;
    if (($xmlfile =~ /\.xml$/i) ||
        ($self->{apache}->content_type() =~ /^(text|application)\/xml/) ||
        $self->{apache}->pnotes('xml_string') ||
        Apache::MimeXML::check_for_xml(eval {$self->get_fh} || ${ $self->get_strref } )
        ) {
            chdir(dirname($xmlfile));
            return 1;
    }
    
    throw Apache::AxKit::Exception::Declined(
            reason => "'$xmlfile' not recognised as XML"
            );
}

sub mtime {
    my $self = shift;
    return $self->{mtime} if exists $self->{mtime};
    return ($self->{mtime} = (stat($self->{file}))[9]);
}

sub get_fh {
    my $self = shift;
    if (!$self->exists()) {
        throw Apache::AxKit::Exception::IO(-text => "File '$self->{file}' does not exist or is not readable");
    }
    my $filename = $self->{file};
    chdir(dirname($filename));
    my $fh = Apache->gensym();
    if (sysopen($fh, $filename, O_RDONLY)) {
        flock($fh, LOCK_SH);
        # seek($fh, 0, 0);
        return $fh;
    }
    throw Apache::AxKit::Exception::IO( -text => "Can't open '$self->{file}': $!" );
}

sub get_strref {
    my $self = shift;
    my $fh = $self->get_fh();
    local $/;
    my $contents = <$fh>;
    return \$contents
}

1;
