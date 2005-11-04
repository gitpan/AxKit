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

# $Id: Provider.pm,v 1.24 2005/08/10 12:21:55 matts Exp $

package Apache::AxKit::Provider;
use strict;

use Apache::AxKit::Exception;
use Apache::Constants qw(OK DECLINED);
use AxKit;

# use vars qw/$COUNT/;

# protocol registry

my %pseudo_protocols =
  (
   'axkit' => \&AxKit::get_axkit_uri,
   );

sub register_protocol {
    my ($protocol, $handler) = @_;
    $pseudo_protocols{lc($protocol)} = $handler;
}

sub has_protocol {
    exists $pseudo_protocols{lc($_[0])};
}

# end of protocol registry

sub get_provider {
    my ($uri,$r,$provider_cb) = @_;
    AxKit::Debug(8,"get_provider: $uri");
    my ($protocol) = ($uri =~ m/^([a-zA-Z0-9]+):/);
    if ($protocol) {
        throw Apache::AxKit::Exception::Error(-text => "this resource has no provider ($uri)") if !ref($pseudo_protocols{$protocol});
        return $pseudo_protocols{$protocol}->new_provider($r, uri => $uri);
    } elsif (substr($uri,0,1) ne '/') { # resolve relative URIs -- FIXME: does $r->lookup_uri do this for us?
        my $base = AxKit::ToUTF8($r->uri());
        $base =~ s{[^/]*$}{};
        $uri = $base.$uri;
        $uri =~ s/\?.*$//;
        $uri =~ s{/./}{/}g;
        $uri =~ s{/[^/]+/+../}{/}g;
        AxKit::Debug(8,"Absolute URI: ".$uri);
    }
    
    # create a subrequest, so we get the right AxKit::Cfg for the URI
    my $sub = $r->lookup_uri($uri);
    my $cfg = Apache::AxKit::ConfigReader->new($sub);
    
    my $result = do {
        local $AxKit::Cfg = $cfg;
        ($provider_cb?$provider_cb->($sub):__PACKAGE__->new_content_provider($sub));
    };
    undef $sub;
    undef $cfg;
    return $result;
}

sub get_uri {
    my ($uri,$r,$provider_cb) = @_;
    my ($protocol) = ($uri =~ m/^([a-zA-Z0-9]+):/);
    if ($protocol && ref($pseudo_protocols{$protocol})) {
        AxKit::Debug(8, "using pseudo_protocol: $protocol");
        return $pseudo_protocols{$protocol}->($uri,$r);
    }
    
    my $str = get_provider(@_)->get_strref;
    
    return $$str;
}

# end of protocol utilities

sub new_provider { # make this just "new"? (would be logical, but probably breaks things...)
    my ($self, $r, @args) = @_;
    my $provider = bless { apache => $r }, $self;
    $provider->init(@args);
    return $provider;
}

sub new_style_provider {
    my $class = shift;
    my $apache = shift;
    my $self = bless { apache => $apache }, $class;

    if (my $alternate = $AxKit::Cfg->StyleProviderClass()) {
        AxKit::Debug(8, "Style Provider Override: $alternate" );
        AxKit::reconsecrate($self, $alternate);
    }

    $self->init(@_);

    AxKit::add_depends("{style}".$self->key());

    return $self;
}

sub new_content_provider {
    my $class = shift;
    my $apache = shift;
    my $self = bless { apache => $apache }, $class;

    if (my $alternate = $AxKit::Cfg->ContentProviderClass()) {
        AxKit::Debug(8, "Content Provider Override: $alternate" );
        AxKit::reconsecrate($self, $alternate);
    }

    $self->init(@_);

    AxKit::add_depends("{content}".$self->key());

    return $self;
}

sub new {
    my $class = shift;
    return $class->new_content_provider( @_ );
}

sub init {
    # blank - override to provide functionality
}

# sub DESTROY {
#     AxKit::Debug(7, "Provider->DESTROY Count: " . --$COUNT);
# }

sub get_strref {
    throw Apache::AxKit::Exception::Error (
        -text => "Subclass must implement get_strref"
        );
}

sub get_fh {
    throw Apache::AxKit::Exception::Error (
        -text => "Subclass must implement get_fh"
        );
}


sub get_document_uri {
    return shift->{apache}->uri();
}

