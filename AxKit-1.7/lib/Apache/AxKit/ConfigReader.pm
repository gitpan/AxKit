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

# $Id: ConfigReader.pm,v 1.21 2005/07/14 18:43:33 matts Exp $

package Apache::AxKit::ConfigReader;

use strict;

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my $r = shift;

#    my $cfg = AxKit::get_config($r);
#    if (!$cfg) {
#        $cfg = {};
#        AxKit::Debug(2, "Unable to get_config(). Using blank hashref instead");
#    }

#    use Apache::Peek 'Dump';
#    Dump($cfg);
#     use Data::Dumper;
#     $Data::Dumper::Indent = 1;
#     warn("Cfg: ", Data::Dumper->Dump([$cfg], ['cfg']));

    my $self = bless { apache => $r, output_charset_ok => 0 }, $class;

    $self->get_config($r);

    if (my $alternate = $self->{cfg}->{ConfigReader} || $r->dir_config('AxConfigReader')) {
        if ($alternate ne __PACKAGE__) {
            AxKit::reconsecrate($self, $alternate);
            # re-get config if different package
            $self->get_config($r);
        }
    }

    return $self;
}

# you may want to override this in your subclass if you write your own ConfigReader
sub get_config {
    my $self = shift;
        $self->{cfg} = _get_config($self->{apache});
}

# sub DESTROY {
#     AxKit::Debug(7, "ConfigReader->DESTROY count: ".--$COUNT);
# }

# returns a hash reference consisting of key = type, value = module
sub StyleMap {
    my $self = shift;
    if ($self->{cfg}->{StyleMap}) {
        return $self->{cfg}->{StyleMap};
    }
    # no StyleMap, try dir_config
    my %hash = split /\s*(?:=>|,)\s*/, $self->{apache}->dir_config('AxStyleMap');
    return \%hash;
}

# returns the location of the cache dir
sub CacheDir {
    my $self = shift;
    if (my $cachedir =
            $self->{cfg}->{CacheDir}
            ||
            $self->{apache}->dir_config('AxCacheDir')) {
        if (substr($cachedir,0,1) eq '+') {
                $self->{cfg}->{CacheDir} = $cachedir = Apache->request()->document_root.'/'.substr($cachedir,1);
        }
        return $cachedir;
    }
    
    use File::Basename;
    my $dir = dirname($self->{apache}->filename());
    return $dir . "/.xmlstyle_cache";
}

sub ContentProviderClass {
    my $self = shift;
    if (my $alternate = $self->{cfg}{ContentProvider} || 
            $self->{apache}->dir_config('AxContentProvider')) {
        return $alternate;
    }
    
    return 'Apache::AxKit::Provider::File';
}

sub DependencyChecks {
    my $self = shift;
    return $self->{cfg}{DependencyChecks};
}

sub StyleProviderClass {
    my $self = shift;
    if (my $alternate = $self->{cfg}{StyleProvider} || 
            $self->{apache}->dir_config('AxStyleProvider')) {
        return $alternate;
    }
    
    return 'Apache::AxKit::Provider::File';
}

sub NoCache {
    my $self = shift;
    return $self->{cfg}{NoCache} || 
            $self->{apache}->dir_config('AxNoCache');
}

sub PreferredStyle {
    my $self = shift;
    
    return
        $self->{apache}->notes('preferred_style')
                ||
        $self->{cfg}->{Style}
                ||
        $self->{apache}->dir_config('AxPreferredStyle')
                ||
        '';
}

sub PreferredMedia {
    my $self = shift;
    
    return
        $self->{apache}->notes('preferred_media')
                ||
        $self->{cfg}->{Media}
                ||
        $self->{apache}->dir_config('AxPreferredMedia')
                ||
        'screen';
}

sub CacheModule {
    my $self = shift;
    return $self->{cfg}{CacheModule}
        || $self->{apache}->dir_config('AxCacheModule');
}

sub DebugLevel {
    my $self = shift;
    return $self->{cfg}{DebugLevel} ||
            $self->{apache}->dir_config('AxDebugLevel') ||
            0;
}

sub DebugTime {
    my $self = shift;
    return $self->{apache}->dir_config('AxDebugTime') || 0;
}

sub StackTrace {
    my $self = shift;
    return $self->{cfg}{StackTrace} ||
            $self->{apache}->dir_config('AxStackTrace') ||
            0;
}

sub TraceIntermediate {
    my $self = shift;
    if (my $dir = $self->{cfg}{TraceIntermediate} ||
            $self->{apache}->dir_config('AxTraceIntermediate')) {
        return undef if $dir =~ m/^\s*(?:off|none|disabled?)\s*$/i;
        if (substr($dir,0,1) eq '+') {
                $self->{cfg}{TraceIntermediate} = $dir = Apache->request()->document_root.'/'.substr($dir,1);
        }
        return $dir;
    }

    return undef;
}

sub DebugTidy {
    my $self = shift;
    return $self->{cfg}{DebugTidy} ||
            $self->{apache}->dir_config('AxDebugTidy') ||
            0;
}

