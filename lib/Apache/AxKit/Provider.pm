# $Id: Provider.pm,v 1.10 2000/09/14 20:33:40 matt Exp $

package Apache::AxKit::Provider;
use strict;

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my $apache = shift;
    my $self = bless { apache => $apache }, $class;
    
    if (my $alternate = $AxKit::Cfg->ProviderClass()) {
        AxKit::reconsecrate($self, $alternate);
    }
    
    $self->init(@_);
    
#     AxKit::Debug(7, "Provider->new Count: " . ++$COUNT);
    
    return $self;
}

sub init {
    # blank - override to provide functionality
}

# sub DESTROY {
#     AxKit::Debug(7, "Provider->DESTROY Count: " . --$COUNT);
# }

sub apache_request {
    my $self = shift;
    return $self->{apache};
}

sub get_ext_ent_handler {
    my $self = shift;
    return sub {
        my ($e, $base, $sysid, $pubid) = @_;
        if ($sysid =~ /^(https?|ftp):/) {
            if ($pubid) {
                return ''; # do not bring in public DTD's
            }
            return XML::Parser::lwp_ext_ent_handler(@_);
        }
        
#        warn "File provider ext_ent_handler called with '$sysid'\n";
        $sysid =~ s/^file:(\/\/)?//;
        my $provider = Apache::AxKit::Provider->new(
                Apache->request,
                uri => $sysid
                );
        my $str = $provider->get_strref;
        return $$str;
    };
}

1;
__END__

=head1 NAME

Apache::AxKit::Provider - base Provider class

=head1 SYNOPSIS

Override the base Provider class and enable it using:

    AxProvider MyClass
    
    # alternatively use:
    # PerlSetVar AxProvider MyClass

=head1 DESCRIPTION

The Provider class is used to read in the data source for the given URL.
The default Provider is Provider::File, which reads from the filesystem,
although obviously you can read from just about anywhere.

Should you wish to override the default Provider, these are the methods
you need to implement:

=head2 process()

Determine whether or not to process this URL. For example, you don't want
to process a directory request, or if the resource doesn't exist. Return 1
to tell AxKit to process this URL, or die with a Declined exception (with 
a reason) if you do not wish to process this URL.

=head2 mtime()

Return the last modification time in days before the current time.

=head2 get_styles()

Extract the stylesheets and external entities from the XML resource. Should
return a list of ($styles, $ext_ents). Both are array refs, the style
entries are hashes refs with required keys 'href' and 'type'. The external
entities entries are scalars containing the system identifier of the 
external entity.

=head2 get_fh()

This method should return an open filehandle, or die if that's not possible.

=head2 get_strref()

This method returns a reference to a scalar containing the contents of the
stylesheet, or die if that's not possible. At least one of get_fh or 
get_strref B<must> work.

=head2 key()

This method should return a "key" value that is unique to this URL.

=head2 get_ext_ent_handler()

This should return a sub reference that can be used instead of 
XML::Parser's default external entity handler. See the XML::Parser
documentation for what this sub should do (or look at the code in
the File provider).

=head2 exists()

Return 1 if the resource exists (and is readable).

=cut
