# $Id: Cache.pm,v 1.7 2000/06/15 10:30:53 matt Exp $

package Apache::AxKit::Cache;
use strict;

use Apache;
use Apache::AxKit::Exception;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT);

sub new {
	my $class = shift;
	my ($r, $xmlfile, @extras) = @_;
	my $key = md5_hex("$xmlfile:" . join(':', @extras));
	
#	warn "New for: $xmlfile:" . join(':', @extras). "\n";
	
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
		extras => \@extras,
		}, $class;

	if (my $alternate = $AxKit::Cfg->CacheModule()) {
		AxKit::reconsecrate($self, $alternate);
	}
	
	return $self;
}

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
		rename($self->{file}.'new', $self->{file}) || die "Couldn't rename cachefile: $!";
	}
	else {
		die "Couldn't open cachefile for writing: $!";
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

sub deliver {
	my $self = shift;
	return if $self->{no_cache};
	my $r = $self->{apache};

#	warn "Delivering cached copy\n";
	# get content-type
	my $typecache = Apache::AxKit::Cache->new($r, $self->{key} . '.type');
	if (my $type = $typecache->read()) {
		$r->content_type($type);
	}

	$r->filename($self->{file});
	
	die Apache::AxKit::Exception->Declined(
			reason => "delivering cached copy"
			);
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
		$self->{no_cache} = 1;
		my $r = $self->{apache};
		my $fh = Apache->gensym();
		if (sysopen($fh, $self->{file}, O_RDONLY)) {
			flock($fh, 1);
			$r->send_http_header();
			while (<$fh>) {
				$r->print($_);
			}
			close $fh;
		}
		
		$self->reset();
	}
	
	return $self->{no_cache};
}

1;
