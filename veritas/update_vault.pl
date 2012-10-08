#!/usr/bin/perl -w
########################################################
# This program is used to update the vault information #
# in the NetBackup database                            #
########################################################

unless ( $ENV{LOGNAME} =~ /root/ ) {
    print "Please run this program as root\n";
    exit;
}

use strict;
use Getopt::Long;
use POSIX qw(strftime);
use vars qw( $opt_verbose $opt_check $opt_date $opt_tag $opt_case $opt_overwrite );

my $opt_verbose = 0;

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "h|help"     => \&help,
    "v|verbose+" => \$opt_verbose,
    "t|tag=i"    => \$opt_tag,
    "c|case=i"   => \$opt_case,
    "d|date=s"   => \$opt_date,
    "check"      => \$opt_check,
    "overwrite"  => \$opt_overwrite,
);

sub help {
    print "\n$0 [check][overwrite][tag <tagnum>][date <date>] --case <casenum>\n";
    exit;
}

if ( not defined $opt_case ) { &help; }

my $INPUT = "&STDIN";
my %ValidTapes = ();
my @InvalidTapes = ();
my $DateSent = defined $opt_date ? $opt_date : strftime( "%m/%d/%Y", localtime( time ) );
my $VaultTag = defined $opt_tag ? $opt_tag : '00000';
my $VaultSlot = sprintf "%06d", $opt_case;

if ( $opt_verbose >= 1 ) {
    print "Case: $VaultSlot\n";
    print "Tag:  $VaultTag\n";
    print "Date: $DateSent\n";
}

if ( defined $opt_check ) {
    print "Checking $VaultSlot ONLY, no updates will be performed.\n";
}

if ( -f $VaultSlot ) {
    if ( defined $opt_overwrite ) {
        print "WARNING: $VaultSlot already exists and will be overwritten (^C now to abort)!\n";
    } else {
        print "Reading list of tapes from $VaultSlot.  If you wish to create a new file, please use --overwrite\n";
        print "Please wait...\n";
        $INPUT = $VaultSlot;
    }
}

open INPUT, "<$INPUT" or die "Unable to open $INPUT: $!\n";
if ( $INPUT eq "&STDIN" ) {
    print "Please enter tape numbers, one at a time.  Use a blank line when finished...\n";
}

# Turn off echo
system('stty -echo');

while ( <INPUT> ) {
    chomp;

    last if /$^/;

    # Skip non numeric lines
    next unless /^\d+$/;

    my $Tape = sprintf "%06d", $_;

    if ( not $Tape ) {
        print "Tape name is blank!  Skipping...\n";
        next;
    }

    print "$Tape... ";

    # Make sure the tape is valid and has INFINITE retention
    my ( $TapeRetention ) = ( qx(/usr/openv/netbackup/bin/admincmd/bpmedialist -mlist -l -ev $Tape 2>&1)
        =~ /\d+ \S+ \d+ \d+ \d+ \d+ \d+ \d+ \d+ \d+ \d+ (\d+) \d+/ );

    $TapeRetention = 0 unless defined $TapeRetention;

    if ( $TapeRetention < 9 ) {
        print "NOT VALID\n";
        push @InvalidTapes, $Tape;
        next;
    }

    print "OK\n";

    $ValidTapes{$Tape} = $Tape;
    if ( $INPUT ne "&STDIN" ) { sleep 1; } # Needed to keep bpmedialist from hanging
}

# Turn echo back on
system('stty echo');

if ( @InvalidTapes > 0 ) {
    print "The following tapes were invalid:\n";
    foreach my $invalid_tape (@InvalidTapes) {
        print "\t$invalid_tape\n";
    }
}

my $NumberValid = scalar keys( %ValidTapes );

print "$NumberValid tapes are valid.\n";

if ( not defined $opt_check ) {
    print "Updating Database for case $VaultSlot\n";

    for my $Tape ( sort keys %ValidTapes ) {
        system("/usr/openv/volmgr/bin/vmchange -m $Tape -vltsent $DateSent")
            and die "Error setting Vault Sent Date!\n";
        system("/usr/openv/volmgr/bin/vmchange -m $Tape -vltreturn \\0")
            and die "Error setting Vault Return Date!\n";
        system("/usr/openv/volmgr/bin/vmchange -m $Tape -vltslot $VaultSlot")
            and die "Error setting Vault Slot!\n";
        system("/usr/openv/volmgr/bin/vmchange -m $Tape -vltsession $VaultTag")
            and die "Error setting Vault Session!\n";
    }
}

if ( not $NumberValid ) {
    print "No Tapes Processed!\n";
    exit 1;
}

print "Writing tape list to $VaultSlot";

open( TAPE, ">$VaultSlot" ) or die "Unable to write to $VaultSlot: $!\n";

print TAPE "Sent: $DateSent\n";
print TAPE "Tag: $VaultTag\n";
for my $Tape ( sort keys %ValidTapes ) { print TAPE "$Tape\n"; }

close( TAPE );

exit 0;
