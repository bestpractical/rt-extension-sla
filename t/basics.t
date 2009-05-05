#!/usr/bin/perl

use strict;
use warnings;

use RT::Extension::SLA::Test tests => 3, nodb => 1;

use_ok 'RT::Extension::SLA';
use_ok 'RT::Extension::SLA::Report';
use_ok 'RT::Extension::SLA::Summary';

1;
