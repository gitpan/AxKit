# $Id: Util.pm,v 1.2 2000/09/21 16:40:44 matt Exp $

package Apache::AxKit::Language::XSP::Util;
use strict;
use Apache::AxKit::Language::XSP;
use LWP::UserAgent;
use Apache::File;
use XML::DOM;
use HTTP::Request;
use Time::Object; # had to be here (because of overrides to localtime?).

use vars qw/@ISA $NS $VERSION/;

@ISA = ('Apache::AxKit::Language::XSP');
$NS = 'http://www.apache.org/1999/XSP/Util';

$VERSION = 0.03;

sub register {
    my $class = shift;
    $class->register_taglib($NS);
}


## Taglib subs

# insert from a local file
sub include_file {
    my ($document, $parent, $filename) = @_;
    my $p = new XML::DOM::Parser;
    my $inc_dom = $p->parsefile($filename);
    my $root = $inc_dom->getDocumentElement;
    my $clone = $root->cloneNode(1);
    $clone->setOwnerDocument($document);
    $parent->appendChild($clone);
    $inc_dom->dispose;
}


# insert from a (possibly) remote file
# the cool (or maybe *not* so cool) thing is that
# if the uri is located on an AxKit-enabled server,
# we get it "pre-transformed" by any stylesheets
# declared in the doc. could be useful for widget building. . .
sub include_uri {
    my ($document, $parent, $uri) = @_;
    my $ua = LWP::UserAgent->new;
    my $p = new XML::DOM::Parser;
    my $req = HTTP::Request->new(GET => $uri);
    my $res = $ua->request($req);
    my $raw_xml = $res->content;
    my $inc_dom = $p->parse($raw_xml);
    my $root = $inc_dom->getDocumentElement;
    my $clone = $root->cloneNode(1);
    $clone->setOwnerDocument($document);
    $parent->appendChild($clone);
    $inc_dom->dispose;
}
        
# insert from a SCALAR
sub include_expr {
    my ($document, $parent, $frag) = @_;
#        warn "util: expr is $frag\n";
    my $p = new XML::DOM::Parser; 
    my $inc_dom = $p->parse($frag);
    my $root = $inc_dom->getDocumentElement;   
    my $clone = $root->cloneNode(1);
    $clone->setOwnerDocument($document);
    $parent->appendChild($clone);
    $inc_dom->dispose;
}

# insert from a local file as plain text
sub get_file_contents {
    my ($document, $parent, $filename) = @_;
    my $fh = Apache::File->new($filename) || 
       throw Apache::AxKit::Exception::Declined( reason => "error opening $filename");
    local $/;
    my $content = <$fh>;
    my $text = $document->createTextNode($content);
    $parent->appendChild($text);
    $fh->close;
}

# return the time in strftime formats.
sub get_date {
    my ($document, $parent, $format) = @_;
    my $t = localtime;
    my $ret = $t->strftime($format);
    my $text = $document->createTextNode($ret);
    $parent->appendChild($text);
}

## Parser subs
        
sub parse_char {
    my ($e, $text) = @_;
    if ($e->current_element() =~ /expr|href|name|format/) {
        no strict 'refs';
        return "my \$passed_var = \"$text\";\n";
    }
    return ''; # nothing else in util: should have text (?)
}

sub parse_start {
    my ($e, $tag, %attribs) = @_; 
#    warn "Checking: $tag\n";

    if ($tag eq 'include-file' && defined $attribs{name}) {
        return "{# start include-file\nmy \$passed_var = '$attribs{name}';\n";
    }
    elsif ($tag eq 'name' && $e->current_element() eq 'include-file') {
        return "{# start include-file\n";
    }
    elsif ($tag eq 'include-uri' && defined $attribs{href}) {
        return "{# start include-uri\nmy \$passed_var = '$attribs{href}';\n";
    }
    elsif ($tag eq 'href' && $e->current_element() eq 'include-uri') {
        return "{# start include-uri\n";
    }
    elsif ($tag eq 'get-file-contents' && defined $attribs{name}) {
        return "{# starting new text include\nmy \$passed_var = '$attribs{name}';\n";
    }
    elsif ($tag eq 'name' && $e->current_element() eq 'get-file-contents') {
        return "{# start new text include\n"; 
    }
    elsif ($tag eq 'time' && defined $attribs{format}) {
        return "{# starting new date/time\nmy \$passed_var = '$attribs{format}';\n";
    }
    elsif ($tag eq 'format' && $e->current_element() eq 'time') {
        return "{# start new date/time\n";
    }
    elsif ($tag eq 'expr' && $e->current_element() eq 'include-expr') {
        return "{# start include-expr\n";
    }
}

