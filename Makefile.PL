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
				{ name => 'AxAddDefaultStyleMap',
				  errmsg => 'a href and a mime type to use',
				  args_how => 'TAKE23',
				  req_override => 'OR_ALL',
				},
				{ name => 'AxResetDefaultStyleMap',
				  errmsg => 'reset the default styles',
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
				{ name => 'AxStylesCascade',
				  errmsg => 'should stylesheets cascade',
				  args_how => 'FLAG',
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
				{ name => 'AxStyleProvider',
				  errmsg => 'alternative module to use for reading stylesheets',
				  args_how => 'TAKE1',
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
				'Digest::MD5' => 2.09,
				'mod_perl' => 1.17,
				'Storable' => 0.6,
			},
		'clean' => { 'FILES' => '*.xs*' },
);
