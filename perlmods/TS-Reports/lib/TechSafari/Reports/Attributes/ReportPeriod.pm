package TechSafari::Reports::Attributes::ReportPeriod;

use DateTime;

use Moose::Role;
use Moose::Util::TypeConstraints;

enum 'TSR::Attributes::ReportPeriodType' =>
  qw{ Daily Weekly Monthly MonthToDate PriorMonth SemiMonthly AdHoc };

with 'TechSafari::Reports::Attributes::RunDate';

## I want to do this, but it doesn't exactly work in Moose.
##  OK, so I hacked it, and it works.  See near the bottom of this module for
##  the hack.
#
# See http://search.cpan.org/~drolsky/Moose-0.58/lib/Moose.pm#has 
# has +$name for more info (Some Sanity comment)
has '+run_date' => (
  trigger => sub {
    my $self = shift;
    $self->clear_report_period_start_dt();
    $self->clear_report_period_end_dt();
  }
);

### HERE's the other way I tried to hack it...
#sub BUILD {
#  my $self = shift;
#  my $run_date_attr = $self->meta->get_attribute('run_date');
#  my $trigger_attr  = $run_date_attr->meta->get_attribute('trigger');
#
#  $trigger_attr->set_value($trigger_attr,
#    sub {
#      my $self = shift;
#      $self->clear_report_period_start_dt();
#      $self->clear_report_period_end_dt();
#    }
#  );
#}

has 'report_period' => (
  is      => 'rw',
  isa     => 'TSR::Attributes::ReportPeriodType',
  default => 'Daily',
  trigger => sub {
    my $self = shift;
    $self->clear_report_period_start_dt();
    $self->clear_report_period_end_dt();
  }
);

has 'end_date' => (
  is => 'rw',
  isa => 'DateTime',
  coerce => 1,
  default => sub { DateTime->today() },
);


has 'report_period_start_dt' => (
  is         => 'rw',
  isa        => 'DateTime',
  lazy_build => 1,            # auto defines builder, predicate, clearer, lazy
);

has 'report_period_end_dt' => (
  is         => 'rw',
  isa        => 'DateTime',
  lazy_build => 1,
);

sub _build_report_period_start_dt {
  my $self = shift;

  if ( $self->report_period eq 'Daily' ) {
    return DateTime->new(
      year  => $self->run_date->year,
      month => $self->run_date->month,
      day   => $self->run_date->day,
    );
  }
  elsif ( $self->report_period eq 'Monthly'
    || $self->report_period eq 'MonthToDate' )
  {
    return DateTime->new(
      year  => $self->run_date->year,
      month => $self->run_date->month,
      day   => 1,
    );
  }
  elsif ( $self->report_period eq 'Weekly' ) {

    my $dt = DateTime->new(
      year  => $self->run_date->year,
      month => $self->run_date->month,
      day   => $self->run_date->day,
    );

    my $dow = $dt->day_of_week();

    $dt->set_day( $dt->day - ( $dow % 7 ) );

    return $dt;
  }
  elsif ( $self->report_period eq 'PriorMonth' ) {
    my $first_dom = DateTime->new(
      year  => $self->run_date->year,
      month => $self->run_date->month,
      day   => 1,
    );
    
    my $one_month = DateTime::Duration->new( months => 1 );
    
    return $first_dom - $one_month;
  }
  elsif ( $self->report_period eq 'SemiMonthly' ) {
    
    if ( $self->run_date->day <= 15 ) {
      return DateTime->new(
        year  => $self->run_date->year,
        month => $self->run_date->month,
        day   => 1,
      );     
    }
    else {
      return DateTime->new(
        year  => $self->run_date->year,
        month => $self->run_date->month,
        day   => 16,
      );     
    }
  }
  elsif ( $self->report_period eq 'AdHoc' ) {
    return DateTime->new(
      year  => $self->run_date->year,
      month => $self->run_date->month,
      day   => $self->run_date->day,
    );
  }  

  # this will throw a moose error, unless undef is coerced into DateTime->now
  return;
}

