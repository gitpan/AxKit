# $Id: Exception.pm,v 1.17 2001/05/30 16:22:37 matt Exp $

package Apache::AxKit::Exception;
use Error;
@ISA = ('Error');

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    if ($AxKit::Cfg->StackTrace) {
        my $i = $Error::Depth + 1;
        my ($pkg, $file, $line) = caller($i++);
        my @stacktrace;
        while ($pkg) {
            push @stacktrace, { '-package' => $pkg, '-file' => $file, '-line' => $line};
            ($pkg, $file, $line) = caller($i++);
        }
        $self->{'stacktrace'} = \@stacktrace;
    }
    
    return $self;
}

sub stacktrace_list {
    my $E = shift;
    return $E->{'stacktrace'} || [];
}

use overload 'bool' => 'bool';

sub bool {
    my $E = shift;
    1;
}

sub value {
    my $E = shift;
    exists $E->{'-value'} ? $E->{'-value'} : 1;
}

package Apache::AxKit::Exception::Declined;
@ISA = ('Apache::AxKit::Exception');

package Apache::AxKit::Exception::Error;
@ISA = ('Apache::AxKit::Exception');

package Apache::AxKit::Exception::OK;
@ISA = ('Apache::AxKit::Exception');

package Apache::AxKit::Exception::Retval;
@ISA = ('Apache::AxKit::Exception');

package Apache::AxKit::Exception::IO;
@ISA = ('Apache::AxKit::Exception');

1;
