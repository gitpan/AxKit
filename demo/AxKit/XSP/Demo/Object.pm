# $Id: Object.pm,v 1.3 2002/06/25 05:07:52 jwalt Exp $
package AxKit::XSP::Demo::Object;

# Always use strict. Do it. I mean it. And turn on warnings as well.
use strict;

# this single line makes the taglib a Simpletaglib powered one
use Apache::AxKit::Language::XSP::SimpleTaglib;

# providing a version is good style, but not strictly neccessary
$AxKit::XSP::Demo::Object::VERSION = 0.90;

# The namespace associated with this taglib. If it doesn't work, double check
# that you are using the exact same NS uri here and in the XSP.
$AxKit::XSP::Demo::Object::NS = 'http://www.creITve.de/2002/XSP/Demo/Object';

# something to go at the top of the XSP script - this is NOT executed on every
# request, but only once for each httpd process

sub start_document {
    # We are using a Time::Piece object as example. Look at it's man page, it is
    # very straighforward, and a useful module as well.
    return "use Time::Piece;\n";
}

package AxKit::XSP::Demo::Object::Handlers;

# You need this dummy because the existence of a sub alone decides if a tag is
# valid or not, even when the work is done in the opening tag. We tell
# SimpleTaglib that we use 2 attributes as input.
sub new : attrib(name,timestamp) {
    return '';
}

# here the work is done
sub new__open {
    # here we are using the passed arguments, specifically, the 'name'
    # attribute
    my ($e, $tag, %attr) = @_;

    # if you do not nest this object, you can just ignore the name,
    # we provide a default
    my $name = $attr{'name'} || 'object';

    # make the name 'safe'
    $name =~ s/[^a-zA-Z0-9]/_/g;

    # provide a default timestamp (use current time)
    my $time = defined $attr{'timestamp'}? $attr{'timestamp'} : '';

    # We could allow any expression, thus making it more flexible, but
    # this would be unusual usage of XSP so I decided to enforce
    # numeric literals. The XSPish way for dynamic arguments are child
    # tags, but we cannot use them here.
    # Note that this is an important limitation: We cannot use any
    # content of the tag in the opening tag handler, just attributes.
    $time =~ s/[^0-9]//g;

    # note the naming convention: all xsp internal variable names start with
    # _xsp_, followed by the package name minus AxKit::XSP::, replacing '::'
    # with '_'. Oh, and if you are wondering about that 'localtime', read
    # the man page of Time::Piece.
    return 'my $_xsp_demo_object_'.$name.' = localtime('.$time.');'."\n";
}

sub day : expr attrib(name) {
    # this is the same prologue as above, we use it in every tag
    my ($e, $tag, %attr) = @_;
    my $name = $attr{'name'} || 'object';
    $name =~ s/[^a-zA-Z0-9]/_/g;

    # and a one-liner for the actual method call
    return '$_xsp_demo_object_'.$name.'->day';
}

sub month : expr attrib(name) {
    # this is the same prologue as above, we use it in every tag
    my ($e, $tag, %attr) = @_;
    my $name = $attr{'name'} || 'object';
    $name =~ s/[^a-zA-Z0-9]/_/g;

    return '$_xsp_demo_object_'.$name.'->month';
}

sub year : expr attrib(name) {
    # this is the same prologue as above, we use it in every tag
    my ($e, $tag, %attr) = @_;
    my $name = $attr{'name'} || 'object';
    $name =~ s/[^a-zA-Z0-9]/_/g;

    return '$_xsp_demo_object_'.$name.'->year';
}

# ... and so on. For ways of specifying input and output, see the other
# SimpleTaglib demos.

1;

__END__

=head1 NAME

AxKit::XSP::Demo::Object - how to work object oriented with SimpleTaglib

=head1 SYNOPSIS

Add the demo: namespace to your XSP C<<xsp:page>> tag:

    <xsp:page
         language="Perl"
         xmlns:xsp="http://apache.org/xsp/core/v1"
         xmlns:object="http://www.creITve.de/2002/XSP/Demo/Object"
    >

Add this taglib to AxKit (via httpd.conf or .htaccess):

    AxAddXSPTaglib AxKit::XSP::Demo::Object

=head1 DESCRIPTION

This is a demo how to do some OO stuff with SimpleTaglib. It is far from
complete, but gives you an Idea how this would work. See the SimpleTaglib
docs for details.

=head1 AUTHOR

Jörg Walter <jwalt@cpan.org>

=head1 COPYRIGHT

Copyright (c) 2002 Jörg Walter.
All rights reserved. This program is free software; you can redistribute it and/or
modify it under the same terms as AxKit itself.

=head1 SEE ALSO

AxKit, Apache::AxKit::Language::XSP, Apache::AxKit::Language::XSP::SimpleTaglib

=cut
