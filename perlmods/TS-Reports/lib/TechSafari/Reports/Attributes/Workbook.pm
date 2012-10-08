
package TechSafari::Reports::Attributes::Workbook;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose::Role;

use TechSafari::Reports::Workbook;

has 'workbook' => (
  is      => 'rw',
  isa     => 'TechSafari::Reports::Workbook',
  lazy    => 1,
  default => sub { TechSafari::Reports::Workbook->new() },
);

# alias of add_worksheets
sub add_worksheet {
  my $self = shift;
  $self->workbook->add_worksheet(@_);
}

sub add_worksheets {
  my $self = shift;
  $self->workbook->add_worksheets(@_);
}

1;

__END__


=pod

=head1 NAME

TechSafari::Reports::Attributes::Workbook - Interface for working with 
TechSafari::Reports::Workbook[s]

=head1 VERSION

=over

=item $Id: Worksheets.pm 22 2008-06-26 22:01:16Z calderman $

=item $Revision $

=item $HeadURL: svn+ssh://calderman@duvel/data/svn/perlmods/trunk/TS-Reports/lib/TechSafari/Reports/Attributes/Worksheets.pm $

=item $Date: 2008-06-26 18:01:16 -0400 (Thu, 26 Jun 2008) $

=item $Source$

=back

=head1 SYNOPSIS

  package MyPackage;
  use Moose;
  
  with 'TechSafari::Reports::Attributes::Workbook';
  
  ...;
  
=head1 DESCRIPTION

TechSafari::Reports::Attributes::Workbook is a Moose Role, defining attributes 
and methods for working with the workbook/worksheets in other objects. 
Specifically, the reports and the view.

=head1 ATTRIBUTES

workbook isa TechSafari::Reports::Workbook

=head1 METHODS

add_worksheet, add_worksheets - These are just shortcuts to the same
methods in the workbook.  So, instead of calling, 

$self->workbook->add_worksheet() 

you can just 

$self->add_worksheet()

=head1 DEPENDENCIES

=head1 AUTHOR

$Author: calderman $


