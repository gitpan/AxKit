# $Id: HtmlDoc.pm,v 1.4.2.1 2003/07/28 22:51:19 matts Exp $
# Apache::AxKit::Language::HtmlDoc - xhtml->pdf renderer
package Apache::AxKit::Language::HtmlDoc;

@ISA = ('Apache::AxKit::Language');

use strict;

use Apache;
use Apache::Constants qw(:common);
use Apache::Request;
use Apache::AxKit::Language;
use Apache::AxKit::LibXMLSupport;
use Apache::AxKit::Provider;
use XML::LibXSLT;
use IPC::Run qw(run);
use Cwd;

my $olddir;
my $tempdir;

sub stylesheet_exists () { 0; }

sub handler {
    my $class = shift;
    my ($r, $xml_provider, undef, $last_in_chain) = @_;

    my $parser = XML::LibXML->new();
    local($XML::LibXML::match_cb, $XML::LibXML::open_cb,
        $XML::LibXML::read_cb, $XML::LibXML::close_cb);
    Apache::AxKit::LibXMLSupport->reset();

    my $dom;
    my $source_text;
    if ($dom = $r->pnotes('dom_tree')) {
        ;
    } elsif ($source_text = $r->pnotes('xml_string')) {
        $dom = $parser->parse_string($source_text, $r->uri());
    }
    else {
        $source_text = eval { ${$xml_provider->get_strref()} };
        if ($@) {
            my $fh = $xml_provider->get_fh();
            $source_text = join("",<$fh>);
        }
        $dom = $parser->parse_string($source_text, $r->uri());
    }
    $dom->process_xinclude();
    my $style_dom = $parser->parse_string(<< 'EOX','.');
<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns="http://www.w3.org/1999/xhtml">
<xsl:output method="html" encoding="ISO-8859-15"/>
<xsl:template match="*"><xsl:copy select="."><xsl:copy-of select="@*"/><xsl:apply-templates/></xsl:copy></xsl:template>
<xsl:template match="text()"><xsl:value-of select="."/></xsl:template>
</xsl:stylesheet>
EOX
    my $stylesheet = XML::LibXSLT->parse_stylesheet($style_dom);
    my $results = $stylesheet->transform($dom);

    my $result;
    my $input = $stylesheet->output_string($results);
    my $host = $r->hostname;
    $input =~ s{ href="/}{ href="http://$host/}g;
    my $path = $r->document_root;
    $input =~ s{ src="/}{ src="$path/}g;
    $path = $r->uri;
    $path =~ s{/+[^/]*$}{/};
    $input =~ s{ href="(?!/|.{0,5}:)}{ href="http://$host$path}g;
    AxKit::Debug(8, "About to shell out to htmldoc - hope you have it installed...");
    AxKit::Debug(10, $input);
    run(['htmldoc','--quiet','--format','pdf13','--truetype','--size','a4','--color','--charset','8859-15','--webpage',$r->dir_config->get('AxHtmlDocOptions'),'-'],\$input,\$result);

    if (substr($result,0,5) ne '%PDF-') {
        throw Apache::AxKit::Exception::Error(-text => 'htmldoc returned error: '.$result);
    }

    $AxKit::Cfg->AllowOutputCharset(0);

    $r->content_type('application/pdf');
    $r->pnotes('xml_string',$result);
    return OK;
}

1;

=head1 NAME

Apache::AxKit::Language::HtmlDoc - deliver XHTML as PDF

=head1 SYNOPSIS

  AxAddStyleMap text/xhtml Apache::AxKit::Language::HtmlDoc

  # as last step in your processor chain, add:
  AxAddProcessor text/xhtml NULL
  
  # want custom HTMLDOC args? here we go:
  PerlAddVar AxHtmlDocOptions --linkcolor '#ff0000' --linkstyle plain

=head1 DESCRIPTION

Go and get HTMLDOC (L<http://www.easysw.com/htmldoc/>) first, then you
can convert any XHTML page into a quite nice looking PDF document. Be
prepared to do some tweaking of your xhtml input, though, because
HTMLDOC is HTML 3.2 only, it does not yet understand CSS and only some
HTML 4.0 (as of version 1.8.18). Using an extra XSLT stylesheet, it
isn't all that hard to create HTMLDOC friendly input and you get nice
results.

You should not use this for mostly hand-crafted PDFs, for that see the
PassiveTeX module, which converts XSL:FO to PDF. HTMLDOC has its quirks,
sometimes it is a bit frustrating getting the output right. It pays
off if you have lots of existing (or generated) HTML and want all of
them to be PDF, but for a custom PDF like a bill, you have much better
control with PassiveTeX.

=head1 AUTHOR

Jörg Walter, jwalt@cpan.org

=cut
