# $Id: File.pm,v 1.18 2000/10/01 22:08:59 matt Exp $

package Apache::AxKit::Provider::File;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Provider');

use Apache;
use Apache::Log;
use Apache::AxKit::Exception ':try';
use Apache::AxKit::Provider;
use Apache::MimeXML;
use File::Basename;
use XML::Parser;
use Fcntl qw(:DEFAULT);

sub init {
    my $self = shift;
    my (%p) = @_;
    
    if ($p{uri}) {
        my $r = $p{rel} ? $p{rel}->apache_request() : $self->apache_request();
        
        $self->{apache} = $r->lookup_uri($p{uri});
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
    if (-e $self->{file}) {
        if (-r _ ) {
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
    
    if (!-e $xmlfile) {
        throw Apache::AxKit::Exception::Declined(
                reason => "file '$xmlfile' does not exist"
                );
    }
    
    if (!-r _ ) {
        throw Apache::AxKit::Exception::Declined(
                reason => "file '$xmlfile' does not have the read bits set"
                );
    }
    
    if (-d _ ) {
        throw Apache::AxKit::Exception::Declined(
                reason => "'$xmlfile' is a directory"
                );
    }
    
    local $^W;
    if (($xmlfile =~ /\.xml$/i) ||
        ($self->{apache}->content_type() =~ /^(text|application)\/xml/) ||
        $self->{apache}->notes('xml_string') ||
        Apache::MimeXML::check_for_xml(try {$self->get_fh} catch Error with { ${ $self->get_strref } })) {
            chdir(dirname($xmlfile));
            return 1;
    }
    
    throw Apache::AxKit::Exception::Declined(
            reason => "'$xmlfile' not recognised as XML"
            );
}

sub mtime {
    my $self = shift;
    return -M $self->{file};
}

sub get_fh {
    my $self = shift;
    my $filename = $self->{file};
    chdir(dirname($filename));
    my $fh = Apache->gensym();
    if (sysopen($fh, $filename, O_RDONLY)) {
        flock($fh, 1);
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
