# $Id: StyleFinder.pm,v 1.14 2000/06/12 16:17:09 matt Exp $

package Apache::AxKit::StyleFinder;

use strict;
use vars qw($VERSION);

$VERSION = '0.08';

die "************ THIS MODULE IS DEPRECATED *******************\nSee perldoc AxKit now\n";

use Apache;
use Apache::Constants;
use Apache::File;
use Apache::MimeXML;
use Apache::AxKit::ConfigReader;
use XML::Parser;
use Digest::MD5 'md5_hex';
use File::Basename;
use Fcntl qw(:DEFAULT);

my $xmlparser;

sub handler {
	my $r = shift;

	# handled by XMLFinder.pm now?
#	return DECLINED unless $r->is_main();
	
	return DECLINED if $r->notes('axkit_passthru');
	
#	warn "In AxKit::StyleFinder\n";
	
	my $xmlfile = $r->filename;
	
	unless (-e $xmlfile) {
		$r->log->error("File does not exist: $xmlfile");
		return NOT_FOUND;
	}
	
	if (-d _) {
		return DECLINED;
	}
	
	unless ($r->notes('is_xml')
			|| $xmlfile =~ /\.xml$/i
			|| $r->content_type() =~ /\bxml\b/i) {
		return DECLINED;
	}
	
	return DECLINED unless $xmlfile; # just to be safe.
	
	chdir(dirname($xmlfile));
	
	my $cfg = Apache::AxKit::ConfigReader->new($r);
	my %style_mapping = %{ $cfg->StyleMap };
	my $cascade = $cfg->StylesCascade;
	
	my $preferred = $r->notes('preferred_style') || $r->dir_config('PreferredStyle') || '';
	my $media = $r->notes('preferred_media') || $r->dir_config('PreferredMedia') || 'screen';

	if ($media !~ /^(screen|tty|tv|projection|handheld|print|braille|aural)$/) {
		$media = 'screen';
	}
	
	my $big_hash = md5_hex("$xmlfile:$preferred:$media:$cascade");
	
	my $mtime = -M _;
	
	my $styles;
	my $ext_ents;
	my $recreate = 0;
	if (exists($Apache::AxKit::StyleFinder{$big_hash})
			&& $Apache::AxKit::StyleFinder{$big_hash}{mtime} <= $mtime)
	{
		$styles = $Apache::AxKit::StyleFinder{$big_hash}{styles};
		$ext_ents = $Apache::AxKit::StyleFinder{$big_hash}{external_entities};
	}
	else {
		$recreate++;
#		warn "xmlfile mtime cache ($mtime) vs ($Apache::AxKit::StyleFinder{$big_hash}{mtime})\n";
		$styles = [];
		$ext_ents = [];

		$xmlparser ||= XML::Parser->new(ParseParamEnt => 1);
		$xmlparser->setHandlers(
				Start => \&parse_start,
				Proc => \&parse_pi,
				Entity => \&parse_entity_decl,
				);

		eval {
			$xmlparser->parsefile($xmlfile,
				XMLStyle_preferred => $preferred,
				XMLStyle_style => $styles,
				XMLStyle_ext_ents => $ext_ents,
				XMLStyle_style_screen => [],
				XMLStyle_media => $media,
				XMLStyle_cascade => $cascade,
				);
		};
		if ($@) {
			if ($@ !~ /^OK/) {
				warn "Parsing XML file '$xmlfile' returned: $@\n";
				return DECLINED;
			}
		}

		if (!@$styles) {
			my @defaultStyles = ();
			foreach my $val (@{$cfg->DefaultStyleMap}) {
				if (!$val->[2] || ($val->[2] eq 'all' || $val->[2] eq $media)) {
					push @$styles, { href => $val->[0], type => $val->[1], media => $val->[2] };
				}
			}
			if (!@$styles) {
				warn "XML file '$xmlfile' doesn't contain an appropriate xml-stylesheet processing instruction\n";
				warn "And no DefaultStyleMap defined\n";
				return DECLINED;
			}
		}

		foreach my $style (@$styles) {
			my $mapto;
			unless ($mapto = $style_mapping{ $style->{type} }) {
				warn "No implementation mapping available for type '$style->{type}'\n";
				return DECLINED;
			}
			
			$style->{module} = $mapto;

			# first load module if it's not already loaded.
			my $module = $mapto . '.pm';
			$module =~ s/::/\//g;

			if (!$INC{$module}) {
				eval {
					require $module;
				};
				if ($@) {
					warn "Load of '$mapto' failed with: $@\n";
					return DECLINED;
				}
			}

#			warn "Looking up $style->{href} (from $xmlfile)\n";
			no strict 'refs';
			if ($mapto->stylesheet_exists() && $style->{href}) {
				if ($style->{href} =~ /^(http|https|ftp):\/\//i) {
					warn "Only relative URI's supported in <?xml-stylesheet?> at this time\n";
					return DECLINED;
				}

				my $stylefile = $r->lookup_uri($style->{href})->filename;
	#			warn "Matches up to $stylefile\n";

				unless (-e $stylefile) {
					warn "Stylesheet '$stylefile' for '$xmlfile' does not exist\n";
					return DECLINED;
				}

				$style->{stylefile} = $stylefile;
			}
			elsif (!$mapto->stylesheet_exists()) {
				delete $style->{href};
			}
		}
		
		$Apache::AxKit::StyleFinder{$big_hash} = {
					styles => $styles,
					mtime => $mtime,
					external_entities => $ext_ents,
				};
	}
	
	{ local $^W;
	if ($preferred && ($styles->[0]{title} ne $preferred)) {
		# we selected a style that didn't exist. 
		# Make sure we default the cache file, otherwise
		# we setup a potential DoS
		$big_hash = md5_hex("$xmlfile::$media:$cascade");
	}
	}
	
	my $cachedir = $cfg->CacheDir;
	
	if (!-e $cachedir) {
		if (!mkdir($cachedir, 0777)) {
			warn "Can't create cache directory '$cachedir': $!\n";
		}
#		warn "cachedir cache\n";
		$recreate++;
	}

	if (!$recreate) {
#		warn "checking if '$cachedir/$big_hash' exists\n";
		if (!-e "$cachedir/$big_hash") {
#			warn "No cache file\n";
			$recreate++;
		}
		else {
			my $mtime_cache = -M _;
			foreach my $style (@$styles) {
				# check changetimes of styles
				next unless $style->{href};
				no strict 'refs';
				eval {
					if ($style->{module}->get_mtime($style->{stylefile})
							<= $mtime_cache) {
		#				warn "$style->{stylefile} is newer : ", -M $style->{stylefile},
		#						" > $mtime_cache\n";
#						warn "stylesheet mtime cache\n";
						$recreate++;
					}
				};
				if ($@) {
					warn "get_mtime error: $@\n";
					return DECLINED;
				}
			}
			
			# do external entities now!
			if (!$recreate) {
#				warn "External entities\n";
				foreach my $ext (@$ext_ents) {
					local $^W;
#					warn "Looking up external entity: $ext\n";
					my $entfile = $r->lookup_uri($ext)->filename;
#					warn "Got: $entfile\n";
					if ($entfile && (-M $entfile <= $mtime_cache)) {
#						warn "extent cache\n";
						$recreate++;
					}
				}
			}
		}
	}
	
	# defaults
	$r->content_type('text/html; charset=utf-8');
	
	if (!$recreate && !$r->notes('nocache')) {
#		warn "returning cached copy\n";
		$r->filename("$cachedir/$big_hash");
		my $fh = Apache->gensym();
		if (sysopen($fh, "$cachedir/$big_hash\.type", O_RDONLY)) {
			flock($fh, 1); # lock for reading
			my $type = <$fh>;
			close $fh;
			chomp $type;
			$r->content_type($type);
		}
		return DECLINED;
	}
	
	$r->notes('cachefile', "$cachedir/$big_hash");
	
	# rebless $r to my own nasty package...
	bless $r, 'Apache::AxKit::StyleFinder::Apache';
	
	# re-tie STDOUT
	tie *STDOUT, 'Apache::AxKit::StyleFinder::Apache', $r;
	
	if (grep { $_ !~ /::SAX::/ } @$styles) {
		# not all SAX drivers, use default method
		foreach my $style (@$styles) {
			my $stylefile = $style->{stylefile};

			$r->notes('resetstring', 1);
	
			no strict 'refs';
			
			my $mapto = $style->{module};

			my $method = "handler";
			if (defined &{"$mapto\::$method"}) {
#				warn "Calling $mapto\n";
				my $retval = $mapto->$method($r, $xmlfile, $stylefile);
				if ($retval == DECLINED) {
					return DECLINED;
				}
			}
			else {
				warn "$mapto Function not found\n";
				return DECLINED;
			}
		}
	}
	else {
		# All SAX Drivers!
		# use chaining style?
	}
	
	OUTPUT:
	
	if (my $dom = $r->pnotes('dom_tree')) {
		$r->notes('resetstring', 1);
		my $output = $dom->toString;
		$dom->dispose;
		$r->print($output);
	}
	
	if (!$r->notes('nocache')) {
#		warn "Opening cachefile for writing\n";
		my $fh = Apache->gensym();
		if (sysopen($fh, $r->notes('cachefile')."new", O_RDWR|O_CREAT)) {
			flock($fh, 2); # lock for writing
			seek($fh, 0, 0);
			truncate($fh, 0);
			print $fh $r->notes('xml_string');
			close $fh;
			rename($r->notes('cachefile')."new", $r->notes('cachefile')) || die "Couldn't rename cachefile: $!";
		}
		else {
			die "Couldn't open file: $!\n";
		}

#		warn "sending cachefile\n";
		$r->filename($r->notes('cachefile'));
		return DECLINED;

# 		$r->notes('nocache', 1);
# 		$r->send_http_header;
# 		$r->print($r->notes('xml_string'));
	}
	
	return OK;
}

