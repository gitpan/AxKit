package TestAxKit::04plugins;

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

    plan $r, tests => 3;

	test_module("Apache::AxKit::Plugin::Fragment", "XML::XPath");

	test_module("Apache::AxKit::Plugin::Passthru");

	test_module("Apache::AxKit::Plugin::QueryStringCache");
	
    return MP2 ? Apache::OK : Apache::Constants::OK; 
}


1;
