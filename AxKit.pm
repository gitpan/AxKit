# $Id: AxKit.pm,v 1.20 2000/06/15 10:30:36 matt Exp $

package AxKit;
use strict;
use vars qw/$VERSION/;

use DynaLoader ();
use Apache;
use Apache::Log;
use Apache::Constants;
use Apache::ModuleConfig ();
use Apache::AxKit::Provider;
use Apache::AxKit::Exception;
use Apache::AxKit::ConfigReader;
use Apache::AxKit::Cache;
use Apache::AxKit::Provider;
use Apache::AxKit::StyleProvider;
use Apache::AxKit::Provider::File;

$VERSION = "0.95";

if ($ENV{MOD_PERL}) {
	no strict;
	@ISA = qw(DynaLoader);
	__PACKAGE__->bootstrap($VERSION);
}

sub AxResetDefaultStyleMap ($$) {
	my ($cfg, $parms) = @_;
	@{$cfg->{DefaultStyleMap}} = ();
}

sub AxAddDefaultStyleMap ($$$$;$) {
	my ($cfg, $parms, $href, $type, $media) = @_;
	$media ||= 'screen';
	push @{$cfg->{DefaultStyleMap}}, [$href, $type, $media];
}

sub AxResetStyleMap ($$) {
	my ($cfg, $parms) = @_;
	%{$cfg->{StyleMap}} = ();
}

sub AxAddStyleMap ($$$$) {
	my ($cfg, $parms, $type, $module) = @_;
#	warn "Adding style map: $type => $module\n";
	$cfg->{StyleMap}{$type} = $module;
}

sub AxStylesCascade ($$$) {
	my ($cfg, $parms, $cascade) = @_;
	$cfg->{StylesCascade} = $cascade;
}

sub AxCacheDir ($$$) {
	my ($cfg, $parms, $cachedir) = @_;
	$cfg->{CacheDir} = $cachedir;
}

sub AxConfigReader ($$$) {
	my ($cfg, $parms, $configclass) = @_;
	$cfg->{ConfigReader} = $configclass;
}

sub AxProvider ($$$) {
	my ($cfg, $parms, $providerclass) = @_;
	$cfg->{Provider} = $providerclass;
}

sub AxStyleProvider ($$$) {
	my ($cfg, $parms, $styleclass) = @_;
	$cfg->{StyleProvider} = $styleclass;
}

sub AxStyle ($$$) {
	my ($cfg, $parms, $style) = @_;
	$cfg->{Style} = $style;
}

sub AxMedia ($$$) {
	my ($cfg, $parms, $media) = @_;
	$cfg->{Media} = $media;
}

sub AxCacheModule ($$$) {
	my ($cfg, $parms, $cachemodule) = @_;
	$cfg->{CacheModule} = $cachemodule;
}

sub reconsecrate {
	my ($object, $class) = @_;
	
	my $module = $class . '.pm';
	$module =~ s/::/\//g;
	
	if (!$INC{$module}) {
		require $module;
	}
	
	bless $object, $class;
}

sub get_subrequest {
	my ($r, $href) = @_;
	
	if ($href =~ /^(http|https|ftp):\/\//i) {
		die "Only relative URI's supported in <?xml-stylesheet?> at this time";
	}
	
	return $r->lookup_uri($href);
}

#########################################
# main mod_perl handler routine
#########################################

