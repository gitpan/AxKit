# $Id: CharsetConv.pm,v 1.1 2002/01/13 20:45:11 matts Exp $

package Apache::AxKit::CharsetConv;
# Copyright (c) 2000 Michael Piotrowski
# Originally copied from Text::Iconv

use strict;
use vars qw($VERSION @ISA @EXPORT_OK);

require Exporter;
require DynaLoader;

@ISA = qw(Exporter DynaLoader);

@EXPORT_OK = qw( convert );

$VERSION = '1.0';

bootstrap Apache::AxKit::CharsetConv $VERSION;

1;
__END__

