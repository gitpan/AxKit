# $Id: File.pm,v 1.2 2002/03/17 11:13:22 matts Exp $

package Apache::AxKit::Provider::File;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Provider');

use Apache;
use Apache::Log;
use Apache::Constants qw(HTTP_OK);
use Apache::AxKit::Exception;
use Apache::AxKit::Provider;
use AxKit;
use File::Basename;
use Fcntl qw(O_RDONLY LOCK_SH);

sub init {
    my $self = shift;
    my (%p) = @_;
    
    my $stats_done;
    if ($p{key}) {
        $self->{file} = $p{key};
    }
    else {
        
        if ($p{uri} and $p{uri} =~ s|^file:(//)?||) {
            $p{file} = delete $p{uri};
        }
        
        if ($p{uri}) {
            my $r = $p{rel} ? $p{rel}->apache_request() : $self->apache_request();
            
            AxKit::Debug(8, "[uri] File Provider looking up" . ($p{rel} ? " relative" : "") . " uri $p{uri}");
    
            $self->{apache} = $r->lookup_uri($p{uri});
            my $status = $self->{apache}->status();
            if ($status != HTTP_OK) {
                throw Apache::AxKit::Exception::Error(-text => "Subrequest failed with status: " . $status);
            }
            $self->{file} = $self->{apache}->filename();
            
            AxKit::Debug(8, "[uri] File Provider set filename to $self->{file}");
        }
        elsif ($p{file}) {
            if ($p{rel} && $p{file} !~ /^\//) {
                my $file = $p{rel}->apache_request->filename();
                my $dir = File::Basename::dirname($file);
                require File::Spec;
                $self->{file} = File::Spec->rel2abs($p{file}, $dir);
                AxKit::Debug(8, "[file] File Provider set filename to $self->{file}");
            }
            else {
                $self->{file} = $p{file};
            }
        }
        else {
            $self->{file} = $self->{apache}->filename();
            my @stats = stat($self->{apache}->finfo());
            $self->{mtime} = $stats[9];
            if (-e _) {
                if (-r _ ) {
                    $self->{file_exists} = 1;
                }

                if (-d _) {
                    $self->{is_dir} = 1;
                }
                else {
                    $self->{is_dir} = 0;
                }
            }
            $stats_done++;
        }
    }
    
    if (!$stats_done) {
        my @stats = stat($self->{file});
        $self->{mtime} = $stats[9];
        if (-e _) {
            if (-r _ ) {
                $self->{file_exists} = 1;
            }

            if (-d _) {
                $self->{is_dir} = 1;
            }
            else {
                $self->{is_dir} = 0;
            }
        }
    }
}

sub _is_dir {
    my $self = shift;
    return $self->{is_dir} if exists $self->{is_dir};
    return -d $self->{file};
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
        AxKit::Debug(5, "file '$xmlfile' does not exist or is not readable");
        return 0;
    }
    
    if ($self->_is_dir) {
        AxKit::Debug(5, "'$xmlfile' is a directory");
        return 0;
    }
    
    local $^W;
    if (($xmlfile =~ /\.xml$/i) ||
        ($self->{apache}->content_type() =~ /^(text|application)\/xml/) ||
        $self->{apache}->pnotes('xml_string')
        ) {
            # chdir(dirname($xmlfile));
            return 1;
    }
    
    AxKit::Debug(5, "'$xmlfile' not recognised as XML");
    return 0;
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
    # chdir(dirname($filename));
    my $fh = Apache->gensym();
    if (sysopen($fh, $filename, O_RDONLY)) {
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
