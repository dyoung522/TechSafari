package Rhino2::BasicRoyaltyGroups;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
extends 'Rhino2::BasicReport';

###############################################################################
### Attributes
################################################################################

## Additional Public Attributes ##

# Royalty groups to present
# array of rg_desc_txt from royalty groups
has 'royalty_groups' => (
  is      => 'rw',
  isa     => 'ArrayRef',
  default => sub {
    [
      'Beacon 5.0 Score',
      'Beacon 5.0 Auto',
      'Bankruptcy File',
      'Demographic File',
      'Equifax Auto Triggers',
      'Equifax Mortgage Triggers',
      'Tax Assessor',
      'Telephone',
      'ITA File',
      'Student Loan',
      'EFX Credit Auto',
      'EFX Credit Mtg',
      'PreMover File',
      'New Mover File (Volt)',
      'EFX General',
    ];
  },
);

## Private Attributes ##

###############################################################################
### Methods
################################################################################

sub process {
  my $self = shift;

  my %args = $self->process_query_args;

  $self->generate_invoice_query(%args);
  $self->generate_no_bill_query(%args);
  $self->generate_royalty_groups_summary();
  
  return 1;
}


sub generate_invoice_query {
  my ( $self, %args ) = @_;

  # Run main query
  my $tbl = $self->sql->invoice_query(%args);

  # Get column info from query results
  my $cols   = $self->sql->last_column_names;
  my $cindex = $self->sql->last_column_index;    # index does not include rg's

  $self->_add_royalty_group_columns( $tbl, $cols );

  # Hints on Column formatting
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
  my $cindex = $self->sql->last_column_index;    # index does not include rg's

  $self->_add_royalty_group_columns( $tbl, $cols );

  # Apply formatting to columns
  my @types = map { 'None' } @{$cols};
  $types[ $cindex->{'Order Date'} ]   = 'Date';
  $types[ $cindex->{'Record Count'} ] = 'Number';

  # Create the worksheet
  my $sheet = TechSafari::Reports::Worksheet->new(
    name  => "Non Billed Orders - $args{name}",
    title => $self->report_period . " Non Billed Orders - $args{title}",
    table => $tbl,

    col_labels => $cols,
    col_types  => \@types,

    cols_to_splice => [ $cindex->{'count_id'}, $cindex->{'product_id'} ],

    cols_to_summarize => [ $cindex->{'Record Count'} ],
  );

  return $self->add_worksheet($sheet);

}