sub get_dom {
    my ($self, $str) = @_;
    require Apache::AxKit::LibXMLSupport;
    
    AxKit::Debug(8, "Provider::get_dom");
    my $parser = XML::LibXML->new();
    $parser->expand_entities(1);
    $parser->expand_xinclude(1);
    local($XML::LibXML::match_cb, $XML::LibXML::open_cb,
          $XML::LibXML::read_cb, $XML::LibXML::close_cb);
    Apache::AxKit::LibXMLSupport->reset($parser);
    
    my $r = $self->apache_request();
    
    my $xml_doc;
    if ($str) {
    	use bytes;
        AxKit::Debug(8, "Provider::get_dom/parse_string($str, ", $self->get_document_uri(), ")");
        $xml_doc = $parser->parse_string($str, $self->get_document_uri()) || 
            throw Apache::AxKit::Exception::Error(
                -text => "XML::LibXML->parse_string returned nothing!"
                );
	} else {    
		eval {
			my $fh = $self->get_fh();
			AxKit::Debug(8, "Provider::get_dom/parse_fh($fh, ", $self->get_document_uri(), ")");
			$xml_doc = $parser->parse_fh($fh, $self->get_document_uri());
		};
		if ($@) {
			use bytes;
			my $xmlstring = ${$self->get_strref()};
			AxKit::Debug(8, "Provider::get_dom/parse_strref($xmlstring, ", $self->get_document_uri(), ")");
			$xml_doc = $parser->parse_string($xmlstring, $self->get_document_uri()) || 
				throw Apache::AxKit::Exception::Error(
					-text => "XML::LibXML->parse_string returned nothing!"
					);
		}
	}		
    return $xml_doc;
}

sub apache_request {
    my $self = shift;
    return $self->{apache};
}

sub has_changed {
    my $self = shift;
    my $time = shift;
    return 1 unless defined $time;
    return $self->mtime > $time;
}

sub decline {
    my $self = shift;

    AxKit::Debug(4, "provider declined");
    return DECLINED;
}

sub get_ext_ent_handler {
    my $self = shift;
    return sub {
        my ($e, $base, $sysid, $pubid) = @_;
#        warn "ext_ent: base => $base, sys => $sysid, pub => $pubid\n";
        AxKit::Debug(6, "Provider get_ext_ent_handler for $sysid");
        if ($sysid =~ /^http:/) {
            if ($pubid) {
                return ''; # do not bring in public DTD's
            }
            require LWP::Simple;
            import LWP::Simple;
            return get($sysid) || die "Cannot get $sysid";
        }
        elsif ($sysid =~ /^(https|ftp):/) {
            if ($pubid) {
                return ''; # do not bring in public DTD's
            }
            die "Cannot download https (SSL) or ftp URL's yet. Patches welcome";
        }

        # create a subrequest, so we get the right AxKit::Cfg for the URI
        my $apache = AxKit::Apache->request;
        my $sub = $apache->lookup_uri(AxKit::FromUTF8($sysid));
        my $cfg = Apache::AxKit::ConfigReader->new($sub);
    
        my $str = do {
            local $AxKit::Cfg = $cfg;
            my $provider = Apache::AxKit::Provider->new($sub);
            $provider->get_strref;
        };

        undef $apache;
        undef $sub;
        undef $cfg;
        
        return $$str;
    };
}