sub LogDeclines {
    my $self = shift;
    return $self->{cfg}{LogDeclines} ||
            $self->{apache}->dir_config('AxLogDeclines') ||
            0;
}

sub HandleDirs {
    my $self = shift;
    return $self->{cfg}{HandleDirs} ||
            $self->{apache}->dir_config('AxHandleDirs') ||
            0;
}

sub DirHandlerClass {
    my $self = shift;
    if (my $alternate = $self->{cfg}{DirHandler} || 
            $self->{apache}->dir_config('AxDirHandler')) {
        AxKit::load_module($alternate);
        return $alternate;
    }
    
    AxKit::load_module('Apache::AxKit::DirHandler::Basic');
    return 'Apache::AxKit::DirHandler::Basic';
}

sub IgnoreStylePI {
    my $self = shift;
    return $self->{cfg}{IgnoreStylePI} ||
            $self->{apache}->dir_config('AxIgnoreStylePI') ||
            0;
}

sub AllowOutputCharset {
    my $self = shift;
    
    my $oldval = $self->{output_charset_ok};
    if (@_) {
        $self->{output_charset_ok} = shift;
    }
    return $oldval;
}
    
sub OutputCharset {
    my $self = shift;

    return unless $self->{output_charset_ok};

#    warn "OutputCharset\n";
    unless ($self->{cfg}{TranslateOutput} ||
            $self->{apache}->dir_config('AxTranslateOutput')) {
        return;
    }
    
#    warn "Checking OutputCharset\n";
    
    if (my $charset = $self->{cfg}{OutputCharset}
        || $self->{apache}->dir_config('AxOutputCharset')) {
        return $charset;
    }
    
#    warn "Checking Accept-Charset\n";
    # check HTTP_ACCEPT_CHARSET
    if (my $ok_charsets = $self->{apache}->header_in('Accept-Charset')) {
        my @charsets = split(/,\s*/, $ok_charsets);
        my $retcharset;
        my $retscore = 0;
        foreach my $charset (@charsets) {
            my $score;

            ($charset, $score) = split(/;\s*q=/, $charset, 2);
            $score = 1 unless (defined($score) && ($score =~ /^(\+|\-)?\d+(\.\d+)?$/));
           
            if ($score > $retscore || $charset =~ /^utf\-?8$/i) { # we like utf8
                $retcharset = $charset;
                $retscore = $score;
            }
        }
        
        $retcharset =~ s/iso/ISO/;
        $retcharset =~ s/(us\-)?ascii/US-ASCII/;

        return undef if $retcharset =~ /^utf\-?8$/;
	return undef if $retcharset eq '*';
# warn "Charset: '$retcharset'\n";
        return $retcharset;
    }

}

sub ExternalEncoding {
    my $self = shift;
    return $self->{cfg}{ExternalEncoding} || "UTF-8";
}

sub ErrorStyles {
    my $self = shift;

    my $style = $self->{cfg}{ErrorStylesheet};
    my ($type, $href);
    if (!$style || !@$style) {
        ($type, $href) = split(/\s*=>\s*/,
                ($self->{apache}->dir_config('AxErrorStylesheet') || ''),
                2);
        return [] unless $href;
    }
    else {
        ($type, $href) = @$style;
    }
    
    my $style_map = $self->StyleMap;
    
    my $module = $style_map->{ $type };
    
    if (!$module) {
        throw Apache::AxKit::Exception::Error(
                -text => "ErrorStylesheet: No module mapping found for type '$type'"
                );
    }
    
    return [{href => $href, type => $type, module => $module}];
}

sub GzipOutput {
    my $self = shift;
    return $self->{cfg}{GzipOutput}
        || $self->{apache}->dir_config('AxGzipOutput');
}

sub DoGzip {
    # should I actually send GZip for this request?
    my $self = shift;
    return unless $self->GzipOutput;
    
    AxKit::Debug(5, 'Should we zip the output?');
    my $r = $self->{apache};
    return unless $r->header_in('Accept-Encoding') =~ /gzip/io;
    my $can_gzip;
    
    return if $r->protocol =~ /http\/1\.0/i;

    my $ua = $r->header_in('User-Agent');
    if ($ua =~ /MSIE 4\./) {
        return if 
            $r->method =~ /POST/i ||
            $r->header_in('Range') ||
            length($r->uri) > 245;
    }
    elsif ($ua =~ /MSIE 6\.0/) {
        # Don't gzip https on MSIE 6.0
        return if $r->parsed_uri->scheme =~ /https/i;
    }

    # All too buggy to gzip
    if ($r->header_in('Via') =~ /^1\.1\s/ || # MS Proxy 2.0
        $r->header_in('Via') =~ /^Squid\// ||
        $ua =~ /Galean\)/ ||
        $ua =~ /Mozilla\/4\.7[89]/ ||
        $ua =~ /Opera 3\.5/ ||
        $ua =~ /SkipStone\)/)
    {
        return;
    }

    if (($ua =~ /Mozilla\/4\.0/) and (!($ua =~ /compatible/i))) {
        return;
    }

    AxKit::Debug(5, 'Getting Vary header');
    my @vary;
    @vary = $r->header_out('Vary') if $r->header_out('Vary');
    push @vary, "Accept-Encoding", "User-Agent";
    AxKit::Debug(5, 'Setting Vary header');
    $r->header_out('Vary',
                    join ", ",
                    @vary
                );
    unless ($can_gzip) {
        if ($ua =~ m{
                             ^Mozilla/
                             \d+
                             \.
                             \d+
                             [\s\[\]\w\-]+
                             (
                              \(X11 |
                              Macint.+PPC,\sNav
                             )
                            }x
           ) {
            $can_gzip = 1;
        }
    }

    AxKit::Debug(5, $can_gzip ? 'Setting gzip' : 'Not setting gzip');
    $r->header_out('Content-Encoding','gzip') if $can_gzip;

    return $can_gzip;
}

