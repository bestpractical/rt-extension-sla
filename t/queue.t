#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 9;

require 't/utils.pl';

use_ok 'RT';
RT::LoadConfig();
RT::Init();

use_ok 'RT::Ticket';
use_ok 'RT::Extension::SLA';

use Test::MockTime qw( :all );


my $queue = RT::Queue->new($RT::SystemUser);
$queue->Load('General');

my $queue_sla = RT::Attribute->new($RT::SystemUser);

diag 'check set of Due date with Queue default SLA';
{

    # add default SLA for 'General';
    my ($id) = $queue_sla->Create(
        Name        => 'SLA',
        Description => 'Default Queue SLA',
        Content     => '4',
        Object      => $queue
    );

    ok( $id, 'Created SLA Attribute for General' );

    %RT::SLA = (
        Default => '2',
        Levels  => {
            '2' => { Resolve => { RealMinutes => 60 * 2 } },
            '4' => { StartImmediately => 1, Resolve => { RealMinutes => 60 * 4 } },
        },
    );


    set_absolute_time('2007-01-01T00:00:00Z');
    my $time = time;
    my $ticket = RT::Ticket->new($RT::SystemUser);
    ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx' );
    ok( $id, "created ticket #$id" );

    is $ticket->FirstCustomFieldValue('SLA'), '4', 'default sla';

    my $start = $ticket->StartsObj->Unix;
    my $due = $ticket->DueObj->Unix;
    is( $start, $time, 'Start Date is right' );
    is( $due, $time+3600*4, 'Due date is right');

    my ( $status, $message ) = $queue->DeleteAttribute('SLA');
    ok( $status, $message );
}