## generate_royalty_groups_summary
# rollup/summarize the other queries after process().
#
# No need to run another query, we can just use the results from the other
# queries
#
# This subclass is not overriding the process() method from the super class:
# Rhino2::BasicReport.  For more info on 'after', perldoc Moose.
sub generate_royalty_groups_summary {
  my $self = shift;

  my @rg_cols = map { _rg_header_label($_) } sort @{ $self->royalty_groups };

  my %summary;    # we're summarizing by date, the key to this hash is the date

  # summarize the worksheets we already created.
  for my $sheet ( @{ $self->workbook->worksheets } ) {

    my $date_index;
    if ( exists $sheet->col_index->{'Invoice Date'} ) {
      $date_index = $sheet->col_index->{'Invoice Date'};
    }
    elsif ( exists $sheet->col_index->{'Order Date'} ) {
      $date_index = $sheet->col_index->{'Order Date'};
    }
    else {
      Carp::carp 'No date column found in worksheet: '
        . $sheet->name
        . ' ...skipping for summary';
      next;
    }

    for my $row ( @{ $sheet->table } ) {
      my $record_count = $row->[ $sheet->col_index->{'Record Count'} ];
      my $date         = $row->[$date_index];

      # initialize running total with 0's
      if ( not exists $summary{$date} ) {
        my @zeros = map { 0 } ( 'Record Count', @rg_cols );
        $summary{$date} = \@zeros;
      }

      $summary{$date}->[0] += $record_count;    #total Record Count

      # loop over royalty groups, adding to total if the royalty group had
      # an indicator on the worksheet ( Ex:  'X' ).
      for my $i ( 0 .. $#rg_cols ) {
        my $rg_name  = $rg_cols[$i];
        my $rg_index = $sheet->col_index->{$rg_name};

        if ( $row->[$rg_index] ) {
          $summary{$date}->[ $i + 1 ] += $record_count;
        }
      }
    }

  }

  # Create the new worksheet
  my @table;
  for my $date ( sort keys %summary ) {
    push @table, [ $date, @{ $summary{$date} } ];
  }

  my @cols = ( 'Date', 'Record Count', @rg_cols );
  my @types = ( 'Date', 'Number', map { 'Number' } @rg_cols );

  my $sheet = TechSafari::Reports::Worksheet->new(
    name       => 'Royalty Group Summary',
    title      => $self->report_period . ' Royalty Group Summary',
    table      => \@table,
    col_labels => \@cols,
    col_types  => \@types,

    cols_to_summarize => [ 1 .. $#cols ],
  );

  return $self->add_worksheet($sheet);
};

## Private methods ##

# This modifies the table and cols in place.
#  They're pass'd by reference, so to speak.
sub _add_royalty_group_columns {
  my ( $self, $table, $cols ) = @_;

  # Set up royalty group column headers
  my @rg_cols = map { _rg_header_label($_) } sort @{ $self->royalty_groups };

  # Add royalty group columns to cols header and column index.
  push @{$cols}, @rg_cols;
  my %cindex = map { $cols->[$_] => $_ } 0 .. $#{$cols};

  # Add royalty groups to each row
  for my $row ( @{$table} ) {

    # add blank columns to supress 'uninitilized string' warnings
    push @{$row}, map { q{} } @rg_cols;

    my $count_id   = $row->[ $cindex{count_id} ];
    my $product_id = $row->[ $cindex{product_id} ];

    # query selects and product royalty groups
    my @sel_rgs = @{ $self->sql->selects_royalty_groups($count_id) };
    my $prd_rgs = $self->sql->products_royalty_group($product_id);

    # Loop over selects' royalty groups
    for my $rg_name ( @sel_rgs, $prd_rgs  ) {
      my $label = _rg_header_label($rg_name);
      if ( exists $cindex{$label} ) {
      
        # Depending on the report_period, we put 'X' or the record count
        if ( $self->report_period eq 'Monthly' ) {
          $row->[ $cindex{$label} ] = $row->[ $cindex{'Record Count'} ]; 
        }
        else {
          $row->[ $cindex{$label} ] = 'X';  # 'S' or 'P'
        }
      }
    }
    
    ### Commented out b/c included in loop with selects. 
    ## product's royalty group
    #my $label = _rg_header_label( $prd_rgs );
    #if ( exists $cindex{$label} ) {
    #  $row->[ $cindex{$label} ] = 'P';
    #}
    
  }

  return $table;
}

sub _rg_header_label {
  my $rg_name = pop;

  my %map = (
    'EFX Credit Auto'           => 'EFX-AUTO',
    'EFX Credit Mtg'            => 'EFX-MTG',
    'Beacon 5.0 Score'          => 'B50',
    'Beacon 5.0 Auto'           => 'BAuto',
    'Bankruptcy File'           => 'BK',
    'Demographic File'          => 'Demo',
    'Equifax Auto Triggers'     => 'ATrig',
    'Equifax Mortgage Triggers' => 'MTrig',
    'Tax Assessor'              => 'Fares',
    'Telephone'                 => 'Phone',
    'ITA File'                  => 'ITA',
    'Student Loan'              => 'Student',
    'PreMover File'             => 'PreMover',
    'New Mover File (Volt)'     => 'NewMover',
    'ARM File'                  => 'ARM',
    'EFX General'               => 'EFX-GEN',
  );

  if ( !$rg_name ) {
    return 'None';
  }
  if ( exists $map{$rg_name} ) {
    return $map{$rg_name};
  }

  return $rg_name;
}

1;

__END__

=head1 NAME

Rhino2::BasicRoyaltyGroups - Basic Report with royalty groups.

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

This is a subclass of the basic report.  It makes use of the basic report's 
attributes:  hosts, companies, date stuff, etc.  And the basic report's
process_query_args method.

The additional reporting done is:

  1) replacing the data source name with royalty groups, and 
  2) adding a summary / roll up of royalty groups by date.

See L<Rhino2::BasicReport> for more information.

=head1 ATTRIBUTES

See L<Rhino2::BasicReport>

Additional attributes: royalty_groups

=head1 METHODS

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$

