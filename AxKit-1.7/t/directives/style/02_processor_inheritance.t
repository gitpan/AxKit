#!perl
use Apache::Test;
use Apache::TestUtil;
use Apache::TestRequest qw( GET ) ;

plan tests => 1, have_module qw(LWP);

sub test_basic {
    my $resp = GET '/directives/style/larry/moe/curly/02_processor_inheritance.xml' ;    
    #warn "GOT CONTENT:" . $resp->content();
    return 0 unless $resp->content =~ /Larry...Moe...Curly/gi;    
    return 1;
}

ok( test_basic(),1,    "Basic AxAddProcessor inheritance test." );
