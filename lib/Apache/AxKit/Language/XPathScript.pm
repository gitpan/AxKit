# $Id: XPathScript.pm,v 1.1.1.1 2000/05/01 16:12:36 matt Exp $

package Apache::AxKit::Language::XPathScript;

use strict;
use vars qw($VERSION $cache $parser);

use Apache::File;
use Apache::Constants;
use XML::XPath;
use XML::XPath::XMLParser;

$VERSION = '0.03';

sub handler {
	my $r = shift;
	my ($xmlfile, $stylesheet) = @_;
	
	my $xp = XML::XPath->new();
	
	my $mtime = -M $r->finfo;
	
	my $source_tree;
	
	if (exists($cache->{$xmlfile}) 
			&& ($cache->{$xmlfile}{mtime} <= $mtime)) {
		$source_tree = $cache->{$xmlfile}{tree};
	}
	
	$parser ||= XML::XPath::XMLParser->new();
	
	if (!$source_tree) {
		eval {
			$source_tree = $parser->parsefile($xmlfile);
		};
		if ($@) {
			warn "Parse of '$xmlfile' failed: $@";
			return DECLINED;
		}
		$cache->{$xmlfile} = { 
			mtime => $mtime,
			tree => $source_tree,
			};
	}
	
	$xp->set_context($source_tree);
	
	$mtime = -M $stylesheet;
	
	my $package = get_package_name($stylesheet);
	
#	warn "Checking ", $cache->{$stylesheet}{mtime}, " against $mtime\n";
	if (exists($cache->{$stylesheet})
			&& ($cache->{$stylesheet}{mtime} <= $mtime)) {
		# cached... just exec.
#		warn $cache->{$stylesheet}{mtime}, " > $mtime\n";
	}
	else {
		# recompile stylesheet.
		compile($package, $stylesheet);
		$cache->{$stylesheet}{mtime} = $mtime;
	}
	
	my $old_status = $r->status;
	
	no strict 'refs';
	my $cv = \&{"$package\::handler"};

	$Apache::AxKit::Language::XPathScript::xp = $xp;
	my $t = {};
	$Apache::AxKit::Language::XPathScript::trans = $t;
	
	eval {
		$r->content_type('text/html');
		$r->content_encoding('utf-8');
		local $^W;
		$cv->($r, $xp, $t);
	};
	$Apache::AxKit::Language::XPathScript::xp = undef;
	$Apache::AxKit::Language::XPathScript::trans = undef;
	if ($@) {
		$r->log_error($@);
		return 500;
	}
	
#	warn "Returning $old_status\n";
	return $r->status($old_status);
}

sub compile {
	my ($package, $filename) = @_;
	
	my $contents;
	
	my $fh = Apache::File->new($filename) or die $!;
	{
		local $/;
		$contents = <$fh>;
	}
	
	my $script;
	
	my $line = 1;
	
	while ($contents =~ /\G(.*?)(<%=?)(.*?)%>/gcs) {
		my ($text, $type, $perl) = ($1, $2, $3);
		$line += $text =~ tr/\n//;
		$text =~ s/\|/\\\|/g;
		$script .= "print q|$text|;";
		$script .= "\n#line $line $filename\n";
		if ($type eq '<%=') {
			if ($perl =~ /;\s*/) {
				die "XPathScript error at line $line. <%= ... %> must not end with a semi-colon\n";
			}
			$script .= "print( $perl );\n";
			$line += $perl =~ tr/\n//;
		}
		else {
			$script .= $perl;
			$line += $perl =~ tr/\n//;
		}
	}
	
	$contents =~ /\G(.*)/gcs;
	my ($text) = ($1);
	$text =~ s/\|/\\\|/g;
	$script .= "print q|$text|;";
	
	my $eval = join('',
			'package ',
			$package,
			'; use Apache qw(exit);',
			'use XML::XPath::XMLParser;',
			'Apache::AxKit::Language::XPathScript::Toys->import;',
			'sub handler {',
			'my ($r, $xp, $t) = @_;',
			"\n#line 1 $filename\n",
			$script,
			"\n}",
			);
	
	local $^W;
	
#	warn "Recompiling $filename\n";
#	warn "Compiling script:\n$eval\n";
	eval $eval;
	if ($@) {
		die $@;
	}
}

