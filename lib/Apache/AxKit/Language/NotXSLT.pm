package Apache::AxKit::Language::NotXSLT;

# $Id: NotXSLT.pm,v 1.6 2000/05/19 15:47:13 matt Exp $

use strict;
use vars qw(@ISA $VERSION $PREFIX $cache);

$VERSION = '0.04';

use Apache;
use Apache::Constants;
use Apache::File;
use XML::XPath;
use XML::XPath::Node;
use XML::XPath::XMLParser;
use Apache::AxKit::Language;

@ISA = 'Apache::AxKit::Language';

sub handler {
	my $class = shift;
	my ($r, $xmlfile, $stylesheet) = @_;
	

#	warn "In NotXSLT with $xmlfile and $stylesheet\n";

	my $source_finder = XML::XPath->new;
	
	my $parser = XML::XPath::XMLParser->new;
	
	my $source_tree;
	
	my $mtime = -M $r->finfo;
	
	if (exists $cache->{$xmlfile} && 
			$cache->{$xmlfile}{mtime} <= $mtime) {
		$source_tree = $cache->{$xmlfile}{tree};
	}
	else {
		eval {
			$source_tree = $parser->parsefile($xmlfile);
		};
		if ($@) {
			warn "Parse of '$xmlfile' failed with $@";
			return DECLINED; # ???
		}
		$cache->{$xmlfile}{mtime} = $mtime;
		$cache->{$xmlfile}{tree} = $source_tree;
	}
	
	my $template_tree;
	
	$mtime = -M $stylesheet;
	
	if (exists $cache->{$stylesheet} &&
			$cache->{$stylesheet}{mtime} <= $mtime) {
		$template_tree = $cache->{$stylesheet}{tree}
	}
	else {
		eval {
			$template_tree = $parser->parsefile($stylesheet);
		};
		if ($@) {
			warn "Parse of stylesheet '$stylesheet' failed with $@";
			return DECLINED; # ???
		}
		$cache->{$stylesheet}{mtime} = $mtime;
		$cache->{$stylesheet}{tree} = $template_tree;
	}
	
	my $root_node;
	
	# get namespace prefix for template
	# here we search through all children of the root node
	# because there could be comments or PI's here.
	# The root node MUST contain a xmlns:<prefix>="..."
	ROOT:
	foreach my $node ($template_tree->getChildNodes) {
		if ($node->getNodeType == ELEMENT_NODE) {
			# first element node!
			$root_node = $node;
			foreach my $ns ($node->getNamespaceNodes) {
				if ($ns->getExpanded eq 'http://sergeant.org/notxslt') {
					$PREFIX = $ns->getPrefix;
					last ROOT;
				}
			}
			warn "Not a template file - no namespace declaration matching\nhttp://sergeant.org/notxslt in file '$stylesheet'\n";
			return DECLINED;
		}
	}
	
	my $string = parse($source_finder, $source_tree, $root_node);
	$r->print($string);
	
	return OK;
	
}

