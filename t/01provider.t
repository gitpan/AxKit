use Test;
BEGIN { plan tests => 4 }

require "t/test_module.pl";

test_module("Apache::AxKit::Provider");

test_module("Apache::AxKit::Provider::File");

test_module("Apache::AxKit::Provider::Scalar");

test_module("Apache::AxKit::Provider::Filter", "Apache::Filter");
