#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET POST ) ;

plan tests => 1, have_module qw(LWP);

sub test_basic {
    my $resp = GET '/xpathscript-basic/01.xml' ;
    return 0 unless $resp->content =~ m!Current URI: /xpathscript-basic/01.xml!gi;
    return 1;
}

ok( test_basic(),1,    "Testing basic Xpathscript transformation output" );
