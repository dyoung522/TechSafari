
package TechSafari::Reports::Attributes::Schema;

use Moose::Role;
use Moose::Util::TypeConstraints;

subtype 'DBIC::Schema' => as 'Object' =>
  where { $_->isa('DBIx::Class::Schema') };

has 'schema' => (
  is       => 'rw',
  isa      => 'DBIC::Schema',
  required => 1
);

1;
