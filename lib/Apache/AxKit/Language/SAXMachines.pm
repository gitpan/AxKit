package Apache::AxKit::Language::SAXMachines;

use strict;
use vars qw/@ISA $VERSION/;
use XML::SAX::Machines qw( Pipeline );
use XML::LibXML::SAX::Builder;
use Apache;
use Apache::Request;
use Apache::AxKit::Language;

@ISA = 'Apache::AxKit::Language';

$VERSION = 1.0; # this fixes a CPAN.pm bug. Bah!

sub handler {
    my $class = shift;
    my ($r, $xml, $style, $last_in_chain) = @_;
    
    my ($xmlstring, $xml_doc);
    
    AxKit::Debug(7, "[SAXMachines] getting the XML");
    
    if (my $dom = $r->pnotes('dom_tree')) {
        $xml_doc = $dom;
        delete $r->pnotes()->{'dom_tree'};
    }
    else {
        $xmlstring = $r->pnotes('xml_string');
    }
  
    my $machine_class;
    my @machine_spec = split /\s+/, $r->dir_config('AxSAXMachineFilters');

    if ( length( $r->dir_config('AxSAXMachineClass') ) ) {
        my $mclass = $r->dir_config('AxSAXMachineClass');
        eval "require $mclass";
        my $machine_object = $mclass->new();
        $machine_class     = $machine_object->get_machine( $r, $xml, $last_in_chain );
    }
  
    unshift @machine_spec, $machine_class if ref( $machine_class );

    AxKit::Debug(7, "[SAXMachines] Filters: @machine_spec");

    my $dom_builder = XML::LibXML::SAX::Builder->new();
    my $pipeline = Pipeline( @machine_spec, $dom_builder );


    # here's the beef...
    my ($result, $error);

    AxKit::Debug(7, "[SAXMachines] parsing document");

    if ( $xml_doc ) {
        AxKit::Debug(10, "[SAXMachines] generating events from DOM tree");
        my $p = XML::LibXML::SAX::Parser->new( Handler => $pipeline );
        eval {
            $result = $p->generate( $xml_doc );
        };
        $error = $@ if $@;
    }
    elsif ($xmlstring) {
        AxKit::Debug(10, "[SAXMachines] generating events from XML string");
        eval {
            $result = $pipeline->parse_string($xmlstring, $r->uri());
        };
        $error = $@ if $@;
    }
    if (!$xml_doc && !$xmlstring) {
        eval {
            my $fh = $xml->get_fh();
            $result = $pipeline->parse_fh($fh, $r->uri());
        };
        if ($@) {
            $xmlstring = ${$xml->get_strref()};
            eval {
                $result = $pipeline->parse_string( $xmlstring );
            };
            $error = $@ if $@;
        }
    } 

    if ( length( $error ) ) {
        throw Apache::AxKit::Exception::Error(
                    -text => "SAXMachines Error: $error"
                    );
    }

    AxKit::Debug(7, "[SAXMachines] parse complete, returning DOM tree");

    $r->pnotes('dom_tree', $result);
    return Apache::Constants::OK;

}

# SAX Machines ignores stylesheets
sub stylesheet_exists { 0 }

1;

__END__
=pod

=head1 NAME

Apache::AxKit::Language::SAXMachines - Transform Content With SAX Filters

=head1 SYNOPSIS
    
    # add the style processor mapping
    AxAddStyleMap application/x-saxmachines Apache::AxKit::Language::SAXMachines

    # add the processor
    AxAddProcessor application/x-saxmachines .

    # create a simple filter chain
    PerlSetVar AxSAXMachineFilters "XML::Filter1 XML::Filter2"

    # filter set-up via a controller class
    PerlSetVar AxSAXMachineClass "Custom::MachineBuilderClass"

=head1 DESCRIPTION

Language::SAXMachines provides an easy way ( via Barrie Slaymaker's
XML::SAX::Machines ) to use SAX filter chains to transform XML content.

It is not technically a "language" in the same sense that XSP, XPathScript, or
XSLT are since there is no stylesheet to write or process. Instead, the SAX
filters are added via config directives in your .htaccess or *.conf file. 

