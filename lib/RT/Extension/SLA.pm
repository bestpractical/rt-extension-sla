use strict;
use warnings;

package RT::Extension::SLA;

=head1 NAME

RT::Extension::SLA - Service Level Agreements

=head1 DESCRIPTION

=head2 v0.01

* we have one Business::Hours object
* several agreement levels
* options:
** InHoursDefault - default service level ticket created during business hours, but only if level hasn't been set
** OutOfHoursDefault - default service level ticket created during business hours, but only if level hasn't been set
** Levels - each level has definition of agreements for Response and Resolve
*** If you set a requirement for response then we set due date on create or as soon as user replies to some a in the feature, so due date means deadline for reply, as soon as somebody who is not a requestor replies we unset due
*** if you set a requirement for resolve then we set due date on create to a point in the feature, so due date defines deadline for ticket resolving
*** we should support situations when restrictions defined for reply and resolve, then we move due date according to reply deadlines, however when we reach resolve deadline we stop moving.

*** each requirement is described by Business or Real time in terms of L<Business::SLA> module.

so we'll have something like:
%SLA => (
    InHoursDefault => 'one real hour for reply',
    OutOfHoursDefault => 'two business hours for reply',
    Levels => {
        'one real hour for reply' => { Response => { RealMinutes => 60 } },
        'two business hours for reply' => { Response => { BusinessMinutes => 60*2 } },
        '8 business hours for resolve' => { Resolve => { BusinessMinutes => 60*8 } },
        'two b-hours for reply and 3 real days for resolve' => {
            Response => { BusinessMinutes => 60*2 },
            Resolve  => { RealMinutes     => 60*24*3 },
        },
    },
);

=head v0.02

* changing service levels of a ticket in the middle of its live

=head random thoughts

* Defining OutOfHours/InHours defaults sounds not that usefull for response deadlines as for resolve. For resolve I can find an example in real life: I order something in an online shop, the order comes into system when business day ended, so delivery(resolve) deadline is two business days, but in the case of in hours submission of the order they deliver during one business day. For reply deadlines I cannot imagine a situation when different InHours/OutOfHours levels are useful.


=head v0.later

* default SLA for queues
* add support for multiple b-hours definitions, this could be very helpfull when you have 24/7 mixed with 8/5 and/or something like 8/5+4/2 for different tickets(by requestor, queue or something else). So people would be able to handle tickets in the right order using Due dates.

=cut

sub BusinessHours {
    my $self = shift;
    require Business::Hours;
    return new Business::Hours;
}

=head2 Agreements [ Type => 'Response' ]

Returns an instance of L<Business::SLA> class filled with
service levels for particular Type.

Now we take list of agreements and its description from the
RT config.

By default Type is 'Response'. 'Resolve' is another type
we support.

=cut

sub Agreements {
    my $self = shift;
    my %args = ( Type => 'Response', @_ );

    my $class = $RT::SLA{'Module'} || 'Business::SLA';
    eval "require $class" or die $@;
    my $SLA = $class->new(
        BusinessHours     => $self->BusinessHours,
        InHoursDefault    => $RT::SLA{'InHoursDefault'},
        OutOfHoursDefault => $RT::SLA{'OutOfHoursDefault'},
    );

    my $levels = $RT::SLA{'Levels'};
    foreach my $level ( keys %$levels ) {
        my $description = $levels->{ $level }{ $args{'Type'} };
        unless ( defined $description ) {
            $RT::Logger->warning("No $args{'Type'} agreement for $level");
            next;
        }

        if ( ref $description ) {
            $SLA->Add( $level => %$description );
        } elsif ( $levels->{ $level } =~ /^\d+$/ ) {
            $SLA->Add( $level => BusinessMinutes => $description );
        } else {
            $RT::Logger->error("Levels of SLA should be either number or hash ref");
        }
    }

    return $SLA;
}

sub GetCustomField {
    my $self = shift;
    my %args = (Ticket => undef, CustomField => 'SLA', @_);
    unless ( $args{'Ticket'} ) {
        $args{'Ticket'} = $self->TicketObj if $self->can('TicketObj');
    }
    unless ( $args{'Ticket'} ) {
        return RT::CustomField->new( $RT::SystemUser );
    }
    return $args{'Ticket'}->QueueObj->CustomField( $args{'CustomField'} );
}

=head1 DESIGN

=head2 Classes

Actions are subclasses of RT::Action::SLA class that is subclass of
RT::Extension::SLA and RT::Action::Generic classes.

Conditions are subclasses of RT::Condition::SLA class that is subclass of
RT::Extension::SLA and RT::Condition::Generic classes.

RT::Extension::SLA is a base class for all classes in the extension,
it provides access to config, generates B::Hours and B::SLA objects, and
other things useful for whole extension. As this class is the base for
all actions and conditions then we must avoid adding methods which overload
methods in 'RT::{Condition,Action}::Generic' modules.

=cut

1;
