# $Id: Makefile.PL,v 1.22 2003/07/17 16:34:49 matts Exp $

# package AxKit;
# file Makefile.PL
use strict;

use Text::Wrap ();
use Cwd;
use Config;
use ExtUtils::MakeMaker qw(prompt);

use vars qw($DEBUG $is_Win32 $DEVNULL);

require 5.005;

BEGIN {
    $INC{'bytes.pm'}++ if $] < 5.006;
    $INC{'warnings.pm'}++ if $] < 5.006;
}

sub wrap ($)
{
    my $text = shift;
    $text =~ s/^\s+//;
    $text =~ s/\s+$//;
    Text::Wrap::wrap('', '', $text) . "\n\n";
}

my @DIRS = ('./lib/Apache/AxKit');
my $from_dir = cwd;

eval { require ExtUtils::AutoInstall };
if ($@ || $ExtUtils::AutoInstall::VERSION < 0.32) {
  warn( "\n",
        "==================================================================\n",
        "\n",
        "AxKit's installer magic requires ExtUtils::AutoInstall. AxKit comes\n",
        "with an older version, but it will not be installed.  You should\n",
        "install the most recent ExtUtils::AutoInstall at your convenience.\n",
        "\n",
        "==================================================================\n",
        "\n",
      );
  require lib; lib->import('./install');
  require './install/ExtUtils/AutoInstall.pm';
}

######################################################
# Standard bits required for have_library and friends
my %config;

$|=1; # flush output

for (@ARGV) {
     my ($k, $v) = split /=/, $_, 2;
     $config{$k} = $v;
 }

$DEBUG = delete $config{DEBUG};
######################################################

