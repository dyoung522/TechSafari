
package TechSafari::Reports::Attributes::RunDate;
use Moose::Role;

use DateTime;
use TechSafari::DateTime::MooseX;

has 'run_date' => (
  is => 'rw',
  isa => 'DateTime',
  coerce => 1,
  default => sub { DateTime->today() },
);

1;
__END__

=pod

=NAME

TechSafari::Reports::Attributes::RunDate - run date attribute, implemented as a
moose role, consumable by TechSafari::Reports

=DESCRIPTION

run_date is coercible from most anything, using Charlie's neato moose coercions
L<TechSafari::DateTime::MooseX>

run_date defaults to today ( DateTime->today() ), which is the date with the 
time = 0

See also, L<TechSafari::Reports::Attributes::RunPeriod>, for an extension based
on the run_date.

