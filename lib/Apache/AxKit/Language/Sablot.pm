# $Id: Sablot.pm,v 1.25 2001/06/04 16:00:35 matt Exp $

package Apache::AxKit::Language::Sablot;

use strict;
use vars qw/@ISA $xslt_processor $handler/;
use XML::Sablotron 0.40 ();
use Apache;
use Apache::Request;
use Apache::Log;
use Apache::AxKit::Language;

@ISA = 'Apache::AxKit::Language';

sub handler {
    my $class = shift;
    my ($r, $xml, $style) = @_;

    my ($xmlstring);
    
    if (my $dom = $r->pnotes('dom_tree')) {
        $xmlstring = $dom->toString;
        delete $r->pnotes()->{'dom_tree'};
    }
    else {
        $xmlstring = $r->pnotes('xml_string');
    }
    
    if (!$xmlstring) {
        $xmlstring = eval {${$xml->get_strref()}};
        if ($@) {
            my $fh = $xml->get_fh();
            local $/;
            $xmlstring = <$fh>;
        }
    }
        
    my $stylestring = ${$style->get_strref()};
    
    my $retcode;

    # get request form/querystring parameters
    my $cgi = Apache::Request->instance($r);
    my @xslt_params;
    foreach my $param ($cgi->param) {
        push @xslt_params, $param, $cgi->param($param);
    }
    
    # get and register handler object
    $handler->set_apache($r);
    $handler->set_ext_ent_handler($xml->get_ext_ent_handler());
        
    $retcode = $xslt_processor->RunProcessor(
            "arg:/template", "arg:/xml_resource", "arg:/result",
            \@xslt_params,
            ["template" => $stylestring, "xml_resource" => $xmlstring]
            );
    
    $xslt_processor->ClearError();

    if ($retcode) {
        throw Apache::AxKit::Exception::Declined(
                reason => "Sablotron failed to process XML file"
                );
    }

    print $xslt_processor->GetResultArg("result");
    
    $xslt_processor->FreeResultArgs();
}

END {
    $xslt_processor->UnregHandler(0, $handler);
    $xslt_processor->UnregHandler(1, $handler);
    $xslt_processor->UnregHandler(3, $handler);
}

package Apache::AxKit::Language::Sablot::Handler;

sub set_apache {
    my $self = shift;
    $self->{apache} = shift;
}

sub set_ext_ent_handler {
    my $self = shift;
    $self->{ext_ent_handler} = shift;
}

my @levels = qw(debug info warn error crit);

sub MHMakeCode {
    my $self = shift;
    my $processor = shift;

    my ($severity, $facility, $code) = @_;
    return $code;
}

sub MHLog {
    my $self = shift;
    my $processor = shift;
    
    my $r = $self->{apache};
    
    my ($code, $level, @fields) = @_;
    return 1 unless $r->dir_config('AxSablotLogMessages');
    no strict 'refs';
    my $method = $levels[$level];
    $r->log->$method("[AxKit] [Sablotron] Log: ", join(' :: ', @fields));
    return 1;
}

sub MHError {
    my $self = shift;
    my $processor = shift;
    
    my $r = $self->{apache};
    
    my ($code, $level, @fields) = @_;
    no strict 'refs';
    my $method = $levels[$level];
    $r->log->$method("[AxKit] [Sablotron] [$code] Error: ", join(' :: ', @fields));
    return 1;
}

sub SHGetAll {
    my $self = shift;
    my $processor = shift;
    my ($scheme, $rest) = @_;
    
    my $handler = $self->{ext_ent_handler};
    
    my $uri = $scheme . $rest;
    
    $uri =~ s/^axkit\///;
    
    AxKit::Debug(8, "Sablot: Looking up URI: $uri\n");
    
    return $handler->(undef, undef, $uri);
}

sub XHDocumentInfo {
    my ($self, $processor, $type, $encoding) = @_;
    AxKit::Apache->request->content_type("$type; charset=$encoding");
}

BEGIN {
    
    sub new {
        my $class = shift;
        return bless {}, $class;
    }
    
    package Apache::AxKit::Language::Sablot;

    $xslt_processor = XML::Sablotron->new();
    $xslt_processor->SetBase("axkit:");

    $handler = Apache::AxKit::Language::Sablot::Handler->new();
    
    $xslt_processor->RegHandler(0, $handler);
    $xslt_processor->RegHandler(1, $handler);
    $xslt_processor->RegHandler(3, $handler);
}

1;
