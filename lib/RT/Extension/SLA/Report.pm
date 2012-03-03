use 5.8.0;
use strict;
use warnings;

package RT::Extension::SLA::Report;

sub new {
    my $proto = shift;
    my $self = bless {}, ref($proto)||$proto;
    return $self->init( @_ );
}

sub init {
    my $self = shift;
    my %args = (Ticket => undef, @_);
    $self->{'Ticket'} = $args{'Ticket'} || die Carp::longmess( "boo" );
    $self->{'State'} = {};
    $self->{'Stats'} = [];
    return $self;
}

sub Run {
    my $self = shift;
    my $txns = shift || $self->{'Ticket'}->Transactions;

    my $handler = $self->Handlers;

    while ( my $txn = $txns->Next ) {
        my ($type, $field) = ($txn->Type, $txn->Field);
        $_ ||= '' foreach $type, $field;

        my $h = $handler->{ $type };
        unless ( $h ) {
            $RT::Logger->debug( "No handler for $type transaction, skipping" );
        } elsif ( ref $h ) {
            unless ( $h = $h->{ $field } ) {
                $RT::Logger->debug( "No handler for ($type, $field) transaction, skipping" );
            }
        }
        next unless $h;

        $RT::Logger->debug( "Handling transaction #". $txn->id ." ($type, $field) of ticket #". $self->{'Ticket'}->id );

        $self->$h( Ticket => $self->{'Ticket'}, Transaction => $txn );
    }
    return $self;
}

sub State {
    my $self = shift;
    return $self->{State} ||= {};
}

sub Stats {
    my $self = shift;
    return $self->{Stats} ||= [];
}

sub Summary {
    my $self = shift;
    use RT::Extension::SLA::Summary;
    return RT::Extension::SLA::Summary->new->AddReport( $self )->Finalize;
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
        CustomField => { map { $_->id => 'OnServiceLevelChange' } $self->ServiceLevelCustomFields },
        AddWatcher => { Requestor => 'OnRequestorChange' },
        DelWatcher => { Requestor => 'OnRequestorChange' },
    };

    return $cache;
} }

sub OnCreate {
    my $self = shift;
    my %args = ( Ticket => undef, Transaction => undef, @_);

    my $state = $self->State;
    %$state = ();
    $state->{'level'} = $self->InitialServiceLevel( Ticket => $args{'Ticket'} );
    $state->{'requestors'} = [ $self->InitialRequestors( Ticket => $args{'Ticket'} ) ];
    $state->{'owner'} = $self->InitialOwner( Ticket => $args{'Ticket'} );
    return $self->OnResponse( %args );
}

sub OnRequestorChange {
    my $self = shift;
    my %args = ( Ticket => undef, Transaction => undef, @_);

    my $requestors = $self->State->{'requestors'} ||= [];
    if ( $args{'Transaction'}->Type eq 'AddWatcher' ) {
        push @$requestors, $args{'Transaction'}->NewValue;
    }
    else {
        my $id = $args{'Transaction'}->OldValue;
        @$requestors = grep $_ != $id, @$requestors;
    }
}

sub OnServiceLevelChange {
    my $self = shift;
    my %args = ( Transaction => undef, @_);
    $self->State->{'level'} = $args{'Transaction'}->NewValue;
}

sub OnResponse {
    my $self = shift;
    my %args = ( Transaction => undef, Create => 0, @_);

    my $state = $self->State;
    my $txn = $args{'Transaction'};

    my %stats = (
        transaction => $txn->id,
        owner       => $state->{'owner'},
        actor       => $txn->Creator,
        actor_role  =>
            $self->IsRequestorsAct( $txn ) ? 'requestor'
            : $state->{'owner'} == $txn->Creator ? 'owner'
            : 'other'
        ,
        acted_on    => $txn->CreatedObj->Unix,
        previous    => $self->Stats->[-1],
    );

    unless ( $stats{'previous'} ) {
        $stats{'type'} = 'Create';
    }
    elsif ( $stats{'actor_role'} eq 'requestor' ) {
        if ( $stats{'previous'}{'actor_role'} eq 'requestor' ) {
            $stats{'type'} = 'FollowUp';
            $stats{'to'} = $stats{'previous'};
        } else {
            $stats{'type'} = 'Response';
            my $tmp = $stats{'previous'};
            while ( $tmp->{'previous'} && $tmp->{'previous'}{'actor_role'} ne 'requestor' ) {
                $tmp = $tmp->{'previous'};
            }
            $stats{'to'} = $tmp;
        }
    }
    else {
        if ( $stats{'previous'}{'actor_role'} ne 'requestor' ) {
            $stats{'type'} = 'KeepInLoop';
            $stats{'to'} = $stats{'previous'};
        } else {
            $stats{'type'} = 'Response';
            my $tmp = $stats{'previous'};
            while ( $tmp->{'previous'} && $tmp->{'previous'}{'actor_role'} eq 'requestor' ) {
                $tmp = $tmp->{'previous'};
            }
            $stats{'to'} = $tmp;
        }

        $stats{'deadline'} = RT::Extension::SLA->Due(
            Type  => $stats{'type'},
            Level => $state->{'level'},
            Time  => $stats{'to'}{'acted_on'},
        );
        $stats{'difference'} = RT::Extension::SLA->SecondsBetween(
            Level => $state->{'level'},
            From  => $stats{'deadline'},
            To    => $stats{'acted_on'},
        ) if defined $stats{'deadline'};
    }

    $stats{'time'} = RT::Extension::SLA->SecondsBetween(
        Level => $state->{'level'},
        From  => $stats{'to'}{'acted_on'},
        To    => $stats{'acted_on'},
    ) if $stats{'to'};

    push @{ $self->Stats }, \%stats;
}

sub IsRequestorsAct {
    my $self = shift;
    my $txn = shift;

    my $actor = $txn->Creator;

    # owner is always treated as non-requestor
    return 0 if $actor == $self->State->{'owner'};
    return 1 if grep $_ == $actor, @{ $self->State->{'requestors'} || [] };

    # in case requestor is a group
    foreach my $id ( @{ $self->State->{'requestors'} || [] } ){
        my $cgm = RT::CachedGroupMember->new( $RT::SystemUser );
        $cgm->LoadByCols( GroupId => $id, MemberId => $actor, Disabled => 0 );
        return 1 if $cgm->id;
    }
    return 0;
}

sub InitialServiceLevel {
    my $self = shift;
    my %args = @_;

    return $self->InitialValue(
        Ticket   => $args{'Ticket'},
        Current  => $args{'Ticket'}->FirstCustomFieldValue('SLA'),
        Criteria => { CustomField => [ map $_->id, $self->ServiceLevelCustomFields ] },
    );
}

sub InitialRequestors {
    my $self = shift;
    my %args = @_;

    my @current = map $_->MemberId, @{ $args{'Ticket'}->Requestors->MembersObj->ItemsArrayRef };

    my $txns = $self->Transactions(
        Ticket => $args{'Ticket'},
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
    my %args = (Ticket => undef, @_);
    return $self->InitialValue(
        %args,
        Current => $args{'Ticket'}->Owner,
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

    my $txns = RT::Transactions->new( $args{'Ticket'}->CurrentUser );
    $txns->LimitToTicket( $args{'Ticket'}->id );

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

    return @cache = @{ $cfs->ItemsArrayRef };
} }

1;
