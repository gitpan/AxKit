# $Id: Makefile.PL,v 1.29 2001/02/16 19:16:58 matt Exp $

package AxKit;
# file Makefile.PL

use ExtUtils::MakeMaker;

use Apache::ExtUtils qw/command_table/;
use Apache::src ();
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

my $DEBUG = delete $config{DEBUG};
######################################################

if (!have_module('mod_perl', '1.17')) {
    die wrap(<<DEATH);
AxKit requires mod_perl to be able to even run. You do not appear to
have mod_perl installed (or your mod_perl is earlier than version 1.17).

You can download mod_perl from http://perl.apache.org/

DEATH
}
else {
    unless (have_module('mod_perl', '1.24_01')) {
        rename("AxKit.pm", "AxKit.pm.old") || die "Can't fixup AxKit.pm: $!";
        open(FH, "AxKit.pm.old") || die "Can't open AxKit.pm.old: $!";
        open(WRFH, ">AxKit.pm") || die "Can't write AxKit.pm: $!";
        my $nowrite = 0;
        while(<FH>) {
            s/^sub DIR_MERGE(.*)$/sub NO_DIR_MERGE$1 # renamed from DIR_MERGE due to mem leaks/m;
            print WRFH $_;
        }
        close FH;
        close WRFH;
        rm_f("AxKit.pm.old");
    }
}

# delete returns the value, which would be 1 if enabled.
if (delete $config{NO_DIRECTIVES}) { 
    rename("AxKit.pm", "AxKit.pm.old") || die "Can't fixup AxKit.pm: $!";
    open(FH, "AxKit.pm.old") || die "Can't open AxKit.pm.old: $!";
    open(WRFH, ">AxKit.pm") || die "Can't write AxKit.pm: $!";
    my $nowrite = 0;
    while(<FH>) {
        if (!$nowrite && $_ =~ /^if \(\$ENV{MOD_PERL}\) \{/) {
            $nowrite = 1;
        }
        print WRFH $_ unless $nowrite;
        if ($nowrite && $_ =~ /^}/) {
            $nowrite = 0;
        }
    }
    close FH;
    close WRFH;
    rm_f("AxKit.pm.old");
    rename("AxKit.xs", "AxKit.xs.unused") || die "Can't remove (rename) AxKit.xs: $!";
}

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
XML::XPath 1.00 or higher is required for XPathScript and XSP
to work. You don't have to install it, but you won't be able
to use XPathScript stylesheets or XSP pages without it.
REASON

test_module('Storable', '0.7', <<"REASON");
Storable 0.7 or higher is required for XPathScript to work.
You don't have to install it, but you won't be able
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

WriteMakefile(
        'NAME' => __PACKAGE__,
        'VERSION_FROM' => 'AxKit.pm',
        'AUTHOR' => 'AxKit.com Limited - http://axkit.com/',
        'ABSTRACT' => 'AxKit is an XML Application Server for mod_perl',
        'DIR' => [ @DIRS ],
#        %config,
);

#################################################################
# Functions
#################################################################

use Config;
use Symbol;

use vars qw/$LINK/;

BEGIN {
  $LINK = "$Config{ld} -o conftest $Config{ccflags} -I$Config{incpath} %s $Config{ldflags} conftest.c $Config{libs} %s %s";
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
    open(STDOUT, ">/dev/null");
    open(STDERR, ">/dev/null");
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

sub MY::clean {
    package MY;
    my $self = shift;
    
    my $clean = $self->SUPER::clean(@_);
    
    $clean .= <<EOF;
\t-mv AxKit.xs.unused AxKit.xs \$(DEV_NULL)
EOF

    return $clean;
}
