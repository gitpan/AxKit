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

# $Id: CharsetConv.pm,v 1.2 2005/07/14 18:43:33 matts Exp $

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

