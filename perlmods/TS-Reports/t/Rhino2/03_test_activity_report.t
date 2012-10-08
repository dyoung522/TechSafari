
use lib qw{
 ../lib
};

use strict;
use warnings;

use DBI;
use Excel::Template::Plus;

use Rhino2::TriggerReport;


my $dsn = 'dbi:mysql:database=rhino2;host=duvel';
my $dbh = DBI->connect( $dsn, 'root', '' );

my $rpt = TechSafari::Reports::Rhino2::TriggerReport->new(
  run_date => '2007-11-19',
  dbh => $dbh,
);


$rpt->process();

my $sheets = $rpt->worksheets;




if (1) {
  my $excel = Excel::Template::Plus->new(
      engine   => 'TT',
      template => 'common/report.xls.tt',
      config   => { INCLUDE_PATH => "C:\\charlie\\src\\TS-Reports\\view", },
      params   => { worksheets => $sheets },
  );  


  print $excel->write_file('test.xls');
}

