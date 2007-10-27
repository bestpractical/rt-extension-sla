#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 10;

require 't/utils.pl';

use_ok 'RT';
RT::LoadConfig();
RT::Init();

use_ok 'RT::Ticket';
use_ok 'RT::Extension::SLA';

diag 'check business hours';
{

    %RT::SLA = (
        Default => 'Sunday',
        Levels  => {
            Sunday => {
                Resolve       => { BusinessMinutes => 60 },
                BusinessHours => 'Sunday',
            },
            Monday => {
                Resolve       => { BusinessMinutes => 60 },
                BusinessHours => 'Default',
            },
        },
    );

    %RT::BusinessHours = (
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

    my $time = time;

    my $ticket = RT::Ticket->new($RT::SystemUser);
    my ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx' );
    ok( $id, "created ticket #$id" );

    is( $ticket->FirstCustomFieldValue('SLA'), 'Sunday', 'default sla' );

    my $due = $ticket->DueObj->Unix;
    ok( $due > 0, 'Due date is set' );
    ok( $due > $time, 'Due date is in the future');

    my ( undef,$min,$hour,$mday,$mon,$year,$wday ) = gmtime( $due );
    is( $wday, 0, 'original due time is on Sunday' );

    $ticket->AddCustomFieldValue( Field => 'SLA', Value => 'Monday' );
    is( $ticket->FirstCustomFieldValue('SLA'), 'Monday', 'new sla' );
    $due = $ticket->DueObj->Unix;
    ( undef,$min,$hour,$mday,$mon,$year,$wday ) = gmtime( $due );
    is( $wday, 1, 'new due time is on Monday' );
}

