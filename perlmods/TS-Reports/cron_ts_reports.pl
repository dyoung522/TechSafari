#!/usr/bin/perl

# Wrapper for ts reports to run under cron.  Report configuration based on
# config files in /conf folder...
# I'm going to rewrite this, its a mess...

use strict;
use warnings;

# Cpan modules
use Class::MOP;
use DateTime;
use DBI;
use Excel::Template::Plus;
use File::Basename;
use File::Spec;
use Sys::Hostname;
use YAML ();

# Application modules are loaded dynamically after parsing the config file...

#### DateTime stuff...

my $today     = DateTime->today();
my $yesterday = $today - DateTime::Duration->new( days => 1 );
my $date_str  = $yesterday->ymd('-');
my $month_str = $yesterday->month_abbr . q{ } . $yesterday->year;

my $start_tm  = DateTime->now();

print "---- $start_tm ----\n";

## Parse config file... assume /conf folder is located relative to this script.
## conf files are named after the system name... 
my $cfg;
{
  my($file, $dir, $suffix) = File::Basename::fileparse($0);
  my $base_dir  = File::Spec->rel2abs($dir);
  my $system     = Sys::Hostname::hostname;  
  my $config_file = File::Spec->catfile($base_dir, 'conf', "tsr_${system}.yml"); 
  my @yaml_streams = YAML::LoadFile($config_file);
  for my $stream (@yaml_streams) {
    if ( $stream->{system} eq $system && $stream->{name} eq 'TS::Reports' ) {
      $cfg = $stream;
      last;
    }
  }

  if ( not defined $cfg ) {
    die "No reports configured in '$config_file' for system '$system'";
  }
}


# add application lib folders to @INC, load the emailer...
if ( exists $cfg->{application_lib} && $cfg->{application_lib} ) {
  if ( ref $cfg->{application_lib} eq 'ARRAY' ) {
    unshift( @INC, @{ $cfg->{application_lib} } );
  }
  elsif ( ! ref $cfg->{application_lib} ) {
    unshift @INC, $cfg->{application_lib};
  }
}
Class::MOP::load_class('TechSafari::Reports::Emailer');

#### Start reports
my $default_init_args = {

  'Excel::Template::Plus' => {
    engine => 'TT',
    config => { INCLUDE_PATH => $cfg->{template_include_path}, },
  },

};

# Connect to database
my $dbh = DBI->connect( $cfg->{db_dsn}, $cfg->{db_user}, $cfg->{db_pass} )
  || die "Can't connect to database";

# loop through email rules...
for my $rule ( @{ $cfg->{email_rules} } ) {

  # trigger report based on rule
  if (
    ( $rule->{report}{period} eq 'Daily' )
    || ( $rule->{report}{period} eq 'SemiMonthly'
      && ( $today->day == 1 || $today->day == 16 ) )
    || ( $rule->{report}{period} eq 'Monthly' && $today->day == 1 )
    )
  {
    my $rpt_class = $rule->{report}->{class};
    Class::MOP::load_class($rpt_class);
    print YAML::Dump( [ $rule->{report} ] ) . "\n";
    delete $rule->{report}->{class};

    my $rpt = $rpt_class->new(
      dbh           => $dbh,
      run_date      => $yesterday,
      report_period => $rule->{report}{period},
      %{ $rule->{report} },
    );
    
    my $rpt_start_tm = DateTime->now();
    $rpt->process();
    my $rpt_end_tm = DateTime->now();

    my $workbook = $rpt->workbook;
    $workbook->splice_worksheet_cols();

    my $view_class = $rule->{output_to}->{class};
    Class::MOP::load_class($view_class);
    print YAML::Dump( [ $rule->{output_to} ] ) . "\n";
    delete $rule->{output_to}->{class};

    my %opts =
      exists $default_init_args->{$view_class}
      ? %{ $default_init_args->{$view_class} }
      : ();

    my $view = $view_class->new(
      params => { workbook => $workbook },
      %{ $rule->{output_to} },
      %opts
    );

    my $file_basename = $rule->{filename};

    # put dates into filenames... i hate this var substitition... 
    # should do this differently
    $file_basename =~ s/\[date\]/$date_str/;
    $file_basename =~ s/\[month\]/$month_str/;

    my $file_fullpath =
      File::Spec->catfile( $cfg->{reports_store}, $file_basename, );

    $view->write_file($file_fullpath);

    if ( exists $cfg->{only_send_emails_to} ) {
      $rule->{email}->{to} = $cfg->{only_send_emails_to};
    }

    # put dates into email subject lines...
    if ( exists $rule->{email}->{subject} ) {
      $rule->{email}->{subject} =~ s/\[date\]/$date_str/;
      $rule->{email}->{subject} =~ s/\[month\]/$month_str/;
    }

    my $emailer = TechSafari::Reports::Emailer->new(
      dropoff_dir => $cfg->{reports_store},
      attachments => [$file_basename],
      %{ $rule->{email} },
    );

    print "Emailing: \n" . YAML::Dump( [ $rule->{email} ] );
    print "\n";

    my $rc = eval { $emailer->send() };
    
    if ( !$@ ) {
      print "Email sent!\n";
    }
    else {
      print "Error sending email: $@\n";
    }
    
    my $dur = $rpt_end_tm - $rpt_start_tm;
    printf "Report generation time: %d:%.2d:%.2d\n", 
      $dur->hours, $dur->minutes, $dur->seconds;
  }
  
  
}

my $end_tm = DateTime->now;
my $dur = $end_tm - $start_tm;
printf "Entire job run time: %d:%.2d:%.2d\n", 
  $dur->hours, $dur->minutes, $dur->seconds;

