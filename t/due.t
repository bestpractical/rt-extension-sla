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

diag 'check Due date';
{
    %RT::SLA = (
        Default => '2',
        Levels => {
            '2' => { Resolve => { RealMinutes => 60*2 } },
            '4' => { Resolve => { RealMinutes => 60*4 } },
        },
    );

    my $time = time;

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    my ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx' );
    ok $id, "created ticket #$id";

    is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';

    my $orig_due = $ticket->DueObj->Unix;
    ok $orig_due > 0, 'Due date is set';
    ok $orig_due > $time, 'Due date is in the future';

    $ticket->AddCustomFieldValue( Field => 'SLA', Value => '4' );
    is $ticket->FirstCustomFieldValue('SLA'), '4', 'new sla';

    my $new_due = $ticket->DueObj->Unix;
    ok $new_due > 0, 'Due date is set';
    ok $new_due > $time, 'Due date is in the future';

    is $new_due, $orig_due+2*60*60, 'difference is two hours';
}

