# $Id: File.pm,v 1.14 2000/09/14 20:48:38 matt Exp $

package Apache::AxKit::Provider::File;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Provider');

use Apache;
use Apache::Log;
use Apache::AxKit::Exception;
use Apache::AxKit::Provider;
use Apache::MimeXML;
use File::Basename;
use XML::Parser;
use Fcntl qw(:DEFAULT);

sub init {
    my $self = shift;
    my (%p) = @_;
    
    if ($p{uri}) {
        my $uri = $p{uri};
        my $r = $self->{apache};
        
        if ($uri =~ /^\//) {
            my $root = $r->document_root();
            $self->{file} = $r->document_root() . $uri;
        }
        else {
            my $current;
            if ($p{rel}) {
                $current = $p{rel}->get_filename();
            }
            else {
                $current = $r->filename();
            }
            $current =~ s/[^\/]*$//;
            $self->{file} = $current . $uri;
        }
        AxKit::Debug(8, "File Provider set filename to $self->{file}");
    }
    else {
        $self->{file} = $self->{apache}->filename();
    }
}

sub get_filename {
    shift->{file};
}

sub process {
    my $self = shift;
    
    my $xmlfile = $self->{file};
    
    if (!-e $xmlfile) {
        throw Apache::AxKit::Exception::Declined(
                reason => "file '$xmlfile' does not exist"
                );
    }
    
    if (!-r _ ) {
        throw Apache::AxKit::Exception::Declined(
                reason => "file '$xmlfile' does not have the read bits set"
                );
    }
    
    if (-d _ ) {
        throw Apache::AxKit::Exception::Declined(
                reason => "'$xmlfile' is a directory"
                );
    }
    
    local $^W;
    if (($xmlfile =~ /\.xml$/i) ||
        ($self->{apache}->content_type() =~ /^(text|application)\/xml/) ||
        $self->{apache}->notes('xml_string') ||
        Apache::MimeXML::check_for_xml($xmlfile)) {
        chdir(dirname($xmlfile));
        return 1;
    }
    
    throw Apache::AxKit::Exception::Declined(
            reason => "'$xmlfile' not recognised as XML"
            );
}

sub exists {
    my $self = shift;
    if (-e $self->{file}) {
        if (-r _ ) {
            return 1;
        }
        else {
            $self->apache_request()->log->error("'$self->{file}' not readable");
            return;
        }
    }
    return;
}

sub mtime {
    my $self = shift;
    return -M $self->{file};
}

sub get_fh {
    my $self = shift;
    my $filename = $self->{file};
    chdir(dirname($filename));
    my $fh = Apache->gensym();
    if (sysopen($fh, $filename, O_RDONLY)) {
        flock($fh, 1);
        return $fh;
    }
    throw Apache::AxKit::Exception::Error(-text => "Can't open '$self->{file}': $!");
}

sub get_strref {
    my $self = shift;
    my $fh = $self->get_fh();
    local $/;
    my $contents = <$fh>;
    return \$contents
}

sub key {
    my $self = shift;
    return $self->{file};
}

# my $xml_parser;

sub get_styles {
    my $self = shift;
    my ($media, $style) = @_;
    
    # check ye olde method first...
    my ($styles, $ext_ents) = $self->old_get_styles($media, $style);
    if (@$styles) {
        return $styles, $ext_ents;
    }
    
    my $xmlfile = $self->{file};
    
    # need to extract the following from the XML file:
    #   DocType Public Identifier
    #   DTD filename
    #   Root element name (including namespace)
    # use three element array @$vals
    
    my $vals = [];
    $ext_ents = [];
    
    AxKit::Debug(4, "get_styles: creating XML::Parser");
    
    my $xml_parser = XML::Parser->new(
                ParseParamEnt => 1, 
                ErrorContext => 2,
                Namespaces => 1,
                );
    $xml_parser->setHandlers(
                Start => \&parse_start,
                Doctype => \&parse_dtd,
                Entity => \&parse_entity_decl,
                );
    
    eval {
        local $SIG{__DIE__}; # just in case!
        AxKit::Debug(4, "calling parsefile('$xmlfile')");
        $xml_parser->parsefile(
                $xmlfile,
                XMLStyle_ext_ents => $ext_ents,
                XMLStyle_vals => $vals,
                );
    };
    if ($@) {
        AxKit::Debug(4, "parse returned: >> $@ <<");
        if ("$@" !~ /^OK/) { # note that regex bindings don't stringify in 5.6.0 - fixed in 5.6.1
            throw Apache::AxKit::Exception::Error(
                    -text => "Parsing '$xmlfile' returned: $@\n"
                    );
        }
    }
        
    AxKit::Debug(4, "parse returned successfully");
    
    # now get all current styles that match all these properties
    my @styles = $AxKit::Cfg->GetMatchingProcessors($media, $style, @$vals);
    
    # get mime-type => module mapping
    my $style_mapping = $AxKit::Cfg->StyleMap;

    AxKit::Debug(3, "loading style modules");    
    for my $style (@styles) {
        my $mapto;
        AxKit::Debug(4, "looking for mapping for style type: '$style->{type}'");
        if (!( $mapto = $style_mapping->{ $style->{type} } )) {
            throw Apache::AxKit::Exception::Declined(
                    reason => "No implementation mapping available for type '$style->{type}'"
                    );
        }

        $style->{module} = $mapto;

        # first load module if it's not already loaded.
        my $module = $mapto . '.pm';
        $module =~ s/::/\//g;

        if (!$INC{$module}) {
            AxKit::Debug(4, "trying to load module: '$module'");
            eval {
                local $SIG{__DIE__};
                require $module;
            };
            if ($@) {
                throw Apache::AxKit::Exception::Declined(
                        reason => "Load of '$mapto' failed with: $@"
                        );
            }
        }

    }
    
    return \@styles, $ext_ents;
}

