
package Rhino2::ActivityReport;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Carp;

use Moose;
use Moose::Util::TypeConstraints;

with 'TechSafari::Reports::Interface';    #provides run_date and worksheets

use Rhino2::BaseSQL;

################################################################################
### Attributes
################################################################################

subtype 'Rhino2::ActivityReport::ArrayRef' => as 'ArrayRef' => where { 1 };
coerce 'Rhino2::ActivityReport::ArrayRef'  => from 'Value'  => via   { [$_] };

### Public Attributes ###
with 'TechSafari::Reports::Attributes::DBH';
with 'TechSafari::Reports::Attributes::ReportPeriod';

# Generate dailyreports for the following hosts - array can contain
# host name or host ids.  Ex: [2,6] or ['Name Seeker Inc.', 'Market Fox']
has 'hosts' => (
  is      => 'rw',
  isa     => 'Rhino2::ActivityReport::ArrayRef',
  coerce  => 1,
  default => sub {
    [

      'Name Seeker Inc.',

      # 'Market Fox',

    ];
  },
  trigger => sub {
    my $self = shift;
    $self->clear_host_check;
  },
);

has 'report_period_list' => (
  is  => 'rw',
  isa => 'ArrayRef[TSR::Attributes::ReportPeriodType]',    # see attrs:reportper
  default => sub {
    [ 'Daily', 'MonthToDate', 'PriorMonth', ];
  },
);

### Private Attributes
has 'sql' => (
  is      => 'rw',
  isa     => 'Rhino2::BaseSQL',
  lazy    => 1,
  default => sub {
    my $self = shift;
    Rhino2::BaseSQL->new( dbh => $self->dbh );
  },
);

# Counting / Summary rules
# The values here are dependent on the database values. look at 
# royalty_groups.rg_name_txt, products.p_name_txt, hosts.h_desc_txt
# Rules are implemented in _rule_applies method
has 'activity_summary_rules' => (
  is  => 'rw',
  isa => 'ArrayRef[ArrayRef]',

  default => sub {
    [
      [
        'Auto Prescreen' => {
          product_royalty_group => 'EFX Credit Auto',
          disallowed_selects    => ['Equifax Auto Triggers'],
        }
      ],
      [
        'Mortgage Prescreen' => {
          product_royalty_group => 'EFX Credit Mtg',
          disallowed_selects    => ['Equifax Mortgage Triggers'],
        }
      ],
      [
        'Auto Trigger' => {
          product_royalty_group => 'EFX Credit Auto',
          required_selects      => ['Equifax Auto Triggers'],
        }
      ],
      [
        'Mortgage Trigger' => {
          product_royalty_group => 'EFX Credit Mtg',
          required_selects      => ['Equifax Mortgage Triggers'],
        }
      ],
      [ 'Bankruptcy' => { product_royalty_group => 'Bankruptcy File' } ],
      [ 'ITA'        => { product_royalty_group => 'ITA File' } ],
      [ 'Fares'      => { product_royalty_group => 'Tax Assessor' } ],
      [ 'New Mover'  => { product_royalty_group => 'New Mover File (Volt)' } ],
      [ 'Pre Mover'  => { product_royalty_group => 'PreMover File' } ],

      [
        'Move Signals / Masada New Mover' => {
          product_name        => 'New Movers File',
          
          # This is possible, and I've included it here as a reasonable default.
          # However, I don't think it is the best way to do it.  All of these
          # rules can be specified in the configuration file.  I think it would
          # be best to change the rules there -- in terms of management and 
          # design.  See ts_reports.yml
          #
          # One problem with doing it here is that I designed all of the reports
          # to work across all hosts, and I don't like including host specific
          # information in each report.  THe rhino2 application is designed to 
          # work with many different hosts, and so should the reports.  Also,
          # new rules could be added without any code changes in the reports.
          limit_rule_to_hosts => [ 'Masada', 'Move Signals' ],
        }
      ],

      [
        'LSSi/Volt New Mover' => {
          product_name        => 'LSSi/Volt New Mover',
          limit_rule_to_hosts => [ 'Masada', 'Move Signals' ],
        }
      ],


      [
        'Equifax no FICO'     => { 
          product_name        => 'Equifax Credit Data - General',
          limit_rule_to_hosts => [ 'Name Seeker Inc.' ],
        }
      ],

    ];
  },

);

