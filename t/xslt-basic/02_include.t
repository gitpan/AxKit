#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET ) ;

plan tests => 1, have_module qw(LWP);

sub test_basic {
    my $resp = GET '/xslt-basic/02_include.xml' ;
    #warn "GOT CONTENT:" . $resp->content();
    return 0 unless $resp->content =~ /Included overrides default/gi;
    return 1;
}

ok( test_basic(),1,    "Testing stylesheet include behavior." );
