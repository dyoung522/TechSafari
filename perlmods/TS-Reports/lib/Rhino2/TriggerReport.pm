package Rhino2::TriggerReport;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
extends 'Rhino2::SelectsReport';

################################################################################
### Attributes
################################################################################

has '+selects' => (
  default => sub {
    [
      'Auto Inquiry Trigger Date',
      'Auto Inquiry Trigger Date *',      
      'Mortgage Inquiry Trigger Date (0-6 days)',
      'Mortgage Inquiry Trigger Date (7-31 days)',
    ]
  }
);

################################################################################
### Instance Methods
################################################################################


1;

__END__

=head1 NAME

Rhino2::TriggerReport - like the selects query, but defines the specific 
trigger related selects.

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

This report is a subclass of the Selects Report.  See L<Rhino2::SelectsReport>.

=head1 ATTRIBUTES

=head2 selects

This report automatically defines the default selects which are considered 
trigger selects.  They are:

  'Auto Inquiry Trigger Date'
  'Auto Inquiry Trigger Date *'
  'Mortgage Inquiry Trigger Date (0-6 days)'
  'Mortgage Inquiry Trigger Date (7-31 days)'

=head1 METHODS

=head1 DEPENDENCIES

L<Rhino2::SelectsReport>

=head1 AUTHOR

$Author$