sub parse_pi {
	my $e = shift;
	my ($target, $data) = @_;
	if ($target ne 'xml-stylesheet') {
		return;
	}
	
	my $style;
	
	$data = ' ' . $data;
	
	while ($data =~ /\G
			\s+
			(href|type|title|media|charset|alternate)
			\s*
			=
			\s*
			(["']) # match quotes "'
			([^\2<]*?)
			\2     # balance quotes "'
			/gcx) {
		my ($attr, $val) = ($1, $3);
#		warn "PI: got $attr = $val\n";
		$style->{$attr} = $val;
	}
	
	if (!exists($style->{href}) || !exists($style->{type})) {
		# href and type are #REQUIRED
		warn "Invalid <?xml-stylesheet?> processing instruction\n";
		return;
	}
	
	my $mediamatch = 0;

	$style->{media} ||= 'screen'; # default according to TR/REC-html40
	$style->{alternate} ||= 'no'; # default according to TR/xml-stylesheet

	# See http://www.w3.org/TR/REC-html40/types.html#type-media-descriptors
	# for details of what we're doing here.
	my @mediatypes = split(/,\s*/, $style->{media});
	
	# strip anything after first non-(A-Za-z0-9\-) character (see REC-html40)
	@mediatypes = map { $_ =~ s/[^A-Za-z0-9\-].*$//; $_; } @mediatypes;

#	warn "media types are ", join(',', @mediatypes), " [$style->{media}] [$e->{XMLStyle_media}]\n";

	# remove unwanted entries
	@mediatypes = grep /^(screen|tty|tv|projection|handheld|print|braille|aural|all)$/, @mediatypes;

	if (grep { $_ eq $e->{XMLStyle_media} } @mediatypes) {
		# found a match for the preferred media type!
#		warn "Media matches!\n";
		$mediamatch++;
	}
	
	if (grep { $_ eq 'all' } @mediatypes) {
		# always match on media type "all"
#		warn "Media is \"all\"\n";
		$mediamatch++;
	}
	
	if ($e->{XMLStyle_cascade}) {
		if ($e->{XMLStyle_preferred}) {
			# someone picked a "title". Use persistant and alternate styles
			if (
					($style->{alternate} eq 'no') 
					&& (!exists $style->{title})
				)
			{
				# This is a persistant style - always make it first.
				if ($mediamatch) {
					push @{$e->{XMLStyle_style_persistant}}, $style;
				}
				elsif ($style->{media} eq 'screen') {
					# store away in case we need the screen matches
					push @{$e->{XMLStyle_style_screen_persistant}}, $style;
				}
			}
			elsif (lc($style->{title}) eq lc($e->{XMLStyle_preferred})) 
			{
				# matching style
				if ($mediamatch) {
					push @{$e->{XMLStyle_style}}, $style;
				}
				elsif ($style->{media} eq 'screen') {
					push @{$e->{XMLStyle_style_screen}}, $style;
				}
			}
		}
		else {
			# no "title" selected. Use persistent and preferred styles
			if (
					($style->{alternate} eq 'no')
					&& (!exists $style->{title})
				) 
			{
				if ($mediamatch) {
					# This is the persistant style
					push @{ $e->{XMLStyle_style_persistant} }, $style;
				}
				elsif ($style->{media} eq 'screen') {
					push @{$e->{XMLStyle_style_screen_persistant}}, $style;
				}
			}
			elsif (
					($style->{alternate} eq 'no')
					&& (exists $style->{title})
					)
			{
				if ($mediamatch) {
					push @{ $e->{XMLStyle_style} }, $style;
				}
				elsif ($style->{media} eq 'screen') {
					push @{ $e->{XMLStyle_style_screen} }, $style;
				}
			}
		}
		return;
	}
	
	# Non cascading stylesheets. Use scoring system instead.
	# I'm not so sure this is correct, btw.
	
	my $score = 0;
	if ($style->{alternate} eq 'yes') {
		if (!exists($style->{title})) {
			# err... I think this is an error...
			if ($mediamatch) {
				$score = -5;
			}
			else {
				$score = -10;
			}
		}
		elsif (lc($style->{title}) eq lc($e->{XMLStyle_preferred})) {
			if ($mediamatch) {
				$score = 15;
			}
			else {
				$score = 8;
			}
		}
		else {
			if ($mediamatch) {
				$score = -3;
			}
			else {
				$score = -7;
			}
		}
	}
	elsif ($style->{alternate} eq 'no') {
		if (!exists($style->{title})) {
			if ($mediamatch) {
				$score = 3;
			}
			else {
				$score = 0;
			}
		}
		else {
			if ($mediamatch) {
				$score = 10;
			}
			else {
				$score = 5;
			}
		}
	}
	else {
		warn "Incorrect value '$style->{alternate}' for <?xml-stylesheet alternate='...'?> attribute\n";
	}
	
	$style->{score} = $score;
	
	if (exists $e->{XMLStyle_style_nc}) {
		# a style already exists
		if ($score >= $e->{XMLStyle_style_nc}{score}) {
			$e->{XMLStyle_style_nc} = $style;
		}
	}
	else {
		$e->{XMLStyle_style_nc} = $style;
	}
}

sub parse_start {
	my $e = shift;
	
	if (!$e->{XMLStyle_cascade}) {
		if ($e->{XMLStyle_style_nc}) {
			push @{$e->{XMLStyle_style}}, $e->{XMLStyle_style_nc};
		}
	}
	else {
		if (!@{$e->{XMLStyle_style}} && !$e->{XMLStyle_style_persistant}) {
			if ($e->{XMLStyle_style_screen_persistant}) {
				push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen_persistant}};
			}
			if (@{$e->{XMLStyle_style_screen}}) {
		#		warn "Matching style for media ", $e->{XMLStyle_media}, " not found. Using screen media stylesheets instead\n";
				push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen}};
			}
		}
		elsif ($e->{XMLStyle_style_persistant}) {
			unshift @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_persistant}};
		}
	}
	
	die "OK";
}

