#!/usr/bin/perl -Tw
################################################################################
package AxKit::XSP::Demo::SimpleInputAttributes;
# $Id: SimpleInputAttributes.pm,v 1.1 2002/09/13 13:01:05 jwalt Exp $

=pod

=head1 NAME

AxKit::XSP::Demo::SimpleInputAttributes - tag library to demonstrate
SimpleTaglib Input Attributes

=head1 SYNOPSIS

In http.conf or .htaccess:

    AxAddXSPTaglib AxKit::XSP::Demo::SimpleInputAttributes

In XSP page:

  <xsp:page xmlns:xsp="http://www.apache.org/1999/XSP/Core"
            xmlns:demo="http://www.nsds.com/NS/xsp/demo/simple-input-attributes"
            indent-result="yes"
  >

=head1 DESCRIPTION

SimpleTaglib (STL) uses Perl function attributes to define how XML
input gets handled.  This tag library demonstrates the various methods
available in STL for reading XML input.

=head1 TAG REFERENCE

=cut

################################################################################
use strict;
use Apache::AxKit::Language::XSP::SimpleTaglib;
use Apache::AxKit::Language::XSP;

$AxKit::XSP::Demo::SimpleInputAttributes::NS =
  "http://www.nsds.com/NS/xsp/demo/simple-input-attributes";

###############################################################################
package AxKit::XSP::Demo::SimpleInputAttributes::Handlers;

###############################################################################

=pod

=head2 attrib

    <demo:attrib/>

    <demo:attrib parameter="value"/>

This tag demonstrates the SimpleTaglib 'attrib' input attribute, which
passes XML attributes to the handler function via the attribute hash
(the third parameter of the handler function, typically named '%attr').

=cut

#------------------------------------------------------------------------------
sub attrib : attrib(parameter) expr {
    my( $e, $tag, %attr ) = @_;
    if ( not defined $attr{parameter} ) {
	'"parameter is undef"';
    }
    else {
	'"parameter is \'' . $attr{parameter} . '\'"';
    }
}

###############################################################################

=pod

=head2 child

    <demo:child/>

    <demo:child>
      <demo:parameter>value</demo:parameter>
    </demo:child>

This tag demonstrates the SimpleTaglib 'child' input attribute.  XML
input from child tags can be accessed via the '$attr_' variables in
the code fragment returned by the handler function.

=cut

#------------------------------------------------------------------------------
sub child : child(parameter) expr {
    my( $e, $tag, %attr ) = @_;
    # Note that q{} is used to quote the code fragment:
    q{
      if ( not defined $attr_parameter ) {
	  "parameter is undef";
      }
      else {
	  "parameter is '$attr_parameter'";
      }
     };
}

###############################################################################

=pod

=head2 attribOrChild

    <demo:attribOrChild/>

    <demo:attribOrChild parameter="value"/>

    <demo:attribOrChild>
      <demo:parameter>value</demo:parameter>
    </demo:attribOrChild>

    <demo:attribOrChild parameter="value1">
      <demo:parameter>value2</demo:parameter>
    </demo:attribOrChild>

This tag demonstrates the SimpleTaglib 'attribOrChild' input
attribute.  XML input from attributes or child tags can be accessed
via the '$attr_' variables in the code fragment returned by the
handler function.  Input from a child tag takes precedence over
attributes.

=cut

#------------------------------------------------------------------------------
sub attribOrChild : attribOrChild(parameter) expr {
    my( $e, $tag, %attr ) = @_;
    # Note that q{} is used to quote the code fragment:
    q{
      if ( not defined $attr_parameter ) {
	  "parameter is undef";
      }
      else {
	  "parameter is '$attr_parameter'";
      }
     };
}

###############################################################################

=pod

=head2 childStruct

    <demo:childStruct/>

    <demo:childStruct>
      <demo:parameter>value</demo:parameter>
    </demo:childStruct>

    <demo:childStruct>
      <demo:parameter>value1</demo:parameter>
      <demo:parameter>value2</demo:parameter>
    </demo:childStruct>

This tag demonstrates the SimpleTaglib 'childStruct' input attribute.
XML input from child tags can be accessed via the '%_' hash in the
code fragment returned by the handler function.  Input from a child
tag takes precedence over attributes.  Note that complex XML
structures can be passed as input using 'childStruct', but the only
feature demonstrated here is the use of multiple child tags to set a
list value for the parameter.  For a more complex example, see
L<"complex-childStruct">.

=cut

#------------------------------------------------------------------------------
sub childStruct : childStruct(@parameter) expr {
    my( $e, $tag, %attr ) = @_;
    # Note that q{} is used to quote the code fragment:
    q{
      if ( not defined $_{parameter} ) {
	  "parameter is undef";
      }
      elsif ( ref $_{parameter} ) {
	  "parameter is '" . join( "','", @{$_{parameter}} ) . "'";
      }
      else {
	  "parameter is '$_{parameter}'";
      }
     };
}

###############################################################################

=pod

