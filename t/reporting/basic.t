#!/usr/bin/perl

use strict;
use warnings;
use Test::MockTime qw(set_fixed_time);

use Test::More tests => 72;

require 't/utils.pl';

use_ok 'RT';
RT::LoadConfig();
$RT::LogToScreen = $ENV{'TEST_VERBOSE'} ? 'debug': 'warning';
RT::Init();

use_ok 'RT::Ticket';
use_ok 'RT::Extension::SLA::Report';

my $root = RT::User->new( $RT::SystemUser );
$root->LoadByEmail('root@localhost');
ok $root->id, 'loaded root user';

diag '';
{
    %RT::ServiceAgreements = (
        Default => '2',
        Levels => {
            '2' => { Response => { RealMinutes => 60*2 } },
        },
    );

    set_fixed_time('2009-05-05T10:00:00Z');

    my $time = time;

    # requestor creates
    my $id;
    {
        my $ticket = RT::Ticket->new( $root );
        ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx', Requestor => $root->id );
        ok $id, "created ticket #$id";

        is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';

        my $due = $ticket->DueObj->Unix;
        is $due, $time + 2*60*60, 'Due date is two hours from "now"';
    }

    set_fixed_time('2009-05-05T11:00:00Z');

    # non-requestor reply
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";
        $ticket->Correspond( Content => 'we are working on this.' );
    }

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load( $id );
    my $report = RT::Extension::SLA::Report->new( Ticket => $ticket )->Run;
    is_deeply $report->Stats,
        [ {type => 'Response', owner => $RT::Nobody->id, owner_act => 0, failed => 0, shift => -3600 } ],
        'correct stats'
    ;
}


diag '';
{
    %RT::ServiceAgreements = (
        Default => '2',
        Levels => {
            '2' => { Response => { RealMinutes => 60*2 } },
        },
    );

    set_fixed_time('2009-05-05T10:00:00Z');

    my $time = time;

    # requestor creates
    my $id;
    {
        my $ticket = RT::Ticket->new( $root );
        ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx', Requestor => $root->id );
        ok $id, "created ticket #$id";

        is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';

        my $due = $ticket->DueObj->Unix;
        is $due, $time + 2*60*60, 'Due date is two hours from "now"';
    }

    set_fixed_time('2009-05-05T11:00:00Z');

    # non-requestor reply
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";
        $ticket->Correspond( Content => 'we are working on this.' );
    }

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load( $id );
    my $report = RT::Extension::SLA::Report->new( Ticket => $ticket )->Run;
    is_deeply $report->Stats,
        [ {type => 'Response', owner => $RT::Nobody->id, owner_act => 0, failed => 0, shift => -3600 } ],
        'correct stats'
    ;
}


