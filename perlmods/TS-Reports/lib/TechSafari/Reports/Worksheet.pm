
package TechSafari::Reports::Worksheet;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Carp;
use Moose;
use Moose::Util::TypeConstraints;

my $constraint_finder = \&Moose::Util::TypeConstraints::find_type_constraint;

################################################################################
### Custom Type checking / Coercions
################################################################################

enum 'TRW::ColumnTypeEnum' =>
  qw( Currency Number Percentage Decimal Date Time DateTime None );

my $col_type_constraint = $constraint_finder->('TRW::ColumnTypeEnum');

enum 'TRW::SummarizableColumnTypeEnum' =>
  qw( Currency Number Percentage Decimal );

subtype 'ColumnTypeEnumArrayRef' => as 'ArrayRef' => where {
  my $ar = $_;
  for my $val ( @{$ar} ) {
    return unless $col_type_constraint->check($val);
  }
  return 1;
};

# Coerce undefined values to 'None'
coerce 'TRW::ColumnTypeEnum' => from 'Undef' => via { 'None' };

# Coerce all array values, if applicable
coerce 'ColumnTypeEnumArrayRef' => from 'ArrayRef' => via {
  my $ar = $_;
  for my $val ( @{$ar} ) {
    $val = $col_type_constraint->coerce($val);
  }
  return $ar;
};

################################################################################
### Attributes
################################################################################

### Public Attributes ###

has 'name' => ( is => 'rw', isa => 'Str', required => 1 );
has 'title' => ( is => 'rw', isa => 'Str' );

has 'col_types' => (
  is        => 'rw',
  isa       => 'ColumnTypeEnumArrayRef',
  predicate => 'has_col_types',
  coerce    => 1,
);

has 'table' => (
  is       => 'rw',
  isa      => 'ArrayRef[ArrayRef]',
  required => 1,
  trigger  => sub {
    my ( $self, $val, $meta ) = @_;
    $self->_inspect_table($val);
  },
);

has 'col_labels' => (
  is        => 'rw',
  isa       => 'ArrayRef',
  predicate => 'has_col_labels',
  trigger   => sub {
    my ( $self, $val, $meta ) = @_;
    $self->clear_col_index();
  },
);

has 'row_labels' => (
  is        => 'rw',
  isa       => 'ArrayRef',
  predicate => 'has_row_labels',
  trigger   => sub {
    my ( $self, $val, $meta ) = @_;
    $self->clear_row_index();
  }
);

has 'cols_to_splice' => ( is => 'rw', isa => 'ArrayRef[Value]' );

has 'cols_to_summarize' => (
  is        => 'rw',
  isa       => 'ArrayRef[Value]',
  predicate => 'has_cols_to_summarize',
  trigger   => sub {
    my ( $self, $val, $meta ) = @_;
    $self->clear_col_summary($val);
  },
);

has 'row_types_to_summarize' => (
  is        => 'rw',
  isa       => 'TRW::SummarizableColumnTypeEnum',
  predicate => 'has_row_types_to_summarize',
  trigger   => sub {
    my ( $self, $val, $meta ) = @_;
    $self->clear_row_summary($val);
  },
);

#### Automatically generated attributes ####

# The following attributes are automatically generated on triggers when
# other attributes are set.
# These attributes should not be set by users of this module, hence, the
# writers have been redefined.

has 'last_col_index' => (
  is     => 'rw',
  isa    => 'Int',
  writer => '_last_col_index',
);

has 'last_row_index' => (
  is     => 'rw',
  isa    => 'Int',
  writer => '_last_row_index',
);

has 'table_cols' => ( is => 'rw', isa => 'Int', writer => '_table_cols' );
has 'table_rows' => ( is => 'rw', isa => 'Int', writer => '_table_rows' );

