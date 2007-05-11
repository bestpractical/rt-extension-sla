use strict;
use warnings;

package RT::Action::SLA_SetStarts;

use base qw(RT::Action::SLA);

=head2 Prepare

Always run this action.

=cut

sub Prepare { return 1 }

=head2 Commit

Look up the SLA and set the Starts date accordingly unless it's allready set.

=cut

sub Commit {
    my $self = shift;

    my $ticket = $self->TicketObj;

    # get out of here if have date set
    return 1 $ticket->StartsObj->Unix > 0;

    # XXX: we must use SLA to set starts
    my $bizhours = RT::Estension::SLA::BusinessHours();

    my $starts = $bizhours->first_after(
        $self->TransactionObj->CreatedObj->Unix
    );

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
