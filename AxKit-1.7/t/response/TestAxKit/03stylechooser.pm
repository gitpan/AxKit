package TestAxKit::03stylechooser;

use strict;
use warnings FATAL => 'all';
use Apache::Test;
use Apache::TestUtil;
use constant MP2 => $mod_perl::VERSION >= 1.99;
use AxKitTestModule qw(test_module);
  
BEGIN {
	if (MP2) {
		require Apache::Const;
		Apache::Const->import(-compile => qw(OK DECLINED));
	} else {
		require Apache::Constants;
		Apache::Constants->import(qw(OK DECLINED));
	}
} 



sub handler {
    my $r = shift;

    plan $r, tests => 5;

	test_module("Apache::AxKit::StyleChooser::FileSuffix");

	test_module("Apache::AxKit::StyleChooser::Cookie");

	test_module("Apache::AxKit::StyleChooser::PathInfo");

	test_module("Apache::AxKit::StyleChooser::QueryString");

	test_module("Apache::AxKit::StyleChooser::UserAgent");
	
    return MP2 ? Apache::OK : Apache::Constants::OK; 
}


1;