has 'col_index' => (
  is  => 'rw',
  isa => 'HashRef[Int]',

  # lazy_build => 1 is a shortcut to the following attribute meta attributes
  lazy      => 1,
  predicate => 'has_col_index',
  clearer   => 'clear_col_index',
  writer    => '_col_index',
  builder   => '_build_col_index',
);

has 'row_index' => (
  is  => 'rw',
  isa => 'HashRef[Int]',

  lazy_build => 1,
);

has 'col_summary' => (
  is  => 'rw',
  isa => 'ArrayRef',

  lazy_build => 1,
);

has 'row_summary' => (
  is  => 'rw',
  isa => 'ArrayRef',

  lazy_build => 1,
);

################################################################################
### Methods
################################################################################

### Public Methods ###

sub splice_cols {
  my $self = shift;

  return unless defined $self->cols_to_splice and @{ $self->cols_to_splice };

  my @slice;
  my @to_be_spliced;

  my $row_max;
  if ( defined $self->table->[0] and @{ $self->table->[0] } ) {
    $row_max = scalar @{ $self->table->[0] } - 1;
  }
  elsif ( defined $self->col_labels and @{ $self->col_labels } ) {
    $row_max = scalar @{ $self->col_labels } - 1;
  }
  else {
    return;
  }

  # translate column labels for column indexes
  for my $col_label ( @{ $self->cols_to_splice } ) {
    if ( $col_label =~ m/^ \d+ $/x ) {
      push @to_be_spliced, $col_label;
    }
    else {
      if ( defined $col_label && exists $self->col_index->{$col_label} ) {
        push @to_be_spliced, $self->col_index->{$col_label};
      }
      else {
        carp "Can't splice '$col_label' because it is not a column.";
      }
    }
  }

  { # make array slice that is opposite of $self->col_splice (ie columns to keep)
    my %h = map { $_ => 1 } @to_be_spliced;
    @slice = grep { not exists $h{$_} } 0 .. $row_max;
  }

  # splice attributes related to columns - col_labels and col_types
  for my $attribute (qw/col_labels col_types/) {
    if ( defined $self->$attribute and @{ $self->$attribute } ) {
      my @tmp = @{ $self->$attribute }[@slice];
      $self->$attribute( \@tmp );
    }
  }
  
  # clear out col summary and index - will be regen'd
  $self->clear_col_summary();
  $self->clear_col_index();

  # splice every row in the table
  for my $row ( @{ $self->table } ) {
    my @tmp = @{$row}[@slice];
    $row = \@tmp;
  }

  return $self->cols_to_splice( [] );
}

### Private Methods ###

# Summarize the cols -  this is run on a trigger when cols_to_summarize is set.
sub _build_col_summary {
  my $self = shift;

  return unless $self->has_cols_to_summarize;

  my @slice;    # an array of indexes to summarize

  for my $col_label ( @{ $self->cols_to_summarize } ) {
    if ( $col_label =~ m/^ \d+ $/x ) {
      push @slice, $col_label;
    }
    else {
      if ( defined $col_label && exists $self->col_index->{$col_label} ) {
        push @slice, $self->col_index->{$col_label};
      }
      else {
        carp "Can't summarize '$col_label' because it is not a column.";
      }
    }
  }

  my $slice_len = scalar @slice;
  my @sum       = 0 x $slice_len;     #initialize with zeros

  for my $row ( @{ $self->table } ) {
    for my $i ( 0 .. $slice_len - 1 ) {
      $sum[$i] += $row->[ $slice[$i] ];
    }
  }

  my @sum_row = q{} x $self->table_rows;    # initialize with blanks
  for my $i ( 0 .. $slice_len - 1 ) {

    my $val = $sum[$i];

    # Round summaries based on formatting
    if ( $self->col_types->[ $slice[$i] ] eq 'Currency' ) {
      $val = sprintf '%.02f', $val;
    }
    elsif ( $self->col_types->[ $slice[$i] ] eq 'Percentage' ) {
      $val = sprintf '%.03f', $val;
    }

    $sum_row[ $slice[$i] ] = $val;

  }

  return \@sum_row;
}

