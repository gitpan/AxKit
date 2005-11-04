#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET POST ) ;

plan tests => 1, have_module qw(LWP);


sub test_basic {
    my $resp = POST '/provider/post', 'Content-Type' => 'text/xml', content => <<XML;
<?xml version="1.0"?>
<root/>
XML
    return 0 unless $resp->content =~ /document transformed/gi;
    return 1;
}


ok( test_basic(),1,    "testing post provider" );