sub _extract_dir_config_processors {
    my $self = shift;
    my ($style, $media) = @_;

    my @list;
    
    my $processors = $self->{apache}->dir_config('AxProcessors');
    my $found_non_global_style = 0;
    if( $processors ) {
      foreach my $processor (split(/\s*,\s*/, $processors) ) {
        my ($pmedia, $pstyle, @processor) = split(/\s+/, $processor);
        next unless ($pmedia eq $media and ($pstyle eq $style or $pstyle eq '#global'));
        $found_non_global_style++ if $pstyle ne '#global';
        push (@list, [ 'NORMAL', @processor ] );
      }
    }
    
    my @processors = $self->{apache}->dir_config->get('AxProcessor');
    foreach my $processor (@processors) {
        my ($pmedia, $pstyle, @processor) = split(/\s+/, $processor);
        next unless ($pmedia eq $media and ($pstyle eq $style or $pstyle eq '#global'));
        $found_non_global_style++ if $pstyle ne '#global';
        push (@list, [ 'NORMAL', @processor ] );
    }

    return @list if $style eq '#default';

    if ($found_non_global_style) {
        return @list;
    }
    else {
        return $self->_extract_dir_config_processors('#default', $media);
    }
}


sub GetMatchingProcessors {
    my $self = shift;
    my ($media, $style, $doctype, $dtd, $root, $styles, $provider) = @_;
    return @$styles if @$styles;
    
    $style ||= '#default';

    # Add global styles
    my $list = [];

    if( exists($self->{cfg}{Processors}{$media}{'#global'})) {
	push @$list, @{ $self->{cfg}{Processors}{$media}{'#global'} || []};
    }

    # Add styles matching this style
    if (exists($self->{cfg}{Processors}{$media}{$style})) {
        push @$list, @{ $self->{cfg}{Processors}{$media}{$style} || [] };
    }
    else {
        # if the style didn't exist, push the #default styles
        push @$list, @{ $self->{cfg}{Processors}{$media}{'#default'} || [] };
    }

    push @$list, $self->_extract_dir_config_processors($style, $media);   
    
    my @results;
    
    for my $directive (@$list) {
        my $type = $directive->[0];
        my $style_hash = {
                    type => $directive->[1], 
                    href => $directive->[2],
                    title => $style,
                };
        if (lc($type) eq 'normal') {
            push @results, $style_hash;
        }
        elsif (lc($type) eq 'doctype') {
            if ($doctype eq $directive->[3]) {
                push @results, $style_hash;
            }
        }
        elsif (lc($type) eq 'dtd') {
            if ($dtd eq $directive->[3]) {
                push @results, $style_hash;
            }
        }
        elsif (lc($type) eq 'root') {
            if ($root eq $directive->[3]) {
                push @results, $style_hash;
            }
        }
        elsif (lc($type) eq 'uri') {
            my $uri = $provider->apache_request->uri;
            if ($uri =~ /$directive->[3]/) {
                push @results, $style_hash;
            }
        }
        elsif (lc($type) eq 'dynamic') {
            my $package = $directive->[3];
            AxKit::load_module($package);
            no strict 'refs';
            my($handler) = $package.'::handler';
            push @results, $handler->($provider, $media, $style,
                                      $doctype, $dtd, $root);
        } 
        else {
            warn "Unrecognised directive type: $type";
        }
    }

    return @results;
}

sub XSPTaglibs {
    my $self = shift;
    
    my @others;
    
    @others = eval { keys %{ $self->{cfg}{XSPTaglibs} } };
    warn $@ if $@;
    
    if (@others) {
        return @others;
    }
    
    local $^W;
    @others = split(/\s+/, $self->{apache}->dir_config('AxAddXSPTaglibs'));
    
    return @others;
}

sub OutputTransformers {
    my $self = shift;

    my @filters;

    if( my $o_t = $self->{cfg}{OutputTransformers} ) {
        @filters = @$o_t;
    }
    else {
        @filters = split(/\s+/, 
                $self->{apache}->dir_config('AxOutputTransformers'));    
    }

    return @filters;
}

sub Plugins {
    my $self = shift;
    my @plugs;

    if (my $plugins = $self->{cfg}{Plugins}) {
        @plugs = @$plugins;
    }
    else {
        @plugs = split(/\s+/,
                $self->{apache}->dir_config('AxPlugins'));
    }
    return @plugs;
}

1;
