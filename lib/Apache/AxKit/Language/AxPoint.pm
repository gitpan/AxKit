# $Id: AxPoint.pm,v 1.7 2001/06/03 14:15:46 matt Exp $

package Apache::AxKit::Language::AxPoint;

@ISA = ('Apache::AxKit::Language');

use strict;

use Apache;
use Apache::Request;
use Apache::AxKit::Language;
use Apache::AxKit::Provider;
use PDFLib 0.02;
use XML::XPath;

my @xindent;

sub stylesheet_exists () { 0; }

sub handler {
    my $class = shift;
    my ($r, $xml_provider, undef) = @_;
    
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
    
    my $pdf = PDFLib->new();
    $pdf->papersize("slides");
    $pdf->set_border_style("solid", 0);
    
    $pdf->info(Title => $xpath->findvalue("/slideshow/title"));
    $pdf->info(Creator => $xpath->findvalue("/slideshow/metadata/speaker"));
    
    my ($logo_node) = $xpath->findnodes("/slideshow/metadata/logo");
    my ($bg_node) = $xpath->findnodes("/slideshow/metadata/background");
    
    my ($logo, $bg);
    if ($logo_node) {
        $logo = $pdf->load_image(
            filename => $logo_node->string_value,
            filetype => get_filetype($logo_node->string_value),
            )
            || die "Cannot load image $logo_node!";
    }
    
    if ($bg_node) {
        $bg = $pdf->load_image(
            filename => $bg_node->string_value,
            filetype => get_filetype($bg_node->string_value),
            )
            || die "Cannot load image $bg_node!";
    }
    
    my $new_page = sub {
        my ($node) = @_;
        
        $pdf->start_page;
        
        my $transition = $node->findvalue('ancestor-or-self::node()/@transition');
        
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
        
    # title page
    $new_page->($xpath->findnodes('/')->get_node(1));
    
    $pdf->set_font(face => "Helvetica-Bold", size => 24);
    
    my $root_bookmark = $pdf->add_bookmark(text => "Title", open => 1);
    
    $pdf->print_boxed($xpath->findvalue("/slideshow/title"),
            x => 20, y => 40, w => 570, h => 300, mode => "center");
    
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
    
    foreach my $slideset ($xpath->findnodes("/slideshow/*[name() = 'slideset' or name() = 'slide']")) {
        if ($slideset->getName() eq 'slide') {
            process_slide($pdf, $new_page, $slideset, $root_bookmark);
        }
        else {
            process_slideset($pdf, $new_page, $slideset, $root_bookmark);
        }
    }
    
    $r->content_type("application/pdf");
    
    $pdf->finish;
    
    print $pdf->get_buffer;
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
            x => 20, y => 40, w => 570, h => 200, mode => "center");
    
    foreach my $slide ($slideset->findnodes("slide")) {
        process_slide($pdf, $new_page, $slide, $slide_bookmark);
    }
}

sub process_slide {
    my ($pdf, $new_page, $slide, $parent_bookmark) = @_;
    
    $pdf->end_page;
    my @images;
    foreach my $image ($slide->findnodes("image")) {
        push @images, $pdf->load_image(
                filename => $image->string_value,
                filetype => get_filetype($image->string_value),
                );
    }
    
    $new_page->($slide);
    my $h = 300;
    if (my $title = $slide->findvalue("title")) {
        $pdf->add_bookmark(text => $title, level => 3, parent_of => $parent_bookmark);
        $pdf->set_font(face => "Helvetica", size => 24);
        $pdf->print_boxed($title, x => 20, y => 350, 
                w => 570, h => 70, mode => "center");
        $h = 370;
    }
    
    $pdf->set_text_pos(60, $h);
    foreach my $item ($slide->findnodes("point|source_code|image")) {
        if ($item->getName eq "point") {
            point($pdf, $item->findvalue('@level') || 1, $item->string_value);
        }
        elsif ($item->getName eq 'source_code') {
            source_code($pdf, $item->string_value, $item->getAttribute('fontsize'));
        }
        elsif ($item->getName eq 'image') {
            image($pdf, $item->getAttribute('scale') || 1, shift @images);
        }
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
    my ($pdf, $level, $text) = @_;
    
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
}

sub source_code {
    my ($pdf, $text, $size) = @_;
    
    my ($x, $y) = $pdf->get_text_pos;
    
    $pdf->set_font(face => "Courier", size => $size || 14);
    
    $y -= 10 if @xindent;
    
    $pdf->print_boxed($text, x => 80, y => 0, w => 500, h => $y);
    
}

sub image {
    my ($pdf, $scale, $file_handle) = @_;
    
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
    
    $pdf->set_text_pos($x, $y - $imgh);
}

sub get_filetype {
    my $filename = shift;
    
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
    return $source_tree;
}

1;