sub parse_style {
	my $data = shift;
	my $style;
	while ($data =~ /\G\s*$XML::XPath::Parser::NCName\s*=\s*(["'])([^\2<]*?)\2/gco) {
		my ($attr, $val) = ($1, $3);
		$style->{$attr} = $val;
	}
	
	if (!exists($style->{href}) || !exists($style->{type})) {
		warn "Incorrect <?xml-stylesheet?> processing instruction\n";
		return;
	}
	
	return $style;
}

sub escape {
	my $text = shift;
	$text =~ s/&/&amp;/g;
	$text =~ s/</&lt;/g;
	$text =~ s/>/&gt;/g;
	$text =~ s/"/&quot;/g;
	$text =~ s/'/&apos;/g;
	return $text;
}

sub parse {
	my ($xp, $context, $node) = @_;
	
	# examine node
	
	my $string;
	
#	print "Node type is ", ref($node), "\n";
	for ($node->getNodeType) {
		if ($_ == ELEMENT_NODE) {
			local $^W;
			if ($node->getPrefix eq $PREFIX) {
				$string .= process_template_node($xp, $context, $node);
			}
			else {
				# gather attributes
				my @attribs;
				$string .= "<" . $node->getName;
				foreach my $attr ($node->getAttributeNodes) {
					$string .= $attr->toString;
				}
				
				if (@{$node->getChildNodes}) {
					$string .= ">";
					# process children
					foreach my $n ($node->getChildNodes) {
						$string .= parse($xp, $context, $n);
					}
					$string .= "</" . $node->getName . ">";
				}
				else {
					$string .= " />";
				}
			}
		}
		elsif ($_ == TEXT_NODE) {
			$string .= $node->toString;
		}
		elsif ($_ == COMMENT_NODE) {
			# ignore comments for now.
		}
	}
	
	return $string;
}

sub process_template_node {
	my ($xp, $context, $node) = @_;

	my $string;
	
	if ($node->getLocalName eq "select") {
		# find match in $xp, and output.
		my $match;
		foreach my $attrib ($node->getAttributeNodes) {
			if ($attrib->getName eq 'match') {
				$match = $attrib->getValue;
			}
		}
		
		die "No 'match' attribute on $PREFIX:select element" unless $match;
		
		my $results = $xp->find($match, $context);
		
		die "Match '$match' failed!\n" unless defined $results;
		
		if ($results->isa('XML::XPath::NodeSet')) {
			foreach my $result ($results->get_nodelist) {
				$string .= $result->toString;
#				$string .= escape(XML::XPath::XMLParser::as_string($result));
			}
		}
		else {
			$string .= $results->value;
#			$string .= escape($results->value);
		}
	}
	elsif ($node->getLocalName eq "for-each") {
		# find match, get matching nodes, loop over matching nodes
		my $match;
		foreach my $attrib ($node->getAttributeNodes) {
			if ($attrib->getName eq 'match') {
				$match = $attrib->getValue;
			}
		}
		
		die "No 'match' attribute on $PREFIX:for-each element" unless $match;
		
		my $results = $xp->find($match, $context);
		
		if ($results->isa('XML::XPath::NodeSet')) {
			foreach my $result ($results->get_nodelist) {
				foreach my $kid ($node->getChildNodes) {
					$string .= parse($xp, $result, $kid);
				}
			}
		}
		else {
			die "$PREFIX:for-each match doesn't match a set of nodes";
		}
	}
	elsif ($node->getLocalName eq "exec") {
		# find match and ignore results.
		my $match;
		foreach my $attrib ($node->getAttributeNodes) {
			if ($attrib->getName eq 'match') {
				$match = $attrib->getValue;
			}
		}
		
		die "No 'match' attribute on $PREFIX:exec element" unless $match;
		
		my $results = $xp->find($match, $context);
	}
	elsif ($node->getLocalName eq "verbatim") {
		my $match;
		foreach my $attrib ($node->getAttributeNodes) {
			if ($attrib->getName eq 'match') {
				$match = $attrib->getValue;
			}
		}
		
		die "No 'match' attribute on $PREFIX:verbatim element" unless $match;
		
		my $results = $xp->find($match, $context);
		
		if ($results->isa('XML::XPath::NodeSet')) {
			foreach my $node ($results->get_nodelist) {
				if ($node->getNodeType == ELEMENT_NODE) {
					$string .= "<" . $node->getName;
					foreach my $attr ($node->getAttributeNodes) {
						$string .= $attr->toString;
					}

					if ($node->getChildNodes) {
						$string .= ">";
						# process children
						foreach my $n ($node->getChildNodes) {
							$string .= parse($xp, $context, $n);
						}
						$string .= "</" . $node->getName . ">";
					}
					else {
						$string .= " />";
					}
				}
				elsif ($node->getNodeType == TEXT_NODE) {
					$string .= $node->getData;
				}
			}
		}
		else {
			die "$PREFIX:verbatim match doesn't match a set of nodes";
		}
	}
	
	return $string;
}

{
	
	# here we add some functions to the XPath function library.

	package XML::XPath::Function;
	
	use XML::XPath::Literal;

	# why oh why wasn't set_var implemented in the first place???
	sub set_var {
		my $self = shift;
		my ($node, @params) = @_;
		if (@params != 2) {
			die "Usage: set_var('name', value)\n";
		}
		$self->{pp}->set_var($params[0], $params[1]);
	}
	
	# and the same goes for sprintf!
	# (I think the excuse there is "Java doesn't have sprintf". Bah!)
	sub sprintf {
		my $self = shift;
		my ($node, @params) = @_;
		if (!@params) {
			die "Usage: sprintf(Literal [, args]*)\n";
		}
		
		my @vals = map("$_", @params);
		my $format = shift @vals;
		my $val = CORE::sprintf($format, @vals);
		return XML::XPath::Literal->new($val);
	}
	
}


1;
__END__

=head1 NAME

Apache::AxKit::Language::NotXSLT - Matt's non-xslt template processor

=head1 SYNOPSIS

  PerlTypeHandler Apache::AxKit::XMLFinder
  PerlHandler Apache::AxKit::StyleFinder
  PerlSetVar StylesheetMap "application/x-notxslt => \
		Apache::AxKit::Language::NotXSLT"

=head1 DESCRIPTION

This module implements an XML template system that looks a bit like
XSLT, but isn't. Hence the name. It uses XML::XPath, and should be
fast enough to use on small web sites dynamically, rather than using
static transformation.

=head1 AUTHOR

Matt Sergeant, matt@sergeant.org

=head1 SEE ALSO

XML::XPath(1).

=cut

# $Log: NotXSLT.pm,v $
# Revision 1.6  2000/05/19 15:47:13  matt
# Brown bag release of XSP
# Removed content_type/encoding from other modules
#
# Revision 1.5  2000/05/10 21:21:24  matt
# Support for cascading via xml_string
#
# Revision 1.4  2000/05/08 13:10:31  matt
# Updated to new XML::XPath 0.50
#
# Revision 1.3  2000/05/06 11:11:58  matt
# Implemented Languages as subclass of Language.pm
#
# Revision 1.2  2000/05/02 10:32:05  matt
# Rename to AxKit
#