sub _build_row_summary {
  my $self = shift;

  return unless $self->has_row_types_to_summarize;

  unless ( $self->has_col_types ) {
    carp "Can't generatate a row summary without col_types defined.\n";
    return;
  }

  my @row_summary;

  for my $row ( @{ $self->table } ) {

    my $total = 0;
    for my $i ( 0 .. $self->last_col_index ) {

      if ( $self->col_types->[$i] eq $self->row_type_to_summarize ) {
        $total += $row->[$i];
      }
    }
    push @row_summary, $total;
  }

  return \@row_summary;
}

# Set rows/columns properties based on width/length of table
sub _inspect_table {
  my ( $self, $table ) = @_;

  my $rows = scalar @{$table};
  my $cols = defined $table->[0] ? scalar @{ $table->[0] } : 0;

  $self->_table_rows($rows);
  $self->_table_cols($cols);
  $self->_last_row_index( $rows - 1 );
  $self->_last_col_index( $cols - 1 );
}

sub _build_index {
  my $ar = pop;
  my %h = map { $ar->[$_] => $_ } 0 .. ( scalar( @{$ar} ) - 1 );
  return \%h;
}

sub _build_col_index {
  my $self = shift;
  return _build_index( $self->col_labels );
}

sub _build_row_index {
  my $self = shift;
  return _build_index( $self->row_labels );
}


no Moose;
no Moose::Util::TypeConstraints;
1;

__END__


=pod

=head1 NAME

TechSafari::Reports::Worksheet - Representation of one table of report data along
with its corresponding meta information.  

=head1 VERSION

=over

=item $Id$

=item $Revision$

=item $HeadURL$

=item $Date$

=item $Source$

=back


=head1 SYNOPSIS

  use TechSafari::Reports::Worksheet;
  
  my $tbl      = [ [1, 2.20, 42, 101, 'poop'], 
                   [2, 5.50, 81, 102, 'foo' ], 
                   [3, 8.80, 69, 103, 'bar' ] ];
                   
  my $cols   = [   'Id',    'Price', 'Amount', 'Extra-FKey', 'Desc.' ];
  my $types  = [ 'None', 'Currency', 'Number',        undef,  'None' ];
  
  my $sheet = TechSafari::Reports::Worksheet->new(
                name       => "Short Table Name",
                title      => "Long Table Name",
                table      => $tbl,
                col_labels => $cols, 
                col_types  => $types,
                col_splice => [3],         
                cols_to_summarize => [1,2],   #summarize price and amount cols
              );  
              
  $sheet->splice_cols();  #splice out the Extra-ForeignKey column, set in col_splice

=head1 DESCRIPTION

Worksheets are created by the reports and printed out in the views. 
One report will usually consist of multiple worksheets.  See 
L<TechSafari::Reports::Interface> and L<TechSafari::Reports::Workbook> 
for more information on working with multiple worksheets.

The reports will just set up the attributes.  Reports can set up tables
that have more information than what is needed to be presented in the
eventual report document.  Splicing won't be done until asked, which 
will generally be in the View.

=head1 ATTRIBUTES  

Some type checking is done on the attributes, but no checking is done 
on the width of the rows in the table of data.  The object assumes 
that a proper NxM table was inserted.  

Also, the width of the col_labels and col_types rows should be 
the same width as the width of the table.  Similarly, the row_labels array
should be the length of the number of rows.  The arrays can have undefined
elements, as padding, to make sure elements line up with the proper columns.

=over

=item B<name>

Short description of the worksheet.  Required.

=item B<title>

Long description of the worksheet.

=item B<table>

2D table - array of rows.  This is the data to be presented.  Required. 

Additional info like column labels, row labels, summaries, etc should not be 
included here, as they are generated automatically by the worksheet.

=item B<col_labels>

