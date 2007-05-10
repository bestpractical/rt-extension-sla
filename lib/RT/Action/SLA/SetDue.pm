
use strict;
use warnings;

package RT::Action::SLA::SetDue;

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

    my $time   = $self->TransactionObj->CreatedObj->Unix;

    my $due = $SLAObj->Due( $time, $SLAObj->SLA( $time ) );

    my $current_due = $self->TicketObj->DueObj->Unix;

    if ( $current_due && $current_due > 0 && $current_due < $due ) {
        $RT::Logger->debug("Ticket #". $self->TicketObj->id ." has due earlier than by SLA");
        return 1;
    }

    my $date = RT::Date->new( $RT::SystemUser );
    $date->Set( Format => 'unix', Value => $due );
    $self->TicketObj->SetDue( $date->ISO );

    return 1;
}

1;
