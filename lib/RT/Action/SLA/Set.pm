
use strict;
use warnings;

package RT::Action::SLA::Set;

use base qw(RT::Action::SLA);

=head1 NAME

RT::Action::SLA::Set - set default SLA value if it's not set

=cut

sub Prepare { return 1 }
sub Commit {
    my $self = shift;

    return 1 if $self->TicketObj->FirstCustomFieldValue('SLA');

    my $cf = RT::CustomField->new( $self->CurrentUser );
    $cf->LoadByNameAndQueue( Queue => $self->TicketObj->Queue, Name => 'SLA' );
    unless ( $cf->id ) {
        $RT::Logger->warn("SLA scrip applied to a queue that has no SLA CF");
        return 1;
    }

    my $SLAObj = $self->SLA;
    my $sla = $SLAObj->SLA( $self->TransactionObj->CreatedObj->Unix );
    unless ( $sla ) {
        $RT::Logger->error("No default SLA for in hours or/and out of hours time");
        return 0;
    }

    my ($status, $msg) = $self->TicketObj->AddCustomFieldValue(
        Field => $cf->id,
        Value => $sla,
    );
    unless ( $status ) {
        $RT::Logger->error("Couldn't set SLA: $msg");
        return 0;
    }

    return 1;
};

1;
