#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 3;

use_ok 'RT::Extension::SLA';
use_ok 'RT::Extension::SLA::Report';
use_ok 'RT::Extension::SLA::Summary';


1;
