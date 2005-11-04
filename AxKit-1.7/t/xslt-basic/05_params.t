#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET ) ;

plan tests => 1, have_module qw(LWP);

sub test_basic {
    my $resp = GET '/xslt-basic/05_params.xml?p1=passed;p2=data' ;
    #warn "GOT CONTENT:" . $resp->content();
    return 0 unless $resp->content =~ /passed data/gi;
    return 1;
}

ok( test_basic(),1,    "Testing stylesheet param passing behavior." );
