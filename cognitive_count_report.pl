#!/usr/bin/perl -w

use strict;

my $UseDate;

# If we were given a date on the command line, validate it and use it.
if ( defined $ARGV[0] and $ARGV[0] =~ /(\d{6})/ ) { $UseDate = $1; }
else {
    # Our date math.  Calculate what month was last by subtracting the current day * 24 hours
    # which gives us the last day of last month.  Then simply use that as the input to localtime
    # to determine what year + month it was.  This should work for all dates, including leap years.
    my $LastMonthTime = time - ( 86400 * (localtime( time ))[3] );
    $UseDate = sprintf "%04d%02d", ( (localtime($LastMonthTime))[5] + 1900 ), ( (localtime($LastMonthTime))[4] + 1 );
}

my $DATADIR = '/data/in/cognitive/incoming/';
my $PATTERN = $DATADIR . "AUTO_WEEKLYMASDA_RES_F$UseDate*.out";
my $REGEX   = 'AUTO_WEEKLYMASDA_RES_F(\d{6})(\d{2})_(\d+)_.*\.out';

my %Counts  = ();

foreach my $File ( glob $PATTERN ) {
    # Get the file date and number of records sent from the filename.
    my ( $FileDate, $FileDay, $RecordsSent ) = ( $File =~ $REGEX ) or next;

    # Open the file for reading, we need this to count the total records in the file.
    open( FILE, "< $File" ) or die "Unable to read $File: $!\n";

    # Get the number of lines in the file.
    # $. holds the current line number, so we read to the end of the file and record
    # what line we're on.
    1 while ( <FILE> ); my $RecordsReceived = $.;

    # Populate our hash for totals.
    $Counts{$FileDate}{SENT} += $RecordsSent;
    $Counts{$FileDate}{RECEIVED} += $RecordsReceived;

    print "${FileDate}${FileDay}: Sent = $RecordsSent / Received = $RecordsReceived\n";

    # Close the file;
    close( FILE );
}

# If there weren't any records, say so and exit.
if ( not %Counts ) { print "No Records Found for $UseDate\n"; exit; }

# Print totals.
foreach my $YM ( sort keys %Counts ) {
    print "\nTotals for $YM: Sent = $Counts{$YM}{SENT} / Received = $Counts{$YM}{RECEIVED}\n";
}

exit;
