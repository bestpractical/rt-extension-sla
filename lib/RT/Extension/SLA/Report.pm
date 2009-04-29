use 5.8.0;
use strict;
use warnings;

package RT::Extension::SLA::Report;

sub new {}

sub init {}

sub State {
    my $self = shift;
    return $self->{State} ||= {};
}

{ my $cache;
sub Handlers {
    my $self = shift;

    return $cache if $cache;
    
    $cache = {
        Create => 'OnCreate',
        Set    => {
            Owner => 'OnOwnerChange',
        },
        Correspond => 'OnResponse',
        CustomField => { map $_ => 'OnServiceLevelChange', $self->ServiceLevelCustomFields },
        AddWatcher => { Requestor => 'OnRequestorChange' },
        DelWatcher => { Requestor => 'OnRequestorChange' },
    };

    return $cache;
} }

sub Drive {
    my $self = shift;
    my $txns = shift;

    my $state = $self->State;
    my $handler = $self->Handlers;

    while ( my $txn = $txns->Next ) {
        my ($type, $field) = ($txn->Type, $txn->Field);

        my $h = $handler->{ $type };
        unless ( $h ) {
            $RT::Logger->debug( "No handler for $type transaction, skipping" );
        } elsif ( ref $h ) {
            unless ( $h = $h->{ $field } ) {
                $RT::Logger->debug( "No handler for ($type, $field) transaction, skipping" );
            }
        }
        next unless $h;

        $self->$h( Transaction => $txn, State => $state );
    }
}

sub OnCreate {
    my $self = shift;
    my %args = ( Ticket => undef, Transaction => undef, State => undef, @_);

    my $level = $self->InitialServiceLevel( $args{'Ticket'} );

    my $state = $args{'State'};
    %$state = ();
    $state->{'level'} = $level;
    $state->{'transaction'} = $args{'Transaction'};
    $state->{'requestors'} = [ $self->InitialRequestors( $args{'Ticket'} ) ];
    $state->{'owner'} = $self->InitialOwner( $args{'Ticket'} );
    return;
}

sub OnRequestorChange {
    my $self = shift;
    my %args = ( Ticket => undef, Transaction => undef, State => undef, @_);

    my $requestors = $self->State->{'requestors'};
    if ( $args{'Transaction'}->Type eq 'AddWatcher' ) {
        push @$requestors, $args{'Transaction'}->NewValue;
    }
    else {
        my $id = $args{'Transaction'}->OldValue;
        @$requestors = grep $_ != $id, @$requestors;
    }
}

sub OnResponse {
    my $self = shift;
    my $self
}

sub IsRequestorsAct {
    my $self = shift;
    my $txn = shift;

    my $actor = $txn->Creator;

    # owner is always treated as non-requestor
    return 0 if $actor == $self->State->{'owner'};
    return 1 if grep $_ == $actor, @{ $self->State->{'requestors'} };

    # in case requestor is a group
    foreach my $id ( @{ $self->State->{'requestors'} } ){
        my $cgm = RT::CachedGroupMember->new( $RT::SystemUser );
        $cgm->LoadByCols( GroupId => $id, MemberId => $actor, Disabled => 0 );
        return 1 if $cgm->id;
    }
    return 1;
}

sub InitialServiceLevel {
    my $self = shift;
    my $ticket = shift;

    return $self->InitialValue(
        Ticket   => $ticket,
        Current  => $ticket->FirstCustomFieldValue('SLA'),
        Criteria => { CustomField => [ map $_->id, $self->ServiceLevelCustomFields ] },
    );
}

sub InitialRequestors {
    my $self = shift;
    my $ticket = shift;

    my @current = map $_->Member, @{ $ticket->Requestors->MembersObj->ItemsArrayRef };

    my $txns = $self->Transactions(
        Ticket => $ticket,
        Order => 'DESC',
        Criteria => { 'AddWatcher' => 'Requestor', DelWatcher => 'Requestor' },
    );
    while ( my $txn = $txns->Next ) {
        if ( $txn->Type eq 'AddWatcher' ) {
            my $id = $txn->NewValue;
            @current = grep $_ != $id, @current;
        }
        else {
            push @current, $txn->OldValue;
        }
    }

    return @current;
}

sub InitialOwner {
    my $self = shift;
    my $ticket = shift;

    return $self->InitialValue(
        %args,
        Current => $ticket->Owner,
        Criteria => { 'Set', 'Owner' },
    );
}

sub InitialValue {
    my $self = shift;
    my %args = ( Ticket => undef, Current => undef, Criteria => {}, @_ );

    my $txns = $self->Transactions( %args );
    if ( my $first_change = $txns->First ) {
        # intial value is old value of the first change
        return $first_change->OldValue;
    }

    # no change -> initial value is the current
    return $args{'Current'};
}

sub Transactions {
    my $self = shift;
    my %args = (Ticket => undef, Criteria => undef, Order => 'ASC', @_);

    my $txns = $ticket->Transactions;

    my $clause = 'ByTypeAndField';
    while ( my ($type, $field) = each %{ $args{'Criteria'} } ) {
        $txns->_OpenParen( $clause );
        $txns->Limit(
            ENTRYAGGREGATOR => 'OR',
            SUBCLAUSE       => $clause,
            FIELD           => 'Type',
            VALUE           => $type,
        );
        if ( $field ) {
            my $tmp = ref $field? $field : [$field];
            $txns->_OpenParen( $clause );
            my $first = 1;
            foreach my $value ( @$tmp ) {
                $txns->Limit(
                    SUBCLAUSE       => $clause,
                    ENTRYAGGREGATOR => $first? 'AND' : 'OR',
                    FIELD           => 'Field',
                    VALUE           => $value,
                );
                $first = 0;
            }
            $txns->_CloseParen( $clause );
        }
        $txns->_CloseParen( $clause );
    }
    $txns->OrderByCols(
        { FIELD => 'Created', ORDER => $args{'Order'} },
        { FIELD => 'id',      ORDER => $args{'Order'} },
    );

    return $txns;
}

{ my @cache = ();
sub ServiceLevelCustomFields {
    my $self = shift;
    return @cache if @cache;

    my $cfs = RT::CustomFields->new( $RT::SystemUser );
    $cfs->Limit( FIELD => 'Name', VALUE => 'SLA' );
    $cfs->Limit( FIELD => 'LookupType', VALUE => RT::Ticket->CustomFieldLookupType );
    # XXX: limit to applied custom fields only

    push @cache, $_ while $_ = $cfs->Next;

    return @cache;
} }

1;
