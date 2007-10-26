use strict;
use warnings;

package RT::Extension::SLA;

=head1 NAME

RT::Extension::SLA - Service Level Agreements

=head1 DESIGN QUESTIONS

Here is some questionable things developers/users can comment on:

=over 4

=item

What should happen response agreements when there is no requestors?

=back

=head1 DESCRIPTION

To enable service level agreements for a queue administrtor
should create and apply SLA custom field. To define different
levels for different queues he CAN create several CFs with
the same name and different set of values. All CFs MUST be
of the same 'select one value' type.

Values of the CF(s) define service levels.

Each service level can be described using several options:
StartImmediately, OutOfHours, Resolve and Response.

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

=head3 Using both Resolve and Response in the same level

Resolve and Response can be combined. In such case due date is set
according to the earliest of two deadlines and never is dropped to
not set. When non-requestor replies to a ticket, due date is changed to
Resolve deadline, as well this happens when a ticket is closed. So
all the time due date is defined.

If a ticket met its Resolve deadline then due date stops "fliping" and
is freezed and the ticket becomes overdue.

Example:

    'standard delivery' => {
        Response => { RealMinutes => 60*1  }, # one hour
        Resolve  => { RealMinutes => 60*24 }, # 24 real hours
    },

A client orders goods and due date of the order is set to the next one
hour, you have this hour to process the order and write a reply.
As soon as goods are delivered you resolve tickets and usually meet
Resolve deadline, but if you don't resolve or user replies then most
probably there are problems with deliver or the goods. And if after
a week you keep replying to the client and always meeting one hour
response deadline that doesn't mean the ticket is not over due.
Due date was frozen 24 hours after creation of the order.

=head3 Using business and real time in one option

It's quite rare situation when people need it, but we've decided
that deadline described using both types of time then business
is applied first and then real time. For example:

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
and/or reply options if event happens out of business hours.

Example:
    
    'level x' => {
        OutOfHours => { Resolve => { RealMinutes => +60*24 } },
        Resolve    => { RealMinutes => 60*24 },
    },

If a request comes into the system during night then supporters have two
days, otherwise only one.

    'level x' => {
        OutOfHours => { Response => { BusinessMinutes => +60*2 } },
        Resolve    => { BusinessMinutes => 60 },
    },

Supporters have two additional hours in the morning to deal with bunch
of requests that came into the system during the last night.

=head2 BusinessHours

Each level now supports BusinessHours option to specify your own business
hours.

    'level x' => {
        BusinessHours => 'work just in Monday',
        Resolve    => { BusinessMinutes => 60 },
    },

then %RT::BusinessHours should have the corresponding definition:

%RT::BusinessHours = ( 'work just in Monday' => {
        1 => { Name => 'Monday', Start => '9:00', End => '18:00' }
        });

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
    my $meta = $RT::SLA{'Levels'}{ $args{'Level'} };

    my $agreement = $self->Agreement( %args );
    return undef unless $agreement;

    my $res = $args{'Time'};
    if ( defined $agreement->{'BusinessMinutes'} ) {
        my $bhours = $self->BusinessHours( $meta->{'BusinessHours'} );
        $res = $bhours->add_seconds( $res, 60 * $agreement->{'BusinessMinutes'} );
    }
    $res += 60 * $agreement->{'RealMinutes'}
        if defined $agreement->{'RealMinutes'};

    return $res;
}


=head2 Agreements [ Type => 'Response' ]

DEPRECATED

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

=head2 SLA [ Level => $level ]

Returns an instance of L<Business::SLA> class filled with the level.

Now we take list of agreements and its description from the
RT config.

=cut

sub SLA {
    my $self  = shift;
    my %args  = @_;
    my $level = $args{Level};

    my $class = $RT::SLA{'Module'} || 'Business::SLA';
    eval "require $class" or die $@;

    my $SLA = $class->new(
        BusinessHours => $self->BusinessHours(
            $RT::SLA{'Levels'}{ $level }{'BusinessHours'}
        ),
    );

    $SLA->Add( $level => %{ $self->Agreement(%args) } );

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
        local $@;
        eval { require RT::Extension::QueueSLA };
        if ( $@ ) {
            $RT::Logger->crit("Couldn't load RT::Extension::QueueSLA: $@");
        }
        else {
            return $self->TicketObj->QueueObj->SLA
              if $self->TicketObj->QueueObj->SLA;
        }
    }
    return $RT::SLA{'Default'};
}

=head1 TODO

=head2 v0.01

* we have one Business::Hours object
* default SLA for queues
** see below in this class
* changing service levels of a ticket in the middle of its live
** this should work for Due dates, for Starts makes not much sense

=head2 v0.later

* WebUI
* add support for multiple b-hours definitions, this could be very helpfull when you have 24/7 mixed with 8/5 and/or something like 8/5+4/2 for different tickets(by requestor, queue or something else). So people would be able to handle tickets in the right order using Due dates.

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
