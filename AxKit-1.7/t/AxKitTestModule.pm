package AxKitTestModule;

require Exporter;
@ISA = qw(Exporter);

@EXPORT_OK = qw(&test_module);

use Apache::Test;
use Apache::TestUtil;

sub test_module {
    my ($module, @prereqs) = @_;
    foreach my $prereq (@prereqs) {
        my ($ok, $reason) = load_module($prereq);
        if (!$ok) {
            skip("Skip($prereq prerequisite module not available : $reason)", 1);
            return;
        }
    }
    my ($ok, $reason) = load_module($module);
    ok ($ok,1,$reason);
}

sub load_module {
    my $module = shift;
    $module =~ s/::/\//g;
    eval {
        require "$module.pm";
    };
    if ($@) {
		wantarray ? return (0, $@) : 0;
    }
    return 1;
}


1;
