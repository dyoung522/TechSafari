
use lib qw{
 ../lib
};

use strict;
use warnings;

use DBI;
use Excel::Template::Plus;
use Template;

use TechSafari::CustomDateTime;  # Need to rip out this dependency.

use Rhino2::BasicReport;

my $dsn = 'dbi:mysql:database=rhino2;host=localhost;port=5555'; # ssh tunnel to tsapp01
my $dbh = DBI->connect( $dsn, 'root', '' );

#my $dsn = 'dbi:mysql:database=rhino2;host=db05';
#my $dbh = DBI->connect( $dsn, 'reports', '' );

my $rpt;
if ( 1 ) {
  $rpt = Rhino2::BasicReport->new(
    dbh => $dbh,
    #run_date => '2008-07-10',
    report_period => 'MonthToDate',  # Weekly || Daily || Monthly || MonthToDate
    host => 'Data Solutions of America, Inc.',
    #host => 'Dataline'
    #host => 2
  );
}
else {
  $rpt = Rhino2::BillingReport->new(
    dbh => $dbh,
    report_period => 'Daily',
    run_date => '2007-11-19',
    hosts => [ 2, 6 ],
  );
}

$rpt->process();

my $book = $rpt->workbook;
$book->splice_worksheet_cols();

if (1) {
  my $excel = Excel::Template::Plus->new(
      engine   => 'TT',
      template => 'common/report.xls.tt',
      config   => { INCLUDE_PATH => "C:\\charlie\\src\\TS-Reports\\view", },
      params   => { workbook => $book },
  );  

  print $excel->write_file('test.xls');
}
else {
  my $template = Template->new(
      INCLUDE_PATH => "C:\\charlie\\src\\TS-Reports\\view",
  );  

  $template->process( 'common/report.html.tt', { workbook => $book }, 'test.html' );

 
}

