# $Id: AxKit.pm,v 1.68 2001/02/16 15:27:00 matt Exp $

package AxKit;
use strict;
use vars qw/$VERSION/;

use DynaLoader ();
use UNIVERSAL ();
use Apache;
use Apache::Log;
use Apache::Constants ':common';
use Apache::ModuleConfig ();
use Apache::AxKit::Exception ':try';
use Apache::AxKit::ConfigReader;
use Apache::AxKit::Cache;
use Apache::AxKit::Provider;
use Apache::AxKit::Provider::File;
use Apache::AxKit::Provider::Scalar;
use Apache::AxKit::CharsetConv;

$VERSION = "1.3";

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
#    warn "AxAddStyleMap: $type => $module\n";
    load_module($module);
    $cfg->{StyleMap}{$type} = $module;
}

sub AxCacheDir ($$$) {
    my ($cfg, $parms, $cachedir) = @_;
    $cfg->{CacheDir} = $cachedir;
}

sub AxConfigReader ($$$) {
    my ($cfg, $parms, $configclass) = @_;
    load_module($configclass);
    $cfg->{ConfigReader} = $configclass;
}

sub AxProvider ($$$) {
    my ($cfg, $parms, $providerclass) = @_;
    load_module($providerclass);
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
    load_module($cachemodule);
    $cfg->{CacheModule} = $cachemodule;
}

sub AxDebugLevel ($$$) {
    my ($cfg, $parms, $level) = @_;
#    warn "Setting debug level to: $level\n";
    $cfg->{DebugLevel} = $level;
}

sub AxTranslateOutput ($$$) {
    my ($cfg, $parms, $enabled) = @_;
    $cfg->{TranslateOutput} = $enabled;
}

sub AxOutputCharset ($$$) {
    my ($cfg, $parms, $charset) = @_;
    $cfg->{OutputCharset} = $charset;
}

sub AxGzipOutput ($$$) {
    my ($cfg, $parms, $arg) = @_;
    $cfg->{GzipOutput} = $arg;
    if ($arg) {
        require Compress::Zlib;
    }
}

# TODO - may want >1 error stylesheet
sub AxErrorStylesheet ($$$$) {
    my ($cfg, $parms, $type, $style) = @_;
    $cfg->{ErrorStylesheet} = [$type, $style];
}

