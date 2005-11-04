# $Id: Makefile.PL,v 1.2 2005/08/09 18:06:12 matts Exp $

package Apache::AxKit::CharsetConv;

use ExtUtils::MakeMaker;

######################################################
# Standard bits required for have_library and friends
my %config;

$|=1; # flush output

while($_ = shift @ARGV) {
    my ($k, $v) = split /=/, $_, 2;
    $config{$k} = $v;
}

$DEBUG = $AxKit::DEBUG || delete $config{DEBUG};
######################################################

if (have_library("c", "iconv")) {
    # other unix
}
elsif (have_library("iconv", "iconv") || have_library("iconv", "libiconv")) {
    # probably FreeBSD or Win32
    print "Found libiconv. Might be *BSD or Win32...\n\n";
    $config{LIBS} .= " -liconv";
}
else {
    print <<"REASON";
AxKit needs the iconv system library to work properly. This comes by
default with most Unix systems, however it may be that you do not
have the development libraries installed, or possibly that you just
don't have iconv available on your system. For *BSD systems, iconv
is available in your distribution's ports collection. For Win32
systems, a google search will often suffice to find a Win32 library
version.
REASON
    exit(0);
}

######################################################
# test iconv() param types for const
# print "checking if iconv() param 2 is const... ";
# my $cfile = gensym();
# open($cfile, ">conftest.c") || die "Cannot write to file conftest.c";
# print $cfile <<"SRC";
# #include "iconv.h"
# int main() { return 0; }
# int t() {
#     char *foo = "foo";
#     size_t ret;
#     iconv_t iconv_handle;
#     size_t inbytesleft;
#     size_t outbytesleft;
#     char *ocursor;
#     ret = iconv(iconv_handle, &foo, &inbytesleft,
#                             &ocursor, &outbytesleft);
#     return 0;
# }
# SRC
# close $cfile;
# my $output = $is_Win32 ? 
#     eval {
#         backtick(sprintf($CC, $config{INC})) .
#         backtick(sprintf($LINK, $config{LIBS}, " iconv.lib"));
#     }
#     :
#     eval {
#         backtick(sprintf($LINK, $config{INC}, $config{LIBS}, '2>&1'));
#     };
# 
# if ($@) {
#     warn $@ if $DEBUG;
# }
# rm_f("conftest*");
# if ($output =~ /warning: passing arg 2/) {
#     print "yes\n";
#     $config{DEFINE} .= uc(" -Diconv_second_param_is_const");
# }
# else {
#     print "no\n";
# }

######################################################

if ($DEBUG) {
    print "calling WriteMakefile with config:\n";
    foreach my $k (keys %config) {
        print "$k = $config{$k}\n";
    }
}

foreach my $k (keys %config) {
    push @ARGV, "$k=$config{$k}";
}

#%config = () if $] > 5.00560; 
rm_f($DEVNULL) if $is_Win32;

WriteMakefile(
    'NAME' => 'Apache::AxKit::CharsetConv',
    'VERSION_FROM' => 'CharsetConv.pm',
    %config,
);

sub MY::constants {
    package MY;
    my $class = shift;
    my $inherited = $class->SUPER::constants(@_);
#    warn "CONSTANTS: $inherited\n";
    $inherited =~ s|\s\Q../blib\E| ../../../blib|g;
    return $inherited;
}

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
    warn("$k = $v\n");
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