sub handler {
	my $r = shift;
	
	eval {
		die Apache::AxKit::Exception->Declined(reason => 'in subrequest')
				unless $r->is_main;
		
		die Apache::AxKit::Exception->Declined(reason => 'passthru')
				if $r->notes('axkit_passthru');
		
		$AxKit::Cfg = Apache::AxKit::ConfigReader->new($r);
		my $provider = Apache::AxKit::Provider->new($r);
		
		# Do we process this URL?
		if (!$provider->process()) {
			die Apache::AxKit::Exception->Declined(reason => 'Provider declined');
		}
		
		# get preferred stylesheet and media type
		my $preferred = $AxKit::Cfg->PreferredStyle;
		my $media = $AxKit::Cfg->PreferredMedia;
		
		if ($media !~ /^(screen|tty|tv|projection|handheld|print|braille|aural)$/) {
			$media = 'screen';
		}

		# get cache object
		my $cache = Apache::AxKit::Cache->new($r, $r->filename(), $preferred, $media);

		my $key = $cache->key();
		
		my $mtime = $provider->mtime();
		
		my ($styles, $ext_ents, $recreate);
		
		# get styles/ext_ents from cache or re-parse
		if (exists($AxKit::Stash{$key})
				&& $AxKit::Stash{$key}{mtime} <= $mtime)
		{
			($styles, $ext_ents) = 
					@{$AxKit::Stash{$key}}{('styles', 'external_entities')};
		}
		else {
#			warn "No styles in axkit stash\n";
			$recreate++;
			
			($styles, $ext_ents) = $provider->get_styles($media, $preferred);
			
			$AxKit::Stash{$key} = {
				styles => $styles,
				external_entities => $ext_ents,
				mtime => $mtime,
				};
		}
		
		{
			local $^W;
			if ($preferred && ($styles->[0]{title} ne $preferred)) {
				# we selected a style that didn't exist. 
				# Make sure we default the cache file, otherwise
				# we setup a potential DoS
				$cache = Apache::AxKit::Cache->new($r, $r->filename(), '', $media);
				$key = $cache->key();
			}
		}
		
		if (!$recreate && !$cache->exists()) {
#			warn "cache doesn't exist\n";
			$recreate++;
		}
		
		if (!$recreate) {
			my $mtime_cache = $cache->mtime();
			for my $style (@$styles) {
				last if $recreate;
				next unless $style->{href};
				no strict 'refs';
				next unless $style->{module}->stylesheet_exists();
				my $req = get_subrequest($r, $style->{href});
#				warn "checking $style->{module} mtime against cache: $mtime_cache\n";
				if ($style->{module}->get_mtime($req)
						<= $mtime_cache)
				{
					$recreate++;
				}
			}
			
			# check external entities too now
			if (!$recreate) {
				for my $ext (@$ext_ents) {
					last if $recreate;
					local $^W;
					my $ent = get_subrequest($r, $ext);
					my $ent_provider = Apache::AxKit::Provider->new($ent);
					if ($ent && $ent_provider && ($ent_provider->mtime() <= $mtime_cache)) {
						$recreate++;
					}
				}
			}
		}
		
		# set default content-type (expat returns in utf-8, so use that)
		$r->content_type('text/html; charset=utf-8');
		
		if (!$recreate) {
			$cache->deliver();
		}
		
		$AxKit::Cache = $cache;
		
		# reconsecrate Apache request object (& STDOUT) into our own class
		bless $r, 'AxKit::Apache';
		tie *STDOUT, 'AxKit::Apache', $r;
		
		for my $style (@$styles) {
			my $stylereq = get_subrequest($r, $style->{href});
			my $styleprovider = Apache::AxKit::StyleProvider->new($stylereq);

			$r->notes('resetstring', 1);

			no strict 'refs';

			my $mapto = $style->{module};

			my $method = "handler";
			if (defined &{"$mapto\::$method"}) {
				my $retval = $mapto->$method($r, $provider, $styleprovider);
			}
			else {
				die Apache::AxKit::Exception->Error(
						text => "$mapto Function not found"
						);
			}
		}
		
		if (my $dom = $r->pnotes('dom_tree')) {
			$r->notes('resetstring', 1);
			my $output = $dom->toString;
			$dom->dispose();
			$r->print($output);
		}
		
		if (!$cache->no_cache()) {
			$cache->write($r->notes('xml_string'));
			
			$cache->deliver();
		}
		
		die Apache::AxKit::Exception->OK();
	};
	if ($@) {
		if ($@->isa('Apache::AxKit::Exception::Error')) {
			$r->log->error("[AxKit] [Error] $@->{text}");
			return DECLINED;
		}
		elsif ($@->isa('Apache::AxKit::Exception::Declined')) {
			if ($r->dir_config('AxLogDeclines')) {
				$r->log->info("[AxKit] [DECLINED] $@->{reason}")
						if $@->{reason};
			}
			return DECLINED;
		}
		elsif ($@->isa('Apache::AxKit::Exception::OK')) {
			return OK;
		}
		else {
			$r->log->error("[AxKit] [UnCaught] $@");
		}
	}
	
	return DECLINED;
}

