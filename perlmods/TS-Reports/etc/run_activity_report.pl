#!/usr/bin/perl


use lib qw{
  ../lib
  ../../TS-Common/lib
};
use strict;
use warnings;

use DBI;
use Excel::Template::Plus;
use Template;

use Rhino2::ActivityReport;

my $view_include_path = "../view";
my $file_base_name    = 'activity_report';
my $dsn = 'dbi:mysql:database=rhino2;host=duvel';
my $dbh = DBI->connect( $dsn, 'reports', '' );


my $rpt;
if ( 1 ) {
  $rpt = Rhino2::ActivityReport->new(
    dbh => $dbh,
    run_date => '2007-11-19',
    hosts => [ 2 ],            # 'Name Seeker Inc.', 'Masada'  
  );
}

my $start_time = time;
$rpt->process();
my $end_time = time;

printf "report time ( seconds ): %d\n", $end_time - $start_time;

my $book = $rpt->workbook;

# Write to excel or html
if (1) {

  my $excel = Excel::Template::Plus->new(
      engine   => 'TT',
      template => 'common/all_in_one_sheet.xls.tt',
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


