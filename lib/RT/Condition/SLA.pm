
use strict;
use warnings;

package RT::Condition::SLA;
use base qw(RT::Extension::SLA RT::Condition::Generic);

=head1 IsSLAApplied

=cut

sub SLAIsApplied { return 1 }

1;
