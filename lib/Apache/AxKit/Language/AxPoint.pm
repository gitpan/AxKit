# $Id: AxPoint.pm,v 1.12 2001/12/29 08:45:59 matt Exp $

package Apache::AxKit::Language::AxPoint;

@ISA = ('Apache::AxKit::Language');

use strict;

use Apache;
use Apache::Request;
use Apache::AxKit::Language;
use Apache::AxKit::Provider;
use PDFLib 0.02;
use XML::XPath;
use File::Basename ();

my @xindent;

sub stylesheet_exists () { 0; }

sub handler {
    my $class = shift;
    my ($r, $xml_provider, undef, $last_in_chain) = @_;

    my $xpath = XML::XPath->new();
    
    my $source_tree;
    
    my $xml_parser = XML::Parser->new(
            ErrorContext => 2,
            Namespaces => $XML::XPath::VERSION < 1.07 ? 1 : 0,
            ParseParamEnt => 1,
            );
    
    my $parser = XML::XPath::XMLParser->new(parser => $xml_parser);
    
    if (my $entity_handler = $xml_provider->get_ext_ent_handler()) {
        $xml_parser->setHandlers(
                ExternEnt => $entity_handler,
                );
    }
    
    AxKit::Debug(6, "AxPoint: Getting XML Source");
    
    if (my $dom = $r->pnotes('dom_tree')) {
        # dom_tree is an XML::XPath DOM
        $source_tree = $dom;
        delete $r->pnotes()->{'dom_tree'};
    }
    elsif (my $xml = $r->pnotes('xml_string')) {
        eval {
            $source_tree = $parser->parse($xml);
        };
        if ($@) {
            throw Apache::AxKit::Exception::Error(-text => "Parse of xml_string failed: $@");
        }
    }
    else {
        $source_tree = get_source_tree($xml_provider, $parser);
    }
    
    $xpath->set_context($source_tree);

    AxKit::Debug(7, "AxPoint: creating pdf");
    
    my $pdf = PDFLib->new();
    $pdf->papersize("slides");
    $pdf->set_border_style("solid", 0);
    
    $pdf->info(Title => $xpath->findvalue("/slideshow/title"));
    $pdf->info(Creator => $xpath->findvalue("/slideshow/metadata/speaker"));
    
    my ($logo_node) = $xpath->findnodes("/slideshow/metadata/logo");
    my ($bg_node) = $xpath->findnodes("/slideshow/metadata/background");

    AxKit::Debug(7, "AxPoint: loading main bg/logo images");
    
    my ($logo, $bg);
    if ($logo_node) {
        $logo = $pdf->load_image(
            filename => $logo_node->string_value,
            filetype => get_filetype($logo_node->string_value),
            );
        if (!$logo) {
            AxKit::Debug(7, "AxPoint: failed to load logo " . $logo_node->string_value);
            $pdf->finish;
            die "Cannot load image $logo_node!";
        }
    }
    
    if ($bg_node) {
        $bg = $pdf->load_image(
            filename => $bg_node->string_value,
            filetype => get_filetype($bg_node->string_value),
            );
        if (!$bg) {
            AxKit::Debug(7, "AxPoint: failed to load logo " . $bg_node->string_value);
            $pdf->finish;
            die "Cannot load image $bg_node!";
        }
    }

    AxKit::Debug(7, "AxPoint: Creating new_page sub");
    
    my $new_page = sub {
        my ($node, $trans) = @_;
        
        $pdf->start_page;
        
        my $transition = $trans || $node->findvalue('ancestor-or-self::*/@transition') || 'replace';
        
        $pdf->set_parameter("transition", lc($transition)) if $transition;
    
        $pdf->add_image(img => $bg, x => 0, y => 0, scale => $bg_node->findvalue('@scale') || 1.0)
                if $bg_node;
        
        if ($logo_node) {
            my $logo_scale = $logo_node->findvalue('@scale') || 1.0;
            my $logo_w = $logo->width * $logo_scale;
            $pdf->add_image(img => $logo, x => 612 - $logo_w, y => 0, scale => $logo_scale);
        }
    
        $pdf->set_font(face => "Helvetica", size => 18.0);
    
        @xindent = ();
            
        $pdf->set_text_pos(80, 300);
    };
    
    AxKit::Debug(7, "AxPoint: creating front page");
    # title page
    $new_page->($xpath->findnodes('/')->get_node(1));
    
    $pdf->set_font(face => "Helvetica-Bold", size => 24);
    
    my $root_bookmark = $pdf->add_bookmark(text => "Title", open => 1);
    
    $pdf->print_boxed($xpath->findvalue("/slideshow/title"),
            x => 20, y => 50, w => 570, h => 300, mode => "center");
    
    $pdf->print_line("");
    $pdf->print_line("");
    $pdf->print_line("");
    $pdf->print_line("");
    
    my ($x, $y) = $pdf->get_text_pos();
    
    $pdf->set_font(face => "Helvetica-Bold", size => 20);
    
    $pdf->add_link(link => "mailto:" . $xpath->findvalue("/slideshow/metadata/email"),
            x => 20, y => $y - 10, w => 570, h => 24);
    $pdf->print_boxed($xpath->findvalue("/slideshow/metadata/speaker"),
            x => 20, y => 40, w => 570, h => $y - 24, mode => "center");
    
    $pdf->print_line("");
    (undef, $y) = $pdf->get_text_pos();
    
    $pdf->add_link(link => $xpath->findvalue("/slideshow/metadata/link"),
            x => 20, y => $y - 10, w => 570, h => 24);
    $pdf->print_boxed($xpath->findvalue("/slideshow/metadata/organisation"),
            x => 20, y => 40, w => 570, h => $y - 24, mode => "center");

    AxKit::Debug(7, "AxPoint: creating slides");
    
    foreach my $slideset ($xpath->findnodes("/slideshow/*[name() = 'slideset' or name() = 'slide']")) {
        if ($slideset->getName() eq 'slide') {
            process_slide($pdf, $new_page, $slideset, $root_bookmark);
        }
        else {
            process_slideset($pdf, $new_page, $slideset, $root_bookmark);
        }
    }

    AxKit::Debug(7, "AxPoint: outputting pdf");
    
    $r->content_type("application/pdf");

    AxKit::Debug(5, "finish pdf");
    
    $pdf->finish;
    
    $r->print( $pdf->get_buffer );
}

