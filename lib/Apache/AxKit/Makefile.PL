# $Id: Makefile.PL,v 1.4 2001/01/19 22:30:16 matt Exp $

package Apache::AxKit::CharsetConv;

use ExtUtils::MakeMaker;

use Config;
use Symbol;

use vars qw/$LINK/;

BEGIN {
  $LINK = "$Config{ld} -o conftest $Config{ccflags} -I$Config{incpath} %s $Config{ldflags} conftest.c %s %s";
}

######################################################
# Standard bits required for have_library and friends
my %config;

$|=1; # flush output

for(@ARGV) {
    my ($k, $v) = split /=/, $_, 2;
    $config{$k} = $v;
}

my $DEBUG = delete $config{DEBUG};
######################################################

######################################################
# test iconv() param types for const
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
    backtick(sprintf($LINK, $config{INC}, $config{LIBS}, "2>&1"));
};
if ($@) {
    warn $@;
}
rm_f("conftest*");
if ($output =~ /warning: passing arg 2/) {
    $config{DEFINE} .= uc(" -Diconv_second_param_is_const");
}
######################################################

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
    $inherited =~ s|\s\.\./blib| \.\./\.\./\.\./blib|g;
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
    open(STDOUT, ">/dev/null");
    open(STDERR, ">/dev/null");
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
