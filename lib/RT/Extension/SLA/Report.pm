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
        Correpond => 'OnResponse',
        CustomField => { map $_ => 'OnServiceLevelChange', $self->ServiceLevelCustomFields },
    };

    return $cache;
}

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

sub InitialServiceLevel {
    my $self = shift;
    my $ticket = shift;

    my $txns = $ticket->Transactions;
    foreach my $cf ( $self->ServiceLevelCustomFields ) {
        $txns->_OpenParen('ServiceLevelCustomFields');
        $txns->Limit(
            SUBCLAUSE       => 'ServiceLevelCustomFields',
            ENTRYAGGREGATOR => 'OR',
            FIELD           => 'Type',
            VALUE           => 'CustomField',
        );
        $txns->Limit(
            SUBCLAUSE       => 'ServiceLevelCustomFields',
            ENTRYAGGREGATOR => 'AND',
            FIELD           => 'Field',
            VALUE           => $cf->id,
        );
        $txns->_CloseParen('ServiceLevelCustomFields');
    }

    return $self;
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
