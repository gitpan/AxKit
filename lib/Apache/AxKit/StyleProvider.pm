# $Id$

package Apache::AxKit::StyleProvider;
use strict;

sub new {
	my $class = shift;
	my $apache = shift;
	my $self = bless { apache => $apache }, $class;
	
	if (my $alternate = $AxKit::Cfg->StyleProviderClass()) {
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

Apache::AxKit::StyleProvider - base Stylesheet Provider class

=head1 SYNOPSIS

Override the base Stylesheet Provider class and enable it using:

	AxStyleProvider MyClass
	
	# alternatively use:
	# PerlSetVar AxStyleProvider MyClass

=head1 DESCRIPTION

The StyleProvider class is used to read in the stylesheets at the relative 
URL provided by Provider::get_styles for each stylesheet used by the data
source.
The default StyleProvider is Provider::File, which reads from the filesystem,
although obviously you can read from just about anywhere.

Should you wish to override the default StyleProvider, these are the methods
you need to implement:

=head2 get_fh()

This method should return an open filehandle, or die if that's not possible.

=head2 get_strref()

This method returns a reference to a scalar containing the contents of the
stylesheet, or die if that's not possible.

=head2 mtime()

Return the last modification time in days before the current time.

=cut