=head2 attrib-or-childStruct

    <demo:attrib-or-childStruct/>

    <demo:attrib-or-childStruct parameter="value"/>

    <demo:attrib-or-childStruct>
      <demo:parameter>value</demo:parameter>
    </demo:attrib-or-childStruct>

    <demo:attrib-or-childStruct parameter="value1">
      <demo:parameter>value2</demo:parameter>
    </demo:attrib-or-childStruct>

    <demo:attrib-or-childStruct>
      <demo:parameter>value1</demo:parameter>
      <demo:parameter>value2</demo:parameter>
    </demo:attrib-or-childStruct>

This tag demonstrates how to combine the SimpleTaglib 'attrib' and
'childStruct' input attributes.  XML input from attributes or child
tags can be accessed via the '%_' hash in the code fragment returned
by the handler function.  The advantage of this over the
'attribOrChild' input attribute is that multiple child tags can be
used to provide a list value for the parameter.

=cut

#------------------------------------------------------------------------------
sub attrib_or_childStruct : attrib(parameter) childStruct(@parameter) expr {
    my( $e, $tag, %attr ) = @_;
    my $code = '';
    if ( defined $attr{parameter} ) {
	my $quoted_parameter =
	  Apache::AxKit::Language::XSP::makeSingleQuoted( $attr{parameter} );
	$code .= '$_{parameter} = ' . $quoted_parameter .
	  ' unless defined $_{parameter};';
    }
    # Note that q{} is used to quote the code fragment:
    $code .= q{
	       if ( not defined $_{parameter} ) {
		   "parameter is undef";
	       }
	       elsif ( ref $_{parameter} ) {
		   "parameter is '" . join( "','", @{$_{parameter}} ) . "'";
	       }
	       else {
		   "parameter is '$_{parameter}'";
	       }
	      };
    $code;
}

###############################################################################

=pod

=head2 captureContent

    <demo:captureContent/>

    <demo:captureContent>text content</demo:captureContent>

    <demo:captureContent>
      text content
    </demo:captureContent>

This tag demonstrates the SimpleTaglib 'captureContent' input
attribute.  The XML text input can be accessed via the '$_' variable
in the code fragment returned by the handler function.

=cut

#------------------------------------------------------------------------------
sub captureContent : captureContent expr {
    my( $e, $tag, %attr ) = @_;
    # Note that q{} is used to quote the code fragment:
    q{
      if ( not defined $_ ) {
	  "content is undef"; # never happens
      }
      else {
	  "content is '$_'";
      }
     };
}

###############################################################################

=pod

=head2 captureContent-and-keepWhitespace

    <demo:captureContent-and-keepWhitespace/>

    <demo:captureContent-and-keepWhitespace>text content</demo:captureContent-and-keepWhitespace>

    <demo:captureContent-and-keepWhitespace>
      text content
    </demo:captureContent-and-keepWhitespace>

This tag demonstrates the SimpleTaglib 'captureContent' and
'keepWhitespace' input attributes.  The XML text input, including
surrounding whitespace, can be accessed via the '$_' variable in the
code fragment returned by the handler function.

=cut

#------------------------------------------------------------------------------
sub captureContent_and_keepWhitespace : captureContent keepWhitespace expr {
    my( $e, $tag, %attr ) = @_;
    # Note that q{} is used to quote the code fragment:
    q{
      if ( not defined $_ ) {
	  "content is undef"; # never happens
      }
      else {
	  "content is '$_'";
      }
     };
}

###############################################################################

=pod

=head2 complex-childStruct

    <complex-childStruct
      xmlns="http://www.nsds.com/NS/xsp/demo/simple-input-attributes">
        <add>
            <permission type="user">
                foo
            </permission>
            <permission>
                <type>group</type>
                bar
            </permission>
            <target>/test.html</target>
            <comment lang="en" day="Sun">Test entry</comment>
            <comment lang="en" day="Wed">Test entry 2</comment>
            <comment lang="de">Testeintrag</comment>
        </add>
        <remove target="/test2.html">
            <permission type="user">
                baz
            </permission>
        </remove>
    </complex-childStruct>

This tag demonstrates complex usage of the SimpleTaglib 'childStruct'
input attribute.  XML input from child tags can be accessed via the
'%_' hash in the code fragment returned by the handler function.  This
example is from the STL documentation (and slightly modified).

=cut

#------------------------------------------------------------------------------
sub complex_childStruct : childStruct(add{@permission{$type *name} $target $comment(lang)(day)} remove{@permission{$type *name} $target}) expr {
    my( $e, $tag, %attr ) = @_;
    'use Data::Dumper (); "\n" . Data::Dumper->Dump( [ \\%_ ], [ \'*_\' ] )';
}

################################################################################

=pod

=head1 AUTHOR

Ken Neighbors <ken@nsds.com>

=head1 VERSION

$Id: SimpleInputAttributes.pm,v 1.1 2002/09/13 13:01:05 jwalt Exp $

=cut

1;