The names/headers of the columns.  Expecting a row array that is the same
width of each table row.

=item B<row_labels>

Names of each row the columns.  Expecting a row array that is the same
width of each table row.

=item B<col_index>

Hash index of column names -- look up the column index by column name.  The 
index is lazily defined based on the col_labels attribute.  

With the index, you can do something like this to loop through the table:

  for my $row ( @{ $sheet->table } ) {

    for my $col_name ( @{ $sheet->col_labels } ) {
    
      my $index  = $sheet->col_index->{$col_name};
      my $cell   = $row->[ $index ];
      my $format = $sheet->col_formats->[ $index ];
    }
  }

Is that more or less readable than the alternative?  Probably not...

  for my $row ( @{ $sheet->table } ) {

    for my $i ( 0 .. $sheet->last_index ) {
      
      my $cell   = $row->[$i];
      my $format = $sheet->col_formats->[$i];
    }
  }

=item B<row_index>

Hash index of row names.  Also lazy.  See col_index

=item B<col_types>

Formatting type to apply to a column.  This is an enum type that contains 
general descriptions for how to format a column in the view.  

Allowed values: Currency, Number, Percentage, Date, Time, DateTime, None, 
or undef (none)

The col types also have some impact when generating summaries.  Currencies
are rounded to two decimals.  Percentages to three. 

When summarizing a row, only fields typed as Number, Currency, or Percentage
can be summarized.  The user has to pick one.

Predicate: B<has_col_types>

=item B<cols_to_splice>

An array of columns to be spliced out of the worksheet.  If not defined, no 
columns will ever be spliced.  If defined, it must be a subset of the number of 
columns, and those columns will not be presented in the view.  

This can be an array of column indexes or an array of column labels.

The actual splice is only performed when asked for, which is probably best done
in the controller:  $worksheet->splice_cols();

=item B<last_col_index, last_row_index>

Indexes of the last elements for rows/cols in a table.  The col index is
based on the first row in the table.  Row index is based on the number of rows
Both are automatically generated when the table is set.

=item B<table_cols, table_rows>

Number of rows and columns in the table.  Generated automatically.  

=item B<col_summary>

Summary for a particular column or group of columns.  The col_summary is 
automatically defined after setting a values by summarize_cols.  If defined, 
the column values' summary of will be included at the bottom of the 
worksheet.

The col_summary row will be the same width as every other table row.  
Col_summarize is given a slice of rows to summarize.  The non summarized rows 
in col_summary will be undefined values.

Predicate: B<has_col_summary>

=item B<cols_to_summarize>

An array of columns to summarize.  Should be set in the report, b/c the report
knows which columns to summarize.  The col_summary is auto generated based on
this.

This attribute can be set to an array of column indexes (columns are indexed
starting at 0), or an array of column labels to summarize.

Caveats: 
If col_labels are not set, then you can't specify a col label to summarize.
If a col_label looks like an integer, things aren't going to work correctly.

Ex, you can say either:

  $worksheet->cols_to_summarize(['Record Count']);
  $worksheet->cols_to_summarize([2]);  # assuming "Record Count" is column 2

See also SYNOPSIS

=item B<row_summary>

Row summary.  Generated based on row_types_to_summarize

Predicate: B<has_row_summary>

=item B<row_types_to_summarize>

Default: Number.  For each row, summarize all Numbers.  Possible Values:
Number, Currency, Percentage

=back

=head1 METHODS

=over 

=item B<splice_cols>

Splice out the columns in the table, col_labels, coltypes, and col_summary.  
Calling this method will destroy data.  Columns to splice are set in the 
col_splice attribute.  After this method has completed splicing the worksheet, 
the col_splice attribute will be emptied.

=back

=head1 DEPENDENCIES

Moose! It's worth it, see:
L<http://blog.jrock.us/articles/Myth:%20Moose%20is%20an%20unnecessary%20dependency.pod>

=head1 AUTHOR

$Author$




