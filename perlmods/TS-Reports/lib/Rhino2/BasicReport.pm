
package Rhino2::BasicReport;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Carp;

use Moose;
use Moose::Util::TypeConstraints;

with 'TechSafari::Reports::Interface';    #provides run_date and workbook

use Rhino2::BaseSQL;

################################################################################
### Attributes
################################################################################

subtype 'Rhino2::BasicReport::ArrayRef' => as 'ArrayRef' => where { 1 };
coerce  'Rhino2::BasicReport::ArrayRef' => from 'Value'  => via { [$_] };

### Public Attributes ###
with 'TechSafari::Reports::Attributes::DBH';
with 'TechSafari::Reports::Attributes::ReportPeriod';

has 'hosts' => (
  is        => 'rw',
  isa       => 'Rhino2::BasicReport::ArrayRef',
  predicate => 'has_hosts',
  coerce    => 1,
);

has 'companies' => (
  is        => 'rw',
  isa       => 'Rhino2::BasicReport::ArrayRef',
  predicate => 'has_companies',
  coerce    => 1,
);

has 'no_date_flag' => (
  is      => 'rw',
  isa     => 'Bool',
  default => 0,
);

### Private Attributes
has 'sql' => (
  is         => 'rw',
  isa        => 'Rhino2::BaseSQL',
  lazy_build => 1,
);

# overwritable in sub classes - builder for 'sql' attribute, created
# automatically by 'lazy_build => 1'
sub _build_sql {
  my $self = shift;
  return Rhino2::BaseSQL->new( dbh => $self->dbh );
}

################################################################################
### Instance Methods
################################################################################

sub process {
  my $self = shift;

  my %args = $self->process_query_args;

  $self->generate_invoice_query(%args);
  $self->generate_no_bill_query(%args);

  return 1;
}

sub generate_invoice_query {
  my ( $self, %args ) = @_;

  # Run main query
  my $tbl = $self->sql->invoice_query(%args);

  # Get column info from query results
  my $cols   = $self->sql->last_column_names;
  my $cindex = $self->sql->last_column_index;

  # Add data source name based on product_id or count_id
  push @{$cols}, 'Data Source';
  for my $row ( @{$tbl} ) {
    push @{$row}, $self->sql->data_source_name(
      product_id => $row->[ $cindex->{'product_id'} ],
      count_id   => $row->[ $cindex->{'count_id'} ]
    );
  }

  # Apply formatting to columns
  my @types = map { 'None' } @{$cols};
  $types[ $cindex->{'Invoice Date'} ]  = 'Date';
  $types[ $cindex->{'Billed Amount'} ] = 'Currency';
  $types[ $cindex->{'Record Count'} ]  = 'Number';

  # Create the worksheet
  my $sheet = TechSafari::Reports::Worksheet->new(
    name  => "Billed Invoices - $args{name}",
    title => $self->report_period . " Billed Invoices - $args{title}",
    table => $tbl,

    col_labels => $cols,
    col_types  => \@types,

    cols_to_splice => [ $cindex->{'count_id'}, $cindex->{'product_id'} ],

    cols_to_summarize =>
      [ $cindex->{'Billed Amount'}, $cindex->{'Record Count'} ],
  );

  return $self->add_worksheet($sheet);
}

sub generate_no_bill_query {
  my ( $self, %args ) = @_;

  # Run main query
  my $tbl = $self->sql->non_billed_orders_query(%args);

  # Get column info from query results
  my $cols   = $self->sql->last_column_names;
  my $cindex = $self->sql->last_column_index;

  # Add data source name based on product_id or count_id
  push @{$cols}, 'Data Source';
  for my $row ( @{$tbl} ) {
    push @{$row}, $self->sql->data_source_name(
      product_id => $row->[ $cindex->{'product_id'} ],
      count_id   => $row->[ $cindex->{'count_id'} ]
    );
  }

  # Apply formatting to columns
  my @types = map { 'None' } @{$cols};
  $types[ $cindex->{'Order Date'} ]   = 'Date';
  $types[ $cindex->{'Record Count'} ] = 'Number';

  # Create the worksheet
  my $sheet = TechSafari::Reports::Worksheet->new(
    name  => "Non Billed Invoices - $args{name}",
    title => $self->report_period . " Non Billed Invoices - $args{title}",
    table => $tbl,

    col_labels => $cols,
    col_types  => \@types,

    cols_to_splice => [ $cindex->{'count_id'}, $cindex->{'product_id'} ],

    cols_to_summarize => [ $cindex->{'Record Count'} ],
  );

  return $self->add_worksheet($sheet);
}