sub get_package_name {
	my $filename = shift;
	# Escape everything into valid perl identifiers
	$filename =~ s/([^A-Za-z0-9_\/])/sprintf("_%2x",unpack("C",$1))/eg;

	# second pass cares for slashes and words starting with a digit
	$filename =~ s{
				  (/+)       # directory
				  (\d?)      # package's first character
				 }[
				   "::" . (length $2 ? sprintf("_%2x",unpack("C",$2)) : "")
				  ]egx;

	return "Apache::AxKit::Language::XPathScript::ROOT$filename";
}

{
	package Apache::AxKit::Language::XPathScript::Toys;
	
	use XML::XPath::XMLParser;

	use vars '@ISA', '@EXPORT';
	use Exporter;
	@ISA = ('Exporter');
	@EXPORT = ('findnodes', 
				'findvalue', 
				'findnodes_as_string',
				'apply_templates',
			);

	sub findnodes {
		$Apache::AxKit::Language::XPathScript::xp->findnodes(@_);
	}

	sub findvalue {
		$Apache::AxKit::Language::XPathScript::xp->findvalue(@_);
	}

	sub findnodes_as_string {
		$Apache::AxKit::Language::XPathScript::xp->findnodes_as_string(@_);
	}
	
	sub apply_templates {
		my @nodes = @_;
		
		local $^W;
				
		if (@nodes && !ref($nodes[0])) {
			# probably called with a path to find
			return apply_templates(findnodes(@_));
		}
		
		my $retval;
		foreach my $node (@nodes) {
			$retval .= translate_node($node);
		}
		
		return $retval;
	}
	
	sub translate_node {
		my $node = shift;
		
		local $^W;
				
		my $translations = $Apache::AxKit::Language::XPathScript::trans;
		
		if (ref($node) ne 'element') {
			if (ref($node) eq 'text' && $node->[node_text] =~ /^\s*$/) {
				return ' '; # strip whitespace by default
			}
			return XML::XPath::XMLParser::as_string($node);
		}
		
#		warn "translate_node: ", $node->[node_name], "\n";
		
		my $trans = $translations->{$node->[node_name]};

		if (!$trans) {
			return start_tag($node) . 
					apply_templates(@{$node->[node_children]}) .
					end_tag($node);
		}
		
		local $^W;
		
		my $dokids = 1;

		if ($trans->{testcode}) {
			my $result = eval { $trans->{testcode}->($node); };
			if ($result == 0) {
				# don't process anything.
				return;
			}
			if ($result == -1) {
				# -1 means don't do children.
				$dokids = 0;
			}
		}
		
		# default: process children too.
		return $trans->{pre} . 
				($trans->{showtag} ? start_tag($node) : '') .
				($dokids ? apply_templates(@{$node->[node_children]}) : '') .
				($trans->{showtag} ? end_tag($node) : '') .
				$trans->{post};
	}
	
	sub start_tag {
		my ($node) = @_;
		
		my $string = "<" . $node->[node_name];
		
		foreach my $ns (@{$node->[node_namespaces]}) {
			$string .= XML::XPath::XMLParser::as_string($ns);
		}
		
		foreach my $attr (@{$node->[node_attribs]}) {
			$string .= XML::XPath::XMLParser::as_string($attr);
		}

		$string .= ">";
		
		return $string;
	}
	
	sub end_tag {
		my ($node) = @_;
		
		return "</" . $node->[node_name] . ">";
	}

	1;
}

1;
__END__

=head1 NAME

Apache::AxKit::Language::XPathScript - Simple XPath web scripting

=head1 SYNOPSIS

  PerlTypeHandler Apache::AxKit::XMLFinder
  PerlHandler Apache::AxKit::StyleFinder
  PerlSetVar StylesheetMap "application/x-xpathscript => \
		Apache::AxKit::Language::XPathScript"

=head1 DESCRIPTION

This module provides the user with simple XPath crossed with ASP-style scripting
in a template. The system picks the template from the <?xml-stylesheet?>
processing instruction using Apache::AxKit::StyleFinder and then
this module combines the xml source file, and the stylesheet by setting
the xml file up as the document for XPath expressions to be used.

=head1 SYNTAX

The syntax follows the basic ASP stuff. <% introduces perl code, and %> closes
that section of perl code. <%= ... %> can be used to output a perl expression.

The interesting stuff comes when you start to use XPath. The following methods
are available for your use:

=over

=item findnodes($path, [$context])

=item findvalue($path, [$context])

=item findnodes_as_string($path, [$context])

=item apply_templates( $path, [$context])

=item apply_templates( @nodes )

=back

The find* functions are identical to the XML::XPath methods of the same name, so
see L<XML::XPath> for more information. They allow you to create dynamic
templates extremely simply:

  <%
  foreach my $n (findnodes('//fred')) {
    print "Found a fred\n";
    foreach my $m (findnode('..', $n)) {
      print "fred's parent was: ", $m->[node_name], "\n";
    }
  }
  %>

