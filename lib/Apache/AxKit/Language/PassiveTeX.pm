# $Id: PassiveTeX.pm,v 1.2 2001/11/20 20:31:49 matt Exp $

package Apache::AxKit::Language::PassiveTeX;

@ISA = ('Apache::AxKit::Language');

use strict;

use Apache;
use Apache::Request;
use Apache::AxKit::Language;
use Apache::AxKit::Provider;
use File::Copy ();
use File::Temp ();
use File::Path ();
use File::Basename qw(dirname);
use Cwd;

my $olddir;
my $tempdir;

sub stylesheet_exists () { 0; }

sub handler {
    my $class = shift;
    my ($r, $xml_provider, undef, $last_in_chain) = @_;
    
    $tempdir = File::Temp::tempdir();
    if (!$tempdir) {
        die "Cannot create tempdir: $!";
    }
    
    AxKit::Debug(8, "Got tempdir: $tempdir");
    
    $olddir = cwd;
    
    if (my $dom = $r->pnotes('dom_tree')) {
        my $source_text = $dom->toString;
        delete $r->pnotes()->{'dom_tree'};
        my $fh = Apache->gensym();
        chdir($tempdir) || fail("Cannot cd: $!");
        open($fh, ">temp.fo") || fail("Cannot write: $!");
        print $fh $source_text;
        close($fh) || fail("Cannot close: $!");
    }
    elsif (my $source_text = $r->pnotes('xml_string')) {
        # ok...
        my $fh = Apache->gensym();
        chdir($tempdir) || fail("Cannot cd: $!");
        open($fh, ">temp.fo") || fail("Cannot write: $!");
        print $fh $source_text;
        close($fh) || fail("Cannot close: $!");
    }
    else {
        my $text = eval { ${$xml_provider->get_strref()} };
        if ($@) {
            my $fh = $xml_provider->get_fh();
            chdir($tempdir) || fail("Cannot cd: $!");
            File::Copy::copy($fh, "temp.fo");
        }
        else {
            my $fh = Apache->gensym();
            chdir($tempdir) || fail("Cannot cd: $!");
            open($fh, ">temp.fo") || fail("Cannot write: $!");
            print $fh $text;
            close($fh) || fail("Cannot close: $!");
        }
    }
    
    chdir($tempdir) || fail("Cannot cd: $!");
    
    local $ENV{TEXINPUTS} = dirname($r->filename()); 
    AxKit::Debug(8, "About to shell out to pdfxmltex - hope you have passivetex installed...");
    my $retval = system("pdfxmltex temp.fo");
    $retval >>= 8;
    
    if ($retval) {
        fail("pdfxmltex exited with $retval");
    }
    
    my $pdfh = Apache->gensym();
    open($pdfh, "temp.pdf") || fail("Cannot open PDF: $!");
    
    $AxKit::Cfg->AllowOutputCharset(0);
    
    $r->content_type("application/pdf");
    
    local $/;
    
    $r->print(<$pdfh>);
}

sub cleanup {
    chdir $olddir;
    File::Path::rmtree($tempdir);
}

sub fail {
    cleanup();
    die @_;
}

1;
