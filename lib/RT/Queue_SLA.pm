package RT::Extension::QueueSLA;

our $VERSION = '0.01';


=head1 NAME

RT::Extension::QueueSLA - default SLA for Queue

=cut

use RT::Queue;
package RT::Queue;

use strict;
use warnings;


sub SLA {
    my $self = shift;
    my $value = shift;

# TODO: ACL check
#    return undef unless $self->CurrentUserHasRight('XXX');
    my $attr = $self->FirstAttribute('SLA') or return undef;
    return $attr->Content;
}

sub SetSLA {
    my $self = shift;
    my $value = shift;

# TODO: ACL check
#    return ( 0, $self->loc('Permission Denied') )
#        unless $self->CurrentUserHasRight('XXX');

    my ($status, $msg) = $self->SetAttribute(
        Name        => 'SLA',
        Description => 'Default Queue SLA',
        Content     => $value,
    );
    return ($status, $msg) unless $status;
    return ($status, $self->loc('Queue SLA changed'));
}

1;