This, combined with the simplicity of both ASP and XPath, make a pretty powerful
combination.

Even more powerful though is the ability to do XSLT-like apply-templates on
nodes. The apply_templates function looks at the information in the $t hash
reference. If there is a key with the same name as the current tag, the
values in that key are used for processing. Here's a guide to some of the
possibilities:

	<%
	foreach my $node (findnodes('xpath/here')) {
        	print apply_templates($node);
	}
	%>

That prints all nodes found by the path.

	<%
	print findvalue('xpath/here', $context);
	%>

That prints the value of whatever was found by the XPath search in context
$context. (if the search returns a NodeSet it prints the string-value of
the nodeset. See the Xpath spec for what that means).

	<%
	print findnodes_as_string('xpath/here');
	%>

That prints the nodes as they were found. e.g. if the xml was:

	<foo>
        	<bar><foobar>Hello!</foobar></bar>
	</foo>

and the search was '/foo/bar/foobar' it prints '<foobar>Hello!</foobar>'.

	<%
	$t->{'a'}{pre} = '<i>';
	$t->{'a'}{post} = '</i>';
	$t->{'a'}{showtag} = 1;
	%>

When using apply_templates(@nodes) (recommended), this prints all <a> tags
with <i>...</i> around them.

	<%
	$t->{'a'}{pre} = '<i>';
	$t->{'a'}{post} = '</i>';
	%>

When using apply_templates(@nodes), on <a> tags, prints <i>...</i> instead
of <a>...</a>.

	<%
	$t->{'a'}{testcode} = sub {...};
	%>

This sets up a sub to determine what to do with the node when
apply_templates is used. The sub recieves the node as the first (and
only) parameter. Return 0 to stop processing at that node and return,
return -1 to process that node but not its children, and return 1 to
process this node normally (i.e. process this node and its children). An
example of where this might be useful is to test the context of this node:

	<%
	$t->{'a'}{testcode} = 
        sub {
                my $node = shift;
                if (findvalue('ancestor::foo = true()', $node)) {
                    return 0;
                }
                return 1;
        };
	%>

This only process 'a' nodes that aren't descendants of a 'foo' element.

You can also use testcode to setup custom values for pre and post,
depending on context, for example:

  $t->{'title'}{testcode} =
        sub {
                my $node = shift;
                if (findvalue('parent::section = true()', $node)) {
                        $t->{'title'}{pre} = '<h1>';
                        $t->{'title'}{post} = '</h1>';
                }
                elsif (findvalue('parent::subsection = true()', $node)) {
                       $t->{'title'}{pre} = '<h2>';
                        $t->{'title'}{post} = '</h2>';
                }
				else {
					$t->{'title'}{pre} = '<title>';
					$t->{'title'}{post} = '</title>';
				}
                return 1;
        };

Which sets titles to appear as h1's in a section context, or as h2's in a
subsection context, or just ordinary titles in other contexts.

=head1 A COMPLETE EXAMPLE

This is the code I use to process some web pages:

  <%
  $t->{'a'}{pre} = '<i>';
  $t->{'a'}{post} = '</i>';
  $t->{'a'}{showtag} = 1;
  
  $t->{'title'}{testcode} =
    sub {
        my $node = shift;
        if (findvalue('parent::section = true()', $node)) {
            $t->{'title'} =
                 { pre => '<h2>', post => '</h2>' };
        }
        elsif (findvalue('parent::subsection = true()', $node)) {
            $t->{'title'} =
                 { pre => '<h3>', post => '</h3>' };
        }
        return 1;
    };
  
  $t->{'section'}{post} = '<p>';
  $t->{'subsection'}{post} = '<br>';
  
  %>
  <html>
  <head>
  	<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
  	<%= apply_templates('/page/head/title') %>
  </head>
  <body bgcolor="white">
  	<h1><%= findvalue('/page/head/title/text()') %></h1>
	
  <%= apply_templates('/page/body/section') %>

  <br>
  <small>This page is copyright Fastnet Software Ltd, 2000.
  Contact <a href="mailto:matt@sergeant.org">Matt Sergeant</a>
  for details and availability.</small>
  </body>
  </html>


=head1 AUTHOR

Matt Sergeant, matt@sergeant.org

=head1 SEE ALSO

XML::XPath.

=head1 LICENSE

This module is free software, and is distributed under the same terms as Perl.

=cut
