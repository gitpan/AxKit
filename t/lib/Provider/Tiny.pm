package Provider::Tiny;
use strict;
use vars qw( @ISA );
@ISA = qw( Apache::AxKit::Provider );

sub get_strref {
    my $xml = qq*<?xml version="1.0"?>
<root/>
*;
     return \$xml;
}

sub mtime {
    return 0;
}

sub process {
    return 1;
}

sub key {
    my $self = shift;
    return $self->apache_request->uri;
}

1;
