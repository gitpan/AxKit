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

# $Id: FileWrite.pm,v 1.3 2005/07/14 18:43:35 matts Exp $
# file provider implementing write-back support
package Apache::AxKit::Provider::FileWrite;
@ISA = ('Apache::AxKit::Provider::File'); # inherit file methods
use strict;

use Apache::AxKit::Provider::File;
use Apache::AxKit::Exception;
use Fcntl;

Apache::AxKit::Provider::register_protocol('file',__PACKAGE__);

sub get_fh {
        my $self = shift;
        if ($_[0] && !$self->_is_dir()) {
	    my $filename = AxKit::FromUTF8($self->{file});
	    my $fh = Apache->gensym();
	    if (sysopen($fh, $filename, O_WRONLY|O_CREAT|O_TRUNC)) {
		return $fh;
	    }
	    throw Apache::AxKit::Exception::IO( -text => "Can't open '$self->{file}' for writing: $!" );
        }
        return $self->SUPER::get_fh(@_);
}

sub remove {
        my $self = shift;
        if (!unlink(AxKit::FromUTF8($self->{file}))) {
	    throw Apache::AxKit::Exception::IO( -text => "Can't remove '$self->{file}': $!" );
        }
}

sub set_strref {
        my $self = shift;
        my $fh = $self->get_fh(1);
        syswrite($fh,${$_[0]})
	    || throw Apache::AxKit::Exception::IO( -text => "Can't write to '$self->{file}': $!" );
        close($fh)
	    || throw Apache::AxKit::Exception::IO( -text => "Can't write to '$self->{file}': $!" );
}

1;

__END__

=head1 NAME

Apache::AxKit::Provider::FileWrite - File provider class with write support

=head1 SYNOPSIS

Override the base ContentProvider class and enable it using:

    AxContentProvider Apache::AxKit::Provider::FileWrite
    
Using this with the StyleProvider directive is not very useful at the
moment. This might change depending on processor features.
    
=head1 DESCRIPTION

Warning: This is experimental. It was included for testing purposes. The
API might change, or the module might be removed again.

This provider provides the bare minimum of write access. Use this like
any other provider.

This class supports the following additional interfaces:

=over 4

=item * $provider->get_fh(1)

Get a file handle for writing. The old contents of that file are
erased, if any. $provider->get_fh() or an explicit $provider->get_fh(0)
work like before. Directories are not currently supported.

=item * $provider->remove()

Remove the file from the filesystem.

=item * $provider->set_strref(\$text)

Store a string in the file, the opposite of $provider->get_strref().

=back

This is the minimum set of operations to manage files. If you need
locking, you have to implement that yourself. Metadata can be queried
through the AxHandleDirs extension, but cannot yet be set.
are no provisions for locking or metadata - you have to do that yourself.
These primitives are abstract enough to apply to other sources as well,
for example a XML database. If you implement other providers with write
support, please stick to this API.

=cut

=head1 AUTHOR

Jörg Walter <jwalt@cpan.org>

=head1 SEE ALSO

AxKit, Apache::AxKit::Provider

=cut
