
use strict;
use warnings;

package RT::Action::SLA_SetDue;

use base qw(RT::Action::SLA);

=head2 Prepare

Checks if the ticket has service level defined.

=cut

sub Prepare {
    my $self = shift;

    unless ( $self->TicketObj->FirstCustomFieldValue('SLA') ) {
        $RT::Logger->error('SLA::SetDue scrip has been applied to ticket #'
            . $self->TicketObj->id . ' that has no SLA defined');
        return 0;
    }

    return 1;
}

=head2 Commit

Set the Due date accordingly to SLA.

=cut

sub Commit {
    my $self = shift;

    my $ticket = $self->TicketObj;

    my $level = $ticket->FirstCustomFieldValue('SLA');
    unless ( $level ) {
        $RT::Logger->debug('Ticket #'. $ticket->id .' has no service level defined, skip setting Starts');
        return 1;
    }

    my $due = $self->EarliestDue( $level );

    my $date = RT::Date->new( $RT::SystemUser );
    $date->Set( Format => 'unix', Value => $due );
    my ($status, $msg) = $self->TicketObj->SetDue( $date->ISO );
    unless ( $status ) {
        $RT::Logger->error("Couldn't set due date: $msg");
        return 0;
    }

    return 1;
}

sub EarliestDue {
    my $self = shift;
    my $level = shift;

    my $response_time = $self->TransactionObj->CreatedObj->Unix;
    my $response_due = $self->Agreements(
        Type => 'Response', Time => $response_time
    )->Due( $response_time, $level );

    my $create_time = $self->TicketObj->CreatedObj->Unix;
    my $resolve_due  = $self->Agreements(
        Type => 'Resolve', Time => $create_time
    )->Due( $create_time, $level );

    return $resolve_due < $response_due? $resolve_due : $response_due;
}

1;
