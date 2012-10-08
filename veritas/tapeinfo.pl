#!/usr/bin/perl -w
########################################################
# This program is used to provide information and      #
# verify tapes in the NetBackup database               #
########################################################

use strict;

if ( not $ENV{'LOGNAME'} =~ /root/ ) {
    print "\nPlease run this program as root.\n\n";
    exit;
}

sub CheckTape($);

print "Enter tape ID's one per line below (return to exit)...\n";

while (<>) {
    my $Tape = undef;
    chomp;

    last if /^$/;
    last if /exit/i;
    last if /quit/i;

    # Convert the tape number to only 6 digits
    $_ =~ /(\d+)/;
    $Tape = sprintf "%06d", $1;

    if ( not $Tape =~ /^\d{6}$/ ) {
        print "Invalid Tape ID\n";
        next;
    }

    CheckTape( $Tape );
}

exit 1;

sub CheckTape($) {
    my ( $Tape ) = @_;
    my @RetentionPeriod = (
        '1 WEEK',
        '2 WEEKS',
        '3 WEEKS',
        '1 MONTH',
        '2 MONTHS',
        '3 MONTHS',
        '6 MONTHS',
        '9 MONTHS',
        '1 YEAR',
        'INFINITE',
    );

    # Get Tape status
    my ( $MediaID,
         $Junk,
         $Version,
         $Density,
         $TimeAllocated,
         $TimeLastWrite,
         $TimeExpire,
         $TimeLastRead,
         $Kbytes,
         $Nimages,
         $Vimages,
         $TapeRetention,
         $Pool,
         $Resources,
         $Status,
         $Hsize,
         $Ssize,
         $l_offset,
    ) = split / /, qx(/usr/openv/netbackup/bin/admincmd/bpmedialist -mlist -l -ev $Tape 2> /dev/null);

    if ( not defined $MediaID ) {
        printf "    Media ID:   %06d\n", $Tape;
        print  "    Retention:  SCRATCH\n";
        return;
    }

    printf "    Media ID:   %06d\n", $MediaID;

    print  "    Retention:  ";
    if ( $TapeRetention > 9 ) {
        print "Infinite ($TapeRetention)\n";
    } else {
        print "$RetentionPeriod[$TapeRetention] ($TapeRetention)\n";
    }

    printf "    Expires on: %s\n", scalar localtime( $TimeExpire );

    print  "    Status:     ";
    if ( $Status == 0     ) { print "ACTIVE ";    }
    if ( $Status &  0x001 ) { print "FROZEN (DO NOT USE!)";    }
    if ( $Status &  0x002 ) { print "SUSPENDED "; }
    if ( $Status &  0x004 ) { print "UNKNOWN ";   }
    if ( $Status &  0x008 ) { print "FULL ";      }
    print "\n";

    return;
}
