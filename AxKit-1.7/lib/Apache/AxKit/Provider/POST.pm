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

package Apache::AxKit::Provider::POST;
# A Posted data provider for axkit.
# Work in progress.

use strict;
use vars qw/@ISA $VERSION/;
use Apache::AxKit::Provider;
use XML::LibXML;
use Compress::Zlib;
@ISA = ('Apache::AxKit::Provider');
$VERSION = '1.00';


sub get_strref {
 	my $self = shift;
 	
 	my $apache = $self->{apache};	
 	my $str;
 		
 	my $buffer;
 	$apache->read( $buffer, $apache->header_in('Content-length'));
 	
 	if( $apache->header_in('Content-Encoding') eq 'gzip') {
 	
 		$buffer = Compress::Zlib::memGunzip($buffer);
 		
 	}
 
 	my $parser = XML::LibXML->new();
 	   $parser->validation(0);
 	   $parser->expand_xinclude(0);
 		   
 	my $dom = $parser->parse_string($buffer);
 		
 	# We don't actually need to check this, since as long as the user
 	# has done AxResetProcessors, and not added it in, then we'll be ok,
 	# however, this is here just in case. 
 		
 	if($dom->findnodes('//*[namespace-uri() = "http://www.apache.org/1999/XSP/Core"]')) {
 		throw Apache::AxKit::Exception::Error(
 			-text => "Attempt to submit XSP via POST (insecure)"
 		);
 	}
 
 	my $str = $dom->toString(); 
 	return \$str;
}

sub process {
	my $self = shift;

	my $apache = $self->{apache};
	
	unless( $apache->method() eq 'POST') {
		AxKit::Debug(5, "HTTP method should be POST");
		return 0;
	}
	
	unless( $apache->header_in('Content-type') =~ m!^(text/xml|application/xml|.*\+xml)$!) {
		AxKit::Debug(5, "Content type should be xml based");
		return 0;
	}		

	unless ($apache->header_in('Content-length') > 0) {
		AxKit::Debug(5, "Content length should be greater than zero");
		return 0;
	}
	
	return 1;
}

sub key{
	my ($self) = shift;
	return $self->apache_request->uri();
}

sub mtime{
	return time();
}

sub exists{
	return 1;
}

sub get_fh {	
    throw Apache::AxKit::Exception::IO(
        -text => "not implemented"
   );
}

1;

__END__

=head1 NAME

Apache::AxKit::Provider::POST - Allow round tripping of XML via HTTP POST

=head1 DESCRIPTION

This module allows you to use POST'ed data as your XML source. This provides
a very quick and easy way to configure a WebServices system. All the power
of AxKit is available, including plugins and content negotiation.


=head1 SYNOPSIS

 <Location  /WebServices>
	SetHandler axkit
	AxContentProvider Apache::AxKit::Provider::POST
	AxIgnoreStylePI On	# You don't want to act on these.
	AxNoCache On		# You don't want to cache
	AxGzipOutput On		# Better network performance
	AxResetProcessors		# Only allow things we have explicity configured.
	AxResetPlugins
	AxResetStyleMap
	AxResetOutputTransformers
	<AxMediaType screen>
		AxAddStyleMap 	   text/xsl	 Apache::AxKit::Language::LibXSLT	
		AxAddRootProcessor   ....	
	</AxMediaType>	
 </Location>

=head1 SECURITY

It's a good idea to use AxResetProcessor, then you can configure your webservices stuff
to only accept locally configured directives. Things not configured will just get bounced
back to the client unmodified. Since you can't trust the source data, you only want to handle
things you have explicity configured.


=cut    