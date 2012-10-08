
#!/usr/bin/perl

use strict;
use warnings;

use DateTime;

use Test::More tests => 24;
use Test::Exception;

BEGIN {
  use_ok('TechSafari::Reports::Attributes::ReportPeriod');
}

{
  package Foo;
  use Moose;
  with 'TechSafari::Reports::Attributes::ReportPeriod';
}

my $month_start_dt = DateTime->new(
  year   => 2008,
  month  => 4,
  day    => 1,
  hour   => 0,
  minute => 0,
  second => 0,
);

my $month_end_dt => DateTime->new(
  year   => 2008,
  month  => 4,
  day    => 30,
  hour   => 23,
  minute => 59,
  second => 59,
);

my $day_start_dt = DateTime->new(
  year   => 2008,
  month  => 4,
  day    => 20,
  hour   => 0,
  minute => 0,
  second => 0,
);

my $day_end_dt => DateTime->new(
  year   => 2008,
  month  => 4,
  day    => 20,
  hour   => 23,
  minute => 59,
  second => 59,
);

my $foo = Foo->new(
  run_date      => '2008-04-20',
  report_period => 'Daily',
);

ok( $day_start_dt == $foo->report_period_start_dt(), '... daily report_period_start_dt ok');
ok( $day_end_dt   == $foo->report_period_end_dt(),   '... daily report_period_end_dt ok');

$foo->report_period('MonthToDate');
ok( $month_start_dt == $foo->report_period_start_dt(), '... MonthToDate report_period_start_dt ok');
ok( $day_end_dt     == $foo->report_period_end_dt(),   '... MonthToDate report_period_end_dt ok');

$foo->report_period('Monthly');
ok( $month_start_dt == $foo->report_period_start_dt(), '... Monthly report_period_start_dt ok');
ok( $month_end_dt   == $foo->report_period_end_dt(),   '... Monthly report_period_end_dt ok');

throws_ok { $foo->report_period(undef) } 
qr/^Attribute \(report_period\) does not pass the type constraint because\: Validation failed for 'TSR::Attributes::ReportPeriodType' failed with value undef/,
'... this failed cause of type check';

my $new_day_start_dt = DateTime->new(
  year   => 2008,
  month  => 4,
  day    => 23,
  hour   => 0,
  minute => 0,
  second => 0,
);

my $new_day_end_dt = DateTime->new(
  year   => 2008,
  month  => 4,
  day    => 23,
  hour   => 23,
  minute => 59,
  second => 59,
);

$foo->report_period('Daily');
ok( $day_start_dt == $foo->report_period_start_dt(), '... Daily report_period_start_dt ok');
ok( $day_end_dt   == $foo->report_period_end_dt(),   '... Daily report_period_end_dt ok');

$foo->run_date('2008-04-23');
ok( $new_day_start_dt == $foo->report_period_start_dt(), '... New run_date report_period_start_dt ok');
ok( $new_day_end_dt   == $foo->report_period_end_dt(),   '... New run_date report_period_end_dt ok');

my $week_end_dt = DateTime->new( 
  year   => 2008,
  month  => 4,
  day    => 26,
  hour   => 23,
  minute => 59,
  second => 59,
);

$foo->report_period('Weekly');
ok( $day_start_dt == $foo->report_period_start_dt(), '... Weekly report_period_start_dt ok');
ok( $week_end_dt  == $foo->report_period_end_dt(),   '... Weekly report_period_end_dt ok');

$foo->run_date('2008-04-20');
ok( $day_start_dt == $foo->report_period_start_dt(), '... Weekly report_period_start_dt ok');
ok( $week_end_dt  == $foo->report_period_end_dt(),   '... Weekly report_period_end_dt ok');

my $last_month_start_dt = DateTime->new(
  year   => 2008,
  month  => 3,
  day    => 1,
  hour   => 0,
  minute => 0,
  second => 0,
);

my $last_month_end_dt = DateTime->new(
  year   => 2008,
  month  => 3,
  day    => 31,
  hour   => 23,
  minute => 59,
  second => 59,
);

$foo->report_period('PriorMonth');
ok( $last_month_start_dt == $foo->report_period_start_dt(), '... last month report_period_start_dt ok');
ok( $last_month_end_dt  == $foo->report_period_end_dt(),   '... last month report_period_end_dt ok');

$last_month_start_dt = DateTime->new(
  year   => 2008,
  month  => 2,
  day    => 1,
  hour   => 0,
  minute => 0,
  second => 0,
);

$last_month_end_dt = DateTime->new(
  year   => 2008,
  month  => 2,
  day    => 29,
  hour   => 23,
  minute => 59,
  second => 59,
);

$foo->run_date('2008-03-21');
ok( $last_month_start_dt == $foo->report_period_start_dt(), '... last month report_period_start_dt ok');
ok( $last_month_end_dt  == $foo->report_period_end_dt(),   '... last month report_period_end_dt ok');


my $bi_st_dt =  DateTime->new(
  year   => 2008,
  month  => 3,
  day    => 16,
  hour   => 0,
  minute => 0,
  second => 0,
);

my $bi_end_dt = DateTime->new(
  year   => 2008,
  month  => 3,
  day    => 31,
  hour   => 23,
  minute => 59,
  second => 59,
);

$foo->report_period('SemiMonthly');
ok( $bi_st_dt == $foo->report_period_start_dt(), '... bi monthly report_period_start_dt ok');
ok( $bi_end_dt == $foo->report_period_end_dt(),   '... bi monthly report_period_end_dt ok');

$bi_st_dt =  DateTime->new(
  year   => 2008,
  month  => 3,
  day    => 1,
  hour   => 0,
  minute => 0,
  second => 0,
);

$bi_end_dt = DateTime->new(
  year   => 2008,
  month  => 3,
  day    => 15,
  hour   => 23,
  minute => 59,
  second => 59,
);

$foo->run_date('2008-03-15');
ok( $bi_st_dt == $foo->report_period_start_dt(), '... bi monthly report_period_start_dt ok');
ok( $bi_end_dt == $foo->report_period_end_dt(),   '... bi monthly report_period_end_dt ok');

