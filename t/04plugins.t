use Test;
BEGIN { plan tests => 3 }
use lib 't';

require "test_module.pl";

test_module("Apache::AxKit::Plugin::Fragment", "XML::XPath");

test_module("Apache::AxKit::Plugin::Passthru");

test_module("Apache::AxKit::Plugin::QueryStringCache");