sub process_slideset {
    my ($pdf, $new_page, $slideset, $parent_bookmark) = @_;
    $new_page->($slideset);
    
    my $slide_bookmark = $pdf->add_bookmark(
            text => $slideset->findvalue("title"), 
            level => 2, 
            parent_of => $parent_bookmark, 
            open => 1,
            );
    
    $pdf->set_font(face => "Helvetica", size => 24);
    $pdf->print_boxed($slideset->findvalue("title"),
            x => 20, y => 50, w => 570, h => 200, mode => "center");

    my ($x, $y) = $pdf->get_text_pos();
    $pdf->add_link(link => $slideset->findvalue('title/@href'),
        x => 20, y => $y - 5, w => 570, h => 24) if $slideset->findvalue('title/@href');

    if (my $subtitle = $slideset->findvalue("subtitle")) {
      $pdf->set_font(face => "Helvetica", size => 18);
      $pdf->print_boxed($subtitle,
          x => 20, y => 20, w => 570, h => 200, mode => "center");
      if (my $href = $slideset->findvalue('subtitle/@href')) {
          ($x, $y) = $pdf->get_text_pos();
          $pdf->add_link(link => $href,
              x => 20, y => $y - 5, w => 570, h => 18);
      }
    }
    
    foreach my $slide ($slideset->findnodes("slide")) {
        process_slide($pdf, $new_page, $slide, $slide_bookmark);
    }
}

sub process_slide {
    my ($pdf, $new_page, $slide, $parent_bookmark, $do_up_to) = @_;
    
    $pdf->end_page;
    my @images;
    foreach my $image ($slide->findnodes("image")) {
        push @images, $pdf->load_image(
                filename => $image->string_value,
                filetype => get_filetype($image->string_value),
                );
    }
    
    if ($do_up_to) {
        my @nodes = $slide->findnodes("point|source_code|image");
        my $do_to_node = $nodes[$do_up_to - 1];
        $new_page->($slide, $do_to_node->findvalue('@transition'));
    }
    else {
        $new_page->($slide);
    }
    
    my $h = 300;
    if (my $title = $slide->findvalue("title")) {
        $pdf->add_bookmark(text => $title, level => 3, parent_of => $parent_bookmark) unless $do_up_to;
        $pdf->set_font(face => "Helvetica", size => 24);
        $pdf->print_boxed($title, x => 20, y => 350, 
                w => 570, h => 70, mode => "center");

        my ($x, $y) = $pdf->get_text_pos();
        $pdf->add_link(link => $slide->findvalue('title/@href'),
                x => 20, y => $y - 5, w => 570, h => 24) if $slide->findvalue('title/@href');

        $h = 370;
    }
    
    $pdf->set_text_pos(60, $h);

    my $new_do_up_to = 1;
    foreach my $item ($slide->findnodes("point|source_code|image")) {
        if (!$do_up_to && $item->findvalue('@transition')) {
            process_slide($pdf, $new_page, $slide, $parent_bookmark, $new_do_up_to);
        }

        if ($do_up_to) {
            last if $do_up_to == $new_do_up_to;
        }
        
        if ($item->getName eq "point") {
            point($pdf, $item->findvalue('@level') || 1, $item->string_value, $item->findvalue('@href'));
        }
        elsif ($item->getName eq 'source_code') {
            source_code($pdf, $item->string_value, $item->getAttribute('fontsize'));
        }
        elsif ($item->getName eq 'image') {
            image($pdf, $item->getAttribute('scale') || 1, shift @images, $item->findvalue('@href'));
        }
        
        $new_do_up_to++;
    }
    
}

