
package TechSafari::Reports::CommandLineApp;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

# moose
use Moose; 
with 'MooseX::SimpleConfig';
with 'MooseX::Getopt';

# external modules
use File::Basename;
use File::Spec;
use Pod::Usage;

# custom mods
use Rhino2::ActivityReport;
use Rhino2::BasicReport;

# set up base configfile based off the location of the ts_reports.pl script
my ( $configfile );

{  
   my($file, $dir, $suffix) = File::Basename::fileparse($0);
   my $base_dir = File::Spec->rel2abs($dir);
   $configfile  = File::Spec->catfile($base_dir, 'conf', 'ts_config.ini'); 
}

### Attributes - available either on the command line or in the configfile ###

has '+configfile' => ( default => $configfile );


### Public methods ###

sub poop {
  my $self = shift;

  if ( $self->help || $self->h ) {
    pod2usage( -verbose => 2 );
    return;
  }
  
  print 'poop';
}


1;

__END__

=head1 NAME

TechSafari::Reports::CommandLineApp -- NOTE: Don't use this.  It is just
a placeholder with no working code, and I'm not sure I will be implementing
command line reports in this manner.

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

The Command Line App, run using the ts_reports.pl script:

  1) handle the parsing of the configuration file and the command line options, 
  2) reconcile the options to DWIM, 
  3) hand off to the reports (model), 
  4) send the report to the view to create the report as xls/csv/html/whatever
  5) notify/email someone that the report is complete

As is is, this module acts like a Dispatcher/Controller combo, and thus, seemed
too heavy to put into the Controller/ folder

=head1 ATTRIBUTES

All command line options are attributes.

=head1 METHODS

poop()

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$

=head1 LICENSE AND COPYRIGHT
