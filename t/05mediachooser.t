use Test;
BEGIN { plan tests => 1 }
use lib 't';

require "test_module.pl";

test_module("Apache::AxKit::MediaChooser::WAPCheck");
