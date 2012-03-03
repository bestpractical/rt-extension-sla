#!/usr/bin/perl

use strict;
use warnings;
use Test::MockTime qw(set_fixed_time);

use RT::Extension::SLA::Test tests => 17;

use_ok 'RT::Extension::SLA::Report';

use Data::Dumper;

my $root = RT::User->new( $RT::SystemUser );
$root->LoadByEmail('root@localhost');
ok $root->id, 'loaded root user';

my $hour = 60*60;

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
        ($id, undef, my $msg) = $ticket->Create( Queue => 'General', Subject => 'xxx', Requestor => $root->id );
        ok $id, "created ticket #$id" or diag "error: $msg";

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
    test_ticket_report(
        $ticket,
        [
          {
            'previous' => undef,
            'owner' => 6,
            'actor_role' => 'requestor',
            'transaction' => '24',
            'type' => 'Create',
            'acted_on' => 1241517600,
            'actor' => '12',
          },
          {
            'owner' => 6,
            'deadline' => 1241524800,
            'difference' => - $hour,
            'actor' => '1',
            'previous' => -1,
            'to' => -1,
            'time' => $hour,
            'actor_role' => 'other',
            'transaction' => '29',
            'type' => 'Response',
            'acted_on' => 1241521200
          }
        ],
        {
          'messages' => { '*' => 2, 'other' => 1, 'requestor' => 1, },
          'Response' => {
            'other' => {
                'count' => 1,
                'min' => $hour, 'avg' => $hour, 'max' => $hour,
                'sum' => $hour,
            },
            '*' => {
                'count' => 1,
                'min' => $hour, 'avg' => $hour, 'max' => $hour,
                'sum' => $hour,
            },
          },
          'FirstResponse' => {
                'count' => 1,
                'min' => $hour, 'avg' => $hour, 'max' => $hour,
                'sum' => $hour,
          },
          'deadlines' => { 'passed' => 1, failed => undef },
        },
    );
}

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
        ($id, undef, my $msg) = $ticket->Create( Queue => 'General', Subject => 'xxx', Requestor => $root->id );
        ok $id, "created ticket #$id" or diag "error: $msg";

        is $ticket->FirstCustomFieldValue('SLA'), '2', 'default sla';

        my $due = $ticket->DueObj->Unix;
        is $due, $time + 2*60*60, 'Due date is two hours from "now"';
    }

    set_fixed_time('2009-05-05T13:00:00Z');

    # non-requestor reply
    {
        my $ticket = RT::Ticket->new( $RT::SystemUser );
        $ticket->Load( $id );
        ok $ticket->id, "loaded ticket #$id";
        $ticket->Correspond( Content => 'we are working on this.' );
    }

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    $ticket->Load( $id );
    test_ticket_report(
        $ticket,
        [
          {
            'previous' => undef,
            'owner' => 6,
            'actor_role' => 'requestor',
            'transaction' => '37',
            'type' => 'Create',
            'acted_on' => 1241517600,
            'actor' => '12',
          },
          {
            'owner' => 6,
            'deadline' => 1241524800,
            'difference' => $hour,
            'actor' => '1',
            'previous' => -1,
            'to' => -1,
            'time' => 3*$hour,
            'actor_role' => 'other',
            'transaction' => '42',
            'type' => 'Response',
            'acted_on' => 1241528400,
          }
        ],
        {
          'messages' => { '*' => 2, 'other' => 1, 'requestor' => 1, },
          'Response' => {
            'other' => {
                'count' => 1,
                'min' => 3*$hour, 'avg' => 3*$hour, 'max' => 3*$hour,
                'sum' => 3*$hour,
            },
            '*' => {
                'count' => 1,
                'min' => 3*$hour, 'avg' => 3*$hour, 'max' => 3*$hour,
                'sum' => 3*$hour,
            },
          },
          'FirstResponse' => {
                'count' => 1,
                'min' => 3*$hour, 'avg' => 3*$hour, 'max' => 3*$hour,
                'sum' => 3*$hour,
          },
          'deadlines' => { failed => {
                'count' => 1,
                'min' => $hour, 'avg' => $hour, 'max' => $hour,
                'sum' => $hour,
          } },
        },
    );
}

sub test_ticket_report {
    my ($ticket, $exp_report, $exp_summary) = @_;

    for ( my $i = 0; $i < @$exp_report; $i++ ) {
        foreach ( grep $exp_report->[$i]{$_}, qw(to previous) ) {
            $exp_report->[$i]{$_} = $exp_report->[ $i + $exp_report->[$i]{$_} ];
        }
    }

    my $report = RT::Extension::SLA::Report->new( Ticket => $ticket )->Run;
    is_deeply( $report->Stats, $exp_report, 'correct stats' )
        or diag Dumper( $report->Stats );

    my $summary = $report->Summary;
    is_deeply( $summary->Result, $exp_summary, 'correct summary' )
        or diag Dumper( $summary->Result );
}