sub parse_end {
    my ($e, $tag) = @_;

    if ($tag eq 'include-file') {
        return "Apache::AxKit::Language::XSP::Util::include_file(\n" .
        '$document, $parent, $passed_var' .
        ")}\n";
    }
    elsif ($tag eq 'include-uri') {
        return "Apache::AxKit::Language::XSP::Util::include_uri(\n" .
        '$document, $parent, $passed_var' .
        ");}\n";
    }
    elsif ($tag eq 'include-expr') {
        return "Apache::AxKit::Language::XSP::Util::include_expr(\n" .
        '$document, $parent, $passed_var' .
        ");}\n";
    }
    elsif ($tag eq 'get-file-contents') {
        return "Apache::AxKit::Language::XSP::Util::get_file_contents(\n" .
        '$document, $parent, $passed_var' .
        ");}\n";
    }
    elsif ($tag eq 'time') {
        return  "Apache::AxKit::Language::XSP::Util::get_date(\n" .
                '$document, $parent, $passed_var' .
                ");\n}\n";
    }
    return ";";
}
        
1;
                
__END__

=head1 NAME

Apache::AxKit::Language::XSP::Util - XSP util: taglib.

=head1 SYNOPSIS

Add the util: namespace to your XSP C<<xsp:page>> tag:

    <?xml-stylesheet href="." type="application/x-xsp"?>>
    <xsp:page
         language="Perl"
         xmlns:xsp="http://www.apache.org/1999/XSP/Core"
         xmlns:util="http://www.apache.org/1999/XSP/Util"
    >

And add this taglib to AxKit (via httpd.conf or .htaccess):

    AxAddXSPTaglib Apache::AxKit::Language::XSP::Util

=head1 DESCRIPTION

The XSP util: taglib seeks to add a short list of basic utility
functions to the eXtesible Server Pages library. It trivializes the
inclusion of external fragments and adds a few other useful bells and
whistles.

=head2 Tag Structure

Most of of the tags require some sort of "argument" to be passed (e.g.
C<<util:include-file>> requires the B<name> of the file that is to be
read). Unless otherwise noted, all tags allow you to pass this
information either as an attribute of the current  element or as the
text node of an appropriately named child.

Thus, both:

    <util:include-file name="foo.xml" />

and

    <util:include-file>
    <util:name>foo.xml</util:name>
    </util:include-file>

are valid.

=head2 Tag Reference

=over 4

=item C<<util:include-file>>

Provides a way to include an XML fragment from a local file into the
current DOM tree. Requires a B<name> argument. The path may be relative
or absolute.

=item C<<util:include-uri>>

Provides a way to include an XML fragment from a (possibly) remote URI.
Requires an B<href> argument.

=item C<<util:get-file-contents>>

Provides a way to include a local file B<as plain text>. Requires a
B<name> argument. The path may be relative or absolute.

=item C<<util:include-expr>>

Provides a way to include an XML fragment from a scalar variable. Note
that this tag may B<only> pass the required  B<expr> argument as a
child node. Example: 

    <util:include-expr>
    <util:expr>$xml_fragment</util:expr>
    </util:include-expr>

=item C<<util:time>>

Returns a formatted time/date string. Requires a B<format> argument.
The format is defined using the standard strftime() syntax.

=back

=head1 AUTHOR

Kip Hampton, khampton@totalcinema.com

=head1 SEE ALSO

AxKit.

=cut
