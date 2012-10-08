package TechSafari::Reports::Interface;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose::Role;

with 'TechSafari::Reports::Attributes::Workbook';
with 'TechSafari::Reports::Attributes::RunDate';

requires 'process';

1;

__END__

=head1 NAME

TechSafari::Reports::Interface - Moose Role / Interface for defining the requirements
of every report.

=head1 VERSION

=over

=item $Id$

=item $Revision$

=item $HeadURL$

=item $Date$

=item $Source$

=back

=head1 SYNOPSIS

package TechSafari::Reports::MyProduct::MyReport;
with 'TechSafari::Reports::Interface';

=head1 DESCRIPTION


=head1 ATTRIBUTES

The following attributes are common to all reports.  They are located are under 
TechSafari::Reports::Attributes.

Worksheets - worksheets isa ArrayRef[worksheet]

RunDate - run_date isa DateTime
  
=head1 METHODS

Classes implementing this role are required to implement the following methods:

process - This should run the report and generate a workbook


=head1 DEPENDENCIES

=head1 AUTHOR

$Author$

