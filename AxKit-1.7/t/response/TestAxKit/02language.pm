package TestAxKit::02language;

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

    plan $r, tests => 9;

	test_module("Apache::AxKit::Language::XPathScript", "XML::XPath");

	test_module("Apache::AxKit::Language::AxPoint", "XML::Handler::AxPoint");

	test_module("Apache::AxKit::Language::Sablot", "XML::Sablotron");

	test_module("Apache::AxKit::Language::LibXSLT", "XML::LibXSLT");

	test_module("Apache::AxKit::Language::XMLNewsRDF", "XMLNews::HTMLTemplate");

	test_module("Apache::AxKit::Language::XMLNewsNITF", "XMLNews::HTMLTemplate");

	test_module("Apache::AxKit::Language::XSP", "XML::LibXML");

	test_module("Apache::AxKit::Language::XSP::TaglibHelper", "XML::LibXML");

	test_module("Apache::AxKit::Language::PassiveTeX");
	
    return MP2 ? Apache::OK : Apache::Constants::OK; 
}


1;
