# $Id: StyleFinder.pm,v 1.2 2000/05/02 10:32:04 matt Exp $

package Apache::AxKit::StyleFinder;

use strict;
use vars qw($VERSION);

$VERSION = '0.08';

use Apache;
use Apache::Constants;
use Apache::MimeXML;
use XML::Parser;
use Digest::MD5 'md5_hex';

my $xmlparser;

sub handler {
	my $r = shift;

	return DECLINED unless $r->is_main();
	
#	warn "In AxKit::StyleFinder\n";
	
	my $xmlfile = $r->filename;
	
	unless (-e $r->finfo) {
		$r->log->error("File does not exist: $xmlfile");
		return NOT_FOUND;
	}
	
	if (-d $r->finfo) {
		return DECLINED;
	}
	
	unless ($r->notes('is_xml')
			|| $xmlfile =~ /\.xml$/i
			|| $r->content_type() =~ /\bxml\b/i) {
		return DECLINED;
	}
	
	my %style_mapping = split(/\s*(?:=>|,)\s*/, $r->dir_config('StylesheetMap'));
	
	return DECLINED unless $xmlfile; # just to be safe.
	
	my $preferred = $r->notes('preferred_style') || $r->dir_config('PreferredStyle') || '';
	my $media = $r->notes('preferred_media') || $r->dir_config('PreferredMedia') || 'screen';
	my $cascade = $r->dir_config('StylesCascade');
	if (!defined $cascade) {
		$cascade = 1;
	}
	elsif (lc($cascade) eq 'off') {
		$cascade = 0;
	}
	elsif (lc($cascade) eq 'on' || !defined($cascade)) {
		$cascade = 1;
	}	
	
	my $big_hash = md5_hex("$xmlfile:$preferred:$media:$cascade");
	
	my $mtime = -M $r->finfo;
	
	my $styles;
	my $recreate;
	if (exists($Apache::AxKit::StyleFinder{$big_hash})
			&& $Apache::AxKit::StyleFinder{$big_hash}{mtime} <= $mtime)
	{
		$styles = $Apache::AxKit::StyleFinder{$big_hash}{styles};
	}
	else {
		$recreate++;
		$styles = [];

		$xmlparser ||= XML::Parser->new();
		$xmlparser->setHandlers(
				Start => \&parse_start,
				Proc => \&parse_pi,
				);

		eval {
			$xmlparser->parsefile($xmlfile,
				XMLStyle_preferred => $preferred,
				XMLStyle_style => $styles,
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
			my $defaultStyleMap = $r->dir_config('DefaultStyleMap');
			if ($defaultStyleMap) {
				my $s = {};
				($s->{href}, $s->{type}) = split(/\s+/, $defaultStyleMap);
				push @$styles, $s;
			}
			else {
				warn "XML file '$xmlfile' doesn't contain an appropriate xml-stylesheet processing instruction\n";
				return DECLINED;
			}
		}

		foreach my $style (@$styles) {
#			warn "Looking up $style->{href} (from $xmlfile)\n";
			my $stylefile = $r->lookup_uri($style->{href})->filename;
#			warn "Matches up to $stylefile\n";
			
			unless (-e $stylefile) {
				warn "Stylesheet '$stylefile' for '$xmlfile' does not exist\n";
				return DECLINED;
			}
			
			$style->{stylefile} = $stylefile;
		}
		
		$Apache::AxKit::StyleFinder{$big_hash} = {
					styles => $styles,
					mtime => $mtime,
				};
	}
	
	my $cachedir = $r->dir_config('CacheDir');
	if (!$cachedir) {
		$cachedir = $xmlfile;
		$cachedir =~ s/\/([^\/]*)$/\/.xmlstyle_cache/;
	}
	
	if (!-e $cachedir) {
		if (!mkdir($cachedir, 0777)) {
			warn "Can't create cache directory '$cachedir': $!\n";
		}
	}

	if (!$recreate) {
		my $mtime_cache = -M "$cachedir/$big_hash";

		if (!defined $mtime_cache) {
	#		warn "No cache file\n";
			$recreate++;
		}
		else {
			foreach my $style (@$styles) {
				# check changetimes of styles
				if (-M $style->{stylefile} <= $mtime_cache) {
	#				warn "$style->{stylefile} is newer : ", -M $style->{stylefile},
	#						" > $mtime_cache\n";
					$recreate++;
				}
			}
		}
	}
	
	if (!$recreate) {
#		warn "returning cached copy\n";
		$r->filename("$cachedir/$big_hash");
		if (open(FH, "$cachedir/$big_hash\.type")) {
			flock(FH, 1); # lock for reading
			my $type = <FH>;
			close FH;
			chomp $type;
			my ($t, $e) = $type =~ m/^(.*?);\s*(.*)$/;
			$r->content_type($t);
			$r->content_encoding($e);
		}
		else {
			$r->content_type('text/html');
			$r->content_encoding('utf-8');
		}
		return DECLINED;
	}
	
	$r->notes('cachefile', "$cachedir/$big_hash");
	
	unlink($r->notes('cachefile'));
	
	# rebless $r to my own nasty package...
	bless $r, 'Apache::AxKit::StyleFinder::Apache';
	
	# re-tie STDOUT
	tie *STDOUT, 'Apache::AxKit::StyleFinder::Apache', $r;
	
	foreach my $style (@$styles) {
		my $mapto;
		unless ($mapto = $style_mapping{ $style->{type} }) {
			warn "No implementation mapping available for type '$style->{type}'\n";
			return DECLINED;
		}

		if ($style->{href} =~ /^(http|https|ftp):\/\//i) {
			warn "Only relative URI's supported in <?xml-stylesheet?> at this time\n";
			return DECLINED;
		}

		my $stylefile = $style->{stylefile};

		# Now we have all the conditions we need, we just have to load the
		# module and see if it has the right method.

		# first load module if it's not already loaded.
		my $module = $mapto . '.pm';
		$module =~ s/::/\//g;

		if (!$INC{$module}) {
			eval {
				require $module;
			};
			if ($@) {
				$module =~ s/::\w+\.pm$/.pm/;
				eval {
					require $module;
				};
				if ($@) {
					warn "Load of '$mapto' failed with: $@\n";
					return DECLINED;
				}
			}
		}

		# now check if it's a function or a module we're talking about.

		no strict 'refs';

		if (defined &$mapto) {
			# mapto is a function
			my $retval = &$mapto($xmlfile, $stylefile);
			if ($retval == DECLINED) {
				return DECLINED;
			}
		}
		else {
			# mapto is a module, call handler()
			$mapto .= "::handler";
			if (defined &$mapto) {
#					warn "Calling $mapto\n";
				my $retval = &$mapto($r, $xmlfile, $stylefile);
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
	
	OUTPUT:
	
	if ($r->pnotes('dom_tree')) {
		my $output = $r->pnotes('dom_tree')->toString;
		$r->pnotes('dom_tree')->dispose;
		$r->print($output);
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
				# This is the persistant style - always make it first.
				if ($mediamatch) {
					unshift @{$e->{XMLStyle_style}}, $style;
				}
				elsif ($style->{media} eq 'screen') {
					# store away in case we need the screen matches
					unshift @{$e->{XMLStyle_style_screen}}, $style;
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
					unshift @{ $e->{XMLStyle_style} }, $style;
				}
				elsif ($style->{media} eq 'screen') {
					push @{$e->{XMLStyle_style_screen}}, $style;
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
	if (!@{$e->{XMLStyle_style}} && @{$e->{XMLStyle_style_screen}}) {
#		warn "Matching style for media ", $e->{XMLStyle_media}, " not found. Using screen media stylesheets instead\n";
		push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen}};
	}
	die "OK";
}

{
	# Overridden Apache package.
	
	package Apache::AxKit::StyleFinder::Apache;
	use vars qw/@ISA/;
	use Apache;
	@ISA = 'Apache';
	
	sub content_type {
		my $self = shift;
		my ($type) = @_;
		
		if ($type) {
#			warn "Writing content type '$type'\n";
			if (open(FH, ">".$self->notes('cachefile').'.type')) {
				flock(FH, 2); # lock for writing
				print FH $type;
				my $encoding;
				if ($encoding = $self->content_encoding()) {
					print FH "; ", $encoding;
				}
				close FH;
			}
		}
		
		$self->SUPER::content_type(@_);
	}
	
	sub content_encoding {
		my $self = shift;
		
		my ($encoding) = @_;
		
		if ($encoding) {
#			warn "Writing content encoding '$encoding'\n";
			if (open(FH, ">".$self->notes('cachefile').'.type')) {
				flock(FH, 2); # lock for writing
				print FH $self->content_type();
				print FH "; ", $encoding;
				close FH;
			}
		}
		
		$self->SUPER::content_encoding(@_);
	}
	
	sub print {
		my $self = shift;
		
		if (!$self->no_cache()) {
			my $fh;
#			warn "Opening cachefile for writing $self!\n";
			$fh = Apache->gensym();
			if (open($fh, ">>".$self->notes('cachefile'))) {
				flock($fh, 2); # lock for writing
				print $fh @_;
				close $fh;
			}
		}
		
		$self->SUPER::print(@_);
	}
	
	sub PRINT {
		goto &print;
	}
	
	sub no_cache {
		my $self = shift;
		my ($set) = @_;
		
		if ($set) {
			unlink($self->notes('cachefile')); # don't check return value!
		}
		
		$self->SUPER::no_cache(@_);
	}
}

1;
__END__

=head1 NAME

Apache::AxKit::StyleFinder - Execute module based on <?xml-stylesheet?>

=head1 SYNOPSIS

  # in .htaccess
  PerlSetVar StylesheetMap "text/xsl => XML::XSLT::transformfiles, \
                            application/x-mystyle => My::Style"
  
  PerlSetVar PreferredStyle "default style"
  
  PerlSetVar DefaultStyleMap "/default.xsl text/xsl"

=head1 DESCRIPTION

This module automatically detects XML stylesheet types and associates
modules/functions with those stylesheets according to the
StylesheetMap variable. See http://www.w3.org/TR/xml-stylesheet for
details on the xml-stylesheet processing instruction that this module
uses.

This module also checks for you whether the xml file and stylesheet files
exist, so you don't need to check that in your template/stylesheet
implementation if you don't want to. If an error occurs at any point
it is logged in the error log, and DECLINED is returned, so that other
Apache modules might have a chance to process the file.

In the mapping you can either present a function (fully qualified
with package), or a package. Different parameters are passed depending
on whether you specify a function or a package:

=over

=item 'type' => Package::function

The function receives the xml filename as the first parameter, and
the stylesheet filename as the second parameter. The return value of
the method is not considered, and Apache always returns OK.

=item 'type' => Package

The Package's handler() function is called, with the Apache::Request
object as the first parameter, the xml filename as the second parameter
and the stylesheet filename as the third parameter. Apache returns
whatever the return value of the handler() function is.

=back

If no <?xml-stylesheet?> processing instruction is found, or that
processing instruction is in some way broken, then the option
I<DefaultStyleMap> is checked for, and the href and type in that
variable (separated by whitespace) are used instead.

=head1 Cascading Style Sheets

I'm not talking about HTML css here. I'm talking about any type of 
stylesheet system that you want to cascade. i.e. you want the output
of one stylesheet to be the input to the next. This system supports
cascading by default, but you can turn this off using the directive:

	PerlSetVar StylesCascade Off

To your httpd.conf or .htaccess file. B<However>... it is the responsibility
of the module in question (the module that is cascading) to pass on the
output to the next stylesheet's input. To do this a module must store it's
DOM tree output in $r->pnotes('dom_tree'). This module will figure out for
you all the caching and printing the DOM tree (using $dom->toString).

=head1 Stylesheet Choice

Choosing from multiple stylesheets is a difficult problem. There are many
things to consider. With a cascading system, which the HTML specification
was designed for, it's a simple choice, and well defined by the HTML
specification. However for non-cascading systems it gets a little harder.

The approach I've taken is a scoring system. The scoring is based on the
selected "title", the selected "media" and the values in xml-stylesheet.
The selected media and title can both be set one of two ways. The first
is to specify them in httpd.conf or .htaccess:

	PerlSetVar PreferredMedia print
	PerlSetVar PreferredStyle "my alternate style"

This is a rather static setting, and a better way is to use a stacked
handlers and set the notes 'preferred_style' and preferred_media'. To
do this setup Apache::AxKit::StyleFinder as the first handler in a chain:

    PerlHandler My::MediaExtractor \
                My::StyleExtractor \
                +Apache::AxKit::StyleFinder

This actually sets up 2 extra handlers: One extracts the media and one
extracts the preferred stylesheet. There are many potential ways to do
this - its up to you how you do it. I suggest either a value in the
querystring, or a PATH_INFO, or for media types you could/should use a
browser detection routine combined with perhaps a querystring/PATH_INFO
for requesting a printable version. That's just a suggestion... See
L<AXDTL::StyleChooser::QueryString> and L<Apache::AxKit::StyleChooser::PathInfo>
for working examples that you can use.

Having set all that up, how does Apache::AxKit::StyleFinder pick a stylesheet
to use. After all, it has to pick just one stylesheet if it's not in
cascading mode. The scoring is based on whether the xml-stylesheet
references a persistant stylesheet, a preferred stylesheet, or an
alternate stylesheet, all combined with what I consider to be errors, and
the values given for media and preferred style by the methods above. Here
is the table of scoring used:

          |  Media  | Title  | Title   |
    Score | Matches | Exists | Matches | Alternate
  ++++++++++++++++++++++++++++++++++++++++++++++++++
  0           no        no        -         no
  3           yes       no        -         no
  5           no        yes      N/A        no
  8           no        yes      yes        yes
  10          yes       yes      N/A        no
  15          yes       yes      yes        yes
  -5 (err?)   yes       no        -         yes
  -10 (err?)  no        no        -         yes

It's also worth noting that the default media if it doesn't exist is
"screen", and this is also the default if it doesn't get set by one
of the above methods. So the chances of a media match are quite high.
And it's worth noting that Cocoon-style broken media types are not
supported. The media types must come from the list in REC-html40, or
they will simply be ignored.

If you think this table is in some way incorrect, let me know. I did
put quite a bit of thought into it, but I'm sure it could probably 
be improved somehow. Before you come back to me about it though, please
do read the HTML40 specification. It has some details about what
defines a preferred, persistant and alternate stylesheet that are
relevant here.

=head2 Cascading Styles

Of course the above is irrelevant when you leave the default option of
StylesCascade Yes on. When that is the case, the stylesheets chosen are
according to the rules specified by the W3C at 
http://www.w3.org/TR/REC-html40/styles.html for details on the rules
involved, but the basics are:

=over 4

=item *

If no title is defined (and alternate="..." doesn't exist or is "no") then
this is a persistent stylesheet, and is always applied (provided the media
matches).

=item *

If a title is defined and alternate="no" (or isn't present), this is a
preferred stylesheet, and is used if no preferred stylesheet is chosen
(see details above on choosing a preferred style).

=item *

If alternate="yes", a title must be defined. This stylesheet is used if
and only if it is selected as a preferred style.

=item *

Media type must always match (media="all" matches everything). The default
media type is "screen" if it is not provided in the processing instruction.
If no module provides media matching capabilities,
then the default media of "screen" is used to compare to the value in the
processing instruction.

=back

=head1 AUTHOR

Matt Sergeant, matt@sergeant.org

=head1 LICENSE

This module is distributed under the same terms as Perl itself.

=cut
