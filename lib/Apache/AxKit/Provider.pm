# $Id: Provider.pm,v 1.33 2001/06/04 16:00:33 matt Exp $

package Apache::AxKit::Provider;
use strict;

use Apache::AxKit::Exception;
#use XML::Parser;

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my $apache = shift;
    my $self = bless { apache => $apache }, $class;
    
    if (my $alternate = $AxKit::Cfg->ProviderClass()) {
        AxKit::reconsecrate($self, $alternate);
    }
    
    $self->init(@_);
    
    AxKit::add_depends($self->key());
    
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

sub has_changed {
    my $self = shift;
    my $time = shift;
    return $self->mtime > $time;
}

sub decline {
    my $self = shift;
    my %args = @_;
    
    throw Apache::AxKit::Exception::Declined(
                reason => $args{reason} || "provider declined");
}

sub get_ext_ent_handler {
    my $self = shift;
    return sub {
        my ($e, $base, $sysid, $pubid) = @_;
#        warn "ext_ent: base => $base, sys => $sysid, pub => $pubid\n";
        if ($sysid =~ /^http:/) {
            if ($pubid) {
                return ''; # do not bring in public DTD's
            }
            eval {
                require HTTP::GHTTP;
            };
            if ($@) {
                require LWP;
                return XML::Parser::lwp_ext_ent_handler(@_);
            }
            my $r = HTTP::GHTTP->new($sysid);
            $r->process_request;
            return $r->get_body;
        }
        elsif ($sysid =~ /^(https|ftp):/) {
            if ($pubid) {
                return ''; # do not bring in public DTD's
            }
            die "Cannot download https (SSL) or ftp URL's yet. Patches welcome";
        }
        
#        warn "File provider ext_ent_handler called with '$sysid'\n";
        my $provider = Apache::AxKit::Provider->new(
                AxKit::Apache->request,
                uri => $sysid,
#                rel => $self,
                );
#        warn "Got provider with key: ", $provider->key, "\n";
        my $str = $provider->get_strref;
#        warn "Returning string with length: ", length($$str), "\n";
        return $$str;
    };
}

sub get_styles {
    my $self = shift;
    my ($media, $pref_style) = @_;
    
    if ($pref_style eq '#default') {
        undef $pref_style;
    }
    
    my $xml_styles = [];
    my $vals = [];
    
    my $key = $self->key();
    
    # need to extract the following from the XML file:
    #   DocType Public Identifier
    #   DTD filename
    #   Root element name (including namespace)
    # use three element array @$vals
    
    if (defined &Apache::AxKit::Provider::xs_get_styles_fh) {
        AxKit::Debug(2, "using XS get_styles (libxml2)\n");
        my ($xs_styles, $doctype, $dtd, $root) = 
                $self->xs_get_styles($media, $pref_style);
        @$xml_styles = @$xs_styles;
        @$vals = ($doctype, $dtd, $root);
    }
    else {
        require XML::Parser;
        
        AxKit::Debug(4, "get_styles: creating XML::Parser");
        
        my $xml_parser = XML::Parser->new(
                Namespaces => 1,
                ErrorContext => 2,
                Handlers => {
                    Start => \&parse_start,
                    Doctype => \&parse_dtd,
                    Proc => \&parse_pi,
                },
            );
    
        my $to_parse;
        eval { 
            $to_parse = $self->get_fh();
        };
        if ($@) {
            $to_parse = ${ $self->get_strref(); };
        }
        
        AxKit::Debug(4, "get_styles: calling XML::Parser->parse('$key')");
        $xml_parser->parse(
                $to_parse,
                XMLStyle_preferred => $pref_style,
                XMLStyle_media => $media,
                XMLStyle_style => $xml_styles,
                XMLStyle_vals => $vals,
                XMLStyle_style_screen => [],
                );
            
        AxKit::Debug(4, "get_styles: parse returned successfully");
    }
    
    # Let GetMatchingProcessors to process the @$styles array
    AxKit::Debug(4, "Calling GetMatchingProcessors with ($media, $pref_style, $vals->[0], $vals->[1], $vals->[2])");
    my @styles = $AxKit::Cfg->GetMatchingProcessors($media,
		$pref_style, @$vals[0 .. 2], $xml_styles, $self);
    
    if (!@styles) {
        throw Apache::AxKit::Exception::Declined(
                reason => "No styles defined for '$key'"
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
        eval {
            AxKit::load_module($mapto);
        };
        if ($@) {
            throw Apache::AxKit::Exception::Error(
                    -text => "Load of '$mapto' failed with: $@"
                    );
        }
    }
    
    return \@styles;
}

sub xs_get_styles {
    my $self = shift;
    my ($media, $pref_style) = @_;
    
    my $bits;
    eval {
        my $fh = $self->get_fh();
        AxKit::Debug(4, "calling xs_get_styles_fh()\n");
        $bits = xs_get_styles_fh($self->apache_request, $fh);
    };
    if ($@) {
        my $strref = $self->get_strref();
        AxKit::Debug(4, "calling xs_get_styles_str()\n");
        $bits = xs_get_styles_str($self->apache_request, $$strref);
    }
    
    my @xml_stylesheet = @{$bits->[0]};
    my %attribs = @{$bits->[2]};
    my $element = $bits->[1];
    
    # resolve namespaces (libxml doesn't!)
    if ($attribs{'xmlns'} && $element !~ /:/) {
        $element = "{$attribs{xmlns}}$element";
    }
    elsif ($element =~ /^(.*):(.*)$/) {
        my ($prefix, $el) = ($1, $2);
        my $ns = $attribs{"xmlns:$prefix"};
        $element = "{$ns}$el";
    }
    
    my $e = {
        XMLStyle_style => [], 
        XMLStyle_style_screen => [],
        XMLStyle_preferred => $pref_style,
        XMLStyle_media => $media,
        };
    
    foreach my $pi (@xml_stylesheet) {
        parse_pi($e, "xml-stylesheet", $pi);
    }
    
    if (!@{$e->{XMLStyle_style}} && !$e->{XMLStyle_style_persistant}) {
        if ($e->{XMLStyle_style_screen_persistant}) {
            push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen_persistant}};
        }
        if (@{$e->{XMLStyle_style_screen}}) {
            push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen}};
        }
    }
    elsif ($e->{XMLStyle_style_persistant}) {
        unshift @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_persistant}};
    }
    
    AxKit::Debug(4, "xs_get_styles returned: $bits->[3], $bits->[4], $element\n");
    
    return ($e->{XMLStyle_style}, $bits->[3], $bits->[4], $element);
}

sub parse_start {
    my ($e, $el) = @_;
    my $ns = $e->namespace($el);
    # use James Clark's universal name format
    $e->{XMLStyle_vals}[2] = $ns ? "{$ns}$el" : $el;
    
    if (!@{$e->{XMLStyle_style}} && !$e->{XMLStyle_style_persistant}) {
        if ($e->{XMLStyle_style_screen_persistant}) {
            push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen_persistant}};
        }
        if (@{$e->{XMLStyle_style_screen}}) {
            push @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_screen}};
        }
    }
    elsif ($e->{XMLStyle_style_persistant}) {
        unshift @{$e->{XMLStyle_style}}, @{$e->{XMLStyle_style_persistant}};
    }
    
    $e->finish();
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

Extract the stylesheets from the XML resource. Should return an array
ref of styles. The style entries are hashes refs with required keys
'href' and 'type'.

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
