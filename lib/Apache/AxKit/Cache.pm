# $Id: Cache.pm,v 1.15 2000/10/02 17:35:34 matt Exp $

package Apache::AxKit::Cache;
use strict;

use Apache;
use Apache::AxKit::Exception;
use Digest::MD5 ();
use Compress::Zlib;
use Fcntl qw(:DEFAULT);

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my ($r, $xmlfile, @extras) = @_;
    my $key = Digest::MD5->new->add("$xmlfile:" . join(':', @extras))->hexdigest;
    
#    warn "New for: $xmlfile:" . join(':', @extras). "\n";
    
    my $cachedir = $AxKit::Cfg->CacheDir();
    
    my $no_cache;
    
    if (!-e $cachedir) {
        if (!mkdir($cachedir, 0777)) {
            warn "Can't create cache directory '$cachedir': $!\n";
            $no_cache = 1;
        }
    }
    
    my $self = bless { 
        apache => $r,
        key => $key, 
        no_cache => $no_cache, 
        dir => $cachedir,
        file => "$cachedir/$key",
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
        flock($fh, 2);
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
    
    if ($AxKit::Cfg->GzipOutput) {
        AxKit::Debug(3, 'Creating gzip output cache');
        my $fh = Apache->gensym();
        if (sysopen($fh, $self->{file}.'new.gz', O_RDWR|O_CREAT)) {
            flock($fh, 2);
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
        flock($fh, 1);
        local $/;
        return <$fh>;
        # closes and unlocks automatically upon loss of scope
    }
    return '';
}

sub get_fh {
    my $self = shift;
    return if $self->{no_cache};
    my $fh = Apache->gensym();
    if (sysopen($fh, $self->{file}, O_RDONLY)) {
        flock($fh, 1);
        return $fh;
    }
    else {
        throw Apache::AxKit::Exception::IO( -text => "Cannot open cache file for reading: $!");
    }
}

sub deliver {
    my $self = shift;
    return if $self->{no_cache};
    my $r = $self->{apache};

    {
        # get content-type
        AxKit::Debug(4, "Cache: Getting content-type");
        my $typecache = Apache::AxKit::Cache->new($r, $self->{key} . '.type');
        if (my $type = $typecache->read()) {
            $r->content_type($type);
        }
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

        if ($AxKit::Cfg->DoGzip) {
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
    return -M $self->{file};
}

sub exists {
    my $self = shift;
    return if $self->{no_cache};
    return -e $self->{file};
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
#             flock($fh, 1);
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
