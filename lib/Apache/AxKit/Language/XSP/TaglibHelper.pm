# $Id: TaglibHelper.pm,v 1.9 2001/06/04 15:40:59 matt Exp $

package Apache::AxKit::Language::XSP::TaglibHelper;
@ISA = qw(Apache::AxKit::Language::XSP);
use XML::XPath;
use XML::XPath::Node;

use strict;

sub parse_char {
    my ($e, $text) = @_;
    $text =~ s/^\s*//;
    $text =~ s/\s*$//;

    return '' unless $text;

    $text =~ s/\|/\\\|/g;
    return ". q|$text|";
}

# Try to find the given function name and see if it's in the "use"ing
# module's list of exported functions. Retuns the function spec if
# if it found it, or undef if it didn't.
sub is_function ($$) {
    my ($pkg, $fname) = @_;

    no strict;
    my @exports = @{"$pkg\::EXPORT_TAGLIB"};
    use strict;

    foreach my $funspec(@exports) {
        return $funspec if $funspec =~ /^$fname *\(/;
    }

    return undef;
}

sub func_name ($) {
    my ($funspec) = @_;

	my %opts = func_options($funspec);
	return $opts{isreally} if $opts{isreally};
    my ($argspec) = ($funspec =~ /^ *(.*?)\(/);
    return $argspec;
}

sub func_options ($) {
    my ($funspec) = @_;

    my @args = split (/: */, $funspec);
    shift @args;
    my %retval = ();
    foreach (@args) {
        my ($key, $value) = ($_ =~ /(.*)=(.*)/);
        $retval{$key} = $value;
    }
    return %retval;
}

sub required_args ($) {
    my ($funspec) = @_;

    my ($argspec) = ($funspec =~ /\( *([^\);]*)/);
    my @retval;
    foreach my $arg(split (/,/, $argspec)) {
        $arg =~ s/^\s*//g;
        $arg =~ s/\s*$//g;
        push (@retval, $arg);
    }
    return @retval;
}

sub optional_args ($) {
    my ($funspec) = @_;

    my ($argspec) = ($funspec =~ /; *([^\)]*)/);
    my @retval;
    foreach my $arg(split (/,/, $argspec)) {
        $arg =~ s/^\s*//g;
        $arg =~ s/\s*$//g;
        push (@retval, $arg);
    }
    return @retval;
}

sub find_arg ($@) {
    my $argname = shift;

    foreach (@_) { return $_ if /^.$argname/ }
    return "";
}

# quieten warnings when compiling
sub handle_result ($$$;@);

# The input to this function is the *result* from a taglib function, and
# therefore can be anything. We need to be able to turn it into a set
# of XML tags.
sub handle_result ($$$;@) {
    my $funspec     = shift;
    my $indentlevel = shift;
    my $parent      = shift;

    my $indent = '  ' x $indentlevel;

    my %options = func_options($funspec);

    # if we got more than one result (we assume it's an array),
    # we'll act as if we got a single arrayref
    # forcearray makes it always think there's an array; useful
    # for functions that are returning an array of one value
    if ($indentlevel == 0 and ($options{forcearray} or scalar @_ > 1)) {
        @_ = ([@_]);
    }

    # break down each arg in the results, possibly call self recursively
    foreach my $ref(@_) {
        if ( (ref($ref)) =~ /ARRAY/) {

            # arrays are hard because they're not keyed except by numbers
            # the array list itself will have a wrapper tag of funcname+"-list" if
            # we're at indent level 0, or no wrapper if it's below level 0
            if ($indentlevel == 0) {
                $parent->appendChild(XML::XPath::Node::Text->new("\n" . $indent));
                my $el;
                if ($options{listtag}) {
                    $el = XML::XPath::Node::Element->new($options{listtag});
                }
                else {
                    my $funcname = func_name($funspec);
                    $funcname =~ s/_/-/g;    # convert back to XML-style tagnames
                    $el = XML::XPath::Node::Element->new("${funcname}-list");
                }
                $parent->appendChild($el);
                $parent = $el;
            }

            my $id = 1;
            foreach my $value(@$ref) {
		# each item within an array should have a wrapper "-item" tag
		my $item;
		if ($options{itemtag}) {
		    $item = XML::XPath::Node::Element->new($options{itemtag});
		}
		else {
		    my $funcname = func_name($funspec);
		    $funcname =~ s/_/-/g;    # convert back to XML-style tagnames
		    $item = XML::XPath::Node::Element->new("${funcname}-item");
		}
		my $attrib = XML::XPath::Node::Attribute->new("id", $id++, "");
		$item->appendAttribute($attrib);
		$parent->appendChild($item);
                handle_result($funspec, $indentlevel + 1, $item, $value);
            }
        }
        elsif ( (ref($ref)) =~ /HASH/) {
            # hashes are relatively easy because they're keyed
            $parent->appendChild(XML::XPath::Node::Text->new("\n" . $indent));
            while (my ($key, $value) = each %$ref) {
                my $el = XML::XPath::Node::Element->new($key);
                $parent->appendChild($el);
                handle_result($funspec, $indentlevel + 1, $el, $value);
            }
        }
        else {

            # not arrayref or not hashref: it's either a scalar or an unsupported
            # type, so we'll just dump it as text
            # special case: at the highest level of hierarchy, we can just return a
            # string because it will be turned automatically into a text node by
            # AxKit
            if ($indentlevel == 0) {
                return $_[0];
            }
            else {
                $parent->appendChild(XML::XPath::Node::Text->new($_[0]));
            }
        }

    }
}

# quieten warnings when compiling
sub convert_from_dom ($);
# This function converts from a DOM tree into a collection of hashes.
# It's used for "*" taglib arguments.
sub convert_from_dom ($) {
    my ($node) = @_;

    # if we're at the first level, we'll ignore our top node, because we know it's just
    # a dummy root node
    if ($node->getNodeType eq ELEMENT_NODE) {
        my @children = ($node->getChildNodes,$node->getAttributeNodes);
		my $multiple = 0;
		my %mdetect = ();
		# look for multiple children with the same name, which
		# means we should treat it as an array
		foreach (@children) {
			$multiple = 1 if $mdetect{$_->getName};
			$mdetect{$_->getName} = 1;
		}

		if ($multiple) {
			my $retval = [];
			foreach (@children) {
				push(@$retval, convert_from_dom($_));
			}
			return $retval;
		}
		else {
			if (@children > 1) {
        my $retval   = {};
        foreach (@children) {
					$retval->{ $_->getName || 'TEXT' } = convert_from_dom($_);
        }
        return $retval;
    }
			elsif (@children == 1) {
				return convert_from_dom($children[0]);
			}
		}
		return "";
    }
    else {

        # we'll just assume it's text for now
        return $node->getValue;
    }
}

@Apache::AxKit::Language::XSP::TaglibHelper::function_stack = ();

sub parse_start {
    my ($e, $tag, %attribs) = @_;

    # Dashes are more "XML-like" than underscores, but we can't use
    # dashes in function or argument names. So we'll just convert them
    # arbitrarily here.
    $tag =~ s/-/_/g;

    my $pkg = caller;

    # horrible hack: if the caller is the SAX library directly,
    # then we'll just have to assume that we're testing TaglibHelper
    $pkg = "Apache::AxKit::Language::XSP::TaglibHelper" if $pkg eq "AxKit::XSP::SAXHandler";
    my $funspec = is_function($pkg, $tag);

    my $code = "";
    if ($funspec) {
	my %options = func_options($funspec);
        push (@Apache::AxKit::Language::XSP::TaglibHelper::function_stack, $funspec);
        $code = "{ my \%_args = ();";
        while (my ($key, $value) = each %attribs) {
	    my $paramspec = find_arg($key, required_args($funspec), optional_args($funspec));
	    if ($paramspec =~ /^\*/) {
		$code .= " die 'Argument $key to function $tag is tree type, and cannot be set in an attribute.';\n";
	    }
	    elsif ($paramspec =~ /^\@/) {
		$key   =~ s/-/_/g;
		$value =~ s/\|/\\\|/g;
		$code .= " \$_args{$key} ||= []; push \@{\$_args{$key}}, q|$value|;\n";
	    }
	    else {
		$key   =~ s/-/_/g;
		$value =~ s/\|/\\\|/g;
		$code .= " \$_args{$key} = q|$value|;\n";
	    }
        }
	# if it's a "conditional" function (i.e. it wraps around conditional tags)
	# we need to pick up the arguments in the attributes only, and execute
	# the function here
	if ($options{conditional}) {
	    foreach my $arg(required_args($funspec)) {
		$arg =~ s/^.//g;    # ignore type specs for now
		$code .=
    " die 'Required arg \"$arg\" for tag $tag is missing' if not defined \$_args{$arg};\n";
	    }
	    $code .= " if ($pkg\::" . func_name($funspec) . "(";

	    foreach my $arg(required_args($funspec), optional_args($funspec)) {
		$arg =~ s/^.//g;    # remove type specs from hash references
		$code .= "\$_args{$arg},";
	    }
	    $code .= ")) {\n";
            $e->manage_text(0);
	}
	else {
	    $e->start_expr($tag);
	}
    }
    else {
        my $funspec =
          $Apache::AxKit::Language::XSP::TaglibHelper::function_stack
          [$#Apache::AxKit::Language::XSP::TaglibHelper::function_stack];
        my $paramspec = find_arg($tag, required_args($funspec), optional_args($funspec));

        # if the param is of type '*', then we have to prepare a new DOM tree
        # but we default to assuming it's a scalar argument
        if ($paramspec =~ /^\*/) {
            $code =
" { my \$theparent = \$parent ; \$parent = XML::XPath::Node::Element->new('ROOT-$tag'); \$_args{$tag} = \$parent;\n";
            $e->manage_text(0);
        }
        elsif ($paramspec =~ /^\@/) {
            $code = " \$_args{$tag} ||= []; push \@{\$_args{$tag}}, \"\"\n";
        }
        else {
            $code = " \$_args{$tag} = \"\"\n";
        }
    }
    return $code;
}

sub parse_end {
    my ($e, $tag) = @_;

    my $origtag = $tag;
    $tag =~ s/-/_/g;

    my $pkg = caller;
    $pkg = "Apache::AxKit::Language::XSP::TaglibHelper" if $pkg eq "AxKit::XSP::SAXHandler";
    my $funspec = is_function($pkg, $tag);

    my $code = "";
    if ($funspec) {
        pop (@Apache::AxKit::Language::XSP::TaglibHelper::function_stack);
	my %options = func_options($funspec);
	if ($options{conditional}) {
            $e->manage_text(1);
	    return "}}\n";
	}
	else {
	    $code = ";";
	    foreach my $arg(required_args($funspec)) {
		$arg =~ s/^.//g;    # ignore type specs for now
		$code .=
    " die 'Required arg \"$arg\" for tag $origtag is missing' if not defined \$_args{$arg};\n";
	    }
	    $code .=
    " Apache::AxKit::Language::XSP::TaglibHelper::handle_result('$funspec', 0, \$parent, $pkg\::"
	      . func_name($funspec) . "(";

	    foreach my $arg(required_args($funspec), optional_args($funspec)) {
		$arg =~ s/^.//g;    # remove type specs from hash references
		$code .= "\$_args{$arg},";
	    }
	    $code .= "));}\n";
	    $e->append_to_script($code);
	    $e->end_expr();
	    return '';
	}
    }
    else {

        # what function are we in?
        my $funspec =
          $Apache::AxKit::Language::XSP::TaglibHelper::function_stack
          [$#Apache::AxKit::Language::XSP::TaglibHelper::function_stack];
        my $paramspec = find_arg($tag, required_args($funspec), optional_args($funspec));

        # if the param is of type '*', then we restore the old DOM tree
        if ($paramspec =~ /^\*/) {
            $e->manage_text(1);
            $code =
" \$parent = \$theparent; \$_args{$tag} = Apache::AxKit::Language::XSP::TaglibHelper::convert_from_dom(\$_args{$tag}); }";
        }
        return "$code;\n";
    }
}

##############################################################################
# a built-in taglib, so we can test the functionality of TaglibHelper
no strict;

$NS = 'http://apache.org/xsp/testtaglibhelper/v1';
@EXPORT_TAGLIB = (
  'test_hello($name)', 
  'test_echo(*whatever)', 
  'test_echo_array(@array)', 
  'test_get_person($name)', 
  'test_get_people($name)',
  'test_get_people2($name):listtag=people:itemtag=person',
);

use strict;

# now you declare your functions
sub test_hello ($) {
    my ($name) = @_;
    return "Hello, $name!";
}

sub test_echo ($) {
    my ($whatever) = @_;
    return $whatever;
}

sub test_echo_array ($) {
    my ($whatever) = @_;
    return $whatever;
}

sub test_get_person ($) {
    my ($name) = @_;
    srand(time + $$) if not $Apache::AxKit::Language::XSP::TaglibHelper::didsrand;
    $Apache::AxKit::Language::XSP::TaglibHelper::didsrand = 1;
    return {
        person => {
            name  => $name,
              age => int(rand(99)),
        }
    };
}

sub test_get_people ($) {
    my ($name) = @_;
    return [
        test_get_person($name),       test_get_person($name . "2"),
        test_get_person($name . "3"), test_get_person($name . "4"),
    ];
}

sub test_get_people2 ($) {
    my ($name) = @_;
    return (test_get_person($name)->{person}, test_get_person($name . "2")->{person},
      test_get_person($name . "3")->{person}, test_get_person($name . "4")->{person},);
}

1;

__END__

=head1 NAME

TaglibHelper - module to make it easier to write a taglib

=head1 SYNOPSIS

Put this code at the top of your taglib module:

    # this stuff, you change for each taglib
    $NS = 'http://apache.org/xsp/testtaglib/v1';
    @EXPORT_TAGLIB = (
	'func1($arg1)',
	'func2($arg1,$arg2)',
	'func3($arg1,$arg2;$optarg)',
	'func4($arg1,*treearg)',
	'func4($arg1,*treearg):listtag=mylist:itemtag=item',
    );

    # this stuff you don't
    use Apache::AxKit::Language::XSP::TaglibHelper;
    sub parse_char { Apache::AxKit::Language::XSP::TaglibHelper::parse_char(@_); }
    sub parse_start { Apache::AxKit::Language::XSP::TaglibHelper::parse_start(@_); }
    sub parse_end { Apache::AxKit::Language::XSP::TaglibHelper::parse_end(@_); }
    use strict;

...and then edit the $NS and @EXPORT_TAGLIB to reflect
your taglib's namespace and list of functions.

=head1 DESCRIPTION

The TaglibHelper module is intended to make it much easier to build
a taglib module than had previously existed. When you create a library
that uses TaglibHelper, you need only to write "regular" functions that
take string arguments (optional arguments are supported) and return
standard Perl data structures like strings and hashrefs.

=head1 FUNCTION SPECIFICATIONS

The @EXPORT_TAGLIB global variable is where you list your exported
functions. It is of the format:

    funcname(arguments)[:options]

The C<<arguments>> section contains arguments of the form:

    $argument   a argument that is expected to be a plain string
    *argument   a argument that can take a XML tree in hashref form
    @argument   a argument that is expected to be an array of plain strings
		(i.e. this argument can be called multiple times, like in
		the Sendmail taglib)

These arguments are separated by commas, and optional args are separated
from required ones by a semicolon. For example, C<$field1,$field2;$field3,$field4>
has required parameters C<field1> and C<field2>, and optional parameters
C<field3> and C<field4>.

The options are colon-separated and give extra hints to TaglibHelper
in places where the default behavior isn't quite what you want.
Currently recognized options are:

    listtag     For functions that return arrays, use the indicated
		wrapper tag for the list instead of <funcname>-list
    itemtag     For functions that return arrays of strings, use the
		indicated wrapper tag for the list items instead of 
		<funcname>-item
    forcearray  For functions that always return an array, you should
		generally set this option to "1". the reason is that
		if your array-returning function only returns one value
		in its array, the result won't be treated as an array
		otherwise.
    conditional The function's return value will not be printed, and
		instead will be used to conditionally execute child
		tags. NOTE that arguments to the function cannot
		be brought in via child tags, but instead must come
		in via attributes.
	isreally	this function specification is actually an alias for
		a perl function of a different name. For example, a specification
		of "person($name):isreally=get_person" allows you to have
		a tag <ns:person name="joe"/> that will resolve to Perl code
		"get_person('Joe')".


=head1 EXAMPLE

if you had these two functions:


    sub hello ($) {
	my ($name) = @_;
	return "Hello, $name!";
    }

    sub get_person ($) {
	my ($name) = @_;
	return { 
	    person => { 
		name => $name,
		age => 25,
		height => 200,
	    }
	}
    }

...and you called them with this xsp fragment:

    <test:hello>
	<test:name>Joe</test:name>
    </test:hello>

    <test:get-person name="Bob"/>

...you would get this XML result:

    Hello, Joe!
    <person>
      <height>200</height>
      <age>25</age>
    <name>Bob</name></person>

If your function returned deeper result trees, with hashes containing
hashrefs or something similar, that would be handled fine. There are some
limitations with arrays, however, described in the BUGS AND LIMITATIONS
section.

=head1 STRUCTURED INPUT EXAMPLE

If you wish to send structured data (i.e. not just a scalar) to a taglib
function, use "*" instead of "$" for a variable. The input to a taglib
function specified as "insert_person($pid,*extra)" might be:

    <test:insert-person pid="123">
	<test:extra>
	    <weight>123</weight>
	    <friends>	
		<pid>3</pid>
		<pid>5</pid>
		<pid>13</pid>
	    </friends>
	</test:extra>
    </test:insert-person>

The function call would be the same as:

    insert_function("123", { 
	weight => 123, 
	friends => [ 3, 5, 13 ]
    });

The <friends> container holds repeating tags, notice, and TaglibHelper
figured out automatically that it needs to use an arrayref instead of
hashref for the values. But you'll get unexpected results if you mix
repeating tags and nonrepeating ones:

	<test:extra>
		<weight>123</weight>
		<friend>3</friend>
		<friend>5</friend>
		<friend>13</friend>
	</test:extra>

Just wrap your singular repeated tags with a plural-form tag, in this
case <friends>.

=head1 BUGS AND LIMITATIONS

Arrays and arrayrefs are generally difficult to work with because the
items within the array have no keys other than the index value. As a
result, if you want items within an array to be identified correctly,
you must currently make all array items point to a hashref that contains
the item's key or you must use the optional arguments to give TaglibHelper
enough "hints" to be able to represent the XML tree the way you want.


=head1 AUTHOR

Steve Willer, steve@willer.cc

=head1 SEE ALSO

AxKit.

=cut