sub parse_start {
    my ($e, $el) = @_;
    my $ns = $e->namespace($el);
    # use James Clark's universal name format
    $e->{XMLStyle_vals}[2] = $ns ? "{$ns}$el" : $el;
    die "OK\n";
}

sub parse_entity_decl {
    my $e = shift;
    my ($name, $val, $sysid, $pubid, $ndata) = @_;
#    warn "external entity: '$sysid'\n";
    if (!defined $val) {
        # external entity - save so the cache gets done properly!
        push @{$e->{XMLStyle_ext_ents}}, $sysid;
    }
}

sub parse_dtd {
    my ($e, $name, $sysid, $pubid) = @_;
    
    $e->{XMLStyle_vals}[0] = $pubid;
    $e->{XMLStyle_vals}[1] = $sysid;
}

# my $xmlparser;

sub old_get_styles {
    my $self = shift;
    
    my $xmlfile = $self->{file};
    
    my ($media, $pref_style) = @_;
    
    if ($pref_style eq '#default') {
        undef $pref_style;
    }
    
    my $styles = [];
    my $ext_ents = [];
    
    AxKit::Debug(4, "get_styles: creating XML::Parser object");
    
    my $xmlparser = XML::Parser->new(
            ParseParamEnt => 1, 
            ErrorContext => 2,
            );
    $xmlparser->setHandlers(
            Start => \&Apache::AxKit::Provider::File::OldParser::parse_start,
            Proc => \&Apache::AxKit::Provider::File::OldParser::parse_pi,
            Entity => \&Apache::AxKit::Provider::File::OldParser::parse_entity_decl,
            );
    
    eval {
        local $SIG{__DIE__}; # just in case...
        AxKit::Debug(4, "calling parsefile('$xmlfile')");
        $xmlparser->parsefile($xmlfile,
            XMLStyle_preferred => $pref_style,
            XMLStyle_style => $styles,
            XMLStyle_ext_ents => $ext_ents,
            XMLStyle_style_screen => [],
            XMLStyle_media => $media,
            );
    };
    if ($@) {
        AxKit::Debug(4, "parse returned: >> $@ <<");
        if ("$@" !~ /^OK/) { # note that regex bindings don't stringify in 5.6.0 - fixed in 5.6.1
            throw Apache::AxKit::Exception::Error(
                    -text => "Parsing '$xmlfile' returned: $@\n"
                    );
        }
    }
    
    AxKit::Debug(4, "parse returned successfully");
    
    if (!@$styles) {
        throw Apache::AxKit::Exception::Declined(
                reason => "'$xmlfile' has no xml-stylesheet PI\nand no DefaultStyleMap defined"
                );
    }
    
    # get mime-type => module mapping
    my $style_mapping = $AxKit::Cfg->StyleMap;

    AxKit::Debug(3, "loading style modules");    
    for my $style (@$styles) {
        my $mapto;
        AxKit::Debug(4, "looking for mapping for style type: '$style->{type}'");
        if (!( $mapto = $style_mapping->{ $style->{type} } )) {
            throw Apache::AxKit::Exception::Declined(
                    reason => "No implementation mapping available for type '$style->{type}'"
                    );
        }

        $style->{module} = $mapto;

        # first load module if it's not already loaded.
        my $module = $mapto . '.pm';
        $module =~ s/::/\//g;

        if (!$INC{$module}) {
            AxKit::Debug(4, "trying to load module: '$module'");
            eval {
                local $SIG{__DIE__};
                require $module;
            };
            if ($@) {
                throw Apache::AxKit::Exception::Declined(
                        reason => "Load of '$mapto' failed with: $@"
                        );
            }
        }

    }
        
    return ($styles, $ext_ents);
}

############################################################
# XML::Parser callbacks
############################################################

