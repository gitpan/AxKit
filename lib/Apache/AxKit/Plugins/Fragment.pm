# $Id: Fragment.pm,v 1.2 2000/05/12 11:44:22 matt Exp $

package Apache::AxKit::Plugins::Fragment;

use strict;

use Apache::Constants;
use Apache::AxKit::Language::XPathScript;
use XML::XPath;
use XML::XPath::Parser;
use XML::XPath::XMLParser;

sub handler {
	my $r = shift;
	
#	warn "Fragment handler\n";
	
	my $mtime = -M $r->finfo;
	my $xmlfile = $r->filename;
	
	my $qs = $ENV{QUERY_STRING};
	return DECLINED unless $qs;
	return DECLINED if ($qs =~ /^\w+=/);
	
#	warn "qs: $qs\n";
	
	my $source_tree;
	my $parser = XML::XPath::XMLParser->new();
	my $xp = XML::XPath->new();

	if (exists($Apache::AxKit::Language::XPathScript::cache->{$xmlfile})
			&& $Apache::AxKit::Language::XPathScript::cache->{$xmlfile}{mtime} <= $mtime) {
		$source_tree = $Apache::AxKit::Language::XPathScript::cache->{$xmlfile}{tree};
	}
	
	if (!$source_tree) {
		eval {
			$source_tree = $parser->parsefile($xmlfile);
		};
		if ($@) {
			warn "Parse of '$xmlfile' failed: $@";
			return DECLINED;
		}
		
		$Apache::AxKit::Language::XPathScript::cache->{$xmlfile} =
			{
				mtime => $mtime,
				tree => $source_tree
			};
	}
	
	my $query = eval {XML::XPath::Parser->new()->parse($qs) };
	if ($@) {
		warn "Invalid query '$qs': $@\n";
		return DECLINED;
	}
	
	my $results = $query->evaluate($source_tree);
	
	$r->no_cache(1);
	$r->notes('nocache', 1);
	
	my $toptag = $r->dir_config('XPathFragmentElement') || 'resultset';
	
	if ($results->isa('XML::XPath::NodeSet')) {
#		warn "setting xml_string to a nodeset size: ", $results->size, "\n";
		$r->notes('xml_string', "<$toptag>" . join('', map { $_->toString } $results->get_nodelist) . "</$toptag>");
	}
	else {
#		warn "setting xml_string to a value\n";
		$r->notes('xml_string', "<$toptag>" . $results->value . "</$toptag>");
	}
	
	return OK;
}

1;
__END__

=head1 NAME

Apache::AxKit::Plugins::Fragment - Fragment plugin

=head1 DESCRIPTION

This module provides direct web access to XML fragments, using an
XPath syntax. By simply providing a querystring containing an
XPath query, this module will set the XML to be parsed to be
the XML nodes returned by the query. The nodes will be wrapped in
either <resultset>...</resultset> or you can specify the outer tag
using:

	PerlSetVar XPathFragmentElement foo

to wrap it in <foo>...</foo>.

=head1 USAGE

Simply add this module to the plugin list before StyleFinder:

	PerlHandler Apache::AxKit::Plugins::Fragment \
			Apache::AxKit::StyleFinder

Then request a URL as follows:

	http://server/myfile.xml?/some/xpath/query

Queries that match the regular expression: ^\w+= are ignored, as are
any invalid XPath queries.

Note that it's important to write your stylesheet to make use of this
capability! If you intend to use this Fragment plugin, you can't assume
that your stylesheet will just magically work. It will have to not make
assumptions about the XML being passed into it. The apply_templates()
method of XPathScript is extremely useful here, as is the xpath query
'name(/child::node())' which identifies the top level element's name.
Here's how I got around this with my first experiments with this:

	<!-- Main document body -->
	<% if (findvalue('name(/child::node())') eq 'page') { %>
		<%= apply_templates('/page/body/section') %>
	<% } else { %>
		<%= apply_templates('/') %>
	<% } %>

Which checks that the top level element is called 'page', otherwise it
simply does apply_templates() on all the nodes.

=cut
