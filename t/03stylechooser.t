use Test;
BEGIN { plan tests => 5 }

require "t/test_module.pl";

test_module("Apache::AxKit::StyleChooser::FileSuffix");

test_module("Apache::AxKit::StyleChooser::Cookie");

test_module("Apache::AxKit::StyleChooser::PathInfo");

test_module("Apache::AxKit::StyleChooser::QueryString");

test_module("Apache::AxKit::StyleChooser::UserAgent");
