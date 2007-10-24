
use strict;
use warnings;

package RT::Condition::SLA;
use base qw(RT::Extension::SLA RT::Condition::Generic);

=head1 SLAIsApplied

=cut

sub SLAIsApplied { return 1 }

=head1 IsCustomFieldChange

=cut

sub IsCustomFieldChange {
    my $self = shift;
    my $cf_name = shift;

    my $txn = $self->TransactionObj;
    
    return 0 unless $txn->Type eq 'CustomField';

    my $cf = $self->TicketObj->QueueObj->CustomField( $cf_name );
    unless ( $cf->id ) {
        $RT::Logger->error("Couldn't load the '$cf_name' field");
        return 0;
    }
    return 0 unless $cf->id == $txn->Field;
    return 1;
}

1;
