package TechSafari::Reports::Workbook;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Carp;
use Moose;
use Moose::Util::TypeConstraints;

use TechSafari::Reports::Worksheet;

################################################################################
### Custom Type checking / Coercions
################################################################################
{
  my $constraint_finder = \&Moose::Util::TypeConstraints::find_type_constraint;
  my $trw_constraint = $constraint_finder->('TechSafari::Reports::Worksheet');

  # Explicitly define type for the worksheet class if it doesnt already exist;
  unless ($trw_constraint) {
    $trw_constraint =
      subtype 'TechSafari::Reports::Worksheet' => as 'Object' => where {
      $_->isa('TechSafari::Reports::Worksheet');
      };
  }

  # Coerce HashRefs into the worksheet class;
  coerce 'TechSafari::Reports::Worksheet' => from 'HashRef' => via {
    TechSafari::Reports::Worksheet->new( %{$_} );
  };

  subtype 'TRW::ArrayRef' => as 'ArrayRef[TechSafari::Reports::Worksheet]' =>
    where { 1 };

  # coerce each individual element in the arrayref..
  coerce 'TRW::ArrayRef' => from 'ArrayRef' => via {
    my $ar = $_;
    for my $val ( @{$ar} ) {
      $val = $trw_constraint->coerce($val);
    }
    return $ar;
  };

}
################################################################################
### Attributes
################################################################################

has 'worksheets' => (
  is      => 'rw',
  isa     => 'TRW::ArrayRef',
  default => sub { [] },
  coerce  => 1,
);

################################################################################
### Methods
################################################################################

# alias of add_worksheets
sub add_worksheet {
  my @sheets = @_;
  return add_worksheets(@sheets);
}

# add many worksheets to the triggers attribute
# accepts a ref to an array of triggers or just an array of triggers
sub add_worksheets
{    ## no critic(RequireArgUnpacking) - sheets can be an array or an arrayref
  my $self    = shift;
  my @sheets  = ref $_[0] eq 'ARRAY' ? @{ $_[0] } : @_;
  my @current = @{ $self->worksheets };

  push @current, @sheets;
  return $self->worksheets( \@current );
}

# Check to see if the worksheet is what it claims to be -- confess if not
sub check_worksheet {
  my ( $self, $sheet ) = @_;

  unless ( Scalar::Util::blessed($sheet) eq 'TechSafari::Reports::Worksheet' ) {
    Carp::confess sprintf
      q{Attempting to add '%s' as a worksheet to report '%s'},
      ref($sheet) ? ref($sheet) : $sheet, $self->name;
  }

  return 1;
}

sub splice_worksheet_cols {
  my $self = shift;

  for my $sheet ( @{ $self->worksheets } ) {
    $sheet->splice_cols();
  }

  return 1;
}

sub merge_workbook {
  my ( $self, $workbook ) = @_;

  confess "Argument value '$workbook' is not a " . __PACKAGE__ . "\n"
    unless $workbook->isa('TechSafari::Reports::Workbook');

  $self->add_worksheets( $workbook->worksheets );

  return 1;
}

no Moose;
no Moose::Util::TypeConstraints;

1;

__END__

=head1 NAME

TechSafari::Reports::Workbook - A container of many worksheets.

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

Initially all reports had a list of worksheets.  I realized that I would be 
unable to easily perform operations across all worksheets, so I created
this class.  

After creating this object, I am going to try not to change the API any more.

=head1 ATTRIBUTES

worksheets - this is a ref to a list of worksheets

=head1 METHODS

=head2 add_worksheet

push another worksheet onto the worksheet list

=head2 add_worksheets 

push many worksheets onto the worksheet list

=head2 check_worksheet 

confess unless the worksheet is as it claims

=head2 splice_worksheet_cols

call splice_cols on all worksheets.

=head2 merge_workbook

merge another workbook into this one.  Right now, this just pushes the other 
worksheets array onto this worksheets array

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$