sub parse_entity_decl {
	my $e = shift;
	my ($name, $val, $sysid, $pubid, $ndata) = @_;
#	warn "external entity: '$sysid'\n";
	if (!defined $val) {
		# external entity - save so the cache gets done properly!
		push @{$e->{XMLStyle_ext_ents}}, $sysid;
	}
}

#########################################################################
# Apache Request Object subclass
#########################################################################

{
# Overridden Apache package.

package Apache::AxKit::StyleFinder::Apache;
use vars qw/@ISA/;
use Apache;
use Fcntl qw(:DEFAULT);
@ISA = 'Apache';

sub TIEHANDLE {
	my($class, $r) = @_;
	$r ||= Apache->request;
}

sub content_type {
	my $self = shift;
	my ($type) = @_;

	if ($type) {
#		warn "Writing content type '$type'\n";
		my $fh = Apache->gensym();
		if (sysopen($fh, $self->notes('cachefile').'.type', O_RDWR|O_CREAT)) {
			flock($fh, 2); # lock for writing
			seek($fh, 0, 0);
			truncate($fh, 0);
			print $fh $type;
			close $fh;
		}
	}

	$self->SUPER::content_type(@_);
}

sub print {
	my $self = shift;

	if (!$self->notes('nocache')) {

		if ($self->notes('resetstring')) {
			$self->notes('xml_string', '');
			$self->notes('resetstring', 0);
		}

		$self->notes()->{'xml_string'} .= join('', @_);
	}
	else {
		$self->send_http_header unless $self->notes('headers_sent');
		$self->SUPER::print(@_);
	}
}

*PRINT = \&print;

sub no_cache {
	my $self = shift;
	my ($set) = @_;

	$self->SUPER::no_cache(@_);

	if ($set) {
#		warn "caching being turned off!\n";
		$self->notes('nocache', 1);
		# send what's been sent already
		my $fh = Apache->gensym();
		if (sysopen($fh, $self->notes('cachefile'), O_RDONLY)) {
			flock($fh, 1);
			$self->send_http_header;
			while (<$fh>) {
				$self->SUPER::print($_);
			}
			close $fh;
		}

		# might fail due to not existing so ignore return value
		unlink($self->notes('cachefile'));
	}
}

sub send_http_header {
	my $self = shift;
	my ($content_type) = @_;

	return if $self->notes('headers_sent');

	if ($content_type) {
		$self->content_type($content_type);
	}

	$self->notes('headers_sent', 1);

	$self->SUPER::send_http_header;
}
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleFinder - Execute module based on <?xml-stylesheet?>

=head1 DESCRIPTION

This module is completely deprecated to the point of not working.

=cut
