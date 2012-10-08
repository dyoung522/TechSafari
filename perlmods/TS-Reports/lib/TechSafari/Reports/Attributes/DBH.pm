
package TechSafari::Reports::Attributes::DBH;
use Moose::Role;

has 'dbh' => (
  is  => 'rw',
  isa => 'DBI::db',
  required => 1,
);

1;