has 'host_check' => (
  is         => 'rw',
  isa        => 'HashRef',
  lazy_build => 1,
);

################################################################################
### Instance Methods
################################################################################

sub process {
  my $self = shift;

  for my $period ( @{ $self->report_period_list } ) {
    $self->generate_activity_report($period);
  }

  return 1;
}

sub generate_activity_report {
  my ( $self, $period ) = @_;

  # Look up host info
  my ( @host_ids, @host_names );
  for my $host_id ( @{ $self->hosts } ) {
    my $host = $self->sql->host_info($host_id);
    push @host_ids,   $host->{id};
    push @host_names, $host->{h_desc_txt};
  }

  $self->hosts( \@host_names );

  # Setting this automagically updates $self->report_period_start_dt and end_dt
  # See TSR::Attributes::ReportPeriod
  $self->report_period($period);

  # Run invoice query
  my $invoices = $self->sql->invoice_query(
    start_dt => $self->report_period_start_dt,
    end_dt   => $self->report_period_end_dt,
    host_id  => \@host_ids,
  );
  my $cindex = $self->sql->last_column_index;

  # Initialize %totals w/0's
  # keyd by rule name => [ record count, billed amount ]
  my %totals = map { $_->[0] => [ 0, 0 ] } @{ $self->activity_summary_rules };

  # Loop through invoices - summarize the invoice query
  for my $invoice ( @{$invoices} ) {

    my $hits = 0;
    my @hit_rules;

    # Try to apply every rule to the invoice
    for my $rule ( @{ $self->activity_summary_rules } ) {

      my $rule_name  = $rule->[0];
      my $product_id = $invoice->[ $cindex->{'product_id'} ];
      my $count_id   = $invoice->[ $cindex->{'count_id'} ];

      if ( $self->_rule_applies( $rule, $product_id, $count_id ) ) {
        $totals{$rule_name}->[0] += $invoice->[ $cindex->{'Record Count'} ];
        $totals{$rule_name}->[1] += $invoice->[ $cindex->{'Billed Amount'} ];

        $hits += 1;
        push @hit_rules, $rule_name;
      }
    }

    ## Should all invoices be counted once and only once?  I am not enforcing
    # it this way, but the report is flexible enough to allow invoices to be
    # counted in different rows.
    #
    # Right now, if a particular invoice does not hit on only 1 rule, carp.
    #   maybe should confess?
    if ( $hits == 0 ) {
      carp 'WARNING: invoice.id ('
        . $invoice->[ $cindex->{'Invoice'} ]
        . ') counted in 0 summaries';
    }
    elsif ( $hits > 1 ) {
      carp 'WARNING: invoice.id ('
        . $invoice->[ $cindex->{'Invoice'} ]
        . ") counted in $hits summaries. [ "
        . ( join ', ', @hit_rules ) . ' ]';
    }
  }

  ## Build Worksheet ##
  my @table;
  my $count = 1;
  
SUMMARY_ROW:
  for my $item_num ( 1 .. scalar @{ $self->activity_summary_rules } ) {
    my $rule      = $self->activity_summary_rules->[ $item_num - 1 ];
    my $rule_name = $rule->[0];

    # Don't present summary for rules that were limited to particular hosts
    next SUMMARY_ROW unless $self->_rule_applies_to_hosts($rule);

    my $avg = 0;
    if ( $totals{$rule_name}->[0] != 0 ) {
      $avg = $totals{$rule_name}->[1] / $totals{$rule_name}->[0];
    }

    push @table, [ $count, $rule_name, @{ $totals{$rule_name} }, $avg ];
    $count += 1;
  }

  my $cols  = [ 'Item #', 'Description', 'Records', 'Revenue',  'Average' ];
  my $types = [ 'None',   'None',        'Number',  'Currency', 'Decimal' ];

  my $title;
  if ( $period eq 'PriorMonth' || $period eq 'Monthly' ) {
    $title =
        "$period Activity Report for "
      . $self->report_period_start_dt->month_abbr . q{ }
      . $self->report_period_start_dt->year;
  }
  else {
    $title = "$period Activity Report as of " . $self->run_date->ymd;
  }

  my $sheet = TechSafari::Reports::Worksheet->new(
    name       => "$period Activity Report",
    title      => $title,
    table      => \@table,
    col_labels => $cols,
    col_types  => $types,

    cols_to_summarize => [ 'Records', 'Revenue' ],
  );

  return $self->add_worksheet($sheet);
}