( Note, future versions may add an associated XML application grammar that 
may be used to define/configure the filter chain, but rushing forward to that is 
Truly Bad Idea(tm) for a number of reasons ).

The configuration directives that are required or recognized by Language::SAXMachines
are detailed below.

=head2 Style Processor Mapping (AxAddStyleMap)

To use Language::SAXMachines you must set set up the mapping between
the style processor's MIME type and the Language::SAXMachines module.
This is achieved via the typical AxAddStyleMap directive:

    AxAddStyleMap application/x-saxmachines Apache::AxKit::Language::SAXMachines

=head2 Invoking The Processor (AxAddProcessor, etc.)

To apply Language::SAXMachines processor to a given document request, you must use
the AxAddProcessor directive (or one of its relations): 

    <Files *.xml>
      AxAddProcessor application/x-saxmachines .
    </Files>

Note the dot ('.') there. Like XSP, there is no external stylesheet to
process so the URI must be set to point back to the document itself.

See the section labeled "ASSOCIATING STYLESHEETS WITH XML FILES" in the 
main AxKit POD ( perldoc AxKit ) for additional options.

=head2 Setting Up a Simple SAX Filter Chain (AxSAXMachineFilters)

For simple cases where you want to process the document through 
a static list of SAX filters, use the AxSAXMachineFilters option. It
accepts a white-space-seperated list of valid SAX Filter module names and
builds a linear processing pipeline from those modules. Filters are applied
in the same order that they appear in the AxSAXMachineFilters directive.

The following would create a simple pipleline that applies the SAX filters 
XML::Filter1 and XML::Filter2 (in that order) to the document.

    PerlSetVar AxSAXMachineFilters "XML::Filter1 XML::Filter2"

=head2 Using a SAX::Machines-aware Controller Class (AxSAXMachineClass)

A static list of SAX Filters is fine for many tasks. However, for more advanced
applications, it is often desireable for sets of filters (or other SAX::Machines)
to be dynamically chosen and set up at request time. 

The AxSAXMachinesClass directive accpets the module name of a class that is 
capable of building a SAX::Machines processing chain. The object returned
from that module's get_machine() method is expected to a blessed and valid
reference to to a SAX::Machine object (including Pipelines, ByRecords, etc.).

The following would use the SAX::Machines object returned by the
get_machine() method of the the Custom::MachineBuilderClass module to
create the SAX processing chain.

    PerlSetVar AxSAXMachineClass "Custom::MachineBuilderClass"

In addition, the get_machines() method in the class defined by the AxSAXMachineClass
directive is passed a reference to the current Apache::Request instance (as well as 
few other possibly useful bits of information) allowing the module to create a processing
chain that is more directly responsive to the context of the current request. A typical
get_machine() implementation might start off like:

   sub get_machine {
       my ($self, $r, $last_in_chain) = @_;

       # make some choices about what filters to add, or machines to build
       # based on the info the Apache::Request object in $r
     
       # assumes 'use XML::SAX::Machines qw( Pipeline );'
       my $machine = Pipeline( @list_of_filters_we_picked ); 
       return $machine;
  }

Note that machines can be nested sets of other machines just as in the regular 
usage of XML::SAX::Machines, get_machine() need only return the top-level 'wrapper machine'. 

=head2 When Worlds Collide ( Using Both AxSAXMAchineFilters and AxSAXMachineClass )

In cases where both AxSAXMachineFilters and AxSAXMAchineClass are used to set up the 
processing for a given request, the machine returned by  AxSAXMAchineClass is given 
processing precedence. That is, the document's event stream will be run through the
machine returned by the AxSAXMAchineClass first, and then passed through the filters
defined by the AxSAXMAchineFilters directive. So,

    PerlSetVar AxSAXMachineFilters "XML::Filter1 XML::Filter2"
    PerlSetVar AxSAXMachineClass "Custom::MachineBuilderClass"

appearing in the same config block would send the document's events through a linear pipeline
consisting of the machine returned by Custom::MachineBuilderClass's get_machine() method 
followed by the filters XML::Filter1 and XML::Filter2.

=head1 SEE ALSO

AxKit, XML::SAX::Machines
 
=cut
