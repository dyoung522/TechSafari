#!/usr/bin/perl

use lib qw{
 ../lib
};

use strict;
use warnings;

use DBI;
use Excel::Template::Plus;
use Template;

use Rhino2::BasicReport;
use Rhino2::BasicRoyaltyGroups;
use Rhino2::TriggerReport;

my $view_include_path = "/home/tuser/perlmods/TS-Reports/view";
my $file_base_name    = 'basic_report';


#my $dsn = 'dbi:mysql:database=rhino2;host=localhost;port=5555'; # ssh tunnel to tsapp01
#my $dbh = DBI->connect( $dsn, 'root', '' );

my $dsn = 'dbi:mysql:database=rhino2;host=localhost';
my $dbh = DBI->connect( $dsn, 'root', '' );

my $rpt;
if ( 1 ) {
  $rpt = Rhino2::BasicReport->new(
    dbh => $dbh,
    run_date => '2008-04-30',
    report_period => 'Daily',  # Weekly || Daily || Monthly || MonthToDate
    hosts => [ 2 ],            # 'Masada'
     
    #no_date_flag => 1,
    #companies => [ 'Fidelis Marketing Inc.' ],
    
  );
}

$rpt->process();

my $book = $rpt->workbook;
$book->splice_worksheet_cols();

# Write to excel or html
if (1) {

  my $excel = Excel::Template::Plus->new(
      engine   => 'TT',
      template => 'common/report.xls.tt',
      config   => { INCLUDE_PATH => $view_include_path, },
      params   => { workbook => $book },
  );  

  print $excel->write_file("${file_base_name}.xls");
}
else {

  my $template = Template->new(
      INCLUDE_PATH => $view_include_path,
  );  

  $template->process( 
    'common/report.html.tt', 
    { workbook => $book }, 
    "${file_base_name}.html" 
  ); 
}