###########################################################
# functions
###########################################################

sub new_page {
    my ($pdf, $node, $logo, $bg) = @_;
    
    $pdf->start_page;
    
    my $transition = $node->findvalue('ancestor-or-self::node()/@transition');
    
    $pdf->set_parameter("transition", lc($transition)) if $transition;

    $pdf->add_image(img => $bg, x => 0, y => 0, scale => 1.0);

    $pdf->add_image(img => $logo, x => 420, y => 0, scale => 0.4);

    $pdf->set_font(face => "Helvetica", size => 18.0);

    @xindent = ();
        
    $pdf->set_text_pos(80, 300);
    
}

sub bullet {
    my ($pdf, $level) = @_;
    
    my ($char, $size);
    if ($level == 1) {
        $char = "l";
        $size = 18;
    }
    elsif ($level == 2) {
        $char = "u";
        $size = 16;
    }
    elsif ($level == 3) {
        $char = "p";
        $size = 14;
    }
    
    my $leading = $pdf->get_value("leading");
    $pdf->set_value("leading", $leading + 4);
    $pdf->set_value("leading", $leading + 20) if $level == 1;
    
    $pdf->print_line("");
    
    my ($x, $y) = $pdf->get_text_pos;
    
    if (!@xindent || $level > $xindent[0]{level}) {
        unshift @xindent, {level => $level, x => $x};
    }
    
    $pdf->set_font(face => "ZapfDingbats", size => $size - 4, encoding => "builtin");
    $pdf->print($char);
    $pdf->set_font(face => "Helvetica", size => $size);
    $pdf->print("   ");
    return $size;
}

sub point {
    my ($pdf, $level, $text, $href) = @_;
    
    my ($x, $y) = $pdf->get_text_pos;
    
    if (@xindent && $level <= $xindent[0]{level}) {
        my $last;
        while ($last = shift @xindent) {
            if ($last->{level} == $level) {
                $pdf->set_text_pos($last->{x}, $y);
                $x = $last->{x};
                last;
            }
        }
    }
    
    if ($level == 1) {
        $pdf->set_text_pos(80, $y);
    }
    
    my $size = bullet($pdf, $level);
    
    ($x, $y) = $pdf->get_text_pos;
    
    $pdf->print_boxed($text, x => $x, y => 0, w => 570 - $x, h => $y + $size);
    $pdf->add_link(link => $href,
        x => 20, y => $y - 5 + $level, w => 570, h => $size) if $href;

}

sub source_code {
    my ($pdf, $text, $size) = @_;
    
    my ($x, $y) = $pdf->get_text_pos;
    
    $pdf->set_font(face => "Courier", size => $size || 14);
    
    $y -= 10 if @xindent;
    
    $pdf->print_boxed($text, x => 80, y => 0, w => 500, h => $y);
    
}

sub image {
    my ($pdf, $scale, $file_handle, $href) = @_;
    
    $pdf->print_line("");
    
    my ($x, $y) = $pdf->get_text_pos;
    
    my ($imgw, $imgh) = (
            $pdf->get_value("imagewidth", $file_handle->img),
            $pdf->get_value("imageheight", $file_handle->img)
            );
    
    $imgw *= $scale;
    $imgh *= $scale;
    
    $pdf->add_image(img => $file_handle,
            x => (612 / 2) - ($imgw / 2),
            y => ($y - $imgh),
            scale => $scale);
    $pdf->add_link(link => $href, x => 20, y => $y - $imgh, w => 570, h => $imgh) if $href;
    
    $pdf->set_text_pos($x, $y - $imgh);
}

sub get_filetype {
    my $filename = shift;

    AxKit::Debug(8, "AxPoint: get_filetype($filename)");
    
    my ($suffix) = $filename =~ /([^\.]+)$/;
    $suffix = lc($suffix);
    if ($suffix eq 'jpg') {
        return 'jpeg';
    }
    return $suffix;
}

