use strict;
use warnings;

package RT::Action::SLA_SetStarts;

use base qw(RT::Action::SLA);

=head1 NAME

RT::Action::SLA_SetStarts - set starts date field of a ticket according to SLA

=head1 DESCRIPTION

Look up the SLA of the ticket and set the Starts date accordingly. Nothing happens
if the ticket has no SLA defined.

Note that this action doesn't check if Starts field is set already, so you can
use it to set the field in a force mode or can protect field using a condition
that checks value of Starts.

=cut

sub Prepare { return 1 }

sub Commit {
    my $self = shift;

    my $ticket = $self->TicketObj;

# XXX I encountered a 'Couldn't set starts date: That is already the current 
# value' warning if I didn't test it here. wierd
    return 0 if $ticket->StartsObj->Unix > 0;

    my $level = $ticket->FirstCustomFieldValue('SLA');
    unless ( $level ) {
        $RT::Logger->debug('Ticket #'. $ticket->id .' has no service level defined, skip setting Starts');
        return 1;
    }

    my $SLA = $self->SLA(Level => $level);
    my $starts = $SLA->Starts( $self->TransactionObj->CreatedObj->Unix, $level );

    my $date = RT::Date->new($RT::SystemUser);
    $date->Set( Format => 'unix', Value => $starts );
    my ($status, $msg) = $ticket->SetStarts( $date->ISO );
    unless ( $status ) {
        $RT::Logger->error("Couldn't set starts date: $msg");
        return 0;
    }

    return 1;
}

1;
