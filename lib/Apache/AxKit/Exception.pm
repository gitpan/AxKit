# $Id: Exception.pm,v 1.13 2000/09/14 20:43:29 matt Exp $

package Apache::AxKit::Exception;
use Error;
use vars qw/@ISA/;
@ISA = ('Error');
use strict;

package Apache::AxKit::Exception::Declined;
use Error;
use vars qw/@ISA/;
@ISA = ('Error');

package Apache::AxKit::Exception::Error;
use Error;
use vars qw/@ISA/;
@ISA = ('Error');

package Apache::AxKit::Exception::OK;
use Error;
use vars qw/@ISA/;
@ISA = ('Error');

package Apache::AxKit::Exception::Retval;
use Error;
use vars qw/@ISA/;
@ISA = ('Error');

1;