sub AxAddXSPTaglib ($$$) {
    my ($cfg, $parms, $package) = @_;
    load_module($package);
    $cfg->{XSPTaglibs}{$package}++;
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

sub AxAddDynamicProcessor ($$$) {
    my ($cfg, $parms, $package) = @_;
    push @{$cfg->{DynamicProcessors}}, $package;
}


sub AxAddRootProcessor ($$$$$) {
    my ($cfg, $parms, $type, $stylesheet, $root_element, $media, $style) = @_;

    $media ||= 'screen';
    $style ||= '#default';

#    warn "AxAddRootProcessor: $type, $stylesheet, $root_element, $media, $style";
    
    my $processor = ['Root', $type, $stylesheet, $root_element];

    push @{$cfg->{Processors}{$media}{$style}}, $processor;
}

sub AxResetProcessors ($$) {
    my ($cfg, $parms) = @_;
    $cfg->{ResetProcessors} = 1;
}

my $ENDMedia = "</AxMediaType>";

sub AxMediaType ($$$;*) {
    my ($cfg, $parms, $media, $cfg_fh, $style) = @_;

#    warn "AxMediaType: $cfg, $parms, $media, $cfg_fh, $style\n";

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

#    warn "AxStyleType: $cfg, $parms, $style, $cfg_fh, $media\n";

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
                $cmd->($cfg, $parms, $params[0], $cfg_fh, $style);
            }
            else {
                $cmd->($cfg, $parms, $params[0], $cfg_fh, $media);
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
        XSPTaglibs
        StyleMap
        );

# This is a source of a mod_perl memory leak in mod_perl <= 1.24.
sub DIR_MERGE {
    my ($parent, $current) = @_;

    my %new;

#    warn "DIR MERGE called : [$parent] [$current]\n";

    return $parent if $parent == $current;
    
    # flat merges (single parameters)
    for my $param (@flat_params) {
#        warn "Merging $param\n";
        $new{$param} = $current->{$param} || $parent->{$param};
    }

    # merge processor mappings
    
    if (!$current->{ResetProcessors}) {
        # from parent
        foreach my $style (keys %{$parent->{Processors} || {}}) {
            foreach my $media (keys %{$parent->{Processors}{$style}}) {
                push @{$new{Processors}{$style}{$media}},
                        @{$parent->{Processors}{$style}{$media}};
            }
        }
    }

    # from current
    foreach my $style (keys %{$current->{Processors} || {}}) {
        foreach my $media (keys %{$current->{Processors}{$style}}) {
            push @{$new{Processors}{$style}{$media}},
                    @{$current->{Processors}{$style}{$media}};
        }
    }

    # copy any dynamic processors
    foreach my $proc (@{$current->{DynamicProcessors}}) {
      push(@{$new{DynamicProcessors}},$proc);
    }

    return bless \%new, ref($parent);
}

###############################################################
# AxKit Utility Functions
###############################################################

sub Debug {
    my $level = shift;
    if ($level <= $AxKit::DebugLevel) {
        my @debug = @_;
        $debug[-1] =~ s/\n$//;
        my $log = Apache->request->log();
        $log->info("[AxKit] : " . join('', @debug));

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

sub load_module {
    my $class = shift;

    my $module = $class . '.pm';
    $module =~ s/::/\//g;

    if (!$INC{$module}) {
        AxKit::Debug(9, "(Re)loading $module");
        require $module;
    }
}

sub reconsecrate {
    my ($object, $class) = @_;

    load_module($class);

    bless $object, $class;
}

sub get_output_transformer {
    my $func = sub { @_ };

    my $actually_transform = 0;
    if (my $charset = $AxKit::Cfg->OutputCharset()) {
        $actually_transform = 1;
        my $outputfunc = $func;

        $func = sub {
            my $map = Apache::AxKit::CharsetConv->new("utf-8", $charset)
			|| die "Charset $charset not supported by Iconv";

            map { $map->convert( $_ ) } ($outputfunc->(@_));
        };
    }

    # to add a new output_transformer here:
    #   enter new scope (maybe with if())
    #   copy $func to a new lexical (my) variable
    #   create a closure using the new lexical to transform @_
    #   set $func to that new closure

    return wantarray ? ($func, $actually_transform) : $func;
}

sub reset_depends {
    %AxKit::__Depends = ();
}

sub add_depends {
    my $depends = shift;
#    warn "Adding depends: $depends\n";
    $AxKit::__Depends{$depends}++;
}

sub get_depends {
    return keys %AxKit::__Depends;
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
        $Error::Debug = 1 if $AxKit::DebugLevel > 3;

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
        my $cache = Apache::AxKit::Cache->new($r, $r->filename() . ($ENV{PATH_INFO} || ''), $preferred, $media, $r->notes('axkit_cache_extra'));

        my $recreate; # regenerate from source (not cached)

        my $styles = get_styles($media, $preferred, $cache, $provider);

        {
            local $^W;
            if ($preferred && ($styles->[0]{title} ne $preferred)) {
                # we selected a style that didn't exist.
                # Make sure we default the cache file, otherwise
                # we setup a potential DoS
                AxKit::Debug(3, "resetting cache with no preferred style ($preferred ne $styles->[0]{title})");
                $cache = Apache::AxKit::Cache->new($r, $r->filename() . $ENV{PATH_INFO}, '', $media);
            }
        }
        
        if (!$cache->exists()) {
            AxKit::Debug(2, "cache doesn't exist");
            $recreate++;
        }
        
        if (!$recreate) {
            $recreate = check_dependencies($r, $provider, $cache);
        }

        if (!$recreate && $r->method() eq 'POST') {
            $recreate++;
        }

        # set default content-type (expat returns in utf-8, so use that)
        $r->content_type('text/html; charset=utf-8');

        $AxKit::Charset = $AxKit::Cfg->OutputCharset();

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
        
        my $uri = $r->uri();
        my $path_info = $r->path_info();
        $uri =~ s/\Q$path_info\E$//;
        $r->uri($uri);

        reset_depends();

        # Main grunt of the work done here...
        process_request($r, $provider, $styles);

        save_dependencies($r, $cache);
        
        if (my $dom = $r->pnotes('dom_tree')) {
            AxKit::Debug(4, "got a dom_tree back - outputting that to the cache");
            $r->notes('resetstring', 1);
            my $output = $dom->toString;
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

        if ($Error::Debug) {
            $r->log->error("[AxKit] [Backtrace] " . $E->stacktrace);
        }

        my $error_styles = $AxKit::Cfg->ErrorStyles;
        if (@$error_styles) {
            my $error = '<error><file>' .
                    xml_escape($r->filename) . '</file><msg>' .
                    xml_escape($E->{-text}) . '</msg>' .
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

            return try {
                process_request($r, $provider, 1, $error_styles);
                bless $r, 'Apache';
                tie *STDOUT, 'Apache', $r;
#                $r->send_http_header();
                print $r->notes('xml_string');
                return OK;
            }
            catch Error with {
                my $E = shift;
                $r->log->error("[AxKit] [FATAL] Error occured while processing Error XML: $E");
                return SERVER_ERROR;
            };
        }

        return SERVER_ERROR;

    }
    catch Apache::AxKit::Exception::Declined with {
        my $E = shift;
        if ($r->dir_config('AxLogDeclines')) {
            $r->log->info("[AxKit] [DECLINED] $E->{reason}")
                    if $E->{reason};
            $r->log->info("[AxKit] [DECLINED] From: $E->{-file} : $E->{-line}");
        }
        AxKit::Debug(4, "DECLINED");
        return DECLINED;
    }
    catch Apache::AxKit::Exception::OK with {
        return OK;
    }
    catch Apache::AxKit::Exception::Retval with {
        my $E = shift;
        my $code = $E->{return_code};
        return $code;
    }
    catch Error::Simple with {
        my $E = shift;
        $r->log->error("[AxKit] [UnCaught] $E");

        if ($Error::Debug) {
            $r->log->error("[AxKit] [Backtrace] " . $E->stacktrace);
        }

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

            return try {
                process_request($r, $provider, 1, $error_styles);
                bless $r, 'Apache';
                tie *STDOUT, 'Apache', $r;
#                $r->send_http_header();
                print $r->notes('xml_string');
                return OK;
            }
            catch Error with {
                my $E = shift;
                $r->log->error("[AxKit] [FATAL] Error occured while processing Error XML: $E");
                return SERVER_ERROR;
            };

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
    my ($r, $provider, $styles) = @_;

    for my $style (@$styles) {
        AxKit::Debug(4, "styles: ", $style->{module}, "(", $style->{href}, ")");
    }

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
            if ($mapto->stylesheet_exists() && !$styleprovider->exists()) {
                throw Apache::AxKit::Exception::Error(
                        -text => "stylesheet '$style->{href}' could not be found or is not readable"
                        );
            }
            my $retval = $mapto->$method($r, $provider, $styleprovider);
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

sub get_styles {
    my ($media, $style, $cache, $provider) = @_;

    my $key = $cache->key();
    my $mtime = $provider->mtime();

    AxKit::Debug(2, "getting styles and external entities from the XML");
    # get styles/ext_ents from cache or re-parse

    my $styles;

    if (exists($AxKit::Stash{$key})
            && $AxKit::Stash{$key}{mtime} <= $mtime)
    {
        AxKit::Debug(3, "styles and external entities cached");
        return $AxKit::Stash{$key}{'styles'};
    }
    else {
        AxKit::Debug(3, "styles and external entities not cached - calling get_styles()");
        my $styles = $provider->get_styles($media, $style);

        $AxKit::Stash{$key} = {
            styles => $styles,
            mtime => $mtime,
            };
        
        return $styles;
    }
}

sub check_resource_mtimes {
    my ($xml_provider, $styles, $mtime) = @_;

    my $r = Apache->request;
    
    AxKit::Debug(3, "checking xml mtime vs cache mtime");
    if ($xml_provider->mtime() <= $mtime) {
        AxKit::Debug(3, "xml newer than cache");
        return 1;
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
            return 1; # recreate
        }
    }

    return 0;
}

sub check_dependencies {
    my ($r, $provider, $cache) = @_;
    AxKit::Debug(2, "Checking dependencies");
    if ($provider->mtime() <= $cache->mtime()) {
        AxKit::Debug(3, "xml newer than cache");
        return 1;
    }
    else {
        my $depend_cache = Apache::AxKit::Cache->new($r, $cache->key() . '.depends');
        my $depends_contents = $depend_cache->read();
        if ($depends_contents) {
            DEPENDENCY:
            for my $dependency (split(/:/, $depends_contents)) {
                AxKit::Debug(3, "Checking dependency: $dependency for resource ", $provider->key());
                my $dep = Apache::AxKit::Provider->new($r, key => $dependency);
                if ($dep->mtime() <= $cache->mtime()) {
                    AxKit::Debug(4, "dependency: $dependency newer");
                    return 1;
                }
            }
        }
        else {
            AxKit::Debug(2, "No dependencies list yet");
            return 1;
#            return check_resource_mtimes($provider, $styles, $cache->mtime());
        }
    }
}

sub save_dependencies {
    my ($r, $cache) = @_;
    
    return if $cache->no_cache();
    
    try {
        my @depends = get_depends();
        my $depend_cache = Apache::AxKit::Cache->new($r, $cache->key() . '.depends');
        $depend_cache->write(join(':', @depends));
    }
    catch Error with {
        my $error = shift;
        AxKit::Debug(2, "Cannot write dependencies cache: $error");
    };
}

sub deliver_to_browser {
    my ($r) = @_;

    if ($AxKit::Cache->no_cache() || 
            lc($r->dir_config('Filter')) eq 'on' ||
            $r->method() eq 'POST') {
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

1;

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
        unless ($type =~ s/charset=(\S|[^;])+/charset=$AxKit::Charset/) {
            $type .= "; charset=$AxKit::Charset";
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

1;

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
http://axkit.org/ for details.

=head1 SYNOPSIS

In httpd.conf:

    # we add custom configuration directives
    # so this *must* be in httpd.conf outside of
    # all request based conditionals
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

    # Optionally set a hard coded cache directory
    # make sure this is writable by nobody
    AxCacheDir /opt/axkit/cachedir

    # turn on debugging (1 - 10)
    AxDebugLevel 5

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
    make install UNINST=1

This removes the custom configuration directives. Note that the 
UNINST=1 is required to make sure that old AxKit files are removed
from the binary directory (since it has no binary component any
more). Now you can change the directives to ordinary PerlSetVar
directives:

    PerlSetVar AxStyleMap "text/xsl => Apache::AxKit::Language::XSLT, \
        application/x-xpathscript => Apache::AxKit::Language::XPathScript"

    PerlSetVar AxCacheDir /opt/axkit/cache

It's worth noting that the PerlSetVar option is available regardless of
whether you compile with NO_DIRECTIVES set, although it is marginally
slower to use PerlSetVar.

Also note that if you go B<back> to using the compiled directives,
you must again install with UNINST=1.

=head1 CONFIGURATION DIRECTIVES

AxKit installs a number of new first class configuration directives for
you to use in Apache's httpd.conf or .htaccess files. These provide very
fine grained control over how AxKit performs transformations and sends its
output to the user.

Each directive below is listed along with how to use that directive with
NO_DIRECTIVES=1 (i.e. via PerlSetVar).

=head2 AxCacheDir

This option takes a single argument, and sets the directory that the cache
module stores its files in. These files are an MD5 hash of the file name
and some other information. Make sure the directory you specify is writable
by either the nobody user or the nobody group (or whatever user your Apache
servers run as). It is probably best to not make these directories world
writable!

    AxCacheDir /tmp/axkit_cache

or

    PerlSetVar AxCacheDir /tmp/axkit_cache

=head2 AxDebugLevel

If present this makes AxKit send output to Apache's error log. The
valid range is 0-10, with 10 producing more output. We recommend not to
use this option on a live server.

    AxDebugLevel 5

or

    PerlSetVar AxDebugLevel 5

=head2 AxGzipOutput

This allows you to use the Compress::Zlib module to gzip output to browsers
that support gzip compressed pages. It uses the Accept-Encoding HTTP header
and some information about User agents who can support this option but
don't correctly send the Accept-Encoding header. This option allows either
On or Off values (default being Off). This is very much worth using on sites
with mostly static pages because it reduces outgoing bandwidth significantly.

    AxGzipOutput On

or

    PerlSetVar AxGzipOutput 1

=head2 AxTranslateOutput

This option enables output character set translation. The default method
is to detect the appropriate character set from the user agent's
Accept-Charset HTTP header, but you can also hard-code an output character
set using AxOutputCharset (see below).

    AxTranslateOutput On

or

    PerlSetVar AxTranslateOutput 1

=head2 AxOutputCharset

Fix the output character set, rather than using either UTF-8 or the user's
preference from the Accept-Charset HTTP header. If this option is present,
all output will occur in the chosen character set. The conversion uses the
iconv library, which is part of GNU glibc and/or most modern Unixes. It
is recommended to not use this option if you can avoid it. This option is
only enable if you also enable AxTranslateOutput.

    AxOutputCharset iso-8859-1

or

    PerlSetVar AxOutputCharset iso-8859-1

=head2 AxErrorStylesheet

If an error occurs during processing that throws an exception, the
exception handler will try and find an ErrorStylesheet to use to process
XML of the following format:

    <error>
        <file>/usr/htdocs/xml/foo.xml</file>
        <msg>Something bad happened</msg>
        <stack_trace>
            <bt level="0">
                <file>/usr/lib/perl/site/AxKit.pm</file>
                <line>342</line>
            </bt>
        </stack_trace>
    </error>

There may potentially be multiple bt tags. If an exception occurs when
the error stylesheet is transforming the above XML, then a SERVER ERROR
will occur and an error written in the Apache error log.

    AxErrorStylesheet text/xsl /stylesheets/error.xsl

or

    PerlSetVar AxErrorStylesheet "text/xsl => /stylesheets/error.xsl"

=head2 AxAddXSPTaglib

XSP supports two types of tag libraries. The simplest type to understand
is merely an XSLT or XPathScript (or other transformation language)
stylesheet that transforms custom tags into the "raw" XSP tag form.
However there is another kind, that is faster, and these taglibs transform
the custom tags into pure code which then gets compiled. These taglibs
must be loaded into the server using the AxAddXSPTaglib configuration
directive.

    # load the SQL taglib
    AxAddXSPTaglib Apache::AxKit::Language::XSP::SQL
    AxAddXSPTaglib Apache::AxKit::Language::XSP::Util

or

    PerlSetVar AxAddXSPTaglibs \
        Apache::AxKit::Language::XSP::SQL \
        Apache::AxKit::Language::XSP::Util

=head2 AxStyle

A default stylesheet title to use. This is useful when a single XML
resource maps to multiple choice stylesheets. One possible way to use
this is to symlink the same file in different directories with .htaccess
files specifying different AxStyle directives.

    AxStyle "My custom style"

or

    PerlSetVar AxPreferredStyle "My custom style"

=head2 AxMedia

Very similar to the previous directive, this sets the media type. It is
most useful in a .htaccess file where you might have an entire directory
for the media "handheld".

    AxMedia tv

or

    PerlSetVar AxPreferredMedia tv

=head2 AxAddStyleMap

This is one of the more important directives. It is responsible for mapping
module stylesheet MIME types to stylesheet processor modules (the reason
we do this is to make it easy to switch out different modules for the same
functionality, for example different XSLT processors).

    AxAddStyleMap text/xsl Apache::AxKit::Language::Sablot
    AxAddStyleMap application/x-xpathscript \
        Apache::AxKit::Language::XPathScript
    AxAddStyleMap application/x-xsp \
        Apache::AxKit::Language::XSP

or

  PerlSetVar AxStyleMap \
     "text/xsl => Apache::AxKit::Language::Sablot, \
      application/x-xpathscript => Apache::AxKit::Language::XPathScript, \
      application/x-xsp => Apache::AxKit::Language::XSP"

=head2 AxResetStyleMap

Since the style map will continue deep into your directory tree, it may
occasionally be useful to reset the style map (I don't have an example
usage of this at this time).

    # option takes no arguments.
    AxResetStyleMap

or

    PerlSetVar AxStyleMap ""

Note that the PerlSetVar version of resetting the style map does I<not>
work with the custom directive version of AxAddStyleMap and vice versa.

=head2 AxAddProcessor

This directive maps all XML files to a particular stylesheet to be
processed with. You can do this in a <Files> directive if you need
to do it by file extension:

    <Files *.dkb>
    AxAddProcessor text/xsl /stylesheets/docbook.xsl
    </Files>

Multiple directives for the same set of files make for a chained set
of stylesheet processing instructions, where the output of one processing
stage goes into the input of the next. This is especially useful for
XSP processing, where the output of the XSP processor will likely not
be HTML (or WAP or whatever your chosen output format is):

    <Files *.xsp>
    # use "." to indicate that XSP gets processed by itself.
    AxAddProcessor application/x-xsp .
    AxAddProcessor text/xsl /stylesheets/to_html.xsl
    </Files>

There is no PerlSetVar equivalent of this directive.

=head2 AxAddDocTypeProcessor

This allows you to map all XML files conforming to a particular XML
public identifier in the document's DOCTYPE declaration, to the specified
stylesheet(s):

    AxAddDocTypeProcessor text/xsl /stylesheets/docbook.xsl \
            "-//OASIS//DTD DocBook XML V4.1.2//EN"

There is no PerlSetVar equivalent of this directive.

=head2 AxAddDTDProcessor

This allows you to map all XML files that specify the given DTD file or
URI in the SYSTEM identifier to be mapped to the specified stylesheet(s):

    AxAddDTDProcessor text/xsl /stylesheets/docbook.xsl \
            /dtds/docbook.dtd

There is no PerlSetVar equivalent of this directive.

=head2 AxAddRootProcessor

This allows you to map all XML files that have the given root element
to be mapped to the specified stylesheet(s):

    AxAddRootProcessor text/xsl /stylesheets/book.xsl book

Namespaces are fully supported via the following syntax:

    AxAddRootProcessor text/xsl /stylesheets/homepage.xsl \
        {http://myserver.com/NS/homepage}homepage

This syntax was taken from James Clark's Introduction to Namespaces article.

There is no PerlSetVar equivalent of this directive.

=head2 AxResetProcessors

This allows you to reset the processor mappings at from the current directory
level down.

    AxResetProcessors

From this directory down you can completely redefine how certain types of files
get processed by AxKit.

=head2 <AxMediaType>

This is a configuration directive block. It allows you to have finer
grained control over the mappings, by specifying that the mappings (which
have to be specified using the 4 directives above) contained within the
block are only relevant when the requested media type is as specified
in the block parameters:

    <AxMediaType screen>
    AxAddProcessor text/xsl /stylesheets/webpage_screen.xsl
    </AxMediaType>

    <AxMediaType handheld>
    AxAddProcessor text/xsl /stylesheets/webpage_wap.xsl
    </AxMediaType>

    <AxMediaType tv>
    AxAddProcessor text/xsl /stylesheets/webpage_tv.xsl
    </AxMediaType>

There is no PerlSetVar equivalent of this directive block.

=head2 <AxStyleName>

This configuration directive block is very similar to the above, only
it specifies alternate stylesheets by name, which can be then requested
via a StyleChooser:

    <AxMediaType screen>
        AxAddProcessor text/xsl /styles/webpage_screen.xsl
        <AxStyleName printable>
            AxAddProcessor text/xsl /styles/webpage_printable.xsl
        </AxStyleName>
    </AxMediaType>

This and the above directive block can be nested, and can also be
contained within <Files> directives to give you even more control over
how your XML is transformed.

There is no PerlSetVar equivalent of this directive block.

=head1 CUSTOMISING AXKIT

There are some configuration directives that are specifically reserved
for customising how AxKit works. These directives allow you to specify
a new class to replace the one being used for certain operations.

These directives all take as a single argument, the name of a module
to load in place of the default. They are:

    AxConfigReader
    AxProvider
    AxCacheModule

The ConfigReader module returns information about various configuration
options. Currently it takes most of its information from the above
mentioned configuration directives, or from PerlSetVar.

The Provider module is the means by which AxKit gets its resources from.
The default Provider simply picks up files from the filesystem, but
alternate providers could pull the information from a DBMS, or perhaps
create some XML structure for directories. There currently exists one
alternate Provider module, which allows AxKit to work as a recipient
for Apache::Filter output. This module is Apache::AxKit::Provider::Filter.

The Cache module is responsible for storing cache data for later
retrieval.

Implementing these is non trivial, and it is highly recommended to join
the AxKit-devel mailing list before venturing to do so, and to also
consult the source for the current default modules. Details of
joining the mailing list are at http://axkit.org/mailinglist.xml

=head1 KNOWN BUGS

There are currently some incompatibilities between the versions of expat
loaded by Apache when compiled with RULE_EXPAT=yes (which is a default,
unfortunately), and XML::Parser's copy of expat. This can cause sporadic
segmentation faults in Apache's httpd processes. The solution is to
recompile Apache with RULE_EXPAT=no. If you have a recent mod_perl and
use mod_perl's Makefile.PL to compile Apache for you, this option will
be enabled automatically for you.

There are a number of known bugs in XSP at this time. This is being
re-written to use SAX2, and so we are not focusing on fixing these bugs
until the re-write is further down the line.

=head1 AUTHOR and LICENSE

AxKit is developed by AxKit.com Ltd. See http://axkit.com/ for more details.

AxKit is licensed under either the GNU GPL Version 2, or the Perl Artistic
License.

Copyright AxKit.com, 2000.

=head1 MORE DOCUMENTATION

For more documentation on things like XPathScript, XSP and XSLT, and a quick
getting started guide, please visit our community web site at
http://axkit.org/

=head1 SEE ALSO

L<Apache::AxKit::Plugins::Fragment>, 
L<Apache::AxKit::Plugins::Passthru>,
L<Apache::AxKit::StyleChooser::QueryString>,
L<Apache::AxKit::StyleChooser::UserAgent>,
L<Apache::AxKit::StyleChooser::PathInfo>,
L<Apache::AxKit::StyleChooser::FileSuffix>,
L<Apache::AxKit::StyleChooser::Cookie>,
L<Apache::AxKit::MediaChooser::WAPCheck>,
L<Apache::AxKit::Provider>,
L<Apache::AxKit::Provider::Filter>,
L<Apache::AxKit::Provider::File>,
L<Apache::AxKit::Provider::Scalar>

(and probably others I have forgotten about)

=cut
