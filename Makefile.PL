# $Id: Makefile.PL,v 1.50 2001/12/11 13:02:58 matt Exp $

package AxKit;
# file Makefile.PL

use ExtUtils::MakeMaker;

use Text::Wrap ();
use Cwd;

require 5.005;

sub wrap ($)
{
    my $text = shift;
    $text =~ s/^\s+//;
    $text =~ s/\s+$//;
    Text::Wrap::wrap('', '', $text) . "\n\n";
}

my @DIRS = ('./lib/Apache/AxKit', './Apache-MimeXML');
my $from_dir = cwd;
my $expat_dir = "expat-1.95.1";

######################################################
# Standard bits required for have_library and friends
my %config;

$|=1; # flush output

while($_ = shift @ARGV) {
    my ($k, $v) = split /=/, $_, 2;
    $config{$k} = $v;
}

$DEBUG = delete $config{DEBUG};
######################################################

if (!have_module('mod_perl', '1.17')) {
    die wrap(<<DEATH);
AxKit requires mod_perl to be able to even run. You do not appear to
have mod_perl installed (or your mod_perl is earlier than version 1.17).

You can download mod_perl from http://perl.apache.org/

DEATH
}

require Apache::src;

my $install_expat = 0;

unless (have_module('XML::Parser', '2.27')) {
    # XML::Parser not installed
    if (!have_library("expat")) {
        print "compiling expat... ";
        eval {
            my $expat_opts = delete $config{EXPAT_OPTS};
            xsystem("cd $expat_dir && ./configure $expat_opts && make");
            $install_expat = 1;
            $config{"EXPATINCPATH"} = MM->catdir($from_dir, $expat_dir, 'lib');
            $config{"EXPATLIBPATH"} = MM->catdir($from_dir, $expat_dir, 'lib', '.libs');
            print "ok\n";
        };
        if ($@) {
            print "failed\n";
            die "Compilation of expat failed. Re-run with DEBUG=1 to see why.\n";
        }
    }
    push @DIRS, 'XML-Parser-2.30';
}

unless (have_module('Digest::MD5', '2.09')) {
    push @DIRS, 'Digest-MD5-2.12';
}

unless (have_module('Compress::Zlib')) {
    push @DIRS, 'Compress-Zlib-1.09';
}

unless (have_module('Error', '0.13')) {
    push @DIRS, 'Error-0.13';
}

unless (have_module('Apache::Request', '0.31_03')) {
    push @DIRS, 'libapreq-0.31_03';
}

test_module('XML::XPath', '1.00', <<"REASON");
XML::XPath 1.00 or higher is required for XPathScript
to work. You don't have to install it, but you won't be able
to use XPathScript stylesheets without it.
REASON

test_module('HTTP::GHTTP', '1.00', <<"REASON");
HTTP::GHTTP is used for retrieving remote URIs within AxKit.
We use HTTP::GHTTP because it is significantly faster and lighter
than LWP, however AxKit will use LWP if it cannot locate
HTTP::GHTTP.
REASON


test_module('XML::Sablotron', '0.40', <<"REASON");
XML::Sablotron 0.40 or higher is required for our Sablotron 
XSLT processor to work. You don't have to install it, 
but you won't be able to use Apache::AxKit::Language::Sablot without it.
REASON

test_module('XML::LibXML', '1.31', <<"REASON");
XML::LibXML 1.31 or higher is required for the XSP engine
to work. You don't have to install it, but you won't
be able to use XSP pages without it.
REASON
        
test_module('XML::LibXSLT', '1.31', <<"REASON");
XML::LibXSLT 1.31 or higher is required for our LibXSLT 
XSLT processor to work. You don't have to install it, 
but you won't be able to use Apache::AxKit::Language::LibXSLT without it.
REASON


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
}
elsif (!$is_Win32) {
    my $apache;
    
    print <<EOT;

We will now check if your apache has XML symbols in it, to be sure that
AxKit will work under your version of Apache. If you do not wish to 
perform this check, please just enter 0 (zero) below.

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
    $config{INC} .= qq{ -I"$Apache::MyConfig::Setup{MODPERL_INC}/../.." }
        . qq{ -I"$Apache::MyConfig::Setup{APACHE_INC}" }
        . qq{ -I"$Apache::MyConfig::Setup{APACHE_INC}/../os/win32" };
    $config{CCFLAGS} = $Config{ccflags} . 
        ' -D_WINSOCK2API_ -D_MSWSOCK_ -D_INC_SIGNAL -D_INC_MALLOC ';
    $config{LIBS} = 
        qq{ -L"$Apache::MyConfig::Setup{APACHE_LIB}" -lApacheCore } .
        qq{ -L"$Apache::MyConfig::Setup{MODPERL_LIB}" -lmod_perl};
}

$config{INC} .= ' ' . Apache::src->new->inc;

if ($DEBUG) {
    print "calling WriteMakefile with config:\n";
    foreach my $k (keys %config) {
        print "$k = $config{$k}\n";
    }
}

foreach my $k (keys %config) {
    push @ARGV, "$k=$config{$k}";
}

%config = () if $] > 5.00560; 
rm_f($DEVNULL) if $is_Win32;

WriteMakefile(
        'NAME' => __PACKAGE__,
        'VERSION_FROM' => 'AxKit.pm',
        'AUTHOR' => 'AxKit.com Limited - http://axkit.com/',
        'ABSTRACT' => 'AxKit is an XML Application Server for mod_perl',
        'DIR' => [ @DIRS ],
        'OBJECT' => '$(O_FILES)',
        %config,
);

#################################################################
# Functions
#################################################################

use Config;
use Cwd;
use Symbol;
use File::Spec;

use vars qw/$DEVNULL $is_Win32/;

BEGIN {
    $is_Win32 = ($^O =~ /Win32/);
    if ($is_Win32) {
        $DEVNULL = 'DEVNULL';
    }
    else {
        $DEVNULL = eval { File::Spec->devnull };
        if ($@) { $DEVNULL = '/dev/null' }
    }
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
        if ($INC{'CPAN.pm'}) {
            if (prompt("Add $module to list of modules to install?", 'Y') =~ /^y/i) {
                $config{PREREQ_PM}{$module} = $version;
            }
        }
        else {
            print wrap($reason);
        }
        return 0;
    }
    return 1;
}

sub MY::install {
    package MY;
    my $self = shift;

    my $install = $self->SUPER::install(@_);
    
    if ($install_expat) {
        $install =~ s/(install :: .*)$/$1 expat_install/m;
        $install .= <<INSTALL;

expat_install :
\t\@cd $expat_dir && \$(SHELL) -c \$(MAKE) install

INSTALL
    }
    
    return $install;
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
