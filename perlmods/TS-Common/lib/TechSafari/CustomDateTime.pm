
=pod

=head1 NAME

CustomDateTime - This is a class which defines the DateType subtype
and provides some coercions and date calculation routines.

=head1 DESCRIPTION

This class is not really meant to be instantiated.

The initial implementation of this DateTime stuff is through DateTime and 
Date::Manip.  Date::Manip is a HUGE perl module that is not built for 
performance.  

TODO: Rewrite/search for faster DateTime calculation stuff to greatly
improve performance by removing Date::Manip dependency.

As an initial implementation of the TODO above, I have short-cut common
date formats to avoid the Date

=head1 SUBTYPES

DateTime - can be coerced from a string or a hashref.

=cut

package TechSafari::CustomDateTime;

use Moose;
use Moose::Util::TypeConstraints;

use Carp;

use DateTime;
use DateTime::Duration;
use DateTime::Format::DateManip;
use DateTime::Format::MySQL;

## Sub routines ###
=head1 UTILITY METHODS 

=over

=item format_date ( $date [DateTime] )

Pass in a date, this formats it to the format we're using to pass to the database

=cut

sub format_date { 
  my $dt = pop;
  $dt = convert_to_datetime($dt);
  return DateTime::Format::MySQL->format_date($dt) 
}

=item convert_to_datetime ( $something )

pass something in, try to convert it to a datetime.

something = a DateTime object, a string, a hashref, a hash, undef

=item convert_str_to_datetime ( $string )

pass in a string and try to convert it to a datetime.  this tries to shortcut
common dates before eventually using Date::Manip to do the conversion

=cut

sub convert_to_datetime {
  my $class = shift if defined $_[0] && $_[0] eq __PACKAGE__;
  my $dt    = shift;
  my @rest  = @_;
  my $ret;
  
  if ( blessed $dt and blessed $dt eq 'DateTime' ) {
    $ret = $dt;
  }
  elsif ( not defined $dt ) {
    $ret = DateTime->new(year => 1978);
  }  
  elsif ( @rest ) {
    $ret = DateTime->new($dt, @rest);
  }
  elsif ( ref $dt eq 'HASH' ) {
    $ret = DateTime->new(%$dt);
  }
  elsif ( not ref $dt ) {
    $ret = __PACKAGE__->convert_str_to_datetime($dt);
  }
  else {
    Carp::croak "Can't convert whatever to DateTime: " . ref $dt;
  }

  return $ret;
}

sub convert_str_to_datetime {
  my $class = shift if $_[0] eq __PACKAGE__;
  my $str   = shift;
  my $ret;
  
  if ( $str =~ m/^(\d{4})(\d{2})(\d{2})$/ ) {
    $ret = DateTime->new( year => $1, month => $2, day => $3 );
  }
  elsif ( $str =~ m/^(\d{4})-(\d{2})-(\d{2})$/ ) {
    $ret = DateTime->new( year => $1, month => $2, day => $3 );
  }
  elsif ( $str =~ m{^(\d\d?)/(\d\d?)/(\d{4})$} ) {
    $ret = DateTime->new( year => $3, month => $1, day => $2 );
  }
  elsif ( lc $str eq 'current' ) {
    $ret = DateTime->today();
  }
  elsif ( lc $str eq 'yesterday' ) {
    $ret = DateTime->today();
    $ret->subtract( DateTime::Duration->new( days => 1 ) );
  }
  elsif ( $str =~ m{^\d{10}$} ) {
    $ret = DateTime->from_epoch( epoch => $str );
  }
  else {
    # this is the slow way
    $ret = DateTime::Format::DateManip->parse_datetime($str);
  }
  return $ret;
}

=item convert_unix_to_mysql

=item convert_mysql_to_unix

=cut

sub convert_unix_to_mysql {
  my $unix = pop;
  my $dt = DateTime->from_epoch( epoch => $unix );
  return DateTime::Format::MySQL->format_datetime($dt);  
}

sub convert_mysql_to_unix {
  my $mysql = pop;
  my $dt = DateTime::Format::MySQL->parse_datetime( $mysql );
  return $dt->epoch;
}


