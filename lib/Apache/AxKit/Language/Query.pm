package Apache::AxKit::Language::Query;

use strict;

use DBI;
use XML::DOM;

sub handler {
	my $r = shift;
	my ($xmlfile, $stylesheet) = @_;

	my $vals;
	open(STYLE, $stylesheet) || die "Can't open stylesheet '$stylesheet': $!";
	flock(STYLE, 1);
	while(my $line = <STYLE>) {
		$line =~ s/\r?\n//; # chomp no good if people editing on Win32
		$line =~ s/#.*//; # strip comments
		next if $line =~ /^\s*$/; # ignore blank (or whitespace) lines
		my ($key, $val) = split(/\s*=\s*/, $line, 2);
		next unless $key;
		$vals->{$key} = $val;
	}

	my $dsn;
	if ($vals->{CONNECT_STRING}) {
		$dsn = $vals->{CONNECT_STRING};
	}
	else {
		$dsn = "dbi:$vals->{DRIVER}:$vals->{CONNECT_EXTRA}";
	}

	my %attr;
	foreach my $key (keys %$vals) {
		next unless $key =~ /^ATTR_(.*)$/;
		$attr{$1} = $vals->{$key};
	}

	my $dbh = DBI->connect($dsn, $vals->{USER}, $vals->{PASSWORD}, \%attr);

    return Apache::Constants::OK;
}

1;
