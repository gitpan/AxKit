#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET POST ) ;

plan tests => 2, have_module qw(LWP);

sub test_basic1 {
    my $resp1 = GET '/component/configreader/get_matching_processors_1.xml' ;
    return 0 unless $resp1->content =~ /get_matching_processors_1.xsl/gi;
    return 1;
}

sub test_basic2 {
    my $resp2 = GET '/component/configreader/get_matching_processors_2.xml' ;
    return 0 unless $resp2->content =~ /get_matching_processors_2.xsl/gi;
    return 1;
}

ok( test_basic1(),1,    "Testing Get Matching Processors" );
ok( test_basic2(),1,    "Testing Get Matching Processors doesn't leak");
