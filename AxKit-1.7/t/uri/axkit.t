#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET POST ) ;

plan tests => 1, have_module qw(LWP);

sub test_basic {
    my $resp = GET '/uri/axkit/01.xml' ;
    return 0 unless $resp->content =~ /subrequest text added/gi;
    return 1;
}

ok( test_basic(),1,    "Testing axkit:// subrequests" );
