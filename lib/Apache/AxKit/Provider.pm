# $Id: Provider.pm,v 1.13 2000/09/24 15:10:55 matt Exp $

package Apache::AxKit::Provider;
use strict;

use Apache::AxKit::Exception ':try';

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my $apache = shift;
    my $self = bless { apache => $apache }, $class;
    
    if (my $alternate = $AxKit::Cfg->ProviderClass()) {
        AxKit::reconsecrate($self, $alternate);
    }
    
    $self->init(@_);
    
#     AxKit::Debug(7, "Provider->new Count: " . ++$COUNT);
    
    return $self;
}

sub init {
    # blank - override to provide functionality
}

# sub DESTROY {
#     AxKit::Debug(7, "Provider->DESTROY Count: " . --$COUNT);
# }

sub apache_request {
    my $self = shift;
    return $self->{apache};
}

sub get_ext_ent_handler {
    my $self = shift;
    return sub {
        my ($e, $base, $sysid, $pubid) = @_;
        if ($sysid =~ /^(https?|ftp):/) {
            if ($pubid) {
                return ''; # do not bring in public DTD's
            }
            return XML::Parser::lwp_ext_ent_handler(@_);
        }
        
#        warn "File provider ext_ent_handler called with '$sysid'\n";
        $sysid =~ s/^file:(\/\/)?//;
        my $provider = Apache::AxKit::Provider->new(
                Apache->request,
                uri => $sysid
                );
        my $str = $provider->get_strref;
        return $$str;
    };
}

sub get_styles {
    my $self = shift;
    my ($media, $pref_style) = @_;
    
    if ($pref_style eq '#default') {
        undef $pref_style;
    }
    
    my $styles = [];
    my $ext_ents = [];
    my $vals = [];
    
    my $key = $self->key();
    
    # need to extract the following from the XML file:
    #   DocType Public Identifier
    #   DTD filename
    #   Root element name (including namespace)
    # use three element array @$vals
    
    AxKit::Debug(4, "get_styles: creating XML::Parser");
    
    my $xml_parser = XML::Parser->new(
                ParseParamEnt => 1, 
                ErrorContext => 2,
                Namespaces => 1,
                );
    $xml_parser->setHandlers(
                Start => \&parse_start,
                Doctype => \&parse_dtd,
                Proc => \&parse_pi,
                Entity => \&parse_entity_decl,
                );
    
    my $to_parse = try { 
        $self->get_fh();
    } catch Error with {
        ${ $self->get_strref(); };
    };
    
    try {
        AxKit::Debug(4, "get_styles: calling XML::Parser->parse('$key')");
        $xml_parser->parse(
                $to_parse,
                XMLStyle_preferred => $pref_style,
                XMLStyle_style => $styles,
                XMLStyle_ext_ents => $ext_ents,
                XMLStyle_vals => $vals,
                XMLStyle_style_screen => [],
                XMLStyle_media => $media,
                );
    }
    catch Error with {
        my $E = shift;
        AxKit::Debug(4, "get_styles: parse returned: >> $E <<");
        if ("$E" !~ /^OK/) { # note that regex bindings don't stringify in 5.6.0 - fixed in 5.6.1
            throw Apache::AxKit::Exception::Error(
                    -text => "Parsing '$key' returned: $E\n"
                    );
        }
    };
        
    AxKit::Debug(4, "get_styles: parse returned successfully");

    my @styles;
        
    if (@$styles) {
        @styles = @$styles;
    }
    else {
        # now get all current styles that match all these properties
        @styles = $AxKit::Cfg->GetMatchingProcessors($media, $pref_style, @$vals);
    }
    
    if (!@styles) {
        throw Apache::AxKit::Exception::Error(
                -text => "No styles defined for '$key'"
                );
    }
    
    # get mime-type => module mapping
    my $style_mapping = $AxKit::Cfg->StyleMap;

    AxKit::Debug(3, "get_styles: loading style modules");    
    for my $style (@styles) {
        my $mapto;
        AxKit::Debug(4, "get_styles: looking for mapping for style type: '$style->{type}'");
        if (!( $mapto = $style_mapping->{ $style->{type} } )) {
            throw Apache::AxKit::Exception::Declined(
                    reason => "No implementation mapping available for type '$style->{type}'"
                    );
        }

        $style->{module} = $mapto;

        # first load module if it's not already loaded.
        try {
            AxKit::load_module($mapto);
        }
        catch Error with {
            my $E = shift;
            throw Apache::AxKit::Exception::Declined(
                    reason => "Load of '$mapto' failed with: $E"
                    );
        };
    }
    
    return \@styles, $ext_ents;
}

sub parse_start {
    my ($e, $el) = @_;
    my $ns = $e->namespace($el);
    # use James Clark's universal name format
    $e->{XMLStyle_vals}[2] = $ns ? "{$ns}$el" : $el;
    
#    warn "styles: ", scalar @{$e->{XMLStyle_style_screen_persistant}}, "\n";
    
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
        AxKit::Debug(10, "parse_pi: $attr = $val");
        $style->{$attr} = $val;
    }
    
    if (!exists($style->{href}) || !exists($style->{type})) {
        # href and type are #REQUIRED
        AxKit::Debug(3, "pi_get_styles: Invalid <?xml-stylesheet?> processing instruction\n");
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
        # warn "someone picked a \"title\" : $e->{XMLStyle_preferred}. Use persistant and alternate styles\n";
        if (
                ($style->{alternate} eq 'no') 
                && (!exists $style->{title})
            )
        {
            # warn "This is a persistant style - always make it first\n";
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
            # warn "matching style\n";
            if ($mediamatch) {
                push @{$e->{XMLStyle_style}}, $style;
            }
            elsif ($style->{media} eq 'screen') {
                push @{$e->{XMLStyle_style_screen}}, $style;
            }
        }
    }
    else {
        # warn "no \"title\" selected. Use persistent and preferred styles\n";
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

1;
__END__

=head1 NAME

Apache::AxKit::Provider - base Provider class

=head1 SYNOPSIS

Override the base Provider class and enable it using:

    AxProvider MyClass
    
    # alternatively use:
    # PerlSetVar AxProvider MyClass

=head1 DESCRIPTION

The Provider class is used to read in the data source for the given URL.
The default Provider is Provider::File, which reads from the filesystem,
although obviously you can read from just about anywhere.

Should you wish to override the default Provider, these are the methods
you need to implement:

=head2 process()

Determine whether or not to process this URL. For example, you don't want
to process a directory request, or if the resource doesn't exist. Return 1
to tell AxKit to process this URL, or die with a Declined exception (with 
a reason) if you do not wish to process this URL.

=head2 mtime()

Return the last modification time in days before the current time.

=head2 get_styles()

Extract the stylesheets and external entities from the XML resource. Should
return a list of ($styles, $ext_ents). Both are array refs, the style
entries are hashes refs with required keys 'href' and 'type'. The external
entities entries are scalars containing the system identifier of the 
external entity.

=head2 get_fh()

This method should return an open filehandle, or die if that's not possible.

=head2 get_strref()

This method returns a reference to a scalar containing the contents of the
stylesheet, or die if that's not possible. At least one of get_fh or 
get_strref B<must> work.

=head2 key()

This method should return a "key" value that is unique to this URL.

=head2 get_ext_ent_handler()

This should return a sub reference that can be used instead of 
XML::Parser's default external entity handler. See the XML::Parser
documentation for what this sub should do (or look at the code in
the File provider).

=head2 exists()

Return 1 if the resource exists (and is readable).

=cut
