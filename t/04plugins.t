use Test;
BEGIN { plan tests => 3 }

require "t/test_module.pl";

test_module("Apache::AxKit::Plugins::Fragment", "XML::XPath");

test_module("Apache::AxKit::Plugins::Passthru");

test_module("Apache::AxKit::Plugins::QueryStringCache");
