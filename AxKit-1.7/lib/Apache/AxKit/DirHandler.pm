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

# $Id: DirHandler.pm,v 1.2 2005/07/14 18:43:33 matts Exp $

package Apache::AxKit::DirHandler;
use strict;
use Apache;
use Apache::Log;
use Apache::URI;
use AxKit;
use Data::Dumper;
use File::Basename;

sub new {
    my $class = shift;
    my $provider = shift;
    my $self = bless {
        provider => $provider,
        directory => AxKit::FromUTF8($provider->{file}),
    }, $class;

    # init() ourselves, if a subclass wants to
    $self->init(@_);

    return $self;
}

sub init {
    # blank - override to provide functionality
}

#
# return mtime information for all files in this directory
sub mtime {
    my $self = shift;
    my $dir = $self->{directory};
    my $mtime = 0;
    if (opendir(DIR, $dir)) {
        while(my $line = readdir(DIR)) {
            # stat the current file and, if it's mtime is bigger than
            # anything we've so far seen, snag it
            my @stat = stat(File::Spec->catfile($dir,$line));
            $mtime = $stat[9] if ($stat[9] > $mtime);
        }
        AxKit::Debug(8, "Directory mtime is $mtime");
        return $mtime;
    }
    AxKit::Debug(8, "Directory mtime calculations failed");
    return undef;
}

#
# return the filename for the current request...its just plain easier
# to use this way IMHO.
sub _request_filename {
    my $self = shift;
    my $provider = $self->{provider};
    my $apache = $provider->apache_request;
    return $apache->filename;
}

#
# take a filename, and return a proper URI for that, given the
# current apache request
sub _request_uri {
    my $self = shift;
    my $path = shift;
    my $provider = $self->{provider};
    my $r = $provider->apache_request;
    my $uri = Apache::URI->parse($r);

    # Traverse through to the ".." directory
    if ($path and $path eq '..') {
        # We don't want to climb above the document_root
        return undef if ($uri->path eq '/');

        # trim off the last directory on the URI and return
        # the modified Apache::URI object
        my $new_path = $uri->path;
        $new_path =~ s{/[^/]+/$} {/};
        $uri->path($new_path);
    }
    
    # Process the "." directory
    elsif ($path and $path eq '.' or basename($path) eq '.') {
        # Take the path, which may be multi-leveled, and remove
        # the "." directory from the end of it; if this is not
        # multi-leveled, don't do anything.
        $uri->path(dirname($uri->path . $path));
    }
    
    # For all other files, tack the filename onto the end of the URI
    elsif ($path) {
        $uri->path($uri->path . $path);
    }

    return ($uri, $uri->unparse) if (wantarray);
    return $uri->unparse;
}

#
# pretty-format a filesize in kilobytes, megabytes, etc
sub _format_filesize {
    my $self = shift;
    my $size = shift;
    my $factor = undef;
    my $base = 1024;
    my @suffix = qw( B kB MB GB TB PB );
    for ($factor = $#suffix; $factor > 0; $factor--) {
        last if ($size / $base ** $factor >= 1);
    }
    return sprintf('%.2f', $size / $base ** $factor) . $suffix[$factor];
}

1;
__END__

=head1 NAME

Apache::AxKit::DirHandler - base class for Directory handlers

=head1 SYNOPSIS

Override the base DirHandler class and enable it by using:

    AxDirHandler MyClass

    # alternatively use:
    # PerlSetVar AxDirHandler MyClass

=head1 DESCRIPTION

AxKit supports the capability to handle directory requests.  Therefore, instead of
relying on Apache to serve a Directory Index file or generating a file listing,
AxKit will generate XML representing the content of the indicated directory for
processing by your stylesheet pipeline.

In many cases the default XML grammar provided will be sufficient, but for those
instances when something more specific is necessary, this default behavior can be
overridden.

This class is a base-class implementing basic behavior, but must be inherited for
directory listings to function.  To write your own directory handler, simply override
this class and implement the C<get_strref()> method.

=head1 PUBLIC METHODS

The following are the methods available from this class:

=head2 get_strref

This method is called to generate the XML contents of a directory.  The "directory"
property of the object contains the path of the directory to be returned.  The return
value is expected to be a reference to the XML string to be returned.

=head2 init()

This method is called shortly after object construction, and can be used to initialize
anything necessary to the operation of a directory handler.

=head2 mtime()

This returns the latest last modified time of any file or directory within the requested
directory.  This is used for caching purposes.

=head1 PRIVATE METHODS

Apache::AxKit::DirHandler provides a few convenience methods that can make the business
of processing directory listings easier.

=head2 _request_filename

This returns the requested filename from the Apache object.

=head2 _request_uri

Given a filename relative to the currently processed directory, this will return a full
URI for the file.  If called in a scalar context it will return the full URI, while in an
array context it will return both an Apache::URI object and the "unparsed" URI string.

=head2 _format_filesize

This will return a fancy filesize string (XkB, etc) for a given byte-size.

=cut
