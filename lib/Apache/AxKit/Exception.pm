# $Id: Exception.pm,v 1.4 2003/01/29 01:35:49 jwalt Exp $

package Apache::AxKit::Exception;
use Error 0.14;
@ISA = ('Error');

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    
    if ($AxKit::Cfg && $AxKit::Cfg->StackTrace) {
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

sub as_xml {
    my $E = shift;
    my $filename = shift || $E->filename;

    my $error = '<error><file>' .
            AxKit::xml_escape($filename) . '</file><msg>' .
            AxKit::xml_escape($E->{-text}) . '</msg>' .
            '<stack_trace><bt level="0">'.
            '<file>' . AxKit::xml_escape($E->{'-file'}) . '</file>' .
            '<line>' . AxKit::xml_escape($E->{'-line'}) . '</line>' .
            '</bt>';
    
    my $i = 1;
    for my $stack (@{$E->stacktrace_list}) {
        $error .= '<bt level="' . $i++ . '">' .
                '<file>' . AxKit::xml_escape($stack->{'-file'}) . '</file>' .
                '<line>' . AxKit::xml_escape($stack->{'-line'}) . '</line>' .
                '</bt>';
    }

    $error .= '</stack_trace></error>';
    return $error;
}

sub filename {
    # Overload this if you don't want to pass $r->filename to as_xml
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
