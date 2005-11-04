#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET ) ;

plan tests => 1, have_module qw(LWP);

sub test_basic {
    my $resp = GET '/provider/dir';
    return 0 unless $resp->content =~ /document transformed/gi;
    return 1;
}


ok(test_basic(), 1, "testing dir provider (AxHandleDirs)");

