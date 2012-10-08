package Rhino2::OrdersReport;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
use Moose::Util::TypeConstraints;

extends 'Rhino2::BasicReport';

use Rhino2::OrdersSQL;

################################################################################
### Attributes
################################################################################

## Private attribute.  This builds the sql attribute.  It is defined by the
## 'sql' attribute in the super class ( Basic Report ).  See lazy_build.
sub _build_sql {
  my $self = shift;
  return Rhino2::OrdersSQL->new( dbh => $self->dbh );
}

################################################################################
### Instance Methods
################################################################################

sub process {
  my $self = shift;

  my %args = $self->process_query_args;

  #$args{debug} = 1;
  $self->generate_orders_query(%args);

  return 1;
}

sub generate_orders_query {
  my ( $self, %args ) = @_;

  # Run main query
  my $tbl = $self->sql->orders_query(%args);

  # Get column info from query results
  my $cols   = $self->sql->last_column_names;
  my $cindex = $self->sql->last_column_index;

  # Apply formatting to columns
  my @types = map { 'None' } @{$cols};
  $types[ $cindex->{'Order Date'} ] = 'Date';
  $types[ $cindex->{'Record Count'} ]    = 'Number';

  # Create the worksheet
  my $sheet = TechSafari::Reports::Worksheet->new(
    name  => $args{name},
    title => $self->report_period . " $args{title}",
    table => $tbl,

    col_labels => $cols,
    col_types  => \@types,
    
    cols_to_summarize => [ 'Record Count' ] 
    
  );

  return $self->add_worksheet($sheet);

}

1;

__END__

=head1 NAME

Rhino2::SelectsReport

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

see L<Rhino2::BasicQuery> for common attributes


=head1 METHODS

=head2 process

=head2 generate_orders_query

Internally called by process.

=head1 DEPENDENCIES

L<Rhino2::BasicReport>

=head1 AUTHOR

$Author: calderman $