package Apache::AxKit::Provider::File::OldParser;

sub parse_pi {
    my $e = shift;
    my ($target, $data) = @_;
    if ($target ne 'xml-stylesheet') {
        return;
    }
    
    my $style;
    
    $data = ' ' . $data;
    
    while ($data =~ /\G
            \s+
            (href|type|title|media|charset|alternate)
            \s*
            =
            \s*
            (["']) # match quotes "'
            ([^\2<]*?)
            \2     # balance quotes "'
            /gcx) {
        my ($attr, $val) = ($1, $3);
        AxKit::Debug(5, "PI: got $attr = $val\n");
        $style->{$attr} = $val;
    }
    
    if (!exists($style->{href}) || !exists($style->{type})) {
        # href and type are #REQUIRED
        AxKit::Debug(3, "Invalid <?xml-stylesheet?> processing instruction\n");
        return;
    }
    
    my $mediamatch = 0;

    $style->{media} ||= 'screen'; # default according to TR/REC-html40
    $style->{alternate} ||= 'no'; # default according to TR/xml-stylesheet

    # See http://www.w3.org/TR/REC-html40/types.html#type-media-descriptors
    # for details of what we're doing here.
    my @mediatypes = split(/,\s*/, $style->{media});
    
    # strip anything after first non-(A-Za-z0-9\-) character (see REC-html40)
    @mediatypes = map { $_ =~ s/[^A-Za-z0-9\-].*$//; $_; } @mediatypes;

#    warn "media types are ", join(',', @mediatypes), " [$style->{media}] [$e->{XMLStyle_media}]\n";

    # remove unwanted entries
    @mediatypes = grep /^(screen|tty|tv|projection|handheld|print|braille|aural|all)$/, @mediatypes;

    if (grep { $_ eq $e->{XMLStyle_media} } @mediatypes) {
        # found a match for the preferred media type!
#        warn "Media matches!\n";
        $mediamatch++;
    }
    
    if (grep { $_ eq 'all' } @mediatypes) {
        # always match on media type "all"
#        warn "Media is \"all\"\n";
        $mediamatch++;
    }
    
    if ($e->{XMLStyle_preferred}) {
        # someone picked a "title". Use persistant and alternate styles
        if (
                ($style->{alternate} eq 'no') 
                && (!exists $style->{title})
            )
        {
            # This is a persistant style - always make it first.
            if ($mediamatch) {
                push @{$e->{XMLStyle_style_persistant}}, $style;
            }
            elsif ($style->{media} eq 'screen') {
                # store away in case we need the screen matches
                push @{$e->{XMLStyle_style_screen_persistant}}, $style;
            }
        }
        elsif (lc($style->{title}) eq lc($e->{XMLStyle_preferred})) 
        {
            # matching style
            if ($mediamatch) {
                push @{$e->{XMLStyle_style}}, $style;
            }
            elsif ($style->{media} eq 'screen') {
                push @{$e->{XMLStyle_style_screen}}, $style;
            }
        }
    }
    else {
        # no "title" selected. Use persistent and preferred styles
        if (
                ($style->{alternate} eq 'no')
                && (!exists $style->{title})
            ) 
        {
            if ($mediamatch) {
                # This is the persistant style
                push @{ $e->{XMLStyle_style_persistant} }, $style;
            }
            elsif ($style->{media} eq 'screen') {
                push @{$e->{XMLStyle_style_screen_persistant}}, $style;
            }
        }
        elsif (
                ($style->{alternate} eq 'no')
                && (exists $style->{title})
                )
        {
            if ($mediamatch) {
                push @{ $e->{XMLStyle_style} }, $style;
            }
            elsif ($style->{media} eq 'screen') {
                push @{ $e->{XMLStyle_style_screen} }, $style;
            }
        }
    }
}

sub parse_start {
    my $e = shift;
    
    if (!@{$e->{XMLStyle_style}} && !$e->{XMLStyle_style_persistant}) {
        if ($e->{XMLStyle_style_screen_persistant}) {
            push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen_persistant}};
        }
        if (@{$e->{XMLStyle_style_screen}}) {
    #        warn "Matching style for media ", $e->{XMLStyle_media}, " not found. Using screen media stylesheets instead\n";
            push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen}};
        }
    }
    elsif ($e->{XMLStyle_style_persistant}) {
        unshift @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_persistant}};
    }

#    warn "Parse start. Now returning to your regularly scheduled programming...\n";    
    die "OK\n";
}

sub parse_entity_decl {
    my $e = shift;
    my ($name, $val, $sysid, $pubid, $ndata) = @_;
#    warn "external entity: '$sysid'\n";
    if (!defined $val) {
        # external entity - save so the cache gets done properly!
        push @{$e->{XMLStyle_ext_ents}}, $sysid;
    }
}

1;
