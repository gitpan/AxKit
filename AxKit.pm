# $Id: AxKit.pm,v 1.37 2000/09/14 21:29:06 matt Exp $

package AxKit;
use strict;
use vars qw/$VERSION $REQUESTS/;

use DynaLoader ();
use UNIVERSAL ();
use Apache;
use Apache::Log;
use Apache::Constants;
use Apache::ModuleConfig ();
use Apache::AxKit::Exception qw(:try);
use Apache::AxKit::ConfigReader;
use Apache::AxKit::Cache;
use Apache::AxKit::Provider;
use Apache::AxKit::Provider::File;
use Apache::AxKit::Provider::Scalar;

use Unicode::Map8 ();
use Unicode::String ();
use Compress::Zlib ();

# not used here, but loaded so that they are in the parent process (shared)
use DBI;
use MIME::Base64;
use Storable;
use Apache::Request ();

use Apache::AxKit::Language::XPathScript;
use Apache::AxKit::Language::Sablot;

$VERSION = "0.99";

if ($ENV{MOD_PERL}) {
    no strict;
    @ISA = qw(DynaLoader);
    __PACKAGE__->bootstrap($VERSION);
}

###########################################################
# Configuration Directive Callbacks
###########################################################

sub AxResetStyleMap ($$) {
    my ($cfg, $parms) = @_;
    %{$cfg->{StyleMap}} = ();
}

sub AxAddStyleMap ($$$$) {
    my ($cfg, $parms, $type, $module) = @_;
    $cfg->{StyleMap}{$type} = $module;
}

sub AxCacheDir ($$$) {
    my ($cfg, $parms, $cachedir) = @_;
    $cfg->{CacheDir} = $cachedir;
}

sub AxConfigReader ($$$) {
    my ($cfg, $parms, $configclass) = @_;
    $cfg->{ConfigReader} = $configclass;
}

sub AxProvider ($$$) {
    my ($cfg, $parms, $providerclass) = @_;
    $cfg->{Provider} = $providerclass;
}

sub AxStyle ($$$) {
    my ($cfg, $parms, $style) = @_;
    $cfg->{Style} = $style;
}

sub AxMedia ($$$) {
    my ($cfg, $parms, $media) = @_;
    $cfg->{Media} = $media;
}

sub AxCacheModule ($$$) {
    my ($cfg, $parms, $cachemodule) = @_;
    $cfg->{CacheModule} = $cachemodule;
}

sub AxDebugLevel ($$$) {
    my ($cfg, $parms, $level) = @_;
    $cfg->{DebugLevel} = $level;
}

sub AxOutputCharset ($$$) {
    my ($cfg, $parms, $charset) = @_;
    $cfg->{OutputCharset} = $charset;
}

sub AxGzipOutput ($$$) {
    my ($cfg, $parms, $arg) = @_;
    $cfg->{GzipOutput} = $arg;
}

# TODO - may want >1 error stylesheet
sub AxErrorStylesheet ($$$$) {
    my ($cfg, $parms, $style, $type) = @_;
    $cfg->{ErrorStylesheet} = [$style, $type];
}

################################################
# New mapping directives experiment
################################################

sub AxAddProcessor ($$$$) {
    my ($cfg, $parms, $type, $stylesheet, $media, $style) = @_;
    
    $media ||= 'screen';
    $style ||= '#default';
    
#    warn "AxAddProcessor: $type, $stylesheet [$media, $style]\n";
    
#    warn "Debug Level currently: $cfg->{DebugLevel}\n";
    
    my $processor = ['NORMAL', $type, $stylesheet];
    
    push @{$cfg->{Processors}{$media}{$style}}, $processor;
    return 1;
}

sub AxAddDocTypeProcessor ($$$$$) {
    my ($cfg, $parms, $type, $stylesheet, $pubid, $media, $style) = @_;
    
    $media ||= 'screen';
    $style ||= '#default';
    
#    warn "AxAddDocTypeProcessor: $type, $stylesheet, $pubid [$media, $style]\n";
    
    my $processor = ['DocType', $type, $stylesheet, $pubid];
    
    push @{$cfg->{Processors}{$media}{$style}}, $processor;
}