sub process_query_args {
  my $self = shift;

  confess 'No hosts or companies specified.'
    unless $self->has_hosts || $self->has_companies;

  my %args;

  if ( $self->has_companies ) {

    my ( @cp_ids, $cp );
    for my $company ( @{ $self->companies } ) {
      $cp = $self->sql->company_info($company);
      push @cp_ids, $cp->{id};
    }

    $args{company_id} = \@cp_ids;

    if ( scalar(@cp_ids) == 1 ) {
      $args{name}  = $cp->{cp_name_txt};
      $args{title} = $cp->{cp_name_txt};
    }
    else {
      $args{name}  = 'Multiple companies.';
      $args{title} = 'Multiple companies.';
    }

  }

  if ( $self->has_hosts ) {

    my ( @host_ids, $host );
    for my $host_id ( @{ $self->hosts } ) {
      $host = $self->sql->host_info($host_id);
      push @host_ids, $host->{id};
    }

    $args{host_id} = \@host_ids;

    if ( scalar(@host_ids) == 1 ) {
      $args{name}  = $host->{h_desc_txt};
      $args{title} = "$host->{h_desc_txt} ($host->{h_url_prefix_txt})";
    }
    else {
      $args{name}  = 'Multiple hosts.';
      $args{title} = 'Multiple hosts.';
    }

  }

  if ( not $self->no_date_flag ) {
    $args{start_dt} = $self->report_period_start_dt;
    $args{end_dt}   = $self->report_period_end_dt;
  }

  return %args;
}

1;

__END__

=head1 NAME

Rhino2::BasicReport - Basic report including invoices and non-billed orders.

This report is the superclass of a few other reports, as it provides common
attributes and functionality.

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

=head1 ATTRIBUTES

Subclasses should know that this report provides a number of attributes:

=head2 common attributes

workbook, run_date, report_period, report_period_start_dt, report_period_end_dt

For more info on these common attributes, refer to the respective Moose Roles
under TechSafari::Reports::Attributes::XXX

=head2 hosts

A list of hosts, which can be specified by either host id or host description
(h_desc_txt).

The report is constrained to the list of hosts and companies provided. If 
companies are also specified, the report is further constrained.  The report 
won't run unless either hosts or companies are specified.  

=head2 companies

A list of companies, which can be specified by either company id or company
name (c_name_txt).

See also, hosts attribute

=head2 no_date_flag

To run a report that is not constrained by some time period, this flag must
be explicitly set. 

By default, if the run_date and report_period are not set, the report will
run for the current day.

=head2 sql

This is a private attribute used internally, containing all the queries for
the report.  It lazily defaults to L<Rhino2::BaseSQL>

Sub classes should know that the sql attribute can be updated to SQL subclasses
of L<Rhino2::BaseSQL>, by overriding the _build_sql() method

=head1 METHODS

The only method a user of this report needs is process(), however sub classed
reports may need to know about: process_query_args, generate_invoice_query,
generate_no_bill_query.

=head2 process

=head2 process_query_args

Generates query conditions based on the hosts, companies, report_period, 
run_date, and no date flag.

Returns an %args hash to be passed into the queries in BaseSQL.

Confesses (dies) if no hosts or companies are specified, to try to keep the
data set a manageble size.

=head2 generate_invoice_query

Invoices created as an individual worksheet.

=head2 generate_no_bill_query

Non billed orders as an individual worksheet

=head1 DEPENDENCIES

Moose, Rhino2::BaseSQL

=head1 AUTHOR

$Author$

