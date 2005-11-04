package TestAxKit::11xsp_attr_value_template;

use strict;
use warnings FATAL => 'all';
use Apache::Test;
use Apache::TestUtil;
use constant MP2 => $mod_perl::VERSION >= 1.99;

use Apache::AxKit::Language::XSP;

# Test for attribute value templates

sub handler{
    my $r = shift;
    plan $r, tests => 15;

    my $e = {};
    
    {
        # test no curlies is OK
        my $value = 'value';
        my $result = AxKit::XSP::DefaultHandler::_attr_value_template($e, $value);
        ok($result);
        ok($result !~ /do/);
        print $result, "\n";
        eval $result;
        ok(!$@);
    }
    
    {
        # test 1 curly is OK
        my $value = 'value {{';
        my $result = AxKit::XSP::DefaultHandler::_attr_value_template($e, $value);
        ok($result);
        ok($result !~ /do/);
        print $result, "\n";
        eval $result;
        ok(!$@);
    }
    
    {
        # test expr is OK
        my $value = 'value {time()}';
        my $result = AxKit::XSP::DefaultHandler::_attr_value_template($e, $value);
        ok($result);
        ok($result =~ /do/);
        print $result, "\n";
        eval $result;
        ok(!$@);
    }
    
    {
        # test 2 expr is OK
        my $value = 'value {time()} text {time()}';
        my $result = AxKit::XSP::DefaultHandler::_attr_value_template($e, $value);
        ok($result);
        ok($result =~ /do/);
        print $result, "\n";
        eval $result;
            print $@;
        ok(!$@);
    }

    {
        my $value = '{$cgi->param("foo")}';
        my $result = AxKit::XSP::DefaultHandler::_attr_value_template($e, $value);
        ok($result);
        ok($result =~ /do/);
        my $cgi = bless {}, 'CGI';
        print $result, "\n";
        eval $result;
        print $@;
        ok(!$@);
    }

    return MP2 ? Apache::OK : Apache::Constants::OK; 
}

package CGI;

sub param { '' }
    
1;
    

