# $Id: SQL.pm,v 1.7 2001/01/13 18:59:58 matt Exp $

package Apache::AxKit::Language::XSP::SQL;
use strict;
use vars qw/@ISA $NS/;
@ISA = ('Apache::AxKit::Language::XSP');

$NS = 'http://www.apache.org/1999/SQL';

use Apache::AxKit::Language::XSP;
use DBI;

my @dbparams = qw(
		username
		password
		doc-element
		row-element
		null-indicator
		tag-case
		id-attribute
		id-attribute-column
		max-rows
		skip-rows
		count-attribute
		query-attribute
		skip-rows-attribute
		max-rows-attribute
		update-rows-attribute
		namespace
	);

my $dbparam_regex = '^(' . join('|', @dbparams) . ')$';

# What comes below is a string, even though it doesn't look like one...
sub execute_query {
	my ($document, $parent, $driver, $dbiline, $query, $dbparams) = @_;
	my $dbh = DBI->connect("dbi:$driver:$dbiline", 
			$dbparams->{'username'},
			$dbparams->{'password'});
	my $sth = $dbh->prepare($query);
	if ($driver eq 'Oracle') {
		my $ignore = $sth->{NAME}; # for Oracle 8.0.5 bug?
	}
	$sth->execute();

	my $rowid = 0;
	
	if ($dbparams->{'skip-rows'}) {
		1 while ($rowid++ < $dbparams->{'skip-rows'} && $sth->fetchrow_arrayref());
	}	

	if ($dbparams->{'doc-element'}) {
		my $el = $XML::XPath::Node::Element->new($dbparams->{'doc-element'});
		$parent->appendChild($el); $parent = $el;
		
		if ($dbparams->{'skip-rows-attribute'}) {
			my $attr = XML::Node::Attribute->new($dbparams->{'skip-rows-attribute'}, $rowid);
			$parent->appendAttribute($attr);
		}
		if ($dbparams->{'query-attribute'}) {
			my $attr = XML::Node::Attribute->new($dbparams->{'query-attribute'}, $query);
			$parent->appendAttribute($attr);
		}
	}

	$dbparams->{'tag-case'} ||= 'preserve';
	my $names;
	if ($dbparams->{'tag-case'} eq 'preserve') {
		$names = $sth->{NAME};
	}
	elsif ($dbparams->{'tag-case'} eq 'lower') {
		$names = $sth->{NAME_lc};
	}
	elsif ($dbparams->{'tag-case'} eq 'upper') {
		$names = $sth->{NAME_uc};
	}
	
	my $currentrow = 0;
	while (my $row = $sth->fetchrow_arrayref()) {
		$currentrow++;
		$rowid++;
		
		my %hash;
		
		@hash{ @$names } = @$row;
		
		if ($dbparams->{'row-element'}) {
			my $el = XML::XPath::Node::Element->new($dbparams->{'row-element'});
			$parent->appendChild($el); $parent = $el;
			
			if ($dbparams->{'id-attribute'}) {
				if ($dbparams->{'id-attribute-column'}) {
					my $attr = XML::XPath::Node::Attribute->new($dbparams->{'id-attribute'},
					$hash{$dbparams->{'id-attribute-column'}});
					$parent->appendAttribute($attr);
				}
				else {
					my $attr = XML::XPath::Node::Attribute->new($dbparams->{'id-attribute'}, $rowid);
					$parent->appendAttribute($attr);
				}
			}
		}

		for my $col (@$names) {
			my $el = XML::XPath::Node::Element->new($col);
			$parent->appendChild($el);
			if (!defined($hash{$col})) {
				if ($dbparams->{'null-indicator'} =~ /^y(es)?$/) {
					my $attr = XML::XPath::Node::Attribute->new("NULL", "YES");
					$el->appendAttribute($attr);
				}
				$hash{$col} = '';
			}
			
			if ($dbparams->{'column-format'}{$col}) {
				my $formatter = $dbparams->{'column-format'}{$col}{'class'}->new(@{$dbparams->{'column-format'}{$col}{'parameters'}});
				$hash{$col} = $formatter->format($hash{$col});
			}
			
			my $text = XML::XPath::Node::Text->new($hash{$col});
			$el->appendChild($text);
		}

		
		if ($dbparams->{'row-element'}) {
			$parent = $parent->getParentNode();
		}
		
		if ($dbparams->{'max-rows'}) {
			last if $currentrow >= $dbparams->{'max-rows'};
		}
	}
	
	
	if ($dbparams->{'doc-element'}) {
		if ($dbparams->{'count-attribute'}) {
			my $attr = XML::XPath::Node::Attribute->new($dbparams->{'count-attribute'}, $rowid);
			$parent->appendAttribute($attr);
		}
		if ($dbparams->{'max-rows-attribute'}) {
			my $attr = XML::XPath::Node::Attribute->new($dbparams->{'max-rows-attribute'}, $currentrow);
			$parent->appendAttribute($attr);
		}
		$parent = $parent->getParentNode();
	}
}

sub parse_char {
	my ($e, $text) = @_;
	
	$text =~ s/^\s*//;
	$text =~ s/\s*$//;
	
	return '' unless $text;
	
	$text =~ s/\|/\\\|/g;
	return ". q|$text|";
}

sub parse_start {
	my ($e, $tag, %attribs) = @_;

# 	warn "dbparam regex: $dbparam_regex\n";
# 	warn "Checking: $tag\n";
	
	if ($tag eq 'execute-query') {
		return "{ # query section - new scope\nmy \%dbparams;\nuse DBI;\n";
	}
	elsif ($tag eq 'driver') {
		return "my \$driver = ''";
	}
	elsif ($tag eq 'dburl') {
		return "my \$dbiline = ''";
	}
	elsif ($tag eq 'query') {
		return "my \$query = ''";
	}
	elsif ($tag =~ /$dbparam_regex/o) {
		return "\$dbparams{'$tag'} = ''";
	}
	elsif ($tag eq 'column-format') {
		return "{ # new column format\nmy \@params;\n";
	}
	elsif ($tag eq 'name' && $e->current_element() eq 'column-format') {
		return "my \$name = ''";
	}
	elsif ($tag eq 'class' && $e->current_element() eq 'column-format') {
		return "my \$class = ''";
	}
	elsif ($tag eq 'parameter' && $e->current_element() eq 'column-format') {
		return "push \@params, ''";
	}
}

sub parse_end {
	my ($e, $tag) = @_;
	
	if ($tag eq 'execute-query') {
		return "Apache::AxKit::Language::XSP::SQL::execute_query(\n" .
				'$document, $parent, $driver, $dbiline, $query, \%dbparams' .
				");\n} # end query\n";
	}
	elsif ($tag eq 'column-format') {
		return "\$dbparams{'column-format'}{\$name}{'class'} = \$class;\n" .
				"\$dbparams{'column-format'}{\$name}{'parameters'} = \\\@params;\n" .
				"} # end column-format\n";
	}
	return ";";
}

1;
__END__
