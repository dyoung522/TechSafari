#!/usr/bin/perl -w
########################################################
# This program is used to provide information and      #
# verify tapes in the NetBackup database               #
########################################################

use strict;
use Getopt::Long;
use vars qw(
    $Element
    $Tag
    $Slots
    %Tapes
    $opt_verbose
    $opt_nagios
    $opt_fullonly
    %Count
    %TapeStatus
);

my $VERSION = q(2.0);

# Pull in the media status database
&GetTapes or die "Unable to get tape status!\n";

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "V|version"    => \&version,
    "h|help"       => \&help,
    "v|verbose+"   => \$opt_verbose,
    "F|fullonly"   => \$opt_fullonly,
    "nagios"       => \$opt_nagios,
);

if ( not $ENV{'LOGNAME'} =~ /root/ ) {
    print "\nPlease run this program as root.\n\n";
    exit;
}

# Unset verbose if we're running in "nagios" mode
if ( defined $opt_nagios ) { $opt_verbose = 0; }

my $SG_TAPE_DEV = "/dev/sg2";
open MTX, "/usr/sbin/mtx -f $SG_TAPE_DEV status |" or die "Unable to run mtx status: $! \n";

while (<MTX>) {
    if ( /Storage Changer .* (\d+) Slots/ ) {
        $Slots = $1;
    }
    else { next unless $Slots; }

    next unless ($Element, $Tag) = /Storage Element (\d+):.*VolumeTag=(\d+)/;

    # Convert the tape number to only 6 digits
    my $Tape = sprintf "%06d", $Tag;

    if ( not $Tape =~ /^\d{6}$/ ) {
        print "Invalid Tape ID \"$Tag\"\n" if $opt_verbose;
        next;
    }

    $Tapes{$Element} = $Tag;
}

$Element = 0;
while ( $Element++ < $Slots ) {
    my ( $MediaID, $Status, $Retention, $Message ) = ( q(------), q(EMPTY), q(), q() );

    if ( not defined $opt_verbose ) { next unless defined $Tapes{$Element}; }

    if ( defined $Tapes{$Element} ) {
        $MediaID = $Tapes{$Element};

        # If it's not in the tape inventory, it's SCRATCH
        if ( defined $TapeStatus{$Tapes{$Element}} ) {
            $Status  = $TapeStatus{$MediaID}{'STATUS'};
            $Retention = $TapeStatus{$MediaID}{'RETENTION'};
            $Message = $TapeStatus{$MediaID}{'INFO'};
        } else {
            $Status = q(SCRATCH);
        }
    }

    # Keep a running count
    $Count{$Status}++;

    if ( defined $opt_nagios ) { next; }

    if ( defined $opt_fullonly ) { next unless $Status =~ /FULL/; }

    printf "[%02d] %6s %-20s %-15s %s\n",
        $Element,
        $MediaID,
        $Status,
        $Retention,
        $Message;
}

if ( $opt_verbose or defined $opt_nagios ) {
    if ( defined $Count{'SUSPENDED '}     ) { $Count{'FULL'} += $Count{'SUSPENDED '}; }
    if ( defined $Count{'SUSPENDED FULL'} ) { $Count{'FULL'} += $Count{'SUSPENDED FULL'}; }
    if ( defined $Count{'EMPTY'}          ) { $Slots -= $Count{'EMPTY'}; }

    if ( defined $opt_nagios ) {
        printf "tapes:%d; full:%d; active:%d; scratch:%d",
            $Slots,
            defined $Count{'FULL'}    ? $Count{'FULL'}    : 0,
            defined $Count{'ACTIVE'}  ? $Count{'ACTIVE'}  : 0,
            defined $Count{'SCRATCH'} ? $Count{'SCRATCH'} : 0;
    }

    if ( $opt_verbose ) {
        printf "\n%d slots in use ( %d Full, %d Active, %d Scratch )\n",
            $Slots,
            defined $Count{'FULL'}    ? $Count{'FULL'}    : 0,
            defined $Count{'ACTIVE'}  ? $Count{'ACTIVE'}  : 0,
            defined $Count{'SCRATCH'} ? $Count{'SCRATCH'} : 0;
    }
}

exit 1;

sub GetTapes {
    my ( $Retention, $Status, $Info ) = ();
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

    # Build the tape status database
    open ML, q(/usr/openv/netbackup/bin/admincmd/bpmedialist -mlist -l 2> /dev/null |) or die "Unable to run bpmedialist: $!\n";
    while ( <ML> ) {
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
            $TapeStatus,
            $Hsize,
            $Ssize,
            $l_offset,
        ) = split / / or next;

        if ( $TapeStatus == 0 ) { $Status = q(ACTIVE);    }
        if ( $TapeStatus & 1  ) { $Status = q(FROZEN (DO NOT USE!)); }
        if ( $TapeStatus & 2  ) { $Status = q(SUSPENDED); }
        if ( $TapeStatus & 4  ) { $Status = q(UNKNOWN);   }
        if ( $TapeStatus & 8  ) { $Status = q(FULL);      }
        if ( not defined $Status ) { $Status = "UNKNOWN ($TapeStatus)";   }

        if ( $TapeRetention > 9 ) {
            $Retention = "INFINITE ($TapeRetention)";
        } else {
            $Retention = "$RetentionPeriod[$TapeRetention]";
        }

        if ( $Status =~ /FULL/ && $TapeRetention < 9 ) {
            $Info = "Expires on: " . scalar localtime( $TimeExpire );
        }
        else {
            $Info = "Last Mounted on: " . scalar localtime( $TimeLastWrite );
        }

        $TapeStatus{$MediaID}{'STATUS'} = $Status;
        $TapeStatus{$MediaID}{'RETENTION'} = $Retention;
        $TapeStatus{$MediaID}{'INFO'} = $Info;
    }

    return 1;
}

sub version {
    print "tapelist.pl v$VERSION\n";
    return;
}

sub help {
    print "\n";
    &version;
    print "
    -F    : Only display FULL tapes
    -h    : This help message
    -v    : Show all slots (even empty ones)
    -V    : Display version info

";
    exit;
}
