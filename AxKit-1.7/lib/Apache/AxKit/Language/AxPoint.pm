# Copyright 2001-2005 The Apache Software Foundation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# $Id: AxPoint.pm,v 1.6 2005/07/14 18:43:34 matts Exp $

package Apache::AxKit::Language::AxPoint;

@ISA = ('Apache::AxKit::Language');

use strict;

use Apache;
use Apache::Constants qw(OK);
use Apache::Request;
use XML::SAX;
use XML::Handler::AxPoint;

my @xindent;

sub stylesheet_exists () { 0; }

sub handler {
    my $class = shift;
    my ($r, $xml_provider, undef, $last_in_chain) = @_;

    my $output_handler = Apache::AxKit::Language::AxPoint::Output->new($r);
    
    my ($xmlstring);
    
    if (my $dom = $r->pnotes('dom_tree')) {
        $xmlstring = $dom->toString;
        delete $r->pnotes()->{'dom_tree'};
    }
    else {
        $xmlstring = $r->pnotes('xml_string');
    }

    AxKit::Debug(5, "AxPoint: creating parser and handler");
    
    my $parser = XML::SAX::ParserFactory->parser(
        Handler =>
            XML::Handler::AxPoint->new(
                Output => $output_handler,
                PrintMode => 1,
            )
    );

    AxKit::Debug(5, "AxPoint: Parsing XML");

    if (length($xmlstring)) {
        $parser->parse_string($xmlstring,
            { Source => { SystemId => $xml_provider->key } });
    }
    else {
       eval {
            my $fh = $xml_provider->get_fh();
            $parser->parse_fh($fh, 
                { Source => { SystemId => $xml_provider->key } });
        };
        if ($@) {
            my $str = $xml_provider->get_strref();
            $parser->parse_string($$str,
                { Source => { SystemId => $xml_provider->key } });
        }
    }

    AxKit::Debug(7, "AxPoint: outputting pdf");

    $AxKit::Cfg->AllowOutputCharset(0);
    
    $r->content_type("application/pdf");

    AxKit::Debug(5, "AxPoint: done");

    return OK;
}

package Apache::AxKit::Language::AxPoint::Output;
use XML::SAX::Writer;
use vars qw(@ISA);
@ISA = ('XML::SAX::Writer::ConsumerInterface');

sub new {
    my $class = shift;
    my ($r) = @_;
    return bless { apache => $r }, $class;
}

sub output {
    my $self = shift;
    my ($data) = @_;
    $self->{apache}->print($data);
}

1;

__END__

=head1 NAME

AxPoint - An AxKit PDF Slideshow generator

=head1 SYNOPSIS

  AxAddStyleMap application/x-axpoint Apache::AxKit::Language::AxPoint
  
  AxAddRootProcessor application/x-axpoint NULL slideshow

=head1 DESCRIPTION

AxPoint allows you to create slideshows or presentations using an XML
definition of the slideshow. The full documentation is in
L<XML::Handler::AxPoint>.

AxPoint when processed via AxKit defaults to producing the slides in
"Print mode" - this removes all transitions from the slides. If you
want to get a version with transitions it is recommended to use the
command line tools shipped with XML::Handler::AxPoint. The reason for
this decision is because the browser-embedded version of Adobe Acrobat
does not seem to go full screen very well, if at all, so it is pretty
much useless for giving live presentations over the web.

=head1 AUTHOR

Matt Sergeant, matt@axkit.com

=cut
