use strict;
use warnings;

package RT::Extension::SLA;

=head1 NAME

RT::Extension::SLA - Service Level Agreements for RT

=head1 DESCRIPTION

RT's extension that allows you to automate due dates using
service levels.

=head1 CONFIGURATION

To enable service level agreements for a queue administrator
should create and apply SLA custom field. To define different
levels for different queues he CAN create several CFs with
the same name and different set of values. All CFs MUST be
of the same 'select one value' type.

Values of the CF(s) define service levels.

Each service level can be described using several options:
L</StartImmediately>, L</OutOfHours>, L</Resolve> and L</Response>.

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

Example:
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

As response deadlines are calculated using requestors' activity
so several rules applies to make things quite sane:

=over 4

=item

If requestors reply multiple times and are ignored then the deadline
is calculated using the oldest requestors' correspondence.

=item

If a ticket has no requestors then it has no response deadline.

=item

If a ticket is created by non-requestor then due date is left unset.

=item

If owner of a ticket is its requestor then his actions are treated
as non-requestors'.

=back

=head3 Using both Resolve and Response in the same level

Resolve and Response can be combined. In such case due date is set
according to the earliest of two deadlines and never is dropped to
not set.

If a ticket met its Resolve deadline then due date stops "fliping",
is freezed and the ticket becomes overdue. Before that moment when
non-requestor replies to a ticket, due date is changed to Resolve
deadline instead of 'Not Set', as well this happens when a ticket
is closed. So all the time due date is defined.

Example:

    'standard delivery' => {
        Response => { RealMinutes => 60*1  }, # one hour
        Resolve  => { RealMinutes => 60*24 }, # 24 real hours
    },

A client orders goods and due date of the order is set to the next one
hour, you have this hour to process the order and write a reply.
As soon as goods are delivered you resolve tickets and usually meet
Resolve deadline, but if you don't resolve or user replies then most
probably there are problems with delivery of the goods. And if after
a week you keep replying to the client and always meeting one hour
response deadline that doesn't mean the ticket is not over due.
Due date was frozen 24 hours after creation of the order.

=head3 Using business and real time in one option

It's quite rare situation when people need it, but we've decided
that business is applied first and then real time when deadline
described using both types of time. For example:

    'delivery' => {
        Resolve => { BusinessMinutes => 0, RealMinutes => 60*8 },
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

=head2 OutOfHours (struct, no default)

Out of hours modifier. Adds more real or business minutes to resolve
and/or reply options if event happens out of business hours, see also
</BusinessHours> below.

Example:
    
    'level x' => {
        OutOfHours => { Resolve => { RealMinutes => +60*24 } },
        Resolve    => { RealMinutes => 60*24 },
    },

If a request comes into the system during night then supporters have two
hours, otherwise only one.

    'level x' => {
        OutOfHours => { Response => { BusinessMinutes => +60*2 } },
        Resolve    => { BusinessMinutes => 60 },
    },

Supporters have two additional hours in the morning to deal with bunch
of requests that came into the system during the last night.

=head2 BusinessHours

In the config you can set one or more work schedules. Use the following
format:

    %RT::BusinessHours = (
        'label to use' => {
            ... description ...
        },
        'another label' => {
            ... description ...
        },
    );

Read more about how to describe a schedule in L<Business::Hours>.

=head3 Defining different business hours for service levels

Each level supports BusinessHours option to specify your own business
hours.

    'level x' => {
        BusinessHours => 'work just in Monday',
        Resolve    => { BusinessMinutes => 60 },
    },

then %RT::BusinessHours should have the corresponding definition:

    %RT::BusinessHours = ( 'work just in Monday' => {
        1 => { Name => 'Monday', Start => '9:00', End => '18:00' }
    } );

Default Business Hours setting is in $RT::BusinessHours{'Default'}.

=head2 Default service levels

In the config and per queue defaults(this is not implemented).

=cut

sub BusinessHours {
    my $self = shift;
    my $name = shift || 'Default';

    require Business::Hours;
    my $res = new Business::Hours;
    $res->business_hours( %{ $RT::BusinessHours{ $name } } )
        if $RT::BusinessHours{ $name };
    return $res;
}

sub Agreement {
    my $self = shift;
    my %args = ( Level => undef, Type => 'Response', Time => undef, @_ );

    my $meta = $RT::ServiceAgreements{'Levels'}{ $args{'Level'} };
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

    if ( $args{'Time'} and my $tmp = $meta->{'OutOfHours'}{ $args{'Type'} } ) {
        my $bhours = $self->BusinessHours( $meta->{'BusinessHours'} );
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

sub Due {
    my $self = shift;
    my %args = ( Level => undef, Type => undef, Time => undef, @_ );

    my $agreement = $self->Agreement( %args );
    return undef unless $agreement;

    my $meta = $RT::ServiceAgreements{'Levels'}{ $args{'Level'} };

    my $res = $args{'Time'};
    if ( defined $agreement->{'BusinessMinutes'} ) {
        my $bhours = $self->BusinessHours( $meta->{'BusinessHours'} );
        $res = $bhours->add_seconds( $res, 60 * $agreement->{'BusinessMinutes'} );
    }
    $res += 60 * $agreement->{'RealMinutes'}
        if defined $agreement->{'RealMinutes'};

    return $res;
}

sub Starts {
    my $self = shift;
    my %args = ( Level => undef, Time => undef, @_ );

    my $meta = $RT::ServiceAgreements{'Levels'}{ $args{'Level'} };
    return undef unless $meta;

    return $args{'Time'} if $meta->{'StartImmediately'};

    my $bhours = $self->BusinessHours( $meta->{'BusinessHours'} );
    return $bhours->first_after( $args{'Time'} );
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
        local $@;
        eval { require RT::Queue_SLA };
        if ( $@ ) {
            $RT::Logger->crit("Couldn't load RT::Queue_SLA: $@");
        }
        else {
            return $args{'Queue'}->SLA if $args{'Queue'}->SLA;
        }
        if ( $RT::ServiceAgreements{'QueueDefault'} && $RT::ServiceAgreements{'QueueDefault'}{ $args{'Queue'}->Name } ) {
            return $RT::ServiceAgreements{'QueueDefault'}{ $args{'Queue'}->Name };
        }
    }
    return $RT::ServiceAgreements{'Default'};
}

=head1 TODO

    * default SLA for queues
    ** implemented
    ** TODO: docs, tests

    * add support for multiple b-hours definitions, this could be very helpfull
      when you have 24/7 mixed with 8/5 and/or something like 8/5+4/2 for different
      tickets(by requestor, queue or something else). So people would be able to
      handle tickets in the right order using Due dates.
    ** implemented
    ** TODO: tests

    * WebUI

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