#########################################################################
# Apache Request Object subclass
#########################################################################

package AxKit::Apache;
use vars qw/@ISA/;
use Apache;
use Fcntl qw(:DEFAULT);
@ISA = ('Apache');

sub TIEHANDLE {
	my($class, $r) = @_;
	$r ||= Apache->request;
}

sub content_type {
	my $self = shift;
	
	my ($type) = @_;

	if ($type && !$AxKit::Cache->no_cache()) {
#		warn "Writing content type '$type'\n";
        my $typecache = Apache::AxKit::Cache->new($self, $AxKit::Cache->key() . '.type');
        $typecache->write($type);
	}

	$self->SUPER::content_type(@_);
}

sub print {
	my $self = shift;

	if (!$AxKit::Cache->no_cache()) {

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
		$AxKit::Cache->no_cache(1);
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

1;
__END__

=head1 NAME

AxKit - an XML Delivery Toolkit for Apache

=head1 DESCRIPTION

AxKit provides the user with an application development environment
for mod_perl, using XML, Stylesheets and a few other tricks. See 
http://xml.sergeant.org/axkit/ for details.

=head1 SYNOPSIS

In httpd.conf:

	PerlModule AxKit

Then in any Apache configuration section (Files, Location, Directory,
.htaccess):

	# Install AxKit main parts
	SetHandler perl-script
	PerlHandler AxKit
	
	# Setup style type mappings
	AxAddStyleMap text/xsl Apache::AxKit::Language::Sablot
	AxAddStyleMap application/x-xpathscript \
			Apache:AxKit::Language::XPathScript
	
	# Optionally setup a default style mapping
	AxAddDefaultStyleMap /default.xsl text/xsl
	
	# Optionally set a hard coded cache directory
	AxCacheDir /opt/axkit/cachedir
	
Now simply create xml files with stylesheet declarations:

	<?xml version="1.0"?>
	<?xml-stylesheet href="test.xsl" type="text/xsl"?>
	<test>
		This is my test XML file.
	</test>

And for the above, create a stylesheet in the same directory as the
file called "test.xsl" that compiles the XML into something usable  by
the browser. If you wish to use other languages than XSLT, you can,
provided a module exists for that language.

=head1 BUILD PROBLEMS

If you have trouble compiling AxKit, or apache fails to start after 
installing, it's possible to use AxKit without the built in
configuration directives (which have been known to generate segfaults).
To do this install as follows:

	perl Makefile.PL NO_DIRECTIVES=1
	make
	make test
	make install

This removes the custom configuration directives. Note that you may have
to manually remove old AxKit.pm files from your perl library directory
if you have previously built it, because dynamically built libraries
go into the i386 (or whatever processor you have) directory. Now
you can change the directives to ordinary PerlSetVar directives:

	PerlSetVar AxStyleMap "text/xsl => Apache::AxKit::Language::XSLT, \
		application/x-xpathscript => Apache::AxKit::Language::XPathScript"
	
	# note brackets here
	PerlSetVar AxDefaultStyleMap "(/default.xsl text/xsl) \
				(/other.xsl text/xsl)"
	
	PerlSetVar AxCacheDir /opt/axkit/cache
	
It's worth noting that the PerlSetVar option is available regardless of
whether you compile with NO_DIRECTIVES set, although it is marginally
slower to use PerlSetVar.

=cut
