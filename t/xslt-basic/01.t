#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET POST ) ;

plan tests => 1, have_module qw(LWP);

sub test_basic {
    my $resp = GET '/xslt-basic/01.xml' ;
    # warn "GOT CONTENT:" . $resp->content();
    return 0 unless $resp->content =~ /child text added/gi;
    return 1;
}

ok( test_basic(),1,    "Testing basic XSLT Transformation  output" );
