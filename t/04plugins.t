use Test;
BEGIN { plan tests => 3 }

require "t/test_module.pl";

test_module("Apache::AxKit::Plugin::Fragment", "XML::XPath");

test_module("Apache::AxKit::Plugin::Passthru");

test_module("Apache::AxKit::Plugin::QueryStringCache");
