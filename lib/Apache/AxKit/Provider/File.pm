# $Id: File.pm,v 1.4 2000/06/02 13:41:51 matt Exp $

package Apache::AxKit::Provider::File;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Provider');

use Apache;
use Apache::AxKit::Exception;
use Apache::AxKit::Provider;
use Apache::MimeXML;
use File::Basename;
use XML::Parser;
use Fcntl qw(:DEFAULT);

sub init {
	my $self = shift;
	$self->{file} = $self->{apache}->filename();
}

sub process {
	my $self = shift;
	
	my $xmlfile = $self->{file};
	
	unless (-e $xmlfile) {
		die Apache::AxKit::Exception->Declined(
				reason => "file '$xmlfile' does not exist"
				);
	}
	
	if (-d _ ) {
		die Apache::AxKit::Exception->Declined(
				reason => "'$xmlfile' is a directory"
				);
	}
	
	if (($xmlfile =~ /\.xml$/i) ||
		$self->{apache}->notes('xml_string') ||
		Apache::MimeXML::check_for_xml($xmlfile)) {
		chdir(dirname($xmlfile));
		return 1;
	}
	
	die Apache::AxKit::Exception->Declined(
			reason => "'$xmlfile' not recognised as XML"
			);
}

sub mtime {
	my $self = shift;
	return -M $self->{file};
}

sub get_fh {
	my $self = shift;
	my $filename = $self->{file};
	chdir(dirname($filename));
	my $fh = Apache->gensym();
	if (sysopen($fh, $filename, O_RDONLY)) {
		flock($fh, 1);
		return $fh;
	}
	die "Can't open: $!";
}

sub get_strref {
	my $self = shift;
	my $fh = $self->get_fh();
	local $/;
	my $contents = <$fh>;
	return \$contents
}

sub key {
	my $self = shift;
	return $self->{file};
}

my $xmlparser;

sub get_styles {
	my $self = shift;
	
	my $xmlfile = $self->{file};
	
	my ($media, $pref_style) = @_;
	
	my $styles = [];
	my $ext_ents = [];
	
	$xmlparser ||= XML::Parser->new(ParseParamEnt => 1, ErrorContext => 2);
	$xmlparser->setHandlers(
			Start => \&parse_start,
			Proc => \&parse_pi,
			Entity => \&parse_entity_decl,
			);
	
	eval {
		$xmlparser->parsefile($xmlfile,
				XMLStyle_preferred => $pref_style,
				XMLStyle_style => $styles,
				XMLStyle_ext_ents => $ext_ents,
				XMLStyle_style_screen => [],
				XMLStyle_media => $media,
				);
	};
	if ($@) {
		if ($@ !~ /^OK/) {
			die Apache::AxKit::Exception->Error(
					text => "Parsing '$xmlfile' returned: $@\n"
					);
		}
	}
	
	if (!@$styles) {
		for my $st (@{$AxKit::Cfg->DefaultStyleMap()}) {
			if (!$st->[2] || ($st->[2] eq 'all' || $st->[2] eq $media)) {
				push @$styles, { href => $st->[0], type => $st->[1], media => $st->[2] };
			}
		}
		if (!@$styles) {
			die Apache::AxKit::Exception->Declined(
					reason => "'$xmlfile' has no xml-stylesheet PI\nand no DefaultStyleMap defined"
					);
		}
	}
	
	# get mime-type => module mapping
	my $style_mapping = $AxKit::Cfg->StyleMap;
	
	for my $style (@$styles) {
		my $mapto;
		unless ($mapto = $style_mapping->{ $style->{type} }) {
			die Apache::AxKit::Exception->Declined(
					reason => "No implementation mapping available for type '$style->{type}'"
					);
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
				die Apache::AxKit::Exception->Declined(
						reason => "Load of '$mapto' failed with: $@"
						);
			}
		}

	}
		
	return ($styles, $ext_ents);
}

############################################################
# XML::Parser callbacks
############################################################

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
}

sub parse_start {
	my $e = shift;
	
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

1;