## Private methods ##

sub _rule_applies {
  my ( $self, $rule, $product_id, $count_id ) = @_;

  return unless $self->_rule_applies_to_hosts($rule);

  my $rule_h = $rule->[1];

  my ( $prd_rg, $prd_nm );

  if ( exists $rule_h->{'product_royalty_group'} ) {
    $prd_rg = $self->sql->products_royalty_group($product_id);
  }
  if ( exists $rule_h->{'product_name'} ) {
    $prd_nm = $self->sql->product_name($product_id);
  }

  if ( ( $prd_rg && $prd_rg eq $rule_h->{'product_royalty_group'} )
    || ( $prd_nm && $prd_nm eq $rule_h->{'product_name'} ) )
  {

    if ( exists $rule_h->{'required_selects'}
      || exists $rule_h->{'disallowed_selects'} )
    {
      my @sel_rgs = $self->sql->selects_royalty_groups($count_id);
      my %sel_rgh = map { $_ => 1 } @sel_rgs;
      my $r       = \%sel_rgh;

      if ( exists $rule_h->{'required_selects'} ) {
        for my $sel ( @{ $rule_h->{'required_selects'} } ) {
          return unless $sel_rgh{$sel};
        }
      }

      if ( exists $rule_h->{'disallowed_selects'} ) {
        for my $sel ( @{ $rule_h->{'disallowed_selects'} } ) {
          return if $sel_rgh{$sel};
        }
      }
    }

    return 1;
  }

  return;
}

sub _rule_applies_to_hosts {
  my ( $self, $rule ) = @_;

  if ( exists $rule->[1]->{limit_rule_to_hosts} ) {
    my $ok_host;
    for my $host ( @{ $rule->[1]->{limit_rule_to_hosts} } ) {
      if ( $self->host_check->{$host} ) {
        $ok_host = 1;
      }
    }
    return $ok_host;
  }

  return 1;
}

sub _build_host_check {
  my $self = shift;

  my %h = map { $self->hosts->[$_] => 1 } 0 .. scalar( @{ $self->hosts } ) - 1;

  return \%h;
}

1;

__END__

=head1 NAME

Rhino2::ActivityReport - Activity Report for NameSeeker.

=head1 VERSION

=over

=item $Id$

=item $Revision$

=item $HeadURL$

=item $Date$

=item $Source$

=back

=head1 SYNOPSIS

=head1 DESCRIPTION

This report has some custom rules for how to summarize products and selects
royalty groups.

=head1 ATTRIBUTES

=head2 run_date - default, today

=head2 hosts - default, NameSeeker.  

Not really meant for anything else...

=head2 report_period_list

List of report periods to generate reports on.  Default:

Daily,
MonthToDate,
PriorMonth

One worksheet is generated per period.

=head1 METHODS

=head2 process

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$

