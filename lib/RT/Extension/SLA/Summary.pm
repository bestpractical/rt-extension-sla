use 5.8.0;
use strict;
use warnings;

package RT::Extension::SLA::Summary;

sub new {
    my $proto = shift;
    my $self = bless {}, ref($proto)||$proto;
    return $self->init( @_ );
}

sub init {
    my $self = shift;
    return $self;
}

sub Result {
    my $self = shift;
    return $self->{'Result'} ||= { };
}

sub AddReport {
    my $self = shift;
    my $report = shift;

    my $new = $self->OnReport( $report );

    my $total = $self->Result;
    while ( my ($user, $stat) = each %$new ) {
        my $tmp = $total->{$user} ||= {};
        while ( my ($action, $count) = each %$stat ) {
            $tmp->{$action} += $count;
        }
    }

    return $self;
}

sub OnReport {
    my $self = shift;
    my $report = shift;

    my $res = {};
    foreach my $stat ( @{ $report->Stats } ) {
        if ( $stat->{'owner_act'} ) {
            my $owner = $res->{ $stat->{'owner'} } ||= { };
            if ( $stat->{'failed'} ) {
                $owner->{'failed'}++;
            } else {
                $owner->{'passed'}++;
            }
        } else {
            my $owner = $res->{ $stat->{'owner'} } ||= { };
            my $actor = $res->{ $stat->{'actor'} } ||= { };
            if ( $stat->{'failed'} ) {
                $owner->{'failed'}++;
                $actor->{'late help'}++;
            } else {
                $owner->{'got help'}++;
                $actor->{'helped'}++;
            }
        }
    }
    return $res;
}

1;
