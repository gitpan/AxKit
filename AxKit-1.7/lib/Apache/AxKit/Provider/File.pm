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

# $Id: File.pm,v 1.20 2005/08/09 17:50:35 matts Exp $

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
use File::Spec;
use Fcntl qw(O_RDONLY LOCK_SH);

#Apache::AxKit::Provider::register_protocol('file',__PACKAGE__);

sub init {
    my $self = shift;
    my (%p) = @_;

    my $stats_done;
    if ($p{key}) {
        AxKit::Debug(7, "File Provider instantiated by key: $p{key}");
        # assumed already UTF-8
        $self->{file} = $p{key};
    }
    else {
        if ($p{uri} and $p{uri} =~ s|^file:(//)?||) {
            $p{file} = delete $p{uri};
	    $self->{protocol} = "file:$1";
        }

        if ($p{uri}) {
            my $r = $self->apache_request();

            AxKit::Debug(7, "[uri] File Provider looking up uri $p{uri}");

            # assumed already UTF-8
            $self->{apache} = $r->lookup_uri(AxKit::FromUTF8($p{uri}));
            my $status = $self->{apache}->status();
            if ($status != HTTP_OK) {
                throw Apache::AxKit::Exception::Error(-text => "Subrequest failed with status: " . $status);
            }
            $self->{file} = AxKit::ToUTF8($self->{apache}->filename());

            AxKit::Debug(7, "[uri] File Provider set filename to $self->{file}");
        }
        elsif ($p{file}) {
            AxKit::Debug(7, "[file] File Provider given file: $p{file}");
            # assumed already UTF-8
            $self->{file} = $p{file};
        }
        else {
            $self->{file} = AxKit::ToUTF8($self->{apache}->filename());
            AxKit::Debug(7, "[req] File Provider given \$r: $self->{file}");
            my @stats = stat( $self->{apache}->filename() );
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
        my @stats = stat(AxKit::FromUTF8($self->{file}));
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
    return $self->{is_dir} = -d AxKit::FromUTF8($self->{file});
}

sub key {
    my $self = shift;
    return $self->{file};
}

sub exists {
    my $self = shift;
    return $self->{file_exists} if exists $self->{file_exists};
    if (-e AxKit::FromUTF8($self->{file})) {
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

sub get_document_uri {
    my $self = shift;
    return $self->{protocol}.$self->{file} if ($self->{protocol});
    return $self->SUPER::get_document_uri(@_);
}

sub get_dir_xml {
	my $self = shift;
    my $r = AxKit::Apache->request;
    my $package = $AxKit::Cfg->DirHandlerClass();
    my $dirhandler = $self->{dirhandler_obj}
        || ($self->{dirhandler_obj} = $package->new($self));
    my $output = $dirhandler->get_strref();
    AxKit::Debug(8,"Generated file list: $$output") if (defined($$output));
		return $output;
	}

sub decline {
    my $self = shift;
    if ($self->_is_dir and ($self->{apache}->uri !~ /\/$/)) {
        $self->{apache}->header_out('Location' => $self->{apache}->uri . "/");
        return 302;
    }
    return $self->SUPER::decline();
}

sub process {
    my $self = shift;

    my $xmlfile = $self->{file};

    unless ($self->exists()) {
        AxKit::Debug(5, "file '$xmlfile' does not exist or is not readable");
        return 0;
    }

    if ( $self->_is_dir ) {
        # process directories if AxHandleDirs is On and dir ends in /
        # (otherwise we decline and let apache redirect)
        if ($AxKit::Cfg->HandleDirs()) {
            if ($self->{apache}->uri !~ /\/$/) {
                return 0;
            }
	    my $output = $self->get_dir_xml();
	    return 0 if (!defined $output);
	    $self->{dir_xml} = $output;
            return 1;
        }
        # else
        AxKit::Debug(5, "'$xmlfile' is a directory");
        return 0;
    }

    # Test for an XML file type only if not using FastHandler
    if (!$AxKit::FastHandler) {
        local $^W;
        if (($xmlfile =~ /\.xml$/i) ||
            ($self->{apache}->content_type() =~ /^(text|application)\/xml/) ||
            $self->{apache}->pnotes('xml_string')
            ) {
                # chdir(dirname($xmlfile));
                return 1;
        }
    }
    else {
        return 1;
    }

    AxKit::Debug(5, "'$xmlfile' not recognised as XML");
    return 0;
}

sub mtime {
    my $self = shift;
    if ($self->_is_dir and $AxKit::Cfg->HandleDirs()) {
        my $package = $AxKit::Cfg->DirHandlerClass();
        my $dirhandler = $self->{dirhandler_obj}
            || ($self->{dirhandler_obj} = $package->new($self));
        return $dirhandler->mtime();
    }
    return $self->{mtime} if defined $self->{mtime};
    return ($self->{mtime} = (stat(AxKit::FromUTF8($self->{file})))[9]);
}

sub get_fh {
    my $self = shift;
    if (!$self->exists()) {
        throw Apache::AxKit::Exception::IO(-text => "File '$self->{file}' does not exist or is not readable");
    }
    if ($self->_is_dir()) {
        throw Apache::AxKit::Exception::IO(-text => "Can't get filehandle on directory. ($self->{file})");
    }
    my $filename = AxKit::FromUTF8($self->{file});
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
    if ($self->_is_dir()) {
        my $xml = $self->{dir_xml} || $self->get_dir_xml();
        return $xml if $$xml;
        throw Apache::AxKit::Exception::IO(
          -text => "directory $self->{file} cannot be read");
    }
    my $fh = $self->get_fh();
    local $/;
    my $contents = <$fh>;
    return \$contents
}

1;
