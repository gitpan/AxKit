use Test;
BEGIN { plan tests => 2 }

require "t/test_module.pl";

test_module("Apache::AxKit::Plugins::Fragment", "XML::XPath");

test_module("Apache::AxKit::Plugins::Passthru");
