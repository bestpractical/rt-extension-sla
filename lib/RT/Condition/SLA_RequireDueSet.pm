use strict;
use warnings;

package RT::Condition::SLA_RequireDueSet;

use base qw(RT::Condition::SLA);

=head1 NAME

RT::Condition::SLA_RequireDueSet - checks if Due date require update

=head1 DESCRIPTION

Checks if Due date require update. This should be done when we create
a ticket and it has service level value or when we set serveice level.

=cut

sub IsApplicable {
    my $self = shift;
    return 0 unless $self->SLAIsApplied;

    if ( $self->TransactionObj->Type eq 'Create' ) {
        return 1 if $self->TicketObj->FirstCustomFieldValue('SLA');
    } elsif ( $self->TransactionObj->Type eq 'Create' ) {
        return 1 if $self->IsCustomFieldChange('SLA');
    }
    return 0;
}

1;