ExtUtils::AutoInstall->import
  ( -version => '0.32',
    -core => [
        mod_perl          => '1.17',
        'Digest::MD5'     => '2.09',
        'Compress::Zlib'  => '',
        'Error'           => '0.14',
        'Apache::Request' => '0.31_03',
        'File::Basename'  => '',
        'File::Spec'      => '',
    ],
    "Apache::Test for live server tests" => [
        -tests => [ <t/xslt-basic/*.t> ],
        'Apache::Test'    => '1.00',
    ],
    "Optional modules for using XPathScript" => [
        -default => 0,
        'XML::Parser'     => '2.27',
        'XML::XPath'      => '1.00',
    ],
    "Optional module for using Sablotron XSLT engine" => [
        -default => 0,
        'XML::Sablotron'  => '0.40',
    ],
    "Optional modules required for XSP and LibXSLT engine" => [
        -default => 0,
        'XML::LibXML'     => '1.51',
    ],
    "Optional module required for LibXSLT engine" => [
        -default => 0,
        'XML::LibXSLT'    => '1.49',
    ],
    "Optional for tidying output of AxTraceIntermediate XSP pages" => [
        -default => 0,
        'Perl::Tidy'      => '',
    ],
  );

require Apache::src;
require Apache::MyConfig;

eval {
    require Apache::TestMM;
    import Apache::TestMM qw(test clean);

    Apache::TestMM::filter_args();
    Apache::TestMM::generate_script('t/TEST');
};
undef $@;

my $xml_parser_found = eval "require XML::Parser";

eval {
    print "running xml2-config... ";
    my $libs = backtick('xml2-config --libs');
    $config{LIBS} .= " $libs" if $libs;
    my $inc = backtick('xml2-config --cflags');
    $config{INC} .= " $inc" if $inc;
    print "ok\n";
};
if ($@) {
    print "failed (will try to find libxml2 anyway)\n";
}

if (have_library('xml2')) {
    $config{DEFINE} .= ' -DHAVE_LIBXML2';
    $config{LIBS} .= ' -lxml2 -lz';
    $xml_parser_found++;
}
elsif (!$is_Win32) {
    my $apache;
    
    print <<EOT;

We will now check if your apache has XML symbols in it, to be sure that
AxKit will work under your version of Apache. If you do not wish to 
perform this check (it shouldn't be necessary if you installed Apache
*after* installing Expat), then please just enter 0 (zero) below and
these tests will be skipped.

EOT

    while (!is_apache($apache)) {
        $apache = prompt("Path to apache httpd?", "/usr/local/apache/bin/httpd");
        last if $apache eq "0";
    }
    
    if ($apache ne "0") {
        print "checking for expat symbols in apache... ";
        eval {
            my $symbols = backtick("grep -i xml $apache");
            if ($symbols) {
                die wrap(<<DEATH);
Your Apache has XML symbols in it. This means it will segfault when you
try and use it with XML::Parser. Your options are to either recompile
Apache, or to install libxml2 from http://www.xmlsoft.org and re-install
AxKit. However if you do not recompile Apache without expat/xml support,
you will not be able to use XPathScript, XSP, or any other modules that
make use of XML::Parser. Please see the AxKit FAQ on http://axkit.org
for more details.
DEATH
            }
        };
        print "ok\n";
    }
}
        
if ($is_Win32) {
    if (!have_module('mod_perl', '1.24_01')) {
        die wrap(<<DEATH);
AxKit on Win32 requires mod_perl greater than 1.24_01 in order to 
get the paths to the Apache and mod_perl build directories.

DEATH
    }
    
    require Apache::MyConfig;
    $config{INC} .= qq( -I"$Apache::MyConfig::Setup{MODPERL_INC}/../.." )
        . qq( -I"$Apache::MyConfig::Setup{APACHE_INC}" )
        . qq( -I"$Apache::MyConfig::Setup{APACHE_INC}/../os/win32" );
    $config{CCFLAGS} = $Config{ccflags} . 
        ' -D_WINSOCK2API_ -D_MSWSOCK_ -D_INC_SIGNAL -D_INC_MALLOC ';
    $config{LIBS} = 
        qq( -L"$Apache::MyConfig::Setup{APACHE_LIB}" -lApacheCore ) .
        qq( -L"$Apache::MyConfig::Setup{MODPERL_LIB}" -lmod_perl);
}

if (!$xml_parser_found) {
    die <<"REASON";

***** ERROR *****

No XML Parser library found (tried XML::Parser and libxml2). You
will need to install one of these before AxKit can function properly.

REASON
}

if (eval { require XML::LibXML }) {
    if (XML::LibXML->VERSION eq '1.53') {
        die <<"REASON";

***** ERROR *****

XML::LibXML 1.53 found. This version does not work with AxKit and
has serious bugs which mean we cannot recommend it.

Please either upgrade to 1.54_03 (available on CPAN via a manual
download), downgrade to 1.52 which is stable, or upgrade to a higher
version when they are released.

REASON
    }
}

$config{INC} .= ' ' . Apache::src->new->inc;

if ($DEBUG) {
    print "calling WriteMakefile with config:\n";
    foreach my $k (keys %config) {
        print "$k = $config{$k}\n";
    }
}

# my %prereq_pm = %{delete $config{PREREQ_PM}||{}};

unless ($Apache::MyConfig::Setup{PERL_USELARGEFILES} == 1) {
    $config{CCFLAGS} = strip_lfs($config{CCFLAGS});
}

# rebuild @ARGV from the stored and modified values.
undef(@ARGV);
foreach my $k (keys %config) {
    push @ARGV, "$k=$config{$k}";
}

%config = () if $] > 5.00560; 
rm_f($DEVNULL) if $is_Win32;

WriteMakefile(
        'NAME' => 'AxKit',
        'VERSION_FROM' => 'lib/AxKit.pm',
        'AUTHOR' => 'AxKit.com Limited - http://axkit.com/',
        'ABSTRACT' => 'AxKit is an XML Application Server for mod_perl',
        'DIR' => [ @DIRS ],
        'OBJECT' => '$(O_FILES)',
        %config,
        # PREREQ_PM => \%prereq_pm,
);

#################################################################
# Functions
#################################################################

use Config;
use Cwd;
use Symbol;
use File::Spec;

use vars qw/$DEVNULL $is_Win32 $RUNNING_UNDER_CPAN/;

BEGIN {
    $is_Win32 = ($^O =~ /Win32/);
    if ($is_Win32) {
        $DEVNULL = 'DEVNULL';
    }
    else {
        $DEVNULL = eval { File::Spec->devnull };
        if ($@) { $DEVNULL = '/dev/null' }
    }
    my $cwd = cwd();
    if ($cwd =~ /cpan/i) {
        $RUNNING_UNDER_CPAN = 1;
    }
    else {
        $RUNNING_UNDER_CPAN = $ENV{RUNNING_UNDER_CPAN} || 0;
    }
}

sub strip_lfs {
    my($cflags) = @_;
    return $cflags unless $Config{uselargefiles};
    my $lf = $Config{ccflags_uselargefiles} || '-D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64';
    $cflags =~ s/$lf//;
    $cflags;
}

sub rm_f {
    my @files = @_;
    my @realfiles;
    foreach (@files) {
        push @realfiles, glob($_);
    }
    if (@realfiles) {
        chmod(0777, @realfiles);
        unlink(@realfiles);
    }
}

sub rm_fr {
    my @files = @_;
    my @realfiles;
    foreach (@files) {
        push @realfiles, glob($_);
    }
    foreach my $file (@realfiles) {
        if (-d $file) {
            # warn("$file is a directory\n");
            rm_fr("$file/*");
            rm_fr("$file/.exists");
            rmdir($file) || die "Couldn't remove $file: $!";
        }
        else {
            # warn("removing $file\n");
            chmod(0777, $file);
            unlink($file);
        }
    }
}

sub xsystem {
    my $command = shift;
    if ($DEBUG) {
        print $command, "\n";
        if (system($command) != 0) {
            die "system call to '$command' failed";
        }
        return 1;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $retval = system($command);
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "system call to '$command' failed";
    }
    return 1;
}

sub backtick {
    my $command = shift;
    if ($DEBUG) {
        print $command, "\n";
        my $results = `$command`;
        chomp $results;
        if ($? != 0) {
            die "backticks call to '$command' failed";
        }
        return $results;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $results = `$command`;
    my $retval = $?;
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "backticks call to '$command' failed";
    }
    chomp $results;
    return $results;
}

sub try_link0 {
    my ($src, $opt) = @_;
    my $cfile = gensym();
    # local $config{LIBS};
    # $config{LIBS} .= $opt;
    unless (mkdir(".testlink", 0777)) {
        rm_fr(".testlink");
        mkdir(".testlink", 0777) || die "Cannot create .testlink dir: $!";
    }
    chdir(".testlink");
    open($cfile, ">Conftest.xs") || die "Cannot write to file Conftest.xs: $!";
print $cfile <<EOT;
#ifdef __cplusplus
extern "C" {
#endif
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#ifdef __cplusplus
}
#endif

EOT
    print $cfile $src;
    print $cfile <<EOT;

MODULE = Conftest          PACKAGE = Conftest

PROTOTYPES: DISABLE

EOT
    close($cfile);
    open($cfile, ">Conftest.pm") || die "Cannot write to file Conftest.pm: $!";
    print $cfile <<'EOT';
package Conftest;
$VERSION = 1.0;
require DynaLoader;
@ISA = ('DynaLoader');
bootstrap Conftest $VERSION;
1;
EOT
    close($cfile);
    open($cfile, ">Makefile.PL") || die "Cannot write to file Makefile.PL: $!";
    print $cfile <<'EOT';
use ExtUtils::MakeMaker;
my %config;
while($_ = shift @ARGV) {
    my ($k, $v) = split /=/, $_, 2;
    $config{$k} = $v;
}
WriteMakefile(NAME => "Conftest", VERSION_FROM => "Conftest.pm", %config);
EOT
    close($cfile);
    open($cfile, ">test.pl") || die "Cannot write to file test.pl: $!";
    print $cfile <<EOT;
use Test; BEGIN { plan tests => 1; } END { ok(\$loaded) }
use Conftest; \$loaded++;
EOT
    close($cfile);
    xsystem("$^X Makefile.PL " . join(' ', map { "'$_=$config{$_}'" } keys %config));
    xsystem("$Config{make} test 'OTHERLDFLAGS=$opt'");
}

sub try_link {
    my $start_dir = cwd();
    my $result = eval {
        try_link0(@_);
    };
    warn $@ if $DEBUG && $@;
    chdir($start_dir);
    rm_fr(".testlink");
    return $result;
}

sub have_library {
    my ($lib, $func) = (@_, "blank");
    printf("checking for %s() in -l%s... ", $func, $lib) if $func ne "blank";
    printf("looking for -l%s... ", $lib) if $func eq "blank";

    my $result;
    if ($func) {
        my $libs = $is_Win32 ? " $lib.lib  " : "-l$lib";
        if ($is_Win32) {
            $result = try_link(<<"SRC", $libs);
#include <windows.h>
#include <winsock.h>
blank() { return 0; }
int t() { ${func}(); return 0; }
SRC
            unless ($result) {
                $result = try_link(<<"SRC", $libs);
#include <windows.h>
#include <winsock.h>
blank() { return 0; }
int t() { void ((*p)()); p = (void ((*)()))${func}; return 0; }
SRC
            }
        }
        else {

            $result = try_link(<<"SRC", $libs);
blank() { return 0; }
int t() { ${func}(); return 0; }
SRC
        }
    }

    unless ($result) {
        print "no\n";
        return 0;
    }

    if ($func ne "main") {
        $config{DEFINE} .= uc(" -Dhave_$func");
    }

    print "yes\n";
    return 1;
}

sub have_module {
    my ($module, $version) = (@_, 0);
    printf("checking for module %s >= version %s... ", $module, $version);
    
    print "eval(\"package Foo; use $module $version;\")\n" if $DEBUG;
    eval "package Foo; use $module $version;";
    if ($@) {
        print $@ if $DEBUG;
        print "no\n";
        return 0;
    }
    print "yes\n";
    return 1;
}

sub test_module {
    my ($module, $version, $reason) = @_;
    unless (have_module($module, $version)) {
        if ($RUNNING_UNDER_CPAN) {
            if (prompt("Add $module to list of modules to install?", 'Y') =~ /^y/i) {
                $config{PREREQ_PM}{$module} = $version;
                return 1;
            }
        }
        else {
            print wrap($reason);
            return 0;
        }
    }
    return 1;
}

sub is_apache {
    my $path = shift;
    return unless $path;
    if (-e $path && -x _) {
        my $version = eval { backtick("$path -v") };
        if (!$@) {
            $version =~ /Server version: Apache/
                && return 1;
        }
    }
    warn("No apache httpd found at $path\n");
    return;
}