sub _build_report_period_end_dt {
  my $self = shift;

  if ( $self->report_period eq 'Daily'
    || $self->report_period eq 'MonthToDate' )
  {
    return DateTime->new(
      year   => $self->run_date->year,
      month  => $self->run_date->month,
      day    => $self->run_date->day,
      hour   => 23,
      minute => 59,
      second => 59,
    );
  }
  elsif ( $self->report_period eq 'Monthly' ) {

    return DateTime->last_day_of_month(
      year   => $self->run_date->year,
      month  => $self->run_date->month,
      hour   => 23,
      minute => 59,
      second => 59,
    );
  }
  elsif ( $self->report_period eq 'Weekly' ) {

    my $dt = DateTime->new(
      year   => $self->run_date->year,
      month  => $self->run_date->month,
      day    => $self->run_date->day,
      hour   => 23,
      minute => 59,
      second => 59,
    );

    my $dow = $dt->day_of_week();

    $dt->set_day( $dt->day - ( $dow % 7 ) + 6 );

    return $dt;
  }
  elsif ( $self->report_period eq 'PriorMonth' ) {
  
    my $one_month  = DateTime::Duration->new( months => 1 );
    my $last_month = $self->run_date - $one_month;
    
    my $last_dom = DateTime->last_day_of_month(
      year   => $last_month->year,
      month  => $last_month->month,
      hour   => 23,
      minute => 59,
      second => 59,
    );
    
    return $last_dom;
  }
  elsif ( $self->report_period eq 'SemiMonthly' ) {
    
    if ( $self->run_date->day <= 15 ) {
      return DateTime->new(
        year   => $self->run_date->year,
        month  => $self->run_date->month,
        day    => 15,
        hour   => 23,
        minute => 59,
        second => 59,        
      );     
    }
    else {
      return DateTime->last_day_of_month(
        year   => $self->run_date->year,
        month  => $self->run_date->month,
        hour   => 23,
        minute => 59,
        second => 59,
      );    
    }
  }
  elsif ( $self->report_period eq 'AdHoc' ) {
    return DateTime->new(
      year  => $self->end_date->year,
      month => $self->end_date->month,
      day   => $self->end_date->day,
    );
  }  

  return;
}

## Hack ##
# mentioned above, near has '+run_date'
  eval q{
    no warnings;  #suppress subroutine redefined warning
    sub Moose::Meta::Attribute::legal_options_for_inheritance {
    
      # original options
      my @options = qw(
		  default coerce required 
		  documentation lazy handles 
		  builder type_constraint
		  definition_context
		  lazy_build
      );
      
      push @options, 'trigger';  # newly added
      return @options;
    }  
  };
  confess $@ if $@;  
## /Hack ##

1;
__END__

=head1 NAME

TechSafari::Reports::Attributes::ReportPeriod - Moose Role providing 
period attributes.

=head1 WARNING

Illegal inherited options => (trigger)

If you ever see this error -- modify the hack

=head1 ATTRIBUTES

=head2 report_period

This is an enum, valid values are: Daily Weekly Monthly MonthToDate PriorMonth
SemiMonthly.

The default value is Daily.

=head2 report_period_start_dt isa DateTime

The start and end dates are based on the run_date and the report_period 
settings.  These attributes are lazily defined, and will change after changing 
the report_period.

These attributes are setup automagically.

Here's an example of the magic:

  $self->run_date( '2008-04-20' );

  $self->report_period( 'Daily' );
  $self->report_period_start_dt  eq '2008-04-20 00:00:00';
  $self->report_period_end_dt    eq '2008-04-20 23:59:59';

  $self->report_period( 'Monthly' );
  $self->report_period_start_dt  eq '2008-04-01 00:00:00';
  $self->report_period_end_dt    eq '2008-04-30 23:59:59';

  # etc... for Weekly, MonthToDate...
  
Weekly is Sunday to Saturday. MonthToDate is the first day of the month
to the run_date.

=head2 report_period_end_dt isa DateTime

=DESCRIPTION

For more info on how this role works, see the t/01_report_period_role.t