=item months_since ( $date [DateTime] )

Pass in a past date, return the number of months from the date to now.

This sub can run as class method, instance method, or package subroutine

=cut 

sub months_since {
  my $prior_date = pop;
  $prior_date = convert_to_datetime($prior_date);  
  
  my $current_date = DateTime->now;
   
  my $delta = DateTime::delta_md($prior_date, $current_date);
         
  return $delta->years * 12 + $delta->months; 
}

1;

=item months_ago ( $int )

Pass in a number, this returns a date $int months prior to now()

=cut

sub months_ago {
  my $months = pop;
  
  my $delta = DateTime::Duration->new( months => $months );
  
  my $date = DateTime->now->subtract_duration($delta);
  
  return $date;  
}

=item months_ago ( $int )

Pass in a number, this returns a date $int days prior to now()

=cut

sub days_ago {
  my $days = pop;
  
  my $delta = DateTime::Duration->new( days => $days );
  
  my $date = DateTime->now->subtract_duration($delta);
  
  return $date;  
}

=item within_interval($date, $months)

Return true/false whether the current date ( now() ) is within $months from
$date

=cut

sub within_interval {
  my $class = shift if defined $_[0] && $_[0] eq __PACKAGE__;
  my ( $date, $months ) = @_;

  return months_since($date) < $months;
}

=compare($date1, $date2) 

Return true/false whether the two datetimes are the same day

=cut

sub compare_dates {
  my $class = shift if defined $_[0] && $_[0] eq __PACKAGE__;
  my $date1 = convert_to_datetime( shift @_ );
  my $date2 = convert_to_datetime( shift @_ );  
  
  return -1 if $date1 < $date2;
  return  1 if $date1 > $date2;
  return  0;  
}

=item same_day($date1, $date2) 

Return true/false whether the two datetimes are the same day

=cut

sub same_day {
  my $class = shift if defined $_[0] && $_[0] eq __PACKAGE__;
  my $date1 = convert_to_datetime( shift @_ );
  my $date2 = convert_to_datetime( shift @_ );  
  
  my $delta = DateTime::subtract_datetime($date1, $date2);
  
  return $delta->delta_days == 0 && $delta->delta_months == 0 
         && $delta->years == 0;
}

=item is_today($date) {

is the date today?

=cut

sub is_today {
  my $dt = pop;
  return same_day(DateTime->now(), $dt);
}

=item within_one_day

a little different from is date today - this is within the last 24 hours.

=cut

sub within_one_day {
  my $dt = pop;
  return within_days( $dt, DateTime->now, 1);
}


=item within_days ( $date1, $date2, $days )

Boolean - within days takes hours into account, so

'2008-05-15 10:00:00' is within 1 day of '2008-05-16 09:00:00', but
'2008-05-15 08:00:00' is not within 1 day b/c there is a 24 hour difference

=cut

sub within_days {
  my $class = shift if defined $_[0] && $_[0] eq __PACKAGE__;
  my $date1 = convert_to_datetime( shift @_ )->clone;
  my $date2 = convert_to_datetime( shift @_ )->clone; 
  my $days  = shift;

  my $delta = DateTime::Duration->new( days => $days );
  
  if ( $date1 > $date2 ) {
    $date1->subtract_duration($delta);  
    return $date1 <= $date2;
  }
  else {
    $date2->subtract_duration($delta);
    return $date2 <= $date1;
  }
}

=item near_quarter($date) 

is today within some multiple of a quarter past the given date?

ex: the given date is 1/1/08, this will return true if the date is within a
week of 4/1/08, 7/1/08, 10/1/08, ...

the ranges would be 4/1/08 - 4/7/08, 

=cut

sub near_quarter {
  my $dt  = convert_to_datetime( pop @_ );
  my $today = DateTime->today();

  my $delta = DateTime::subtract_datetime($today, $dt);
  
  # print "Delta: ", $delta->delta_days, ",", $delta->delta_months, "\n";
  # Only return true if with 7 days after the reference date, and not before
  return ($delta->delta_months % 3) == 0 && ($delta->delta_days >= 0 && $delta->delta_days < 7);
}



__END__

=back
