# $Id: File.pm,v 1.12 2003/01/04 18:11:08 matts Exp $

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

sub get_dir_xml {
	my $self = shift;
	local (*DIR);
	my $dir = AxKit::FromUTF8($self->{file});
	if (opendir(DIR, $dir)) {
		my $output = '<?xml version="1.0" encoding="UTF-8"?>
<filelist xmlns="http://axkit.org/2002/filelist">
';
		while(my $line = readdir(DIR)) {
			my $xmlline = AxKit::ToUTF8($line);
			$xmlline =~ s/&/&amp;/;
			$xmlline =~ s/</&lt;/;
			my @stat = stat(File::Spec->catfile($dir,$line));
			my $attr = "size=\"$stat[7]\" atime=\"$stat[8]\" mtime=\"$stat[9]\" ctime=\"$stat[10]\"";
			$attr .= ' readable="1"' if (-r _);
			$attr .= ' writable="1"' if (-w _);
			$attr .= ' executable="1"' if (-x _);
			
			if (-f _) {
				$output .= "<file $attr>$xmlline</file>\n";
			} elsif (-d _) {
				$output .= "<directory $attr>$xmlline</directory>\n";
			} else {
				$output .= "<unknown $attr>$xmlline</unknown>\n";
			}
		}
		$output .= "</filelist>\n";
		AxKit::Debug(8,"Generated file list: $output");
		return $output;
	}
	return undef;
}

sub process {
    my $self = shift;

    my $xmlfile = $self->{file};

    unless ($self->exists()) {
        AxKit::Debug(5, "file '$xmlfile' does not exist or is not readable");
        return 0;
    }

    if ( $self->_is_dir ) {
        if ($AxKit::Cfg->HandleDirs()) {
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
        return \$xml if $xml;
        throw Apache::AxKit::Exception::IO(
          -text => "directory $self->{file} cannot be read");
    }
    my $fh = $self->get_fh();
    local $/;
    my $contents = <$fh>;
    return \$contents
}

1;
