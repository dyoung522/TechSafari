
use lib qw{
 ../../lib
};

use strict;
use warnings;

use Test::More tests => 1;

use DBI;
use DateTime::Format::MySQL;


BEGIN {
  use_ok('Rhino2::BaseSQL');
}



my $dsn = 'dbi:mysql:database=rhino2;host=duvel';
my $dbh = DBI->connect( $dsn, 'root', '' );

my $sql = Rhino2::BaseSQL->new( dbh => $dbh );

my $rs = $sql->ordered_selects_query(
  
  #debug => 1,

  host_id => [ 2 ],
  start_dt => DateTime::Format::MySQL->parse_datetime('2007-11-01 00:00:00'),
  end_dt   => DateTime::Format::MySQL->parse_datetime('2007-11-01 12:00:00'),
  
  select_id => [10, 20, 30, 40],
);

use Data::Dumper;
$Data::Dumper::Indent = 1;

print Dumper $rs;

#$rs = $sql->invoice_query(
#  host_id => [ 2 ],
#  start_dt => DateTime::Format::MySQL->parse_datetime('2007-11-01 00:00:00'),
#  end_dt   => DateTime::Format::MySQL->parse_datetime('2007-11-01 12:00:00'),
#);


$rs = $sql->non_billed_orders_query(

  host_id => [ 2 ],
  start_dt => DateTime::Format::MySQL->parse_datetime('2007-11-19 00:00:00'),
  end_dt   => DateTime::Format::MySQL->parse_datetime('2007-11-19 23:59:59'),
 

);

print Dumper $rs;