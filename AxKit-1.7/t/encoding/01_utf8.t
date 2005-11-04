#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET ) ;

BEGIN { $INC{'bytes.pm'}++ if $] < 5.006 }

plan tests => 20, have_module qw(LWP);

sub test_basic {
    use bytes;
    my $resp = GET '/encoding/01.xml' ;
    my $bytes = unpack("U0A*", $resp->content());
    return 0 unless $bytes =~ /\xC2\xA9/;
    return 1;
}

for (1..20) {
    ok( test_basic(), 1, "Testing output created right encoding." );
}

