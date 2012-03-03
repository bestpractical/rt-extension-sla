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
    return $self->MergeResults( $new ) if keys %{ $self->Result };
    %{ $self->Result } = %$new;
    return $self;
}

sub Finalize {
    my $self = shift;

    my $res = $self->Result;

    $res->{'messages'}{'*'} += $_ foreach values %{ $res->{'messages'} };

    foreach my $type ( grep $res->{$_}, qw(KeepInLoop FollowUp Response) ) {
        $self->MergeCountMinMaxSum( $_ => $res->{$type}{'*'} ||= {} )
            foreach values %{ $res->{$type} };
        $_->{'avg'} = $_->{'sum'}/$_->{'count'}
            foreach grep $_->{'count'}, values %{ $res->{$type} };
    }
    foreach ( grep $_, $res->{'FirstResponse'}, $res->{'deadlines'}{'failed'} ) {
        $_->{'avg'} = $_->{'sum'}/$_->{'count'};
    }
    return $self;
}

# min, avg, max - initial response time
# min, avg, max - response time
# number of passed
# number of failed
# min, avg, max - past due time
# responses by role

sub OnReport {
    my $self = shift;
    my $report = shift;

    my %res;
    foreach my $stat ( @{ $report->Stats } ) {
        $res{'messages'}{ $stat->{'actor_role'} }++;

        $self->CountMinMaxSum(
            $res{ $stat->{'type'} }{ $stat->{'actor_role'} } ||= {},
            $stat->{'time'},
        ) if $stat->{'time'};

        if ( $stat->{'deadline'} ) {
            if ( $stat->{'difference'} > 0 ) {
                $self->CountMinMaxSum(
                    $res{'deadlines'}{'failed'} ||= {},
                    $stat->{'difference'},
                );
            }
            else {
                $res{'deadlines'}{'passed'}++;
            }
        }
    }

    if ( $report->Stats->[0]{'actor_role'} eq 'requestor' ) {
        my ($first_response) = (grep $_->{'actor_role'} ne 'requestor', @{ $report->Stats });
        $self->CountMinMaxSum(
            $res{'FirstResponse'} ||= {},
            $first_response->{'time'},
        ) if $first_response;
    }

    return \%res;
}

sub MergeResults {
    my $self = shift;
    my $src = shift;
    my $dst = shift || $self->Result;


    while ( my ($k, $v) = each %$src ) {
        unless ( ref $v ) {
            $dst->{$k} += $v;
        }
        elsif ( ref $v eq 'HASH' ) {
            if ( exists $v->{'count'} ) {
                $self->MergeCountMinMaxSum( $src, $dst );
                $self->MergeResults(
                    { map { $_ => $v->{$_} } grep !/^(?:count|min|max|sum)$/, keys %$v  },
                    $dst->{ $k }
                );
            } else {
                $self->MergeResults( $v, $dst->{$k} );
            }
        }
        else {
            die "Don't know how to merge";
        }
    }
    return $self;
}

sub CountMinMaxSum {
    my $self = shift;
    my $hash = shift || {};
    my $value = shift;

    $hash->{'count'}++;
    $hash->{'min'} = $value if !defined $hash->{'min'} || $hash->{'min'} > $value;
    $hash->{'max'} = $value if !defined $hash->{'max'} || $hash->{'max'} < $value;
    $hash->{'sum'} += $value;
    return $hash;
}

sub MergeCountMinMaxSum {
    my $self = shift;
    my $src = shift || {};
    my $dst = shift;

    $dst->{'count'} += $src->{'count'};
    $dst->{'min'} = $src->{'min'}
        if !defined $dst->{'min'} || $dst->{'min'} > $src->{'min'};
    $dst->{'max'} = $src->{'max'}
        if !defined $dst->{'max'} || $dst->{'max'} < $src->{'max'};
    $dst->{'sum'} += $src->{'sum'};

    return $self;
}

1;
