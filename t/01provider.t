use Test;
BEGIN { plan tests => 4 }
use lib 't';

require "test_module.pl";

test_module("Apache::AxKit::Provider");

test_module("Apache::AxKit::Provider::File");

test_module("Apache::AxKit::Provider::Scalar");

test_module("Apache::AxKit::Provider::Filter", "Apache::Filter");
