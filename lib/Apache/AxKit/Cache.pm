# $Id: Cache.pm,v 1.9 2002/12/25 17:59:21 matts Exp $

package Apache::AxKit::Cache;
use strict;

use Apache;
use Apache::Constants qw(OK DECLINED SERVER_ERROR);
use Apache::AxKit::Exception;
use Digest::MD5 ();
use Compress::Zlib qw(gzopen);
use Fcntl qw(:flock O_RDWR O_WRONLY O_CREAT O_RDONLY);

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my ($r, $xmlfile, @extras) = @_;
    
    my $gzip = 0;
    if ($xmlfile =~ /\.gzip/) {
        $gzip++;
#        @extras = grep(!/gzip/, @extras);
    }
    
    local $^W; # suppress "Use of uninitialized value" warnings
    my $key = Digest::MD5->new->add(
            join(':', 
                $r->hostname,
                $r->get_server_port,
                $xmlfile,
                @extras
            ))->hexdigest;
    
    AxKit::Debug(7, "Cache: key = $key");

    my $primary = substr($key,0,2,'');
    my $secondary = substr($key,0,2,'');
    
#    warn "New for: $xmlfile:" . join(':', @extras). "\n";
    
    my $cachedir = $AxKit::Cfg->CacheDir();
    
    my $no_cache;

    if ($AxKit::Cfg->NoCache()) {
        $no_cache = 1;
    }
    
    if (!$no_cache) {
       if (!-e $cachedir) {
           if (!mkdir($cachedir, 0777)) {
               AxKit::Debug(2, "Can't create cache directory '$cachedir': $!");
               $no_cache = 1;
           }
       }

       if (!-e "$cachedir/$primary") {
           if (!mkdir("$cachedir/$primary", 0777)) {
               AxKit::Debug(1, "Can't create cache directory '$cachedir/$primary': $!");
               $no_cache = 1;
           }
       }
       
       if (!-e "$cachedir/$primary/$secondary") {
           if (!mkdir("$cachedir/$primary/$secondary", 0777)) {
               AxKit::Debug(1, "Can't create cache directory '$cachedir/$primary/$secondary': $!");
               $no_cache = 1;
           }
       }
   }

    my $self = bless { 
        apache => $r,
        key => $key, 
        no_cache => $no_cache, 
        dir => $cachedir,
        file => "$cachedir/$primary/$secondary/$key",
        gzip => $gzip,
#        extras => \@extras,
        }, $class;

    if (my $alternate = $AxKit::Cfg->CacheModule()) {
        AxKit::reconsecrate($self, $alternate);
    }
    
#     AxKit::Debug(7, "Cache->new Count: ".++$COUNT);
    
    return $self;
}

sub _get_stats {
    my $self = shift;
    return if $self->{mtime};
    my @stats = stat($self->{file});
    my $exists = -e _ && -r _;
    if ($exists and $self->{gzip}) {
        $exists = -e $self->{file} . '.gz' and -r _;
    }
    $self->{file_exists} = $exists;
    $self->{mtime} = $stats[9];
}

# sub DESTROY {
#     AxKit::Debug(7, "Cache->DESTROY Count: ".--$COUNT);
# }

sub write {
    my $self = shift;
    return if $self->{no_cache};
    AxKit::Debug(7, "[Cache] writing cache file $self->{file}");
    my $fh = Apache->gensym();
    my $tmp_filename = $self->{file}."new$$";
    if (sysopen($fh, $tmp_filename, O_WRONLY|O_CREAT)) {
        # flock($fh, LOCK_EX);
        # seek($fh, 0, 0);
        # truncate($fh, 0);
        print $fh $_[0];
        close $fh;
        rename($tmp_filename, $self->{file}) 
                || throw Apache::AxKit::Exception::IO( -text => "Couldn't rename cachefile: $!");
    }
    else {
        throw Apache::AxKit::Exception::IO( -text => "Couldn't open cachefile for writing: $!");
    }
    
    if ($self->{gzip} && $AxKit::Cfg->GzipOutput) {
        AxKit::Debug(3, "Creating gzip output cache: $self->{file}.gz");
        if (my $gz = gzopen($self->{file}.'new.gz', "wb")) {
            $gz->gzwrite($_[0]);
            $gz->gzclose();
            rename($self->{file}.'new.gz', $self->{file}.'.gz')
                    || throw Apache::AxKit::Exception::IO( -text => "Couldn't rename gzipped cachefile: $!");
        }
        else {
            throw Apache::AxKit::Exception::IO( -text => "Couldn't open gzipped cachefile for writing: $!");
        }
    }
}