sub get_source_tree {
    my ($provider, $parser) = @_;
    my $source_tree;
    AxKit::Debug(7, "AxPoint: reparsing file");
    eval {
        my $fh = $provider->get_fh();
        # warn("parsing FH $fh with parser $parser\n");
        local $/;
        my $contents = <$fh>;
        # warn("FH contains: $contents\n");
        $source_tree = $parser->parse($contents);
        # warn("Parse completed\n");
        close($fh);
    };
    if ($@) {
        # warn("parse_fh failed\n");
        $source_tree = $parser->parse(${ $provider->get_strref() });
    }

    # warn("get_source_tree = $source_tree\n");
    AxKit::Debug(7, "AxPoint: returning source tree"); 
    return $source_tree;
}

1;

__END__

=head1 NAME

AxPoint - An AxKit PDF Slideshow generator

=head1 SYNOPSIS

  AxAddStyleMap application/x-axpoint Apache::AxKit::Language::AxPoint
  
  AxAddRootProcessor application/x-axpoint NULL slideshow

=head1 DESCRIPTION

I got sick of not being able to do pretty slideshows about AxKit without
resorting to the bloated OpenOffice. So I decided to write something that
allows you to do simple slideshows with bullet points and a few other
niceties using XML, AxKit, and rendering to PDF.

I discovered that PDF can do transitions, and full screen mode (even on Linux),
and so it makes the perfect medium for doing a slideshow.

Note: This module requires PDFLib.pm from CPAN. It also requires the library
B<pdflib>, which is available under the Alladin license from
http://www.pdflib.com/. The Alladin license does not allow re-distribution
of modified binaries, so it is not strictly open source, but it is free to
use even for commercial use.

=head1 Usage

The SYNOPSIS section describes how to set this thing up in AxKit, so here I
will focus on the syntax of AxPoint XML files. I tend to use the suffix ".axp"
for my AxPoint files, but you are free to use whatever you please.

The easiest way to describe all the features is with a complete presentation
first:

  <slideshow transition="glitter">
    <title>AxPoint Example</title>
    <metadata>
      <speaker>Matt Sergeant</speaker>
      <email>matt@axkit.com</email>
      <organisation>AxKit.com Ltd</organisation>
      <link>http://axkit.com/</link>
      <logo>ax_logo.png</logo>
      <background>bg.png</background>
    </metadata>
    
    <slide transition="dissolve">
      <title>Top Level Slide</title>
      <point>This is a top level slide</point>
      <point>It is a child of the &lt;slideshow> tag</point>
      <point>Can have it's own transition</point>
    </slide>
    
    <slideset transition="blinds">
      <title>Slidesets</title>
      <subtitle>Slidesets can have subtitles</subtitle>
      
      <slide>
        <title>Slideset Example</title>
        <point>A slideset groups slides under a particular title</point>
        <point>Slidesets can have a transition for the group of slides</point>
      </slide>
    </slideset>
    
    <slideset>
      <title>Slide Tags</title>
      
      <slide>
        <title>Bullet Points</title>
        <point>Level 1 bullet : &lt;point></point>
        <point level="1">Another Level 1 bullet : &lt;point level="1"></point>
        <point level="2">Level 2 bullet : &lt;point level="2"></point>
        <point level="3">Level 3 bullet : &lt;point level="3"></point>
        <point>Back to level 1</point>
      </slide>
      
      <slide>
        <title>Source Core</title>
        <source_code><![CDATA[
Source code
uses   fixed       font
Don't forget to use CDATA sections so you can
 <include/><some/><xml/>
        ]]></source_code>
      </slide>
      
      <slide>
        <title>Pictures</title>
        <point>Images are very simple, and always centered</point>
        <image scale="0.5" href="file_large.jpg">file.jpg</image>
      </slide>
      
    </slideset>
    
    <slideset transition="dissolve">
      <title href="http://foo.bar/aslidesettitle">Slideset titles can have href attributes</title>
      <subtitle href="http://foo.bar/aslidesetsubtitle">Slideset subtitles too</subtitle>
      
      <slide>
        <title href="http://foo.bar/aslidetitle">Don't forget links for slide titles</title>
        <point href="http://foo.bar/apoint">...and for points of various levels</point>
      </slide>
    </slideset>
    
    
  </slideshow>


It's not very complex. And with good reason: generating PDFs can be slow. With this simple schema
we can generate a 100 slide PDF in about 1 second. There are many deficiencies with the tagset,
most significantly that no bold or italics or any coloring can be applied to the text by using
tags. The reason being that this is quite hard to do with PDFLib - you have to do text measurement
yourself and do the word-wrapping yourself, and so on. The way it is setup right now is very
simple to use and implement.

=head1 AUTHOR

Matt Sergeant, matt@axkit.com

=cut
