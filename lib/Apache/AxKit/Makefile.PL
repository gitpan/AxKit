# $Id: Makefile.PL,v 1.15 2001/06/05 09:39:28 matt Exp $

package Apache::AxKit::CharsetConv;

use ExtUtils::MakeMaker;

use Config;
use Symbol;
use File::Spec;

use vars qw/$LINK $DEVNULL/;

BEGIN {
    $LINK = "$Config{cc} $Config{ccdlflags} -o conftest $Config{ccflags} -I$Config{incpath} $Config{ldflags} %s %s conftest.c $Config{libs} %s";
    $DEVNULL = eval { File::Spec->devnull };
    if ($@) { $DEVNULL = "/dev/null" }
}

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

if ($^O =~ /Win32/) {
    $config{LIBS} .= " -liconv";
}
else {
    if (have_library("iconv", "iconv") || have_library("iconv", "libiconv")) {
        # probably FreeBSD
        print "System is probably *BSD. Adding -liconv to LIBS\n\n";
        $config{LIBS} .= " -liconv";
    }
    elsif (have_library("c", "iconv")) {
        # Other Unix - good.
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
    print "checking if iconv() param 2 is const... ";
    my $cfile = gensym();
    open($cfile, ">conftest.c") || die "Cannot write to file conftest.c";
    print $cfile <<"SRC";
#include "iconv.h"
int main() { return 0; }
int t() {
    char *foo = "foo";
    size_t ret;
    iconv_t iconv_handle;
    size_t inbytesleft;
    size_t outbytesleft;
    char *ocursor;
    ret = iconv(iconv_handle, &foo, &inbytesleft,
                            &ocursor, &outbytesleft);
    return 0;
}
SRC
    close $cfile;
    my $output = eval {
        backtick(sprintf($LINK, $config{INC}, $config{LIBS}, '2>&1'));
    };
    if ($@) {
        warn $@ if $DEBUG;
    }
    rm_f("conftest*");
    if ($output =~ /warning: passing arg 2/) {
        print "yes\n";
        $config{DEFINE} .= uc(" -Diconv_second_param_is_const");
    }
    else {
        print "no\n";
    }
}

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

sub try_link0 {
    my ($src, $opt) = @_;
    my $cfile = gensym();
    open($cfile, ">conftest.c") || die "Cannot write to file conftest.c";
    print $cfile $src;
    close($cfile);
    xsystem(sprintf($LINK, $config{INC}, $config{LIBS}, $opt));
}

sub try_link {
    my $result = eval {
        try_link0(@_);
    };
    warn $@ if $DEBUG && $@;
    rm_f("conftest*");
    return $result;
}

sub have_library {
    my ($lib, $func) = (@_, "main");
    
    printf("checking for %s() in -l%s... ", $func, $lib);

    my $result;
    if ($func) {
        my $libs = "-l$lib";
        if ($^O eq 'MSWin32') {
            $result = try_link(<<"SRC", $libs);
#include <windows.h>
#include <winsock.h>
int main() { return 0; }
int t() { #{func}(); return 0; }
SRC
            unless ($result) {
                $result = try_link(<<"SRC", $libs);
#include <windows.h>
#include <winsock.h>
int main() { return 0; }
int t() { void ((*p)()); p = (void ((*)()))#{func}; return 0; }
SRC
            }
        }
        else {

            $result = try_link(<<"SRC", $libs);
int main() { return 0; }
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