sub get_styles {
    my $self = shift;
    my ($media, $pref_style) = @_;

    if ($pref_style eq '#default') {
        undef $pref_style;
    }

	my @styles;
    my $key = $self->key();

    # need to extract the following from the XML file:
    #   DocType Public Identifier
    #   DTD filename
    #   Root element name (including namespace)
    # use three element array @$vals
	
	my ($doctype, $dtd, $root, $xml_styles) = $self->get_xml_info( $media, $pref_style );
	
	$xml_styles = [] if $AxKit::Cfg->IgnoreStylePI();
	
   	foreach my $style (@$xml_styles) {
   	    $style->{title} ||= '#default';
   	}
    
   	# Let GetMatchingProcessors to process the @$styles array
   	{
   	  local $^W; # suppress "Use of uninitialized value" warnings
   	  AxKit::Debug(4, "Calling GetMatchingProcessors with ($media, $pref_style, $doctype, $dtd, $root)");
   	}

   	@styles = $AxKit::Cfg->GetMatchingProcessors($media, $pref_style, $doctype, $dtd, $root, $xml_styles, $self);

    if (!@styles) {
        throw Apache::AxKit::Exception::Declined( reason => "No styles defined for '$key'" );
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

sub get_xml_info{
	my ($self, $media, $pref_style ) = @_;
	
	# This is where the sniffing of the xml content happens.
		
	my $r = $self->apache_request();
	my @ret;
	eval{
		my $fh = $self->get_fh();
		my $pos = eval { tell $fh; };
		if($@) {
			# fh is not seekable, thus we must slurp file at this point.
			undef $@;
			local($/) = undef;
			my $string = <$fh>;	
			$r->pnotes('xml_string', $string);
			@ret = parse_xml_info( $r, undef, \$string, $media, $pref_style);
		} else {
			# seekable.
			@ret = parse_xml_info( $r, $fh, undef, $media, $pref_style);
			seek $fh, 0, $pos;
		}			
	};
	if($@) {
		my $str_ref = $self->get_strref();
		$r->pnotes('xml_string', ${$str_ref});
		@ret = parse_xml_info( $r, undef, $str_ref, $media, $pref_style);
	}
	return @ret;		
}

sub parse_xml_info{
    my ($r, $fh, $str_ref, $media, $pref_style) = @_;

    if ($pref_style eq '#default') {
        undef $pref_style;
    }

    my $xml_styles = [];
    my $vals = [];
	my @styles;

	if (defined &Apache::AxKit::Provider::xs_get_styles_fh) {
		AxKit::Debug(2, "using XS get_styles (libxml2)");
		my ($xs_styles, $doctype, $dtd, $root) = xs_get_styles($r, $fh, $str_ref, $media, $pref_style);
		@$xml_styles = @$xs_styles unless $AxKit::Cfg->IgnoreStylePI();
		@$vals = ($doctype, $dtd, $root);
	}
	else {
		require XML::Parser;

		AxKit::Debug(4, "get_styles: creating XML::Parser");

		my $handlers = {
			Start => \&parse_start,
			Doctype => \&parse_dtd,
			$AxKit::Cfg->IgnoreStylePI() ? () : (Proc => \&parse_pi),
		};

		my $xml_parser = XML::Parser->new(
			Namespaces => 1,
			ErrorContext => 2,
			Handlers => $handlers,
		);

		my $to_parse = $fh || ${$str_ref};
		#eval {
		#	$to_parse = $provider->get_fh();
		#};
		#if ($@) {
		#	$to_parse = ${ $provider->get_strref(); };
		#}
		
		AxKit::Debug(4, "get_styles: calling XML::Parser->parse()");
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
	
	return (@$vals, $xml_styles);
}

sub xs_get_styles {
    my ($r, $fh, $strref, $media, $pref_style) = @_;
    
    my $bits;
    if(defined($fh)) {
        AxKit::Debug(4, "calling xs_get_styles_fh()");
        $bits = xs_get_styles_fh($r, $fh);
    } else {
        AxKit::Debug(4, "calling xs_get_styles_str()");
        $bits = xs_get_styles_str($r, $$strref);
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
    
    { local $^W;
      AxKit::Debug(4, "xs_get_styles returned: $bits->[3], $bits->[4], $element");
    }
    
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

Override the base ContentProvider class and enable it using:

    AxContentProvider MyClass
    
    # alternatively use:
    # PerlSetVar AxContentProvider MyClass

Override the base StyleProvider class and enable it using:

    AxStyleProvider MyClass
    
    # alternatively use:
    # PerlSetVar AxStyleProvider MyClass

=head1 DESCRIPTION

The Provider class is used to read in the data sources for the given URL.
The ContentProvider handles the task of returning the data for the XML source
document, while the StyleProvider fetches the data for any stylesheets that
will be applied to that source document. The default for each is Provider::File, 
which reads from the filesystem, although obviously you can read from just about anywhere.

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
'href', 'module' and 'type'.

A sample return value of get_styles() could be:

  [{ type => "text/xsl",
     href => "path/to/your/stylesheet.xsl",
     module => "Apache::AxKit::Language::LibXSLT" }]

This allows one to use a different stylemapping than the default
server configuration. If 'module' is ommited AxKit will apply the 
given default module for the type as it was added by 'AxAddStyleMap'
in the configuration.


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
