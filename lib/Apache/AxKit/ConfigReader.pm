# $Id: ConfigReader.pm,v 1.13 2000/09/14 20:12:36 matt Exp $

package Apache::AxKit::ConfigReader;

use strict;

use Apache::ModuleConfig ();

# use vars qw/$COUNT/;

sub new {
    my $class = shift;
    my $r = shift;
    
    my $cfg = Apache::ModuleConfig->get($r, 'AxKit') || {};
    
    if (my $alternate = $cfg->{ConfigReader} || $r->dir_config('AxConfigReader')) {
        $class = $alternate;
        my $pkg = $class;
        $pkg =~ s/::/\//g;
        require "$pkg.pm";
    }
    
#     AxKit::Debug(7, "ConfigReader->new count: ".++$COUNT);
    
    return bless { apache => $r, cfg => $cfg }, $class;
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

sub OutputCharset {
    my $self = shift;
    
    if (my $charset = $self->{cfg}{OutputCharset}
        || $self->{apache}->dir_config('AxOutputCharset')) {
        return $charset;
    }
    
    # check HTTP_ACCEPT_CHARSET
    if (my $ok_charsets = $ENV{HTTP_ACCEPT_CHARSET}) {
        my @charsets = split(/,\s*/, $ok_charsets);
        my $retcharset;
        my $retscore = 0;
        foreach my $charset (@charsets) {
            my $score;

            ($charset, $score) = split(/;\s*q=/, $charset, 2);
            $score = 1 unless defined $score;
            
            if ($score > $retscore || $charset =~ /^utf\-?8$/) { # we like utf8
                $retcharset = $charset;
                $retscore = $score;
            }
        }
        
        $retcharset =~ s/iso/ISO/;
        
        return undef if $retcharset =~ /^utf\-?8$/;

        return $retcharset;
    }
    
}

sub ErrorStyles {
    my $self = shift;
    
    my $style = $self->{cfg}{ErrorStylesheet};
    return [] unless $style;
    
    my ($href, $type) = @$style;
    
    my $style_map = $self->StyleMap;
    
    my $module = $style_map->{ $type };
    
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
    
    # This Vary stuff seems to leak memory exponentially,
    # so it is commented out for now. I don't know why or how.
    # but commenting it out worked for me... I've prodded Doug
    # on the matter.
    
#     AxKit::Debug(5, 'Getting Vary header');
#     my @vary = $r->header_out('Vary') if $r->header_out('Vary');
#     push @vary, "Accept-Encoding", "User-Agent";
#     AxKit::Debug(5, 'Setting Vary header');
#     $r->header_out('Vary',
#                     join ", ",
#                     @vary
#                 );
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
    my ($media, $style, $doctype, $dtd, $root) = @_;
    
    my $list = $self->{cfg}{Processors}{$media}{$style};
    
    my @results;
    
    for my $directive (@$list) {
        my $type = $directive->[0];
        if ($type eq 'NORMAL') {
            push @results, { type => $directive->[1], href => $directive->[2] };
        }
        elsif ($type eq 'DocType') {
            if ($doctype eq $directive->[3]) {
                push @results, { type => $directive->[1], href => $directive->[2] };
            }
        }
        elsif ($type eq 'DTD') {
            if ($dtd eq $directive->[3]) {
                push @results, { type => $directive->[1], href => $directive->[2] };
            }
        }
        elsif ($type eq 'Root') {
            if ($root eq $directive->[3]) {
                push @results, { type => $directive->[1], href => $directive->[2] };
            }
        }
        else {
            warn "Unrecognised directive type: $type";
        }
    }
    
    return @results;
}

1;
