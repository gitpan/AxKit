use Test;
BEGIN { plan tests => 9 }

require "t/test_module.pl";

test_module("Apache::AxKit::Language::XPathScript", "XML::XPath");

test_module("Apache::AxKit::Language::AxPoint", "PDFLib");

test_module("Apache::AxKit::Language::Sablot", "XML::Sablotron");

test_module("Apache::AxKit::Language::LibXSLT", "XML::LibXSLT");

test_module("Apache::AxKit::Language::XMLNewsRDF", "XMLNews::HTMLTemplate");

test_module("Apache::AxKit::Language::XMLNewsNITF", "XMLNews::HTMLTemplate");

test_module("Apache::AxKit::Language::XSP", "XML::XPath");

test_module("Apache::AxKit::Language::XSP::TaglibHelper", "XML::XPath");

test_module("Apache::AxKit::Language::PassiveTeX");
