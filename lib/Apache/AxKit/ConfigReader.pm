# $Id: ConfigReader.pm,v 1.2 2002/04/02 16:27:54 matts Exp $

package Apache::AxKit::ConfigReader;

use strict;

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my $r = shift;
    
    my $cfg = AxKit::get_config($r) || {};
    
#    use Apache::Peek 'Dump';
#    Dump($cfg);
#     use Data::Dumper;
#     $Data::Dumper::Indent = 1;
#     warn("Cfg: ", Data::Dumper->Dump([$cfg], ['cfg']));

    my $self = bless { apache => $r, cfg => $cfg, output_charset_ok => 0 }, $class;
    
    if (my $alternate = $cfg->{ConfigReader} || $r->dir_config('AxConfigReader')) {
        AxKit::reconsecrate($self, $alternate);
    }
    
    return $self;
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
        return $cachedir;
    }
    
    use File::Basename;
    my $dir = dirname($self->{apache}->filename());
    return $dir . "/.xmlstyle_cache";
}

sub ProviderClass {
    my $self = shift;
    if (my $alternate = $self->{cfg}{Provider} || 
            $self->{apache}->dir_config('AxProvider')) {
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
    if (my $ok_charsets = $ENV{HTTP_ACCEPT_CHARSET}) {
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

sub ErrorStyles {
    my $self = shift;
    
    my $style = $self->{cfg}{ErrorStylesheet};
    my ($type, $href);
    if (!$style) {
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
    my($can_gzip);
    
    AxKit::Debug(5, 'Getting Vary header');
    my @vary;
    @vary = $r->header_out('Vary') if $r->header_out('Vary');
    push @vary, "Accept-Encoding", "User-Agent";
    AxKit::Debug(5, 'Setting Vary header');
    $r->header_out('Vary',
                    join ", ",
                    @vary
                );
    my($accept_encoding) = $r->header_in("Accept-Encoding") || '';
    $can_gzip = 1 if index($accept_encoding,"gzip")>=0;
    unless ($can_gzip) {
        my $user_agent = $r->header_in("User-Agent");
        if ($user_agent =~ m{
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

sub GetMatchingProcessors {
    my $self = shift;
    my ($media, $style, $doctype, $dtd, $root, $styles, $provider) = @_;
    return @$styles if @$styles;
    
    $style ||= '#default';

    my $list = $self->{cfg}{Processors}{$media}{$style};

    my $processors = $self->{apache}->dir_config('AxProcessors');
    if( $processors ) {
      foreach my $processor (split(/\s*,\s*/, $processors) ) {
	my ($pmedia, $pstyle, @processor) = split(/\s+/, $processor);
	next unless ($pmedia eq $media and $pstyle eq $style);
	push (@$list, [ 'NORMAL', @processor ] );
      }
    }
    
    my @results;
    
    for my $directive (@$list) {
        my $type = $directive->[0];
        my $style_hash = {
                    type => $directive->[1], 
                    href => $directive->[2],
                    title => $style,
                };
        if ($type eq 'NORMAL') {
            push @results, $style_hash;
        }
        elsif ($type eq 'DocType') {
            if ($doctype eq $directive->[3]) {
                push @results, $style_hash;
            }
        }
        elsif ($type eq 'DTD') {
            if ($dtd eq $directive->[3]) {
                push @results, $style_hash;
            }
        }
        elsif ($type eq 'Root') {
            if ($root eq $directive->[3]) {
                push @results, $style_hash;
            }
        }
        elsif ($type eq 'URI') {
            my $uri = $provider->apache_request->uri;
            if ($uri =~ /$directive->[3]/) {
                push @results, $style_hash;
            }
        }
        else {
            warn "Unrecognised directive type: $type";
        }
    }
    
    # list any dynamically chosen stylesheets here
    $list = $self->{cfg}{DynamicProcessors};
    foreach my $package (@$list) {
        AxKit::load_module($package);
        no strict 'refs';
        my($handler) = $package.'::handler';
        push @results, $handler->($provider, $media, $style, 
                                  $doctype, $dtd, $root);
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
