use Test;
BEGIN { plan tests => 1 }

require "t/test_module.pl";

test_module("Apache::AxKit::MediaChooser::WAPCheck");
