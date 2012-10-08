#!/usr/bin/perl

use lib qw{
  ../lib
};

use strict;
use warnings;

use DBI;
use FileHandle;

use Rhino2::QuickBooksReport;
use TechSafari::Reports::Util::IIF;

my $file_base_name    = 'nameseeker_2008-07-15';

#my $dsn = 'dbi:mysql:database=rhino2;host=localhost;port=5555'; # ssh tunnel to tsapp01
#my $dbh = DBI->connect( $dsn, 'root', '' );

my $dsn = 'dbi:mysql:database=rhino2;host=db05';
my $dbh = DBI->connect( $dsn, 'reports', '' );

my $rpt;
$rpt = Rhino2::QuickBooksReport->new(
  dbh           => $dbh,
  run_date      => '2008-07-15',
  report_period => 'Daily',        # Weekly || Daily || Monthly || MonthToDate
  hosts         => [2],            # 'Masada'

  #no_date_flag => 1,
  #companies => [ 'Fidelis Marketing Inc.' ],

);

$rpt->process();
my $book  = $rpt->workbook;
my $table = $book->worksheets->[0]->table;

## Write to IIF ##

my $iif = TechSafari::Reports::Util::IIF->new( table => $table );

$iif->process("${file_base_name}.iif");

