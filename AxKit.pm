# $Id: AxKit.pm,v 1.12 2000/05/28 07:48:26 matt Exp $

package AxKit;

use DynaLoader ();
use Apache::ModuleConfig ();
use Apache::AxKit::StyleFinder;
use Apache::AxKit::XMLFinder;

$VERSION = "0.67";

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
	PerlTypeHandler Apache::AxKit::XMLFinder
	PerlHandler Apache::AxKit::StyleFinder
	
	# Setup style type mappings
	AxAddStyleMap text/xsl Apache::AxKit::Language::XSLT
	AxAddStyleMap application/x-xpathscript \
			Apache:AxKit::Language::XPathScript
	
	# Optionally setup a default style mapping
	AxAddDefaultStyleMap /default.xsl text/xsl
	AxAddDefaultStyleMap /formatter.xsl text/xsl
	
	# Optionally set a hard coded cache directory
	AxCacheDir /opt/axkit/cachedir
	
	# Optionally set an alternative config reader class
	# (this would be for doing configuration outside
	#  of httpd.conf)
	AxConfigReader MyFiles::MyConfigModule

Now simply create xml files with stylesheet declarations:

	<?xml version="1.0"?>
	<?xml-stylesheet href="test.xsl" type="text/xsl"?>
	<test>
		This is my test XML file.
	</test>

And for the above, create a stylesheet in the same directory as the
file called "test.xsl" that compiles the XML into something usable 
by the browser, following the rules for Perl's XML::XSLT. If you
wish to use other languages than XSLT, you can, provided a module
exists for that language.

=head1 BUILD PROBLEMS

If you have trouble compiling AxKit, or apache fails to start after 
installing, it's possible to use AxKit without the built in configuration
directives. To do this install as follows:

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
	
	PerlSetVar AxConfigReader MyFiles::MyConfigModule

It's worth noting that the PerlSetVar option is available regardless of
whether you compile with NO_DIRECTIVES set, although it is slower.

=cut
