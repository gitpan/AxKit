# $Id: Provider.pm,v 1.5 2000/06/02 13:41:48 matt Exp $

package Apache::AxKit::Provider;
use strict;

sub new {
	my $class = shift;
	my $apache = shift;
	my $self = bless { apache => $apache }, $class;
	
	if (my $alternate = $AxKit::Cfg->ProviderClass()) {
		AxKit::reconsecrate($self, $alternate);
	}
	
	eval { $self->init() };
	
	return $self;
}

sub apache_request {
	my $self = shift;
	return $self->{apache};
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
to process a directory request, or if the file doesn't exist. Return 1
to tell AxKit to process this URL, or die with a Declined exception (with 
a reason) if you do not wish to process this URL.

=head2 mtime()

Return the last modification time in days before the current time.

=head2 get_styles()

Extract the stylesheets and external entities from the XML file. Should
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

=cut
