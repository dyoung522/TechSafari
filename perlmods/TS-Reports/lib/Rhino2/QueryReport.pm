
package Rhino2::QueryReport;

our ($VERSION) = '$Revision: 25 $' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
extends 'Rhino2::BasicReport';

use Rhino2::QueryReportSQL;

################################################################################
### Attributes
################################################################################

## Private attribute.  This builds the sql attribute.  It is defined by the
## 'sql' attribute in the super class ( Basic Report ).  See lazy_build.
sub _build_sql {
  my $self = shift;
  return Rhino2::QueryReportSQL->new( dbh => $self->dbh );
}

################################################################################
### Instance Methods
################################################################################

sub process {
  my $self = shift;

  my %args = $self->process_query_args;
  #$args{debug} = 1;
  
  $self->generate_query_report(%args);

  return 1;
}

sub generate_query_report {
  my ( $self, %args ) = @_;

  # Run main query
  my $tbl = $self->sql->qr_invoice_query(%args);

  my $cols   = $self->sql->last_column_names;
  my $cindex = $self->sql->last_column_index;

  # Modify description columns based on host_id, product_id, and bi_bill_cd
  # Sorry about how ugly this is... it was done in a hurry
  # The default description is the product description (p_name_txt)
  #
  # Look at the activity rules in the activity report -- this should be 
  # implemented similarly, data driven instead of nested if/elsif's
  my $simple_desc_trans = {
    3  => 'ITA',
    4  => 'ITA',
    5  => 'FARES',
    6  => 'Bankruptcy',
    13 => 'PreMover',
    14 => 'NewMover',
    41 => 'Equifax no FICO', 
  };
  
  for my $row ( @{$tbl} ) {

    if ( $row->[ $cindex->{'product_id'} ] == 1
      || $row->[ $cindex->{'product_id'} ] == 7 )
    {
      if ( $row->[ $cindex->{'bi_bill_cd'} ] eq 'EFX_AUTO_TRIGGER' ) {
        $row->[ $cindex->{'Description'} ] = 'Auto Trigger';
      }
      else {
        $row->[ $cindex->{'Description'} ] = 'Auto Prescreen';
      }
    }
    elsif ( $row->[ $cindex->{'product_id'} ] == 2
      || $row->[ $cindex->{'product_id'} ] == 10 )
    {
      if ( $row->[ $cindex->{'bi_bill_cd'} ] =~ 'EFX_MTG_TRIGGER' ) {
        $row->[ $cindex->{'Description'} ] = 'Mortgage Trigger';
      }
      else {
        $row->[ $cindex->{'Description'} ] = 'Mortgage Prescreen';
      }
    }
    elsif ( $simple_desc_trans->{ $row->[ $cindex->{'product_id'} ] } ) {
      $row->[ $cindex->{'Description'} ] = 
        $simple_desc_trans->{ $row->[ $cindex->{'product_id'} ] };
    }   

  }
  # /yucko

  my @formatting = map { 'None' } @{$cols};    #blank formatting

  $formatting[ $cindex->{'Invoice Date'} ]  = 'Date';
  $formatting[ $cindex->{'Record Count'} ]  = 'Number';
  $formatting[ $cindex->{'Billed Amount'} ] = 'Currency';

  my $date_str = sprintf '%s %d, %d', $self->run_date->month_name,
    $self->run_date->day, $self->run_date->year;

  my $sheet = TechSafari::Reports::Worksheet->new(
    name  => "Query Report - $args{name}",
    title => "Query Report as of $date_str ($args{title})",

    table      => $tbl,
    col_labels => $cols,
    col_types  => \@formatting,
    
    cols_to_splice => [ 'product_id', 'host_id', 'bi_bill_cd' ],
    cols_to_summarize => [ 'Record Count', 'Billed Amount' ],
  );

  return $self->add_worksheet($sheet);
}

1;

__END__

=head1 NAME

Rhino2::QueryReport - Daily Query Report

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

=head1 ATTRIBUTES

=head1 METHODS

=head2 process

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$