sub AxAddDTDProcessor ($$$$$) {
    my ($cfg, $parms, $type, $stylesheet, $dtd, $media, $style) = @_;
    
    $media ||= 'screen';
    $style ||= '#default';
    
#    warn "AxAddDTDProcessor: $type, $stylesheet, $dtd [$media, $style]\n";
    
    my $processor = ['DTD', $type, $stylesheet, $dtd];
    
    push @{$cfg->{Processors}{$media}{$style}}, $processor;
}
    
sub AxAddRootProcessor ($$$$$) {
    my ($cfg, $parms, $type, $stylesheet, $root_element, $media, $style) = @_;
    
    $media ||= 'screen';
    $style ||= '#default';
    
#    warn "AxAddRootProcessor: $type, $stylesheet, $root_element [$media, $style]\n";
    
    my $processor = ['Root', $type, $stylesheet, $root_element];
    
    push @{$cfg->{Processors}{$media}{$style}}, $processor;
}

my $ENDMedia = "</AxMediaType>";

sub AxMediaType ($$$;*) {
    my ($cfg, $parms, $media, $cfg_fh, $style) = @_;
    
    $media =~ s/>$//;
    
    $style ||= '#default';
    
#    warn "CFG_FH is a: ", ref($cfg_fh), "\n";
#    warn "Next line is: ", <$cfg_fh>, "\n";
            
#    warn "AxMediaType: $media [$style] [$cfg_fh]\n";
    
    parse_contents($cfg, $parms, $ENDMedia, $cfg_fh, $media, $style);
}

sub AxMediaType_END () {
    die "$ENDMedia outside a <AxMediaType> container\n";
}

my $ENDStyle = "</AxStyleName>";

sub AxStyleName ($$$;*) {
    my ($cfg, $parms, $style, $cfg_fh, $media) = @_;
    
    $style =~ s/>$//;
    
    $media ||= 'screen';
    
#    warn "AxStyleName: $style [$media]\n";
    
    parse_contents($cfg, $parms, $ENDStyle, $cfg_fh, $media, $style);
}

sub AxStyleName_END () {
    die "$ENDStyle outside a <AxStyleName> container\n";
}

sub parse_contents {
    my ($cfg, $parms, $end_token, $cfg_fh, $media, $style) = @_;
    
#    warn "parse_contents ($end_token - $cfg_fh)\n";
    
    while (my $line = <$cfg_fh>) {
#        warn "parse line: $line\n";
        
        last if $line =~ /^$end_token/;
        
        $line =~ s/^(<?\w+)// || die "No command found in $line\n";
        my $cmd = $1;
        
        my @params = parse_params($line);
        
#        warn "Found command: $cmd\n";
        
        no strict 'refs';
        if ($cmd =~ s/^<//) {
            if ($cmd =~ /AxMediaType/) {
                AxMediaType($cfg, $parms, $params[0], $style);
            }
            else {
                AxStyleName($cfg, $parms, $params[0], $media);
            }
        }
        else {
            $cmd->($cfg, $parms, @params, $media, $style);
        }
    }
    return 1;
}

