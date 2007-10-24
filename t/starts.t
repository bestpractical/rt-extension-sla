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

my $bhours = RT::Extension::SLA->BusinessHours;

diag 'check Starts date';
{
    %RT::SLA = (
        Default => 'start',
        Levels => {
            'starts' => {
                Response => 2*60,
                Resolve => 7*60*24,
            },
        },
    );

    my $time = time;

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    my ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx' );
    ok $id, "created ticket #$id";

    my $starts = $ticket->StartsObj->Unix;
    ok $starts > 0, 'Starts date is set';
    if ( $bhours->first_after($time) == $time ) {
        # in hours
        ok $starts - $time < 5, 'Starts is quite correct';
    } else {
        ok $starts - $time > 5 , 'Starts is quite correct';
    }
}

diag 'check Starts date with StartImmediately enabled';
{
    %RT::SLA = (
        Default => 'start immediately',
        Levels => {
            'start immediately' => {
                StartImmediately => 1,
                Response => 2*60,
                Resolve => 7*60*24,
            },
        },
    );
    my $time = time;

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    my ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx' );
    ok $id, "created ticket #$id";

    ok $ticket->StartsObj->Unix > 0, 'Starts date is set';
    ok abs($starts - $time) < 5, 'Starts is quite correct';
}

