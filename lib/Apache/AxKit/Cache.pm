# $Id: Cache.pm,v 1.25 2001/05/29 10:20:34 matt Exp $

package Apache::AxKit::Cache;
use strict;

use Apache;
use Apache::AxKit::Exception;
use Digest::MD5 ();
use Compress::Zlib;
use Fcntl qw(:flock O_RDWR O_CREAT O_RDONLY);

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my ($r, $xmlfile, @extras) = @_;
    
    my $gzip = 0;
    if (grep(/gzip/, @extras)) {
        $gzip++;
        @extras = grep(!/gzip/, @extras);
    }
    
    my $key = Digest::MD5->new->add(
            join(':', 
                $r->get_server_name,
                $r->get_server_port,
                $xmlfile,
                @extras
            ))->hexdigest;
    
    AxKit::Debug(7, "Cache: key = $key");
    
#    warn "New for: $xmlfile:" . join(':', @extras). "\n";
    
    my $cachedir = $AxKit::Cfg->CacheDir();
    
    my $no_cache;
    
    if (!-e $cachedir) {
        if (!mkdir($cachedir, 0777)) {
            warn "Can't create cache directory '$cachedir': $!\n";
            $no_cache = 1;
        }
    }
    if ($AxKit::Cfg->NoCache()) {
        $no_cache = 1;
    }
    
    my $self = bless { 
        apache => $r,
        key => $key, 
        no_cache => $no_cache, 
        dir => $cachedir,
        file => "$cachedir/$key",
        gzip => $gzip,
#        extras => \@extras,
        }, $class;

    if (my $alternate = $AxKit::Cfg->CacheModule()) {
        AxKit::reconsecrate($self, $alternate);
    }
    
#     AxKit::Debug(7, "Cache->new Count: ".++$COUNT);
    
    return $self;
}

# sub DESTROY {
#     AxKit::Debug(7, "Cache->DESTROY Count: ".--$COUNT);
# }

sub write {
    my $self = shift;
    return if $self->{no_cache};
    my $fh = Apache->gensym();
    if (sysopen($fh, $self->{file}.'new', O_RDWR|O_CREAT)) {
        flock($fh, LOCK_EX);
        seek($fh, 0, 0);
        truncate($fh, 0);
        print $fh $_[0];
        close $fh;
        rename($self->{file}.'new', $self->{file}) 
                || throw Apache::AxKit::Exception::IO( -text => "Couldn't rename cachefile: $!");
    }
    else {
        throw Apache::AxKit::Exception::IO( -text => "Couldn't open cachefile for writing: $!");
    }
    
    if ($self->{gzip} && $AxKit::Cfg->GzipOutput) {
        AxKit::Debug(3, 'Creating gzip output cache');
        my $fh = Apache->gensym();
        if (sysopen($fh, $self->{file}.'new.gz', O_RDWR|O_CREAT)) {
            flock($fh, LOCK_EX);
            seek($fh, 0, 0);
            truncate($fh, 0);
            print $fh ''.Compress::Zlib::memGzip($_[0]);
            close $fh;
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
    return if $self->{no_cache};
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
        $r->send_http_header() unless lc($r->dir_config('Filter')) eq 'on';
        $r->print( $transformer->( $self->read() ) );
        throw Apache::AxKit::Exception::OK();
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
        
        throw Apache::AxKit::Exception::Declined(
                reason => "delivering cached copy"
                );
    }
    
}

sub reset {
    my $self = shift;
    unlink $self->{file};
}

sub mtime {
    my $self = shift;
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
#         my $r = $self->{apache};
#         my $fh = Apache->gensym();
#         if (sysopen($fh, $self->{file}, O_RDONLY)) {
#             flock($fh, LOCK_SH);
#             $r->send_http_header();
#             while (<$fh>) {
#                 $r->print($_);
#             }
#             close $fh;
#         }
        
        $self->reset();
    }
    
    return $self->{no_cache};
}

1;