sub parse_params {
    my $line = shift;
    
    my @params;
    
    while ($line =~ /\G\s*((["']).*?\2|\S+)/gc) {
        my $match = $1;
        $match =~ s/^["']//;
        $match =~ s/["']$//;
        push @params, $match;
    }
    
    return @params;
}

my @flat_params = qw(
        CacheDir 
        ConfigReader 
        Provider 
        Style 
        Media 
        CacheModule 
        DebugLevel 
        OutputCharset 
        EncodingDir
        GzipOutput
        ErrorStylesheet
        );

# This seems to be a source of a mod_perl memory leak. Doug is aware.
sub NO_DIR_MERGE {
    my ($parent, $current) = @_;
    
    my %new;
    
#    warn "DIR MERGE called : [$parent] [$current]\n";
    
    # style map
    $new{StyleMap} = { %{$parent->{StyleMap} || {}}, %{$current->{StyleMap} || {}} };
    
    # flat merges (single parameters)
    for my $param (@flat_params) {
        $new{$param} = $current->{$param} || $parent->{$param};
    }
    
    # merge processor mappings
    
    # from parent
    foreach my $style (keys %{$parent->{Processors} || {}}) {
        foreach my $media (keys %{$parent->{Processors}{$style}}) {
            push @{$new{Processors}{$style}{$media}},
                    @{$parent->{Processors}{$style}{$media}};
        }
    }
    
    # from current
    foreach my $style (keys %{$current->{Processors} || {}}) {
        foreach my $media (keys %{$current->{Processors}{$style}}) {
            push @{$new{Processors}{$style}{$media}},
                    @{$current->{Processors}{$style}{$media}};
        }
    }
    
    return bless \%new, ref($parent);
}

###############################################################
# AxKit Utility Functions
###############################################################

sub Debug {
    my $level = shift;
    if ($level <= $AxKit::DebugLevel) {
        if ($_[-1] !~ /\n$/) {
            warn("[AxKit] : ", @_, "\n");
        }
        else {
            warn("[AxKit] : ", @_);
        }

#         my $fh = Apache->gensym();
#         my %mem;
#         if (open($fh, "/proc/self/statm")) {
#             @mem{qw(Total Resident Shared)} = split /\s+/, <$fh>;
#             close $fh;
#             
#             if ($AxKit::TOTALMEM != $mem{Total}) {
#                 warn "[AxKit] Mem difference! : ", $mem{Total} - $AxKit::TOTALMEM, "\n";
#                 $AxKit::TOTALMEM = $mem{Total};
#                 my $mtime = -M "/tmp/go_apache";
#                 while ($mtime <= -M "/tmp/go_apache") {
#                     warn "sleeping for /tmp/go_apache\n";
#                     sleep 1;
#                 }
#             }
#             
#             warn("[AxKit] Mem Total: $mem{Total} Shared: $mem{Shared}\n");
#         }
    }
}

sub reconsecrate {
    my ($object, $class) = @_;
    
    my $module = $class . '.pm';
    $module =~ s/::/\//g;
    
    if (!$INC{$module}) {
        AxKit::Debug(9, "(Re)loading $module");
        require $module;
    }
    
    bless $object, $class;
}

# sub get_subrequest {
#     my ($r, $href) = @_;
#     
#     if ($href =~ /^(http|https|ftp):\/\//i) {
#         die "Only relative URI's supported in <?xml-stylesheet?> at this time";
#     }
#     
#     return bless $r->lookup_uri($href), 'AxKit::ApacheDebug';
# }

sub get_output_transformer {
    my $func = sub { @_ };
    
    my $actually_transform = 0;
    if (my $charset = $AxKit::Cfg->OutputCharset()) {
        $actually_transform = 1;
        my $outputfunc = $func;
        
        $func = sub {
            my $map = Unicode::Map8->new($charset) || die "Charset: $charset not suppported by Unicode::Map8";
            
            map { $map->to8(
                    ${ Unicode::String::utf8( $_ ) }
                   ) 
                } ($outputfunc->(@_));
        };
    }
    
    # to add a new output_transformer here:
    #   enter new scope (maybe with if())
    #   copy $func to a new lexical (my) variable
    #   create a closure using the new lexical to transform @_
    #   set $func to that new closure
    
    return wantarray ? ($func, $actually_transform) : $func;
}

# sub DESTROY {
#     my $self = shift;
#     warn "AxKit hash -- : $self->{Type}\n";
# }

#########################################
# main mod_perl handler routine
#########################################

sub handler {
    my $r = shift;

#     ##############################
#     ## COMMENT OUT FOR RELEASE!!!
#     ##############################
#     {
#         local $AxKit::DebugLevel = 1;
#         AxKit::Debug(1, "handler called");
#     }
#     ##############################
    
    local $AxKit::Cfg;
    local $AxKit::Cache;
    
    return try {
        throw Apache::AxKit::Exception::Declined(reason => 'in subrequest')
                unless $r->is_main;
        
        throw Apache::AxKit::Exception::Declined(reason => 'passthru')
                if $r->notes('axkit_passthru');
        
        $AxKit::Cfg = Apache::AxKit::ConfigReader->new($r);
        $AxKit::DebugLevel = $AxKit::Cfg->DebugLevel();
        
        my $provider = Apache::AxKit::Provider->new($r);
        
        AxKit::Debug(1, "handler called for " . $r->uri);
        
        # Do we process this URL?
        AxKit::Debug(2, "checking if we process this resource");
        if (!$provider->process()) {
            throw Apache::AxKit::Exception::Declined(reason => 'Provider declined');
        }
        
        $r->header_out('X-AxKit-Version', $VERSION);
        
        # get preferred stylesheet and media type
        my ($preferred, $media) = get_style_and_media();
        AxKit::Debug(2, "media: $media, preferred style: $preferred");
        
        # get cache object
        my $cache = Apache::AxKit::Cache->new($r, $r->filename(), $preferred, $media);

        my $mtime = $provider->mtime();
        
        my $recreate; # regenerate from source (not cached)
        my $reparse; # XML needs re-parsing
        
        my ($styles, $ext_ents);
        ($styles, $ext_ents, $reparse) = get_styles_and_ext_ents(
                $media,
                $preferred,
                $cache,
                $provider,
                );
        
        $recreate++ if $reparse;
        
        {
            local $^W;
            if ($preferred && ($styles->[0]{title} ne $preferred)) {
                # we selected a style that didn't exist. 
                # Make sure we default the cache file, otherwise
                # we setup a potential DoS
                AxKit::Debug(3, "resetting cache with no preferred style");
                $cache = Apache::AxKit::Cache->new($r, $r->filename(), '', $media);
            }
        }
        
        if (!$recreate && !$cache->exists()) {
            AxKit::Debug(2, "cache doesn't exist");
            $recreate++;
        }
        
        if (!$recreate) {
            $recreate = check_resource_mtimes($styles, $ext_ents, $cache->mtime());
        }
        
        # set default content-type (expat returns in utf-8, so use that)
        $r->content_type('text/html; charset=utf-8');
        
        if (!$recreate) {
            AxKit::Debug(1, "delivering cached copy - all conditions met");
            $cache->deliver();
            AxKit::Debug(1, "UNREACHABLE CODE!!!");
        }
        
        AxKit::Debug(1, "some condition failed. recreating output");

        # Store in package variable for other modules        
        $AxKit::Cache = $cache;
        
        # reconsecrate Apache request object (& STDOUT) into our own class
        bless $r, 'AxKit::Apache';
        tie *STDOUT, 'AxKit::Apache', $r;

        if (my $charset = $AxKit::Cfg->OutputCharset) {
            AxKit::Debug(5, "Different output charset: $charset");
            $r->content_type("text/html; charset=$charset");
        }
            
        # Main grunt of the work done here...
        process_request($r, $provider, $reparse, $styles);
        
        if (my $dom = $r->pnotes('dom_tree')) {
            AxKit::Debug(4, "got a dom_tree back - outputting that to the cache");
            $r->notes('resetstring', 1);
            my $output = $dom->toString;
            $dom->dispose();
            $r->print($output);
        }
        
        # restore $r
        if (ref($r) eq 'AxKit::Apache') {
            bless $r, 'Apache';
            tie *STDOUT, 'Apache', $r;
        }
        
        deliver_to_browser($r);
        
        return OK;
    }
    catch Apache::AxKit::Exception::Error with {
        my $E = shift;
        $r->log->error("[AxKit] [Error] $E->{-text}");
        $r->log->error("[AxKit] From: $E->{-file} : $E->{-line}");

        my $error_styles = $AxKit::Cfg->ErrorStyles;
        if (@$error_styles) {
            my $error = '<error><file>' .
                    xml_escape($r->filename) . '</file><msg>' . 
                    xml_escape($@->{text}) . '</msg>' .
                    '<stack_trace><bt level="0">'.
                    '<file>' . xml_escape($E->{'-file'}) . '</file>' .
                    '<line>' . xml_escape($E->{'-line'}) . '</line>' .
                    '</bt>';

            $error .= '</stack_trace></error>';

            my $provider = Apache::AxKit::Provider::Scalar->new(
                    $r, $error, $error_styles
                    );

            $r->notes('xml_string', $error);

            $r->send_http_header();
            process_request($r, $provider, 1, $error_styles);

            return OK;
        }

        return SERVER_ERROR;
        
    }
    catch Apache::AxKit::Exception::Declined with {
        my $E = shift;
        if ($r->dir_config('AxLogDeclines')) {
            $r->log->info("[AxKit] [DECLINED] $E->{reason}")
                    if $E->{reason};
        }
        AxKit::Debug(4, "DECLINED");
        return DECLINED;
    }
    catch Apache::AxKit::Exception::OK with {
        return OK;
    }
    catch Error::Simple with {
        my $E = shift;
        $r->log->error("[AxKit] [UnCaught] $E");
        # return error page here somehow...
        my $error_styles = $AxKit::Cfg->ErrorStyles;
        if (@$error_styles) {
            my $error = '<error><file>' .
                    xml_escape($r->filename) . '</file><msg>' .
                    xml_escape($E) . '</msg></error>';

            my $provider = Apache::AxKit::Provider::Scalar->new(
                    $r, $error, $error_styles
                    );

            $r->notes('xml_string', $error);

            $r->send_http_header();
            process_request($r, $provider, 1, $error_styles);

            return OK;
        }

        return SERVER_ERROR;
    }
    except {
        # restore $r if it hasn't been restored already
        if (ref($r) eq 'AxKit::Apache') {
            bless $r, 'Apache';
            tie *STDOUT, 'Apache', $r;
        }
        return {};
    }
    otherwise {
        return DECLINED;
    };
}

sub process_request {
    my ($r, $provider, $reparse, $styles) = @_;
    
    for my $style (@$styles) {
        my $styleprovider = Apache::AxKit::Provider->new(
                $r,
                uri => $style->{href},
                );

        $r->notes('resetstring', 1);

        no strict 'refs';

        my $mapto = $style->{module};

        AxKit::Debug(3, "about to execute: $mapto\::handler");

        my $method = "handler";
        if (defined &{"$mapto\::$method"}) {
            my $retval = $mapto->$method($r, $provider, $styleprovider, $reparse);
        }
        else {
            throw Apache::AxKit::Exception::Error(
                -text => "$mapto Function not found"
                );
        }

        AxKit::Debug(3, "execution of: $mapto\::$method finished");

        last if $r->notes('axkit_passthru');
    }
    
}

sub get_style_and_media {
    my $style = $AxKit::Cfg->PreferredStyle;
    my $media = $AxKit::Cfg->PreferredMedia;

    $style ||= '#default';

    if ($media !~ /^(screen|tty|tv|projection|handheld|print|braille|aural)$/) {
        $media = 'screen';
    }
    
    return ($style, $media);
}

sub get_styles_and_ext_ents {
    my ($media, $style, $cache, $provider) = @_;
    
    my $key = $cache->key();
    my $mtime = $provider->mtime();
    
    AxKit::Debug(2, "getting styles and external entities from the XML");
    # get styles/ext_ents from cache or re-parse
    
    my ($styles, $ext_ents);
    
    my $cached;
    
    if (exists($AxKit::Stash{$key})
            && $AxKit::Stash{$key}{mtime} <= $mtime)
    {
        AxKit::Debug(3, "styles and external entities cached");
        ($styles, $ext_ents) = 
                @{$AxKit::Stash{$key}}{('styles', 'external_entities')};
    }
    else {
#        warn "No styles in axkit stash\n";
        $cached++;
        
        AxKit::Debug(3, "styles and external entities not cached - calling get_styles()");
        ($styles, $ext_ents) = $provider->get_styles($media, $style);

        $AxKit::Stash{$key} = {
            styles => $styles,
            external_entities => $ext_ents,
            mtime => $mtime,
            };
    }
    
    return ($styles, $ext_ents, $cached);
}

sub check_resource_mtimes {
    my ($styles, $ext_ents, $mtime) = @_;
    
    my $r = Apache->request;
    
    AxKit::Debug(3, "checking external entities mtimes vs cache mtime");
    # check external entities too now
    for my $ext (@$ext_ents) {
        local $^W;
        my $ent_provider = Apache::AxKit::Provider->new(
                $r,
                uri => $ext,
                );

        if ($ent_provider && ($ent_provider->mtime() <= $mtime)) {
            AxKit::Debug(3, "external entity '$ext' newer than cache");
            return (1,1); # recreate and reparse XML
        }
    }

    AxKit::Debug(3, "checking stylesheet mtimes vs cache mtime");
    for my $style (@$styles) {
        next unless $style->{href};
        next unless $style->{module}->stylesheet_exists();
#                my $req = get_subrequest($r, $style->{href});
        my $provider = Apache::AxKit::Provider->new(
                $r,
                uri => $style->{href},
                );

        if (!$provider->exists()) {
            throw Apache::AxKit::Exception::Declined(
                    reason => "Stylesheet '$style->{href}' does not exist or is not readable"
                    );
        }
#                warn "checking $style->{module} mtime against cache: $mtime_cache\n";
        if ($style->{module}->get_mtime($provider) <= $mtime)
        {
            AxKit::Debug(3, "stylesheet '$style->{href}' newer than cache");
            return (1,0); # recreate but don't reparse
        }
    }

}

sub deliver_to_browser {
    my ($r) = @_;
    
    if ($AxKit::Cache->no_cache()) {
        AxKit::Debug(4, "writing xml string to browser");
        my ($transformer, $doit) = get_output_transformer();
        if ($AxKit::Cfg->DoGzip) {
            AxKit::Debug(4, 'Sending gzipped xml string to browser');
            $r->send_http_header();
            if ($doit) {
                $r->print( Compress::Zlib::memGzip(
                        $transformer->( $r->notes('xml_string') )
                        ) );
            }
            else {
                $r->print( Compress::Zlib::memGzip( $r->notes('xml_string') ) );
            }
        }
        else {
            my $transformer = get_output_transformer();
            $r->send_http_header();
            if ($doit) {
                $r->print(
                        $transformer->( $r->notes('xml_string') )
                        );
            }
            else {
                $r->print( $r->notes('xml_string') );
            }
        }
    }
    else {
        AxKit::Debug(4, "writing xml string to cache and delivering to browser");
        $AxKit::Cache->write($r->notes('xml_string'));
        $AxKit::Cache->deliver();
    }
}

my %escapes = (
        '<' => '&lt;',
        '>' => '&gt;',
        '\'' => '&apos;',
        '&' => '&amp;',
        '"' => '&quot;',
        );

sub xml_escape {
    my $text = shift;
    
    $text =~ s/([<>'&"])
              /
              $escapes{$1}
              /egsx; # '
    
    return $text;
}

#########################################################################
# Apache Request Object subclass
#########################################################################

package AxKit::Apache;
use vars qw/@ISA/;
use Apache;
use Fcntl qw(:DEFAULT);
@ISA = ('Apache');

sub TIEHANDLE {
    my($class, $r) = @_;
    $r ||= Apache->request;
}

sub content_type {
    my $self = shift;
    
    my ($type) = @_;

    if ($type && $AxKit::Charset) {
        # don't mess with me, suckaaaa
        unless ($type =~ s/charset=\S+/charset=$AxKit::Charset/) {
            $type .= " charset=$AxKit::Charset";
        }
    }
    
    if ($type && !$AxKit::Cache->no_cache()) {
#        warn "Writing content type '$type'\n";
        my $typecache = Apache::AxKit::Cache->new($self, $AxKit::Cache->key() . '.type');
        $typecache->write($type);
    }
    
    $self->SUPER::content_type(@_);
}

sub print {
    my $self = shift;
    
    if ($self->notes('resetstring')) {
        $self->notes('xml_string', '');
        $self->notes('resetstring', 0);
    }

    $self->notes()->{'xml_string'} .= join('', @_);
}

*PRINT = \&print;

sub no_cache {
    my $self = shift;
    my ($set) = @_;

    $self->SUPER::no_cache(@_);

    if ($set) {
#        warn "caching being turned off!\n";
        $AxKit::Cache->no_cache(1);
    }
}

sub send_http_header {
    my $self = shift;
    my ($content_type) = @_;

    return if $self->notes('headers_sent');

    if ($content_type) {
        $self->content_type($content_type);
    }

    $self->notes('headers_sent', 1);

    $self->SUPER::send_http_header;
}

package AxKit::ApacheDebug;
use vars qw/@ISA/;
use Apache;
use Fcntl qw(:DEFAULT);
@ISA = ('Apache');

sub DESTROY {
    warn "Apache--\n";
}

1;
__END__

=head1 NAME

AxKit - an XML Delivery Toolkit for Apache

=head1 DESCRIPTION

AxKit provides the user with an application development environment
for mod_perl, using XML, Stylesheets and a few other tricks. See 
http://xml.sergeant.org/axkit/ for details.

=head1 SYNOPSIS

In httpd.conf:

    PerlModule AxKit

Then in any Apache configuration section (Files, Location, Directory,
.htaccess):

    # Install AxKit main parts
    SetHandler perl-script
    PerlHandler AxKit
    
    # Setup style type mappings
    AxAddStyleMap text/xsl Apache::AxKit::Language::Sablot
    AxAddStyleMap application/x-xpathscript \
            Apache::AxKit::Language::XPathScript
    
    # Optionally setup a default style mapping
    AxAddDefaultStyleMap /default.xsl text/xsl
    
    # Optionally set a hard coded cache directory
    AxCacheDir /opt/axkit/cachedir
    
Now simply create xml files with stylesheet declarations:

    <?xml version="1.0"?>
    <?xml-stylesheet href="test.xsl" type="text/xsl"?>
    <test>
        This is my test XML file.
    </test>

And for the above, create a stylesheet in the same directory as the
file called "test.xsl" that compiles the XML into something usable  by
the browser. If you wish to use other languages than XSLT, you can,
provided a module exists for that language.

=head1 BUILD PROBLEMS

If you have trouble compiling AxKit, or apache fails to start after 
installing, it's possible to use AxKit without the built in
configuration directives (which have been known to generate segfaults).
To do this install as follows:

    perl Makefile.PL NO_DIRECTIVES=1
    make
    make test
    make install

This removes the custom configuration directives. Note that you may have
to manually remove old AxKit.pm files from your perl library directory
if you have previously built it, because dynamically built libraries
go into the i386 (or whatever processor you have) directory. Now
you can change the directives to ordinary PerlSetVar directives:

    PerlSetVar AxStyleMap "text/xsl => Apache::AxKit::Language::XSLT, \
        application/x-xpathscript => Apache::AxKit::Language::XPathScript"
    
    # note brackets here
    PerlSetVar AxDefaultStyleMap "(/default.xsl text/xsl) \
                (/other.xsl text/xsl)"
    
    PerlSetVar AxCacheDir /opt/axkit/cache
    
It's worth noting that the PerlSetVar option is available regardless of
whether you compile with NO_DIRECTIVES set, although it is marginally
slower to use PerlSetVar.

=cut
