# $Id: Simple.pm,v 1.2 2002/03/15 00:24:49 jwalt Exp $
package AxKit::XSP::Demo::Simple;

# Always use strict. Do it. I mean it. And turn on warnings as well.
use strict;

# this single line makes the taglib a Simpletaglib powered one
use Apache::AxKit::Language::XSP::SimpleTaglib;

# providing a version is good style, but not strictly neccessary
$AxKit::XSP::Demo::Simple::VERSION = 0.90;

# The namespace associated with this taglib. If it doesn't work, double check
# that you are using the exact same NS uri here and in the XSP.
$AxKit::XSP::Demo::Simple::NS = 'http://www.creITve.de/2002/XSP/Demo/Simple';

# something to go at the top of the XSP script - this is NOT executed on every
# request, but only once for each httpd process

sub start_document {
    return "use Time::Piece;\n".
           # note the naming convention: all xsp internal variable names start with
           # _xsp_, followed by the package name minus AxKit::XSP::, replacing '::'
           # with '_'.
           "my \$_xsp_demo_simple_first_time = localtime();\n".
           "my \$_xsp_demo_simple_last_time = localtime(0);\n";
}

# a utility function.

sub do_long_and_complex_calculation {
    return int(rand(42));
}

################################################################
# package for the handler subs - here the taglib really begins #
################################################################
package AxKit::XSP::Simple::Handlers;

# a very simple tag: <demo:set-time/>
sub set_time
{
    return '$_xsp_demo_simple_last_time = localtime();';
}

# a more complex tag: <demo:first-time [as="node|string"]/>
# input is an attribute, output is a node or a scalar
sub first_time : attrib(as) exprOrNode(first-run-time)
{
    my ($e, $tag, %attribs) = @_;
	if ($attribs{'as'} eq 'string') {
		return '$_xsp_demo_simple_first_time->strftime("%a %b %d %H:%M:%S %Z %Y");';
	} else {
		return '$_xsp_demo_simple_first_time';
	}
}

# another one: <demo:last-time [as="node|string"]/>
sub last_time : attrib(as) exprOrNode(last-run-time)
{
    my ($e, $tag, %attribs) = @_;
	if ($attribs{'as'} eq 'string') {
		return '$_xsp_demo_simple_last_time->strftime("%a %b %d %H:%M:%S %Z %Y");';
	} else {
		return '$_xsp_demo_simple_last_time';
	}
}

# returning a list or a list of nodes
sub times : exprOrNodelist(run-time)
{
	return '($_xsp_demo_simple_first_time,$_xsp_demo_simple_last_time)';
}

# returning a scalar, array, or text node, depending on context.
sub calculate_something : expr
{
    return 'AxKit::XSP::Demo::Simple::do_long_and_complex_calculation();';
}

# input is an attribute or a node
sub set_custom_time : attribOrChild(time)
{
	return '$_xsp_demo_simple_last_time = localtime($attr_time);';
}

# input is the text content of the tag
sub set_custom_time_content : captureContent
{
	return '$_xsp_demo_simple_last_time = localtime(int($_));';
}

# this demo does not cover the childStruct and struct input/output specs.
# stay tuned for the advanced demo.

1;

__END__

=head1 NAME

AxKit::XSP::Demo::Simple - basic SimpleTaglib demo

=head1 SYNOPSIS

Add the demo: namespace to your XSP C<<xsp:page>> tag:

    <xsp:page
         language="Perl"
         xmlns:xsp="http://apache.org/xsp/core/v1"
         xmlns:simple="http://www.creITve.de/2002/XSP/Demo/Simple"
    >

Add this taglib to AxKit (via httpd.conf or .htaccess):

    AxAddXSPTaglib AxKit::XSP::Demo::Simple

=head1 DESCRIPTION

This is a demo of the basic SimpleTaglib features. See the SimpleTaglib docs
for details.

=head1 AUTHOR

Jörg Walter <jwalt@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2002 Jörg Walter.
All rights reserved. This program is free software; you can redistribute it and/or
modify it under the same terms as AxKit itself.

=head1 SEE ALSO

AxKit, Apache::AxKit::Language::XSP, Apache::AxKit::Language::XSP::SimpleTaglib

=cut
