#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 10;

require 't/utils.pl';

use_ok 'RT';
RT::LoadConfig();
RT::Init();

use_ok 'RT::Ticket';

{
    %RT::SLA = (
        Default => 'start immediately',
        Levels => {
            'start immediately' => {
                StartImmediately => 1,
                Response => { RealMinutes => 2*60 },
            },
        },
    );

    my $ticket = RT::Ticket->new( $RT::SystemUser );
    my ($id) = $ticket->Create( Queue => 'General', Subject => 'xxx' );
    ok $id, "created ticket #$id";

    ok $ticket->StartsObj->Unix > 0, 'Starts date is set';
}