sub read {
    my $self = shift;
    return if $self->{no_cache};
    my $fh = Apache->gensym();
    if (sysopen($fh, $self->{file}, O_RDONLY)) {
        flock($fh, LOCK_SH);
        local $/;
        return <$fh>;
        # close($fh);
        # close unlocks automatically
    }
    return '';
}

sub get_fh {
    my $self = shift;
    return if $self->{no_cache};
    my $fh = Apache->gensym();
    if (sysopen($fh, $self->{file}, O_RDONLY)) {
        flock($fh, LOCK_SH);
        return $fh;
    }
    else {
        throw Apache::AxKit::Exception::IO( -text => "Cannot open cache file for reading: $!");
    }
}

sub set_type {
    my $self = shift;
    return if $self->{no_cache};
    
    my $fh = Apache->gensym();
    if (sysopen($fh, $self->{file}.'newtype', O_RDWR|O_CREAT)) {
        flock($fh, LOCK_EX);
        seek($fh, 0, 0);
        truncate($fh, 0);
        print $fh $_[0];
        close $fh;
        rename($self->{file}.'newtype', $self->{file}.'.type') 
                || throw Apache::AxKit::Exception::IO( -text => "Couldn't rename type cachefile: $!");
    }
    else {
        throw Apache::AxKit::Exception::IO( -text => "Couldn't open type cachefile for writing: $!");
    }
}

sub get_type {
    my $self = shift;
    return if $self->{no_cache};
    my $fh = Apache->gensym();
    if (sysopen($fh, $self->{file}.'.type', O_RDONLY)) {
        flock($fh, LOCK_SH);
        local $/;
        return <$fh>;
        # close($fh);
        # close unlocks automatically
    }
    return '';
}

sub deliver {
    my $self = shift;
    return SERVER_ERROR if $self->{no_cache};
    my $r = $self->{apache};

    {
        # get content-type
        AxKit::Debug(4, "Cache: Getting content-type");
        if (my $type = $self->get_type) {
            AxKit::Debug(4, "Cache: setting content-type: $type");
            $r->content_type($type);
        }
    }

    if ($r->content_type eq 'changeme' && !$r->notes('axkit_passthru_type')) {
        $AxKit::Cfg->AllowOutputCharset(1);
        $r->content_type('text/html; charset=' . ($AxKit::Cfg->OutputCharset || "UTF-8"));
    }
    elsif ($r->notes('axkit_passthru_type')) {
        $r->content_type($AxKit::OrigType);
    }


    my ($transformer, $doit) = AxKit::get_output_transformer();

    if ($doit) {
        AxKit::Debug(4, "Cache: Transforming content and printing to browser");
        $r->pnotes('xml_string',$self->read());
        return OK; # upstream deliver_to_browser should handle the rest
    }
    else {
        AxKit::Debug(4, "Cache: Sending untransformed content to browser");

        # Make sure we unset PATH_INFO or wierd things can happen!
        $ENV{PATH_INFO} = '';
        $r->path_info('');

        if ($self->{gzip} && $AxKit::Cfg->DoGzip) {
            AxKit::Debug(4, 'Cache: Delivering gzipped output');
            $r->filename($self->{file}.'.gz');
        }
        else {
            $r->filename($self->{file});
        }

        return DECLINED;
    }

}

sub reset {
    my $self = shift;
    unlink $self->{file};
}

sub mtime {
    my $self = shift;
    $self->_get_stats;
    return $self->{mtime} if exists $self->{mtime};
    return ($self->{mtime} = (stat($self->{file}))[9]);
}

sub has_changed {
    my $self = shift;
    my $time = shift;
    return $self->mtime > $time;
}

sub exists {
    my $self = shift;
    return if $self->{no_cache};
    $self->_get_stats;
    return $self->{file_exists} if exists $self->{file_exists};
    return ($self->{file_exists} = -e $self->{file});
}

sub key {
    my $self = shift;
    return $self->{key};
}

sub no_cache {
    my $self = shift;

    return $self->{no_cache} unless @_;

    if ($_[0]) {
        AxKit::Debug(8, "Turning off cache!");
        $self->{no_cache} = 1;
        $self->reset();
    }
    
    return $self->{no_cache};
}

1;
