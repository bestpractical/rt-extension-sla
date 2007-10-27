#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 46;

require 't/utils.pl';

use_ok 'RT';
RT::LoadConfig();
RT::Init();

use_ok 'RT::Ticket';
use_ok 'RT::Extension::SLA';

diag 'check change of Due date when SLA for a ticket is changed';
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

diag 'when not requestor creates a ticket, we dont set due date';
{
    %RT::SLA = (
        Default => '2',
        Levels => {
            '2' => { Response => { RealMinutes => 60*2 } },
        },
    );

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    my ($id) = $ticket->Create(
        Queue => 'General',
        Subject => 'xxx',
        Requestor => 'user@example.com',
    );
    ok $id, "created ticket #$id";

    is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';

    my $due = $ticket->DueObj->Unix;
    ok $due <= 0, 'Due date is not set';
}

diag 'check that reply to requestors unset due date';
{
    %RT::SLA = (
        Default => '2',
        Levels => {
            '2' => { Response => { RealMinutes => 60*2 } },
        },
    );

    my $root = RT::User->new( $RT::SystemUser );
    $root->LoadByEmail('root@localhost');
    ok $root->id, 'loaded root user';

    # requestor creates
    my $id;
    {
        my $ticket = RT::Ticket->new( $root );
        ($id) = $ticket->Create(
            Queue => 'General',
            Subject => 'xxx',
            Requestor => $root->id,
        );
        ok $id, "created ticket #$id";

        is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';

        my $due = $ticket->DueObj->Unix;
        ok $due > 0, 'Due date is set';
    }

    # non-requestor reply
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";
        $ticket->Correspond( Content => 'we are working on this.' );

        $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        my $due = $ticket->DueObj->Unix;
        ok $due <= 0, 'Due date is not set';
    }

    # non-requestor reply again
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";
        $ticket->Correspond( Content => 'we are still working on this.' );

        $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        my $due = $ticket->DueObj->Unix;
        ok $due <= 0, 'Due date is not set';
    }

    # requestor reply
    my $last_unreplied_due;
    {
        my $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        $ticket->Correspond( Content => 'what\'s going on with my ticket?' );

        $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        my $due = $ticket->DueObj->Unix;
        ok $due > 0, 'Due date is set again';

        $last_unreplied_due = $due;
    }

    # sleep at least one second and requestor replies again
    sleep 1;
    {
        my $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        $ticket->Correspond( Content => 'HEY! Were is my answer?' );

        $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        my $due = $ticket->DueObj->Unix;
        ok $due > 0, 'Due date is still set';
        is $due, $last_unreplied_due, 'due is unchanged';
    }
}

diag 'check that replies dont affect resolve deadlines';
{
    %RT::SLA = (
        Default => '2',
        Levels => {
            '2' => { Resolve => { RealMinutes => 60*2 } },
        },
    );

    my $root = RT::User->new( $RT::SystemUser );
    $root->LoadByEmail('root@localhost');
    ok $root->id, 'loaded root user';

    # requestor creates
    my ($id, $orig_due);
    {
        my $ticket = RT::Ticket->new( $root );
        ($id) = $ticket->Create(
            Queue => 'General',
            Subject => 'xxx',
            Requestor => $root->id,
        );
        ok $id, "created ticket #$id";

        is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';

        $orig_due = $ticket->DueObj->Unix;
        ok $orig_due > 0, 'Due date is set';
    }

    # non-requestor reply
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";
        $ticket->Correspond( Content => 'we are working on this.' );

        $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        my $due = $ticket->DueObj->Unix;
        ok $due > 0, 'Due date is set';
        is $due, $orig_due, 'due is not changed';
    }

    # requestor reply
    {
        my $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        $ticket->Correspond( Content => 'what\'s going on with my ticket?' );

        $ticket = RT::Ticket->new( $root );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";

        my $due = $ticket->DueObj->Unix;
        ok $due > 0, 'Due date is set';
        is $due, $orig_due, 'due is not changed';
    }
}

diag 'check that owner is not treated as requestor';
{
    %RT::SLA = (
        Default => '2',
        Levels => {
            '2' => { Response => { RealMinutes => 60*2 } },
        },
    );

    my $root = RT::User->new( $RT::SystemUser );
    $root->LoadByEmail('root@localhost');
    ok $root->id, 'loaded root user';

    # requestor creates and he is owner
    my $id;
    {
        my $ticket = RT::Ticket->new( $root );
        ($id) = $ticket->Create(
            Queue => 'General',
            Subject => 'xxx',
            Requestor => $root->id,
            Owner => $root->id,
        );
        ok $id, "created ticket #$id";

        is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';
        is $ticket->Owner, $root->id, 'correct owner';

        my $due = $ticket->DueObj->Unix;
        ok $due <= 0, 'Due date is not set';
    }
}

diag 'check that response deadline is left alone when there is no requestor';
{
    %RT::SLA = (
        Default => '2',
        Levels => {
            '2' => { Response => { RealMinutes => 60*2 } },
        },
    );

    my $root = RT::User->new( $RT::SystemUser );
    $root->LoadByEmail('root@localhost');
    ok $root->id, 'loaded root user';

    # create a ticket without requestor
    my $id;
    {
        my $ticket = RT::Ticket->new( $root );
        ($id) = $ticket->Create(
            Queue => 'General',
            Subject => 'xxx',
        );
        ok $id, "created ticket #$id";

        is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';

        my $due = $ticket->DueObj->Unix;
        ok $due <= 0, 'Due date is not set';
    }
}

