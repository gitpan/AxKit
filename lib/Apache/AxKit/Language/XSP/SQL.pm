# $Id: SQL.pm,v 1.3 2000/06/10 14:33:36 matt Exp $

package Apache::AxKit::Language::XSP::SQL;
use strict;
use vars qw/@ISA/;
@ISA = ('Apache::AxKit::Language::XSP');

use Apache::AxKit::Language::XSP;
use DBI;

sub register {
	my $class = shift;
	$class->register_taglib('http://www.apache.org/1999/SQL');
}

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
		my $el = $document->createElement($dbparams->{'doc-element'});
		$parent->appendChild($el); $parent = $el;
		
		if ($dbparams->{'skip-rows-attribute'}) {
			my $attr = $document->createAttribute($dbparams->{'skip-rows-attribute'}, $rowid);
			$parent->setAttributeNode($attr);
		}
		if ($dbparams->{'query-attribute'}) {
			my $attr = $document->createAttribute($dbparams->{'query-attribute'}, $query);
			$parent->setAttributeNode($attr);
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
			my $el = $document->createElement($dbparams->{'row-element'});
			$parent->appendChild($el); $parent = $el;
			
			if ($dbparams->{'id-attribute'}) {
				if ($dbparams->{'id-attribute-column'}) {
					my $attr = $document->createAttribute($dbparams->{'id-attribute'}, $hash{$dbparams->{'id-attribute-column'}});
					$parent->setAttributeNode($attr);
				}
				else {
					my $attr = $document->createAttribute($dbparams->{'id-attribute'}, $rowid);
					$parent->setAttributeNode($attr);
				}
			}
		}

		for my $col (@$names) {
			my $el = $document->createElement($col);
			$parent->appendChild($el);
			if (!defined($hash{$col})) {
				if ($dbparams->{'null-indicator'} =~ /^y(es)?$/) {
					my $attr = $document->createAttribute("NULL", "YES");
					$el->setAttributeNode($attr);
				}
				$hash{$col} = '';
			}
			
			if ($dbparams->{'column-format'}{$col}) {
				my $formatter = $dbparams->{'column-format'}{$col}{'class'}->new(@{$dbparams->{'column-format'}{$col}{'parameters'}});
				$hash{$col} = $formatter->format($hash{$col});
			}
			
			my $text = $document->createTextNode($hash{$col});
			$el->appendChild($text);
		}

# 		my $slash_n = $document->createTextNode("\n");
# 		$parent->appendChild($slash_n);
		
		if ($dbparams->{'row-element'}) {
			$parent = $parent->getParentNode();
		}
		
		if ($dbparams->{'max-rows'}) {
			last if $currentrow >= $dbparams->{'max-rows'};
		}
	}
	
	
	if ($dbparams->{'doc-element'}) {
		if ($dbparams->{'count-attribute'}) {
			my $attr = $document->createAttribute($dbparams->{'count-attribute'}, $rowid);
			$parent->setAttributeNode($attr);
		}
		if ($dbparams->{'max-rows-attribute'}) {
			my $attr = $document->createAttribute($dbparams->{'max-rows-attribute'}, $currentrow);
			$parent->setAttributeNode($attr);
		}
		$parent = $parent->getParentNode();
	}
}

sub parse_char {
	my ($e, $text) = @_;
	
	$text =~ s/^\s*//;
	$text =~ s/\s*$//;
	
	return '' unless $text;
	
	$text =~ s/\|/\|\|/g;
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
	elsif ($tag eq 'name' && $e->current_tag() eq 'column-format') {
		return "my \$name = ''";
	}
	elsif ($tag eq 'class' && $e->current_tag() eq 'column-format') {
		return "my \$class = ''";
	}
	elsif ($tag eq 'parameter' && $e->current_tag() eq 'column-format') {
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
				"\$dbparams{'column-format'}{\$name}{'parameters'} = \@params;\n" .
				"} # end column-format\n";
	}
	return ";";
}

1;
__END__
