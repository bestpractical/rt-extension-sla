
use strict;
use warnings;

package RT::Action::SLA;

use base qw(RT::Extension::SLA RT::Action::Generic);

sub SetDateField {
    my $self = shift;
    my ($type, $value) = (@_);

    my $ticket = $self->TicketObj;

    my $method = $type .'Obj';
    if ( defined $value ) {
        return 1 if $ticket->$method->Unix == $value;
    } else {
        return 1 if $ticket->$method->Unix <= 0;
    }

    my $date = RT::Date->new( $RT::SystemUser );
    $date->Set( Format => 'unix', Value => $value );

    $method = 'Set'. $type;
    my ($status, $msg) = $ticket->$method( $date->ISO );
    unless ( $status ) {
        $RT::Logger->error("Couldn't set $type date: $msg");
        return 0;
    }

    return 1;
}

1;
