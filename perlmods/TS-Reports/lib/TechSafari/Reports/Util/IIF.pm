package TechSafari::Reports::Util::IIF;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;
sub file_extension { 'iif' }

use Carp;
use FileHandle;
use Text::CSV;

use Moose;

## Attributes ##

has 'table' => ( 
  is => 'rw', 
  isa => 'ArrayRef[ArrayRef]',
  predicate => 'has_table',
);

has 'params' => (
  is  => 'rw',
  isa => 'HashRef',
  trigger => sub {
    my ( $self, $val ) = @_;
    $self->table( $val->{workbook}->worksheets->[0]->table ),
  }
);

has 'csv' => (
  is         => 'rw',
  isa        => 'Text::CSV',
  lazy_build => '1',
);

sub _build_csv {
  my $self = shift;
  return Text::CSV->new( { always_quote => 1 } );
}

## Methods ##

sub process {
  my ( $self, $out ) = @_;

  unless ( $self->has_table ) {
    Carp::confess "Can't write to IIF.  Nothing specified in table or params.";
  }

  my $fh;
  if ( $out && blessed($out) && $out->isa('IO::Handle') ) {
    $fh = $out;
  }
  elsif ( $out && !ref $out ) {
    $fh = FileHandle->new( $out, '>' )
      || Carp::confess "Can't open '$out' for writing. $!";
  }
  else {
    $fh = FileHandle->new_from_fd( *STDOUT, '>' )
      || Carp::confess 'FileHandle error when trying to write to STDOUT.';
  }

  for my $row ( @{ $self->table } ) {

    my $line;

    if ( $row->[0] eq 'TRNS' || $row->[0] eq 'SPL' ) {
      my $rc = $self->csv->combine( @{$row} );    # combined with quotes
      $line = $self->csv->string;
    }
    else {
      $line = join q{,}, @{$row};                 # combined with no quotes
    }

    $fh->print( $line, "\n\n" );

  }

  return $fh->close;
}

sub write_file {
  my ( $self, $filename ) = @_;
  
  if ( not defined $filename ) {
    Carp::confess "Can't write IIF to file.  No filename specified.";
  }
  
  return $self->process($filename);  
}

1;

__END__

=head1 NAME

TechSafari::Reports::Util::IIF - Module for printing out IIF files.

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

Quickbooks seems somewhat finicky about importing IIF files.  Fields seem to 
be CSV, but sometimes they are quoted and sometimes not.  

I've tried to reconcile all of that here.

This module expects an array of rows to be printed.  The headers of the IIF
file should be the first rows of the input row array.

=head1 ATTRIBUTES

=head2 table ( $ArrayRef )

Rows in the IIF file.  Don't include blank rows, even though an IIF file 
puts an extra newline between rows.  Also, a record consists of multiple rows,
so make sure the proper ENDTRNS rows are included.  AND, the file header 
should be the first few rows of the array.

=head2 params ( $HashRef )

This is an alternate way to wire in the table.  Params is similar to the
interface for Excel::Template::Plus.  Just give the workbook with the iif,
keyed by workbook, and params will put the table from the first worksheet 
into it's own table.

Like so:

  my $iif = TechSafari::Reports::Util::IIF->new(
    params => { workbook => $rpt->workbook },
  );

Either table or params needs to be specified.

=head1 METHODS

=head2 process ( $filename | $filehandle | undef )

Print out the IIF file.  Pass in a filename to print the rows to, or an open
filehandle (IO::Handle, FileHandle, both work).  OR, if no args are passed in,
process() prints to STDOUT.

=head2 write_file ( $filename )

Explicit way to write to a file.  Calls process with the specified $filename.
Again, this is to mimic Excel::Template::Plus's interface.

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$

