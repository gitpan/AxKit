# $Id: Exception.pm,v 1.4 2000/06/15 10:30:53 matt Exp $

package Apache::AxKit::Exception;
use strict;
use vars qw/$AUTOLOAD/;

sub AUTOLOAD {
	no strict 'refs', 'subs';
	if ($AUTOLOAD =~ /.*::([A-Z]\w+)$/) {
		my $exception = $1;
		*{$AUTOLOAD} = 
			sub {
				shift; 
				my ($package, $filename, $line) = caller;
				push @_, 'caller' => {
								'package' => $package,
								'filename' => $filename,
								'line' => $line,
									};
				bless { @_ }, "Apache::AxKit::Exception::$exception"; 
			};
		goto &{$AUTOLOAD};
	}
	else {
		die "No such exception class: $AUTOLOAD\n";
	}
}

$SIG{__DIE__} = sub {
	if(!ref($_[0])) {
		die Apache::AxKit::Exception->Error(text => join('', @_));
	}
	die @_;
};

package Apache::AxKit::Exception::Error;
use overload '""' => \&str;

sub str {
	shift->{text};
}

1;
