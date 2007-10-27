
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
        $RT::Logger->debug('Ticket #'. $ticket->id .' has no service level defined');
        return 1;
    }

    my $txn = $self->TransactionObj;

    my $last_reply = $self->LastRequestorsEffectiveAct;
    $RT::Logger->debug('Last effective requestors\' reply to ticket #'. $ticket->id .' is txn #'. $last_reply->id )
        if $last_reply;

    my $response_due;
    $response_due = $self->Due(
        Level => $level,
        Type => 'Response',
        Time => $last_reply->CreatedObj->Unix,
    ) if $last_reply;

    my $resolve_due = $self->Due(
        Level => $level,
        Type => 'Resolve',
        Time => $ticket->CreatedObj->Unix,
    );

    my $due;
    $due = $response_due if defined $response_due;
    $due = $resolve_due unless defined $due;
    $due = $resolve_due if defined $due && defined $resolve_due && $resolve_due < $due;

    if ( defined $due ) {
        return 1 if $ticket->DueObj->Unix == $due;
    } else {
        return 1 if $ticket->DueObj->Unix <= 0;
    }

    my $date = RT::Date->new( $RT::SystemUser );
    $date->Set( Format => 'unix', Value => $due );
    my ($status, $msg) = $self->TicketObj->SetDue( $date->ISO );
    unless ( $status ) {
        $RT::Logger->error("Couldn't set due date: $msg");
        return 0;
    }

    return 1;
}

sub IsRequestorsAct {
    my $self = shift;
    my $txn = shift || $self->TransactionObj;

    my $actor = $txn->CreatorObj->PrincipalObj;

    # owner is always treated as non-requestor
    return 0 if $actor->id == $self->TicketObj->Owner;

    return $self->TicketObj->Requestors->HasMemberRecursively( $actor )? 1 : 0;
}

sub LastRequestorsEffectiveAct {
    my $self = shift;

    my $txns = $self->TicketObj->Transactions;
    $txns->Limit( FIELD => 'Type', VALUE => 'Correspond' );
    $txns->Limit( FIELD => 'Type', VALUE => 'Create' );
    $txns->OrderByCols(
        { FIELD => 'Created', ORDER => 'DESC' },
        { FIELD => 'id', ORDER => 'DESC' },
    );

    my $res;
    while ( my $txn = $txns->Next ) {
        return $res unless $self->IsRequestorsAct( $txn );
        $res = $txn;
    }
    return $res;
}

1;
