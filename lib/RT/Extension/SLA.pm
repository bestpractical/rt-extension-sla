use strict;
use warnings;

package RT::Extension::SLA;

=head1 NAME

RT::Extension::SLA - Service Level Agreements

=head1 DESCRIPTION

=head1 SPECIFICATION

To enable service level agreements for a queue administrtor
should create and apply SLA custom field. To define different
levels for different queues he CAN create several CFs with
the same name and different set of values. All CFs MUST be
of the same 'select one value' type.

Values of the CF(s) define service levels.

Each service level can be described using several options:
StartImmediately, Resolve and Response.

=head2 StartImmediately (boolean, false)

By default when ticket is created Starts date is set to
first business minute after time of creation. In other
words if ticket is created during business hours then
Starts will be equal to Created time, otherwise it'll
be beginning of the next business day.

However, if you provide 24/7 support then you most
probably would be interested in Starts to be always equal
to Created time. In this case you can set option
StartImmediately to true value.

Example:
    '24/7' => {
        StartImmediately => 1,
        Response => { RealMinutes => 30 },
    },
    'standard' => {
        StartImmediately => 0, # can be ommited as it's default
        Response => { BusinessMinutes => 2*60 },
    },

=head2 Resolve and Response (interval, no defaults)

These two options define deadlines for resolve of a ticket
and reply to customer(requestors) questions accordingly.

You can define them using real time, business or both. Read more
about the latter below.

The Due date field is used to store calculated deadlines.

=head3 Resolve

Defines deadline when a ticket should be resolved. This option is
quite simple and straightforward when used without L</Response>.

Examples:
    # 8 business hours
    'simple' => { Resolve => 60*8 },
    ...
    # one real week
    'hard' => { Resolve => { RealMinutes => 60*24*7 } },


=head3 Response

In many companies providing support service(s) resolve time
of a ticket is less important than time of response to requestors
from stuff members.

You can use Response option to define such deadlines. When you're
using this option Due time "flips" when requestors and non-requestors
reply to a ticket. We set Due date when a ticket's created, unset
when non-requestor replies... until ticket is closed when ticket's
due date is also unset.

B<NOTE> that behaviour changes when Resolve and Response options
are combined, read below.

=head3 Using both Resolve and Response in the same level

Resolve and Response can be combined. In such case due date is set
according to the earliest of two deadlines and never is dropped to
not set. When non-requestor replies to a ticket, due date is changed to
Response deadline, as well this happens when a ticket is closed. So
all the time due date is defined.

If a ticket met its Resolve deadline then due date stops "fliping" and
is freezed and the ticket becomes overdue.

Example:

    'standard delivery' => {
        Response => { RealMinutes => 60*1  }, # one hour
        Resolve  => { RealMinutes => 60*24 }, # 24 real hours
    },

A client orders a good and due date of the orderis set to the next one
hour, you have this hour to process the order and write a reply.
As soon as goods are delivered you resolve tickets and usually meet
Resolve deadline, but if you don't resolve or user replies then most
probably there are problems with deliver or the good. And if after
a week you keep replying to the client and always meeting one hour
response deadline that doesn't mean the ticket is not over due.
Due date was frozen 24 hours after creation of the order.

=head3 Using business and real time in one option

It's quite rare situation when people need it, but we've decided
that deadline described using both types of time then business
is applied first and then real time. For example:

    'delivery' => {
        Resolve => { BusinessMinutes => 1, RealMinutes => 60*8 },
    },
    'fast delivery' {
        StartImmediately => 1,
        Resolve => { RealMinutes => 60*8 },
    },

For delivery requests which come into the system during business
hours these levels define the same deadlines, otherwise the first
level set deadline to 8 real hours starting from the next business
day, when tickets with the second level should be resolved in the
next 8 hours after creation.


=head1 OLD ideas, some havn't been integrated in the above doc

=head2 v0.01

* we have one Business::Hours object
* several agreement levels
* options:
** InHoursDefault - default service level ticket created during business hours, but only if level hasn't been set
** OutOfHoursDefault - default service level ticket created out of business hours, but only if level hasn't been set
** Levels - each level has definition of agreements for Response and Resolve
*** If you set a requirement for response then we set due date on create or as soon as user replies to some a in the feature, so due date means deadline for reply, as soon as somebody who is not a requestor replies we unset due
*** if you set a requirement for resolve then we set due date on create to a point in the feature, so due date defines deadline for ticket resolving
*** we should support situations when restrictions defined for reply and resolve, then we move due date according to reply deadlines, however when we reach resolve deadline we stop moving.

*** each requirement is described by Business or Real time in terms of L<Business::SLA> module.

so we'll have something like:
%SLA => (
    Default => 'two business hours for reply', 
    Levels => {
        'one real hour for reply' => { Response => { RealMinutes => 60 } },
        'two business hours for reply' => { Response => { BusinessMinutes => 60*2 } },
        '8 business hours for resolve' => { Resolve => { BusinessMinutes => 60*8 } },
        'two b-hours for reply and 3 real days for resolve' => {
            OutOfHours => {
                Response => { RealMinutes => +60 },
                Resolve => { RealMinutes => +60*24 },
            },
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

sub Agreement {
    my $self = shift;
    my %args = ( Level => undef, Type => 'Response', Time => undef, @_ );

    my $meta = $RT::SLA{'Levels'}{ $args{'Level'} };
    return undef unless $meta;
    return undef unless $meta->{ $args{'Type'} };

    my %res;
    if ( ref $meta->{ $args{'Type'} } ) {
        %res = %{ $meta->{ $args{'Type'} } };
    } elsif ( $meta->{ $args{'Type'} } =~ /^\d+$/ ) {
        %res = ( BusinessMinutes => $meta->{ $args{'Type'} } );
    } else {
        $RT::Logger->error("Levels of SLA should be either number or hash ref");
        return undef;
    }

    if ( defined $meta->{'StartImmediately'} ) {
        $res{'StartImmediately'} = $meta->{'StartImmediately'};
    }

    if ( $meta->{'OutOfHours'}{ $args{'Type'} } && $args{'Time'} ) {
        my $bhours = $self->BusinessHours;
        if ( $bhours->first_after( $args{'Time'} ) != $args{'Time'} ) {
            foreach ( qw(RealMinutes BusinessMinutes) ) {
                next unless $tmp->{ $_ };
                $res{ $_ } ||= 0;
                $res{ $_ } += $tmp->{ $_ };
            }
        }
    }

    return \%res;
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
    my %args = ( Type => 'Response', Time => undef, @_ );

    my $class = $RT::SLA{'Module'} || 'Business::SLA';
    eval "require $class" or die $@;
    my $SLA = $class->new( BusinessHours => $self->BusinessHours );

    my $levels = $RT::SLA{'Levels'};
    foreach my $level ( keys %$levels ) {
        my $props = $self->Agreement( %args, Level => $level );
        next unless $props;

        $SLA->Add( $level => %$props );
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

sub GetDefaultServiceLevel {
    my $self = shift;
    my %args = (Ticket => undef, Queue => undef, @_);
    unless ( $args{'Queue'} || $args{'Ticket'} ) {
        $args{'Ticket'} = $self->TicketObj if $self->can('TicketObj');
    }
    if ( !$args{'Queue'} && $args{'Ticket'} ) {
        $args{'Queue'} = $args{'Ticket'}->QueueObj;
    }
    if ( $args{'Queue'} ) {
        # TODO: here we should implement per queue defaults
    }
    return $RT::SLA{'Default'};
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
