# $Id: ConfigReader.pm,v 1.3 2000/05/10 21:20:04 matt Exp $

package Apache::AxKit::ConfigReader;

use strict;

use Apache::ModuleConfig ();

sub new {
	my $class = shift;
	my $r = shift;
	
	my $cfg = Apache::ModuleConfig->get($r, 'AxKit') || {};
	
	if ($cfg->{ConfigReader} || $r->dir_config('AxConfigReader')) {
		$class = $cfg->{ConfigReader} || $r->dir_config('AxConfigReader');
		my $pkg = $class;
		$pkg =~ s/::/\//g;
		require "$pkg.pm";
	}
	
	return bless { apache => $r, cfg => $cfg }, $class;
}

# returns a hash reference consisting of key = type, value = module
sub StyleMap {
	my $self = shift;
	if ($self->{cfg}->{StyleMap}) {
		return $self->{cfg}->{StyleMap};
	}
	# no StyleMap, try dir_config
	my %hash = split /\s*(?:=>|,)\s*/, $self->{apache}->dir_config('AxStyleMap');
	return \%hash;
}

# returns true/false (default is 1, of course)
sub StylesCascade {
	my $self = shift;
	if (defined $self->{cfg}->{StylesCascade}) {
		return $self->{cfg}->{StylesCascade};
	}
	# no cfg - try dir_config
	my $cascade = $self->{apache}->dir_config('AxStylesCascade');
	if (!defined $cascade) {
		return 1;
	}
	elsif ($cascade eq 'Off') {
		return 0;
	}
	else {
		return 1;
	}
}

# returns an array ref of arrays of [ href, type, media ]
sub DefaultStyleMap {
	my $self = shift;
	if ($self->{cfg}->{DefaultStyleMap}) {
		return $self->{cfg}->{DefaultStyleMap};
	}
	# no cfg - try dir_config
	# comes in form:
	
#	PerlSetVar AxDefaultStyleMap (type href media) (type href media)
	my $defmap = $self->{apache}->dir_config('AxDefaultStyleMap') || return [];
	
	my @things = split /\)\s*\(/, $defmap;
	@things = map { $_ =~ s/^\(?(.*)\)?$/$1/ } @things;
	@things = map { my @f = split ' ', $_; \@f; } @things;
	return \@things;
}

# returns the location of the cache dir
sub CacheDir {
	my $self = shift;
	if ($self->{cfg}->{CacheDir}) {
		return $self->{cfg}->{CacheDir};
	}
	my $cachedir = $self->{apache}->dir_config('AxCacheDir');
	return $cachedir if $cachedir;
	
	use File::Basename;
	my $dir = dirname($self->{apache}->filename());
	return $dir . "/.xmlstyle_cache";
}

1;
