# $Id: Makefile.PL,v 1.17 2000/09/14 20:43:09 matt Exp $

package AxKit;
# file Makefile.PL

use ExtUtils::MakeMaker;

use Apache::ExtUtils qw/command_table/;
use Apache::src ();

require 5.005;

my %config;

while($_ = shift) {
    my ($k, $v) = split /=/, $_, 2;
    $config{$k} = $v;
}

my @directives = (
                { name => 'AxAddProcessor',
                  errmsg => 'a mime type and a stylesheet to use',
                  args_how => 'TAKE2',
                  req_override => 'OR_ALL',
                },
                { name => 'AxAddDocTypeProcessor',
                  errmsg => 'a mime type, a stylesheet, and an XML public identifier',
                  args_how => 'TAKE3',
                  req_override => 'OR_ALL',
                },
                { name => 'AxAddDTDProcessor',
                  errmsg => 'a mime type, a stylesheet, and a dtd filename',
                  args_how => 'TAKE3',
                  req_override => 'OR_ALL',
                },
                { name => 'AxAddRootProcessor',
                  errmsg => 'a mime type, a stylesheet, and a root element',
                  args_how => 'TAKE3',
                  req_override => 'OR_ALL',
                },
                { name => '<AxMediaType',
                  errmsg => 'Media type block',
                  args_how => 'RAW_ARGS',
                  req_override => 'OR_ALL',
                },
                { name => '</AxMediaType>',
                  errmsg => 'End of media type block',
                  args_how => 'NO_ARGS',
                  req_override => 'OR_ALL',
                },
                { name => '<AxStyleName',
                  errmsg => 'Style name block',
                  args_how => 'RAW_ARGS',
                  req_override => 'OR_ALL',
                },
                { name => '</AxStyleName>',
                  errmsg => 'End of Style name block',
                  args_how => 'NO_ARGS',
                  req_override => 'OR_ALL',
                },
                { name => 'AxAddStyleMap',
                  errmsg => 'a mime type and a module name to use',
                  args_how => 'TAKE2',
                  req_override => 'OR_ALL',
                },
                { name => 'AxResetStyleMap',
                  errmsg => 'reset the styles',
                  args_how => 'NO_ARGS',
                  req_override => 'OR_ALL',
                },
                { name => 'AxCacheDir',
                  errmsg => 'directory to store cache files',
                  args_how => 'TAKE1',
                  req_override => 'OR_ALL',
                },
                { name => 'AxConfigReader',
                  errmsg => 'alternative module to use for reading configuration',
                  args_how => 'TAKE1',
                  req_override => 'OR_ALL',
                },
                { name => 'AxProvider',
                  errmsg => 'alternative module to use for reading the xml',
                  args_how => 'TAKE1',
                  req_override => 'OR_ALL',
                },
                { name => 'AxStyle',
                  errmsg => 'a default stylesheet (title) to use',
                  args_how => 'TAKE1',
                  req_override => 'OR_ALL',
                },
                { name => 'AxMedia',
                  errmsg => 'a default media to use other than screen',
                  args_how => 'TAKE1',
                  req_override => 'OR_ALL',
                },
                { name => 'AxCacheModule',
                  errmsg => 'alternative cache module',
                  args_how => 'TAKE1',
                  req_override => 'OR_ALL',
                },
                { name => 'AxDebugLevel',
                  errmsg => 'debug level (0 == none, higher numbers == more debugging)',
                  args_how => 'TAKE1',
                  req_override => 'OR_ALL',
                },
                { name => 'AxOutputCharset',
                  errmsg => 'character set used by Unicode::Map8',
                  args_how => 'TAKE1',
                  req_override => 'OR_ALL',
                },
                { name => 'AxGzipOutput',
                  errmsg => 'On or Off [default] to gzip the output',
                  args_how => 'FLAG',
                  req_override => 'OR_ALL',
                },
                { name => 'AxErrorStylesheet',
                  errmsg => 'Error Stylesheet and a content-type for the StyleMap to use',
                  args_how => 'TAKE2',
                  req_override => 'OR_ALL',
                },
            );

unless ($config{NO_DIRECTIVES} == 1) {
    command_table(\@directives);
    require mod_perl;
    if ($mod_perl::VERSION < 1.25) {
        open (FILE, ">>AxKit.xs") || die "Can't append to AxKit.xs: $!";
        print FILE 'void
END()

    CODE:
    if (find_linked_module("AxKit")) {
        remove_module(&XS_AxKit);
    }
';
        close(FILE);
    }
}
else {
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
}

WriteMakefile(
        'NAME' => __PACKAGE__,
        'VERSION_FROM' => 'AxKit.pm',
        'INC' => Apache::src->new->inc,
        'PREREQ_PM' => {
                'XML::XPath' => 0.55,
                'XML::Parser' => 2.27,
                'MIME::Base64' => 0,
                'Digest::MD5' => 2.09,
                'mod_perl' => 1.17,
                'Storable' => 0.6,
                'XML::Sablotron' => 0.40,
                'Apache::Request' => 0,
                'DBI' => 1.13,
                'Unicode::Map8' => 0.10,
                'Unicode::String' => 2.06,
                'Time::HiRes' => 1.20,
                'Compress::Zlib' => 0,
                'Error' => 0.13,
            },
        'clean' => { 'FILES' => '*.xs*' },
        %config,
);
