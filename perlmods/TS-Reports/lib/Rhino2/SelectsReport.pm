package Rhino2::SelectsReport;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
use Moose::Util::TypeConstraints;

extends 'Rhino2::BasicReport';

################################################################################
### Attributes
################################################################################

subtype 'Rhino2::SelectsReport::ArrayRef' => as 'ArrayRef' => where { 1 };
coerce  'Rhino2::SelectsReport::ArrayRef' => from 'Value'  => via { [$_] };

has 'selects' => (
  is        => 'rw',
  isa       => 'Rhino2::SelectsReport::ArrayRef',
  predicate => 'has_selects',
  coerce    => 1,
);

################################################################################
### Instance Methods
################################################################################

sub process {
  my $self = shift;

  my %args = $self->process_query_args;

  if ( $self->has_selects ) {

    my ( @select_ids, $select );
    for my $select_id ( @{ $self->selects } ) {
      $select = $self->sql->select_info($select_id);
      push @select_ids, $select->{id};
    }

    $args{select_id} = \@select_ids;

    if ( scalar(@select_ids) == 1 ) {
      $args{name}  = $select->{s_display_txt};
      $args{title} = "Selects Query: $select->{s_display_txt} ($select->{id})";
    }
    else {
      $args{name}  = 'Selects Query';
      $args{title} = 'Selects Query';
    }

  }

  $self->generate_selects_query(%args);

  return 1;
}

sub generate_selects_query {
  my ( $self, %args ) = @_;

  # Run main query
  my $tbl = $self->sql->ordered_selects_query(%args);

  # Get column info from query results
  my $cols   = $self->sql->last_column_names;
  my $cindex = $self->sql->last_column_index;

  # Apply formatting to columns
  my @types = map { 'None' } @{$cols};
  $types[ $cindex->{'Order Date'} ] = 'Date';
  $types[ $cindex->{'Records'} ]    = 'Number';

  # Create the worksheet
  my $sheet = TechSafari::Reports::Worksheet->new(
    name  => $args{name},
    title => $self->report_period . " $args{title}",
    table => $tbl,

    col_labels => $cols,
    col_types  => \@types,
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

Using the L<Rhino2::BaseSQL::ordered_selects_query>, this report provides 
orders along with specified selects.  

If a particular count uses multiple specified selects, the count will be 
included in the results more than once.  Both billed and non billed
orders are included. 

The resultset is grouped on two columns: select_id and invoice_id.

=head1 ATTRIBUTES

see L<Rhino2::BasicQuery> for common attributes

Additional attribute:

=head2 selects
 
A list of selects, which can be specified by select id or select display text
(s_display_txt).

The use of this attribue mimicks the hosts and companies attributes in
L<Rhino2::BasicQuery>.

=head1 METHODS

=head2 process

=head2 generate_selects_query

Internally called by process.

=head1 DEPENDENCIES

L<Rhino2::BasicReport>

=head1 AUTHOR

$Author$

