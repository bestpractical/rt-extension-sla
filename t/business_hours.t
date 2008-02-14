#!/usr/bin/perl

use strict;
use warnings;


use Test::More tests => 9;

require 't/utils.pl';

use_ok 'RT';
RT::LoadConfig();
$RT::LogToScreen = $ENV{'TEST_VERBOSE'} ? 'debug': 'warning';

# XXX, TODO 
# we assume the RT's Timezone is UTC now, need a smart way to get over that.
$ENV{'TZ'} = $RT::Timezone = 'GMT';

RT::Init();

use_ok 'RT::Ticket';
use_ok 'RT::Extension::SLA';

use Test::MockTime qw( :all );

diag 'check business hours';
{

    no warnings 'once';
    %RT::ServiceAgreements = (
        Default => 'Sunday',
        Levels  => {
            Sunday => {
                Resolve       => { BusinessMinutes => 60 },
                BusinessHours => 'Sunday',
            },
            Monday => {
                Resolve       => { BusinessMinutes => 60 },
            },
        },
    );

    %RT::ServiceBusinessHours = (
        Sunday => {
            0 => {
                Name  => 'Sunday',
                Start => '9:00',
                End   => '17:00'
            }
        },
        Default => {
            1 => {
                Name  => 'Monday',
                Start => '9:00',
                End   => '17:00'
            },
        },
    );

    set_absolute_time('2007-01-01T00:00:00Z');

    my $ticket = RT::Ticket->new($RT::SystemUser);
    my ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx' );
    ok( $id, "created ticket #$id" );

    is( $ticket->FirstCustomFieldValue('SLA'), 'Sunday', 'default sla' );

    my $start = $ticket->StartsObj->Unix;
    my $due = $ticket->DueObj->Unix;
    is( $start, 1168160400, 'Start date is 2007-01-07T09:00:00Z' );
    is( $due, 1168164000, 'Due date is 2007-01-07T10:00:00Z' );

    $ticket->AddCustomFieldValue( Field => 'SLA', Value => 'Monday' );
    is( $ticket->FirstCustomFieldValue('SLA'), 'Monday', 'new sla' );
    $due = $ticket->DueObj->Unix;
    is( $due, 1167645600, 'Due date is 2007-01-01T10:00:00Z' );
}

