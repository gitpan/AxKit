# $Id: AxKit.pm,v 1.18.2.1 2002/06/08 12:03:10 matts Exp $

package AxKit;
use strict;
use vars qw/$VERSION/;

use DynaLoader ();
use UNIVERSAL ();
use Apache qw(warn);
use Apache::Log;
use Apache::Constants ':common';
use Apache::AxKit::Exception;
use Apache::AxKit::ConfigReader;
use Apache::AxKit::Cache;
use Apache::AxKit::Provider;
use Apache::AxKit::Provider::File;
use Apache::AxKit::Provider::Scalar;
use Apache::AxKit::CharsetConv;
use File::Basename ();
use Compress::Zlib ();
use Fcntl;

Apache::AxKit::CharsetConv::raise_error(1);

BEGIN {
    $VERSION = "1.6";
    if ($ENV{MOD_PERL}) {
        $AxKit::ServerString = "AxKit/$VERSION";
        @AxKit::ISA = qw(DynaLoader);
        __PACKAGE__->bootstrap($VERSION);
    }
}

###############################################################
# AxKit Utility Functions
###############################################################

sub _Debug {
    my $level = shift;
    if ($level <= $AxKit::DebugLevel) {
        my @debug = @_;
        $debug[-1] =~ s/\n$//;
        my $log = Apache->request->log();
        $log->warn("[AxKit] : " . join('', @debug));

# Log Time Taken
        if ($AxKit::Cfg->DebugTime) {
            $log->warn( "[Time] : " . int(1000 * Time::HiRes::tv_interval($AxKit::T0)) . "ms" );
        }

# Log Memory Usage
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

sub _reconsecrate {
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

            return map { $map->convert( $_ ) } ($outputfunc->(@_));
        };
    }

    foreach my $AxOutputTransformer ( $AxKit::Cfg->OutputTransformers() ) {
        $actually_transform = 1;
        my $outputfunc = $func;
        no strict 'refs';
        $func = sub {
            map { &{$AxOutputTransformer}( $_ ) } ($outputfunc->(@_));
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

#######################################################
# fast_handler is called from C when AddHandler is used
#######################################################

sub fast_handler {
    my $r = shift;

    local $SIG{__DIE__} = sub { AxKit::prep_exception(@_)->throw };

    # use Carp ();
    # local $SIG{'USR2'} = sub { 
    #     Carp::confess("caught SIGUSR2!");
    # };
    
    $AxKit::Cfg = Apache::AxKit::ConfigReader->new($r);

#    if ($AxKit::Cfg->DebugTime) {
#        require Time::HiRes;
#        $AxKit::T0 = [Time::HiRes::gettimeofday()] if $AxKit::Cfg->DebugTime;
#    }

    $Error::Debug = 1 if (($AxKit::Cfg->DebugLevel() > 3) || $AxKit::Cfg->StackTrace);

    AxKit::Debug(1, "fast handler called for " . $r->uri);
    
    local $AxKit::FastHandler = 1;

    my $plugin_ret = AxKit::run_plugins($r);
    if ($plugin_ret != OK) {
        AxKit::Debug(2, "Plugin returned non-OK value");
        return $plugin_ret;
    }

    my $provider = Apache::AxKit::Provider->new_content_provider($r);

    return $provider->decline(reason => "passthru set")
            if ($r->notes('axkit_passthru') && $r->dir_config('AxFastPassthru'));

    return main_handler($r, $provider);
}

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

    local $SIG{__DIE__} = sub { AxKit::prep_exception(@_)->throw };

    # use Carp ();
    # local $SIG{'USR2'} = sub { 
    #     Carp::confess("caught SIGUSR2!");
    # };
    
    local $AxKit::Cfg;
    local $AxKit::DebugLevel;
    local $Error::Debug;

    $AxKit::Cfg = Apache::AxKit::ConfigReader->new($r);

    if ($AxKit::Cfg->DebugTime) {
        require Time::HiRes;
        $AxKit::T0 = [Time::HiRes::gettimeofday()] if $AxKit::Cfg->DebugTime;
    }

    $Error::Debug = 1 if (($AxKit::Cfg->DebugLevel() > 3) || $AxKit::Cfg->StackTrace);

    AxKit::Debug(1, "handler called for " . $r->uri);

    local $AxKit::FastHandler = 0;

    my $plugin_ret = AxKit::run_plugins($r);
    if ($plugin_ret != OK) {
        AxKit::Debug(2, "Plugin returned non-OK value");
        return $plugin_ret;
    }

    my $provider = Apache::AxKit::Provider->new_content_provider($r);

    return $provider->decline(reason => "passthru set")
            if ($r->notes('axkit_passthru') && $r->dir_config('AxFastPassthru'));

    return main_handler($r, $provider);
}

sub main_handler {
    my ($r, $provider) = @_;

    # Do we process this URL?
    # (moved down here from slow_handler because of AxHandleDirs)
    AxKit::Debug(2, "checking if we process this resource");
    if (!$provider->process()) {
        return $provider->decline();
    }

    if ($r->notes('axkit_passthru')) {
        # slow passthru
        $r->send_http_header('text/xml');
        eval {
            my $fh = $provider->get_fh;
            $r->send_fd($fh);
        };
        if ($@) {
            my $str = $provider->get_strref;
            $r->print($str);
        }
        return OK;
    }
    
    local $AxKit::Cache;

    my $retcode = eval {
        # $r->header_out('X-AxKit-Version', $VERSION);

        chdir(File::Basename::dirname($r->filename));

        $AxKit::OrigType = $r->content_type('changeme');
        
        reset_depends();

        my $result_code = run_axkit_engine($r, $provider);

        # restore $r
        if (ref($r) eq 'AxKit::Apache') {
            bless $r, 'Apache';
            tie *STDOUT, 'Apache', $r;
        }

        deliver_to_browser($r, $result_code);
    };
    my $E = $@;
    unless ($E) {
        return $retcode;
    }
    
    AxKit::Debug(5, "Caught an exception");
    
    # restore $r if it hasn't been restored already
    if (ref($r) eq 'AxKit::Apache') {
        bless $r, 'Apache';
        tie *STDOUT, 'Apache', $r;
    }
    
    if ($E->isa('Apache::AxKit::Exception::OK')) {
        return deliver_to_browser($r); # should return OK
    }
    elsif ($E->isa('Apache::AxKit::Exception::Retval')) {
        my $code = $E->{return_code};
    	AxKit::Debug(5, "aborting with code $code");
        return $code;
    }
    
    $r->content_type($AxKit::OrigType)
                if $r->content_type() eq 'changeme'; # restore content-type
    
    if ($E->isa('Apache::AxKit::Exception::Declined')) {
        if ($AxKit::Cfg && $AxKit::Cfg->LogDeclines()) {
            $r->log->warn("[AxKit] [DECLINED] $E->{reason}")
                    if $E->{reason};
        }
        AxKit::Debug(4, "[DECLINED] From: $E->{-file} : $E->{-line}");
        
        $r->send_http_header('text/xml');
        eval {
            my $fh = $provider->get_fh;
            $r->send_fd($fh);
        };
        if ($@) {
            eval {
                my $str = $provider->get_strref;
                $r->print($str);
            };
            if ($@) {
                return DECLINED;
            }
        }
        return OK;
    }
    elsif ($E->isa('Apache::AxKit::Exception::Error')) {
        $r->log->error("[AxKit] [Error] $E->{-text}");
        $r->log->error("[AxKit] From: $E->{-file} : $E->{-line}");

        if ($Error::Debug) {
            $r->log->error("[AxKit] [Backtrace] " . $E->stacktrace);
        }

        my $error_styles = $AxKit::Cfg->ErrorStyles;
        if (@$error_styles) {
            return process_error($r, $E, $error_styles);
        }

        return SERVER_ERROR;

    }
    elsif ($E->isa('Error::Simple') || $E->isa('Apache::AxKit::Exception')) {
        $r->log->error("[AxKit] [UnCaught] $E");

        if ($Error::Debug) {
            $r->log->error("[AxKit] [Backtrace] " . $E->stacktrace);
        }

        # return error page if a stylesheet for errors has been provided
        my $error_styles = $AxKit::Cfg->ErrorStyles;
        if (@$error_styles) {
            return process_error($r, $E, $error_styles);
        }

        return SERVER_ERROR;
    }
    
    die "Unknown exception, " . (ref($E)?"type: ".ref($E):"message is: $E");
    
    return DECLINED;
}

sub run_axkit_engine {
    my ($r, $provider) = @_;
    
    # get preferred stylesheet and media type
    my ($preferred, $media) = get_style_and_media();
    AxKit::Debug(2, "media: $media, preferred style: $preferred");

    # get cache object
    my $cache = Apache::AxKit::Cache->new($r, $r->filename() . '.gzip' . ($r->path_info() || ''), $preferred, $media, $r->notes('axkit_cache_extra'));

    my $recreate = 0; # regenerate from source (not cached)

    my $styles = get_styles($media, $preferred, $cache, $provider);

    {
        local $^W;
        if ($preferred && ($styles->[0]{title} ne $preferred)) {
            # we selected a style that didn't exist.
            # Make sure we default the cache file, otherwise
            # we setup a potential DoS
            AxKit::Debug(3, "resetting cache with no preferred style ($preferred ne $styles->[0]{title})");
            $cache = Apache::AxKit::Cache->new($r, $r->filename() . '.gzip' . $r->path_info(), '', $media, $r->notes('axkit_cache_extra'));
        }
    }

    if (!$cache->exists()) {
        AxKit::Debug(2, "cache doesn't exist");
        # set no_cache header if cache doesn't exist due to no_cache option
        $r->no_cache(1) if $cache->no_cache();
        $recreate++;
    }

    if (!$recreate && $AxKit::Cfg->DependencyChecks()) {
        $recreate = check_dependencies($r, $provider, $cache);
    }

    if (!$recreate && $r->method() eq 'POST') {
        $recreate++;
    }

    $AxKit::Charset = $AxKit::Cfg->OutputCharset();

    if (!$recreate) {
        AxKit::Debug(1, "delivering cached copy - all conditions met");
        return $cache->deliver();
    }

    AxKit::Debug(1, "some condition failed. recreating output");

    # Store in package variable for other modules
    $AxKit::Cache = $cache;

    # reconsecrate Apache request object (& STDOUT) into our own class
    bless $r, 'AxKit::Apache';
    tie *STDOUT, 'AxKit::Apache', $r;

    if (my $charset = $AxKit::Cfg->OutputCharset) {
        AxKit::Debug(5, "Different output charset: $charset");
        if (!$r->notes('axkit_passthru_type')) {
            $r->content_type("text/html; charset=$charset");
        }
    }
    
    # This is here so that lookup_uri() works on the real thing
    # that we're requesting, not on the thing plus the PATH_INFO
    my $uri = $r->uri();
    my $path_info = $r->path_info();
    $uri =~ s/\Q$path_info\E$//;
    $r->uri($uri);
    $ENV{PATH_INFO} = $path_info;

    {
        # copy styles because we blat the copy
        my @copy = @$styles;
        $AxKit::_CurrentStylesheets = \@copy;
    }
    
    # Main grunt of the work done here...
    my $return_code = process_request($r, $provider, $AxKit::_CurrentStylesheets);

    save_dependencies($r, $cache);
    
    return $return_code;
        
}

sub get_axkit_uri {
    my ($uri) = @_;
    
    AxKit::Debug(3, "get_axkit_uri($uri)");
    
    my $apache = AxKit::Apache->request;
    my $r;
    if ($uri =~ /^axkit:\/(\/.*)$/) {
        my $abs_uri = $1;
        $r = $apache->lookup_uri($abs_uri);
    }
    elsif ($uri =~ /^axkit:(.*)$/) {
        my $rel_uri = $1;
        $r = $apache->lookup_uri($rel_uri);
    }
    else {
        throw Apache::AxKit::Exception (-text => "get_axkit_uri for non-axkit URIs is not yet supported");
    }
    
    local $AxKit::Cfg = Apache::AxKit::ConfigReader->new($r);
    local $AxKit::Cache;

    my $provider = Apache::AxKit::Provider->new_content_provider($r);
    
    my $result_code = run_axkit_engine($r, $provider);
    
    if ($result_code == OK) {
        # results now in $r->pnotes('xml_string') - probably...
        # warning; missing caching logic here from deliver_to_browser.
        if (not $r->pnotes('xml_string') and $r->pnotes('dom_tree')) {
            return $r->pnotes('dom_tree')->toString;
        }
        else {
            return $r->pnotes('xml_string');
        }
    }
    elsif ($result_code == DECLINED) {
        # probably came from the cache system. Try and read it.
        return $AxKit::Cache->read();
    }
    else {
        throw Apache::AxKit::Exception ( -text => "$uri internal request returned unknown result code: ".$result_code);
    }
}

sub process_error {
    my ($r, $E, $error_styles) = @_;
    
    bless $r, 'AxKit::Apache';
    tie *STDOUT, 'AxKit::Apache', $r;

    $r->dir_config->set(AxNoCache => 1);
    $AxKit::Cache = Apache::AxKit::Cache->new($r, 'error', '', '', '');
    
    $r->content_type("text/html; charset=UTF-8"); # set a default for errors
    
    my $error = '<error><file>' .
            xml_escape($r->filename) . '</file><msg>' .
            xml_escape($E->{-text}) . '</msg>' .
            '<stack_trace><bt level="0">'.
            '<file>' . xml_escape($E->{'-file'}) . '</file>' .
            '<line>' . xml_escape($E->{'-line'}) . '</line>' .
            '</bt>';
    
    my $i = 1;
    for my $stack (@{$E->stacktrace_list}) {
        $error .= '<bt level="' . $i++ . '">' .
                '<file>' . xml_escape($stack->{'-file'}) . '</file>' .
                '<line>' . xml_escape($stack->{'-line'}) . '</line>' .
                '</bt>';
    }

    $error .= '</stack_trace></error>';

    my $provider = Apache::AxKit::Provider::Scalar->new(
            $r, $error, $error_styles
            );

    $r->pnotes('xml_string', $error);

    eval {
        process_request($r, $provider, $error_styles);
        if (ref($r) eq 'AxKit::Apache') {
            bless $r, 'Apache';
            tie *STDOUT, 'Apache', $r;
        }
        deliver_to_browser($r);
    };
    if ($@) {
        $r->log->error("[AxKit] [FATAL] Error occured while processing Error XML: $@");
        return SERVER_ERROR;
    }
    
    return OK;
}

sub insert_next_stylesheet {
    my ($type, $href) = @_;
    my $mapping = $AxKit::Cfg->StyleMap;
    my $module = $mapping->{$type};
    if (!$module) {
        throw Apache::AxKit::Exception::Declined(
            reason => "No implementation mapping available for type '$type'"
            );
    }
    unshift @$AxKit::_CurrentStylesheets, 
            {
                type => $type,
                href => $href,
                module => $module,
            };
}

sub insert_last_stylesheet {
    my ($type, $href) = @_;
    my $mapping = $AxKit::Cfg->StyleMap;
    my $module = $mapping->{$type};
    if (!$module) {
        throw Apache::AxKit::Exception::Declined(
            reason => "No implementation mapping available for type '$type'"
            );
    }
    push @$AxKit::_CurrentStylesheets, 
            {
                type => $type,
                href => $href,
                module => $module,
            };
}

sub reset_stylesheets {
    @$AxKit::_CurrentStylesheets = ();
}

sub process_request {
    my ($r, $provider, $styles) = @_;
    my $result_code = OK;

    my $num_styles = 0;
    for my $style (@$styles) {
        AxKit::Debug(4, "styles: ", $style->{module}, "(", $style->{href}, ")");
        $num_styles++;
    }

    my $interm_prefix;
    my $interm_count = 0;
    if ($AxKit::Cfg->TraceIntermediate) {
        $interm_prefix = $r->uri;
        $interm_prefix =~ s{/}{|}g;
        $interm_prefix =~ s/[^0-9a-zA-Z.,_|-]/_/g;
        $interm_prefix = $AxKit::Cfg->TraceIntermediate.'/'.$interm_prefix;
    }

    while (@$styles) {
        my $style = shift @$styles;

        my $styleprovider = Apache::AxKit::Provider->new_style_provider(
                $r,
                uri => $style->{href},
                );

        $r->notes('resetstring', 1);

        no strict 'refs';

        my $mapto = $style->{module};

        AxKit::load_module($mapto);

        AxKit::Debug(3, "about to execute: $mapto\::handler");

        my $method = "handler";
        if (defined &{"$mapto\::$method"}) {
            if ($mapto->stylesheet_exists() && !$styleprovider->exists()) {
                throw Apache::AxKit::Exception::Error(
                        -text => "stylesheet '$style->{href}' could not be found or is not readable"
                        );
            }
            my $retval = $mapto->$method(
                    $r,
                    $provider,
                    $styleprovider,
                    !@$styles, # any more left?
                    );
            $result_code = $retval if $retval != OK;
        }
        else {
            throw Apache::AxKit::Exception::Error(
                -text => "$mapto Function not found"
                );
        }

        if ($interm_prefix) {
            my $fh = Apache->gensym();
            if (sysopen($fh, $interm_prefix.'.'.$interm_count, O_WRONLY|O_CREAT|O_TRUNC)) {
                if (my $dom_tree = $r->pnotes('dom_tree')) {
                    syswrite($fh,$dom_tree->toString);
                } elsif (my $xmlstr = $r->pnotes('xml_string')) {
                    syswrite($fh,$xmlstr);
                } else {
                    syswrite($fh,"<?xml version='1.0'?>\n<empty reason='no data found'/>");
                }
                close($fh);
	        $interm_count++;
            } else {
                AxKit::Debug(1,"could not open $interm_prefix.$interm_count for writing: $!");
            }
        }

        AxKit::Debug(3, "execution of: $mapto\::$method finished");

        last if $r->notes('axkit_passthru');
    }

    return $result_code;
}

sub get_style_and_media {
    my $style = $AxKit::Cfg->PreferredStyle;
    my $media = $AxKit::Cfg->PreferredMedia;

    $style ||= '#default';

#    if ($media !~ /^(screen|tty|tv|projection|handheld|print|braille|aural)$/) {
#        $media = 'screen';
#    }

    return ($style, $media);
}

sub get_styles {
    my ($media, $style, $cache, $provider) = @_;

    my $key = $cache->key();

    AxKit::Debug(2, "getting styles and external entities from the XML");
    # get styles/ext_ents from cache or re-parse

    my $styles;

    if (exists($AxKit::Stash{$key})
            && !$provider->has_changed($AxKit::Stash{$key}{mtime}))
    {
        AxKit::Debug(3, "styles cached");
        return $AxKit::Stash{$key}{'styles'};
    }
    else {
        AxKit::Debug(3, "styles not cached - calling \$provider->get_styles()");
        my $styles = $provider->get_styles($media, $style);
        
        $AxKit::Stash{$key} = {
            styles => $styles,
            mtime => $provider->mtime(),
            };
        
        return $styles;
    }
}

sub check_dependencies {
    my ($r, $provider, $cache) = @_;
    AxKit::Debug(2, "Checking dependencies");
    if ( $provider->has_changed( $cache->mtime() ) ) {
        AxKit::Debug(3, "xml newer than cache");
        return 1;
    }
    else {
        my $depend_cache = Apache::AxKit::Cache->new($r, $cache->key(), '.depends');
        my $depends_contents = $depend_cache->read();
        if ($depends_contents) {
            DEPENDENCY:
            for my $dependency (split(/:/, $depends_contents)) {
                AxKit::Debug(3, "Checking dependency: $dependency for resource ", $provider->key());
                my $dep = Apache::AxKit::Provider->new($r, key => $dependency);
                if ( $dep->has_changed( $cache->mtime() ) ) {
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

    eval {
        my @depends = get_depends();
        my $depend_cache = Apache::AxKit::Cache->new($r, $cache->key(), '.depends');
        $depend_cache->write(join(':', @depends));
    };
    if ($@) {
        AxKit::Debug(2, "Cannot write dependencies cache: $@");
    }
}

sub deliver_to_browser {
    my ($r, $result_code) = @_;
    $result_code ||= OK;

    if (not $r->pnotes('xml_string') and $r->pnotes('dom_tree')) {
        $r->pnotes('xml_string', $r->pnotes('dom_tree')->toString );
    }

    if ($r->content_type eq 'changeme' && !$r->notes('axkit_passthru_type')) {
        $AxKit::Cfg->AllowOutputCharset(1);
        $r->content_type('text/html; charset=' . ($AxKit::Cfg->OutputCharset || "UTF-8"));
    }
    elsif ($r->notes('axkit_passthru_type')) {
        $r->content_type($AxKit::OrigType);
    }

    if (my $charset = $AxKit::Cfg->OutputCharset()) {
        my $ct = $r->content_type;
        $ct =~ s/charset=.*?(;|$)/charset=$charset/i;
        $r->content_type($ct);
    }

    if ($result_code != OK && $result_code != 200) {
    	# no caching - probably makes no sense, and will be turned off
        # anyways, as currently only XSP pages allow to send custom responses
    	AxKit::Debug(4,"sending custom response: $result_code");
        my ($transformer, $doit) = get_output_transformer();
        if ($doit) {
            $r->custom_response($result_code,$transformer->($r->pnotes('xml_string') || ''));
        }
        else {
            $r->custom_response($result_code,$r->pnotes('xml_string') || '');
        }
        return $result_code;
    }

    if ($AxKit::Cache->no_cache() ||
            lc($r->dir_config('Filter')) eq 'on' ||
            $r->method() eq 'POST') {
        AxKit::Debug(4, "writing xml string to browser");
        my ($transformer, $doit) = get_output_transformer();
        if ($AxKit::Cfg->DoGzip) {
            AxKit::Debug(4, 'Sending gzipped xml string to browser');
            AxKit::Apache::send_http_header($r);
            if ($doit) {
                $r->print( unpack("U0A*", Compress::Zlib::memGzip( 
                         $transformer->( $r->pnotes('xml_string') )
                         ) ) );
            }
            else {
                $r->print( unpack("U0A*", Compress::Zlib::memGzip( $r->pnotes('xml_string') ) ) );
            }
        }
        else {
            AxKit::Apache::send_http_header($r);
            if ($doit) {
                $r->print(
                        $transformer->( $r->pnotes('xml_string') )
                        );
            }
            else {
                $r->print( $r->pnotes('xml_string') );
            }
        }
        return OK;
    }
    else {
        AxKit::Debug(4, "writing xml string to cache and delivering to browser");
        my $retval = eval {
            $AxKit::Cache->write($r->pnotes('xml_string'));
            $AxKit::Cache->deliver();
        };
        if (my $E = $@) {
            if ($E->isa('Apache::AxKit::Exception::IO')) {
                AxKit::Debug(1, "WARNING: Unable to write to AxCacheDir or .xmlstyle_cache");
                AxKit::Apache::send_http_header($r);
                $r->print( $r->pnotes('xml_string') );
            }
            else {
                throw $E;
            }
        }
        else {
            return $retval;
        }
    }
}

sub prep_exception {
    my $err = shift;
    
    if (ref($err)) {
        return $err;
    }
    elsif ($err) {
        return Apache::AxKit::Exception::Error->new(-text => $err);
    }
    else {
        return;
    }
}

sub run_plugins {
    my ($r) = @_;
    
    my $method = "handler";
    
    foreach my $plugin ($AxKit::Cfg->Plugins) {
        AxKit::Debug(2, "Running plugin: $plugin");
        AxKit::load_module($plugin);
        if (my $subref = $plugin->can($method)) {
            my $retval = $subref->($r);
            if ($retval == DONE) {
                return OK;
            }
            elsif ($retval == SERVER_ERROR) {
                throw Apache::AxKit::Exception::Error(
                        -text => "Plugin '$plugin' returned SERVER_ERROR",
                        );
            }
            elsif ($retval != OK) {
                return $retval;
            }
        }
        else {
            throw Apache::AxKit::Exception::Error(
                    -text => "Plugin '$plugin' has no $method method",
                    );
        }
    }

    return OK;
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

sub request {
    return bless Apache->request, 'AxKit::Apache';
}

sub TIEHANDLE {
    my($class, $r) = @_;
    $r ||= Apache->request;
}

sub content_type {
    my $self = shift;

    my ($type) = @_;

    if ($type) {
#        warn "Writing content type '$type'\n";
        $AxKit::Cache->set_type($type);
    }

    $self->SUPER::content_type(@_);
}

sub print {
    my $self = shift;

    if ($self->notes('resetstring')) {
        $self->pnotes('xml_string', '');
        $self->notes('resetstring', 0);
    }

    my $current = $self->pnotes('xml_string');
    $self->pnotes('xml_string', $current . join('', @_));
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

AxKit - an XML Application Server for Apache

=head1 DESCRIPTION

AxKit provides the user with an application development environment
for mod_perl, using XML, Stylesheets and a few other tricks. See
http://axkit.org/ for details.

=head1 SYNOPSIS

In httpd.conf:

    # we add custom configuration directives
    # so this *must* be in httpd.conf *outside* of
    # all run time configuration blocks (e.g. <Location>)
    PerlModule AxKit

Then in any Apache configuration section (Files, Location, Directory,
.htaccess):

    # Install AxKit main parts
    SetHandler AxKit

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
file called "test.xsl" that compiles the XML into something usable by
the browser. If you wish to use other languages than XSLT, you can,
provided a module exists for that language. AxKit does not internally
have a built-in XSLT interpreter, instead it relies on interfaces
to other Perl modules. We currently have interfaces in the core
package to XML::Sablotron, XML::LibXSLT, and XML::XSLT.

=head1 CONFIGURATION DIRECTIVES

AxKit installs a number of new first class configuration directives for
you to use in Apache's httpd.conf or .htaccess files. These provide very
fine grained control over how AxKit performs transformations and sends its
output to the user.

Each directive below is listed along with how to use that directive.

=head2 AxCacheDir

This option takes a single argument, and sets the directory that the cache
module stores its files in. These files are an MD5 hash of the file name
and some other information. Make sure the directory you specify is writable
by either the nobody user or the nobody group (or whatever user your Apache
servers run as). It is probably best to not make these directories world
writable!

    AxCacheDir /tmp/axkit_cache

=head2 AxNoCache

Turn off caching. This is a FLAG option - On or Off. Default is "Off". When
this flag is set, AxKit will send out Pragma: no-cache headers.

    AxNoCache On

=head2 AxDebugLevel

If present this makes AxKit send output to Apache's error log. The
valid range is 0-10, with 10 producing more output. We recommend not to
use this option on a live server.

    AxDebugLevel 5

=head2 AxTraceIntermediate

With this option you advise AxKit to store the result of each transformation
request in a special directory for debugging. This directory must exist and must
be writeable by the httpd. The files are stored with their full uri, replacing
slashes with '|', and appending a number indicating the transformation step.
'.0' is the xml after the first transformation.

    AxTraceIntermediate /tmp/axkit-trace

=head2 AxStackTrace

This FLAG option says whether to maintain a stack trace with every exception.
This is slightly inefficient, as it has to call caller() several times for
every exception thrown, but it can give better debugging information.

    AxStackTrace On

=head2 AxLogDeclines

This option is a FLAG, it is either On, or Off (default is Off). When
AxKit declines to process a URI, it gives a reason. Normally this reason
is not sent to the log, however if AxLogDeclines is set, the reason is
logged. This is useful in figuring out why a particular file is not being
processed by AxKit.

If this option is set, the reason is logged regardless of the AxDebugLevel,
however if AxDebugLevel is 4 or higher, the file and line number of B<where>
the DECLINE occured is logged, but not necessarily the reason.

    AxLogDeclines On

=head2 AxAddPlugin

Setting this to a module, will load that module and execute the
handler method of the module before any AxKit processing is done.

This allows you to setup things like sessions, do authentication,
or other actions that require no XML output, before the actual
XML processing stage of AxKit.

    AxAddPlugin MyAuthHandler
    
There is also a companion option, B<AxResetPlugins>, because
plugin lists persist and get merged into directories, so if you
want to start completely fresh, use the following:

    AxResetPlugins
    AxAddPlugin MyFreshPlugin

Note: as with other options that take a module, prefixing with
a "+" sign will pre-load the module at compile time.

=head2 AxGzipOutput

This allows you to use the Compress::Zlib module to gzip output to browsers
that support gzip compressed pages. It uses the Accept-Encoding HTTP header
and some information about User agents who can support this option but
don't correctly send the Accept-Encoding header. This option allows either
On or Off values (default being Off). This is very much worth using on sites
with mostly static pages because it reduces outgoing bandwidth significantly.

    AxGzipOutput On

=head2 AxTranslateOutput

This option enables output character set translation. The default method
is to detect the appropriate character set from the user agent's
Accept-Charset HTTP header, but you can also hard-code an output character
set using AxOutputCharset (see below).

    AxTranslateOutput On

=head2 AxOutputCharset

Fix the output character set, rather than using either UTF-8 or the user's
preference from the Accept-Charset HTTP header. If this option is present,
all output will occur in the chosen character set. The conversion uses the
iconv library, which is part of GNU glibc and/or most modern Unixes. It
is recommended to not use this option if you can avoid it. This option is
only enable if you also enable AxTranslateOutput.

    AxOutputCharset iso-8859-1

=head2 AxAddOutputTransformer

Output transformers are applied just before output is sent to the browser.
This directive adds a transformer to the list of transformers to be applied
to the output.

    AxAddOutputTransformer  MyModule::Transformer

The transformer is a subroutine that accepts a line to process and
returns the transformed line.

    package MyModule;
    sub Transformer {
      my $line = shift;
      ...
      return $line;
    }

An output transformer could be used to add dynamic output to a cached page
(such as the date and time, or a customer name).

=head2 AxResetOutputTransformers

Reset the list of output transformers from the current directory level
down.

   # This directive takes no arguments
   AxResetOutputTransformers

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

=head2 AxAddXSPTaglib

XSP supports two types of tag libraries. The simplest type to understand
is merely an XSLT or XPathScript (or other transformation language)
stylesheet that transforms custom tags into the "raw" XSP tag form.
However there is another kind, that is faster, and these taglibs transform
the custom tags into pure code which then gets compiled. These taglibs
must be loaded into the server using the AxAddXSPTaglib configuration
directive.

    # load the ESQL taglib and Util taglib
    AxAddXSPTaglib AxKit::XSP::ESQL
    AxAddXSPTaglib AxKit::XSP::Util

If you prefix the module name with a + sign, it will be pre-loaded on
server startup (assuming that the config directive is in a httpd.conf,
rather than a .htaccess file).

=head2 AxIgnoreStylePI

Turn off parsing and overriding stylesheet selection for XML files containing
an C<xml-stylesheet> processing instruction at the start of the file. This is
a FLAG option - On or Off. The default value is "Off".

  AxIgnoreStylePI On

=head2 AxHandleDirs

Enable this option to allow AxKit to process directories. Uses XML::Directory
and XML::SAX::Writer to create the directory listing.

  AxHandleDirs On

=head2 AxStyle

A default stylesheet title to use. This is useful when a single XML
resource maps to multiple choice stylesheets. One possible way to use
this is to symlink the same file in different directories with .htaccess
files specifying different AxStyle directives.

    AxStyle "My custom style"

=head2 AxMedia

Very similar to the previous directive, this sets the media type. It is
most useful in a .htaccess file where you might have an entire directory
for the media "handheld".

    AxMedia tv

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

If you prefix the module name with a + sign, it will be pre-loaded on
server startup (assuming that the config directive is in a httpd.conf,
rather than a .htaccess file).

=head2 AxResetStyleMap

Since the style map will continue deep into your directory tree, it may
occasionally be useful to reset the style map, for example if you want
a directory processed by a different XSLT engine.

    # option takes no arguments.
    AxResetStyleMap

=head1 ASSOCIATING STYLESHEETS WITH XML FILES

There are several directives specifically designed to allow you to build
a flexible sitemap that specifies how XML files get processed on your
system.

B<Note:> <?xml-stylesheet?> directives in your XML files override these
directives unless you enable the AxIgnoreStylePI option listed above.

=head2 AxAddProcessor

This directive maps all XML files to a particular stylesheet to be
processed with. You can do this in a <Files> directive if you need
to do it by file extension, or on a file-by-file basis:

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

=head2 AxAddDocTypeProcessor

This allows you to map all XML files conforming to a particular XML
public identifier in the document's DOCTYPE declaration, to the specified
stylesheet(s):

    AxAddDocTypeProcessor text/xsl /stylesheets/docbook.xsl \
            "-//OASIS//DTD DocBook XML V4.1.2//EN"

=head2 AxAddDTDProcessor

This allows you to map all XML files that specify the given DTD file or
URI in the SYSTEM identifier to be mapped to the specified stylesheet(s):

    AxAddDTDProcessor text/xsl /stylesheets/docbook.xsl \
            /dtds/docbook.dtd

=head2 AxAddRootProcessor

This allows you to map all XML files that have the given root element
to be mapped to the specified stylesheet(s):

    AxAddRootProcessor text/xsl /stylesheets/book.xsl book

Namespaces are fully supported via the following syntax:

    AxAddRootProcessor text/xsl /stylesheets/homepage.xsl \
        {http://myserver.com/NS/homepage}homepage

This syntax was taken from James Clark's Introduction to Namespaces article.

=head2 AxAddURIProcessor

This allows you to use a Perl regular expression to match against the
URI of the file in question:

    AxAddURIProcessor text/xsl /stylesheets/book.xsl \
            "book.*\.xml$"

=head2 AxResetProcessors

This allows you to reset the processor mappings at from the current directory
level down.

    AxResetProcessors

From this directory down you can completely redefine how certain types of files
get processed by AxKit.

=head2 <AxMediaType>

This is a configuration directive block. It allows you to have finer
grained control over the mappings, by specifying that the mappings (which
have to be specified using the Add*Processor directives above) contained 
within the block are only relevant when the requested media type is as 
specified in the block parameters:

    <AxMediaType screen>
    AxAddProcessor text/xsl /stylesheets/webpage_screen.xsl
    </AxMediaType>

    <AxMediaType handheld>
    AxAddProcessor text/xsl /stylesheets/webpage_wap.xsl
    </AxMediaType>

    <AxMediaType tv>
    AxAddProcessor text/xsl /stylesheets/webpage_tv.xsl
    </AxMediaType>

=head2 <AxStyleName>

This configuration directive block is very similar to the above, only
it specifies alternate stylesheets by name, which can be then requested
via a StyleChooser:

    <AxMediaType screen>
        <AxStyleName #default>
            AxAddProcessor text/xsl /styles/webpage_screen.xsl
        </AxStyleName>
        <AxStyleName printable>
            AxAddProcessor text/xsl /styles/webpage_printable.xsl
        </AxStyleName>
    </AxMediaType>

This and the above directive block can be nested, and can also be
contained within <Files> directives to give you even more control over
how your XML is transformed.

=head1 CUSTOMISING AXKIT

There are some configuration directives that are specifically reserved
for customising how AxKit works. These directives allow you to specify
a new class to replace the one being used for certain operations.

These directives all take as a single argument, the name of a module
to load in place of the default. They are:

    AxConfigReader
    AxContentProvider
    AxStyleProvider
    AxCacheModule

The ConfigReader module returns information about various configuration
options. Currently it takes most of its information from the above
mentioned configuration directives, or from PerlSetVar.

The Provider modules are the means by which AxKit gets its resources from.
ContentProviders deliver up the document to be processed, while StyleProviders
are used to get the data for any stylesheets that will be applied.
The default Provider for each simply picks up files from the filesystem, but
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

There are currently some incompatibilities between the versions of
expat loaded by Apache when compiled with RULE_EXPAT=yes (which is a
default, unfortunately), and XML::Parser's copy of expat. This can
cause sporadic segmentation faults in Apache's httpd processes. The
solution is to recompile Apache with RULE_EXPAT=no (later Apache's have
implemented this as --disable-rule=expat). If you have a recent
mod_perl and use mod_perl's Makefile.PL DO_HTTPD=1 to compile Apache
for you, this option will be enabled automatically for you.

=head1 AUTHOR and LICENSE

AxKit is developed by AxKit.com Ltd. See http://axkit.com/ for more
details. AxKit.com offer full consultancy services and support for the
AxKit product line, and also offer some custom solutions based on AxKit
for doing content management, and rendering various other file formats
using XML techniques. Contact info@axkit.com for more details.

AxKit is licensed under either the GNU GPL Version 2, or the Perl Artistic
License.

Copyright AxKit.com, 2001.

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

=cut
