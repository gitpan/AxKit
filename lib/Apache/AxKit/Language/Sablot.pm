# $Id: Sablot.pm,v 1.15 2000/09/14 20:39:33 matt Exp $

package Apache::AxKit::Language::Sablot;

use strict;
use vars qw/@ISA/;
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
		$dom->dispose;
		delete $r->pnotes()->{'dom_tree'};
	}
	else {
		$xmlstring = $r->notes('xml_string');
	}
	
	if (!$xmlstring) {
		$xmlstring = eval {${$xml->get_strref()}};
		if ($@) {
			my $fh = $xml->get_fh();
			local $/;
			$xmlstring = <$fh>;
		}
	}
	
	my $xslt_processor = XML::Sablotron->new();
	$xslt_processor->SetBase("axkit:");
	
	my $stylestring = ${$style->get_strref()};
	
	my $retcode;

	# get request form/querystring parameters	
	my $cgi = Apache::Request->new($r);
	my @xslt_params;
	foreach my $param ($cgi->param) {
		push @xslt_params, $param, $cgi->param($param);
	}
	
	# get and register handler object
	my $handler = Apache::AxKit::Language::Sablot::Handler->new(
			$r, $xml->get_ext_ent_handler()
			);
	
	$xslt_processor->RegHandler(0, $handler);
	$xslt_processor->RegHandler(1, $handler);
	
	$retcode = $xslt_processor->RunProcessor(
			"arg:/template", "arg:/xml_resource", "arg:/result",
			\@xslt_params,
			["template" => $stylestring, "xml_resource" => $xmlstring]
			);
	
	$xslt_processor->ClearError();
	$xslt_processor->UnregHandler(0, $handler);
	$xslt_processor->UnregHandler(0, $handler);

	if ($retcode) {
		throw Apache::AxKit::Exception::Declined(
				reason => "Sablotron failed to process XML file"
				);
	}
	
	print $xslt_processor->GetResultArg("result");
	$xslt_processor->FreeResultArgs();
}

package Apache::AxKit::Language::Sablot::Handler;

sub new {
	my $class = shift;
	my $r = shift;
	my $ext_ent_handler = shift;
	bless {apache => $r, ext_ent_handler => $ext_ent_handler}, $class;
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

1;
