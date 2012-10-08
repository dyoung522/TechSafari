#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use vars qw( $opt_verbose );

my %Device = ();
my @DevMap = (
    '/dev/sdb1',
    '/dev/sdc1',
    '/dev/sdd1',
    '/dev/sde1',
    '/dev/sdf1',
    '/dev/sdg1',
    '/dev/sdh1',
    '/dev/sdi1',
    '/dev/sdj1',
    '/dev/sdk1',
);

if ( qx(id -u) != 0 ) { print "Sorry, this program requires root privileges.\n"; exit; }

sub get_3ware_controllers {
    my @RET = ();

    open TWCLI, "/usr/local/bin/tw_cli show|" or die "Unable to run tw_cli: $!\n";
    while ( <TWCLI> ) {
        next unless /^(c\d+)\s+/;
        push @RET, $1;
    }
    close TWCLI;

    return @RET;
}

sub check_mount {
    my $Dev = shift;
    return qx(grep $Dev /proc/mounts);
}

sub get_device {
    my ( $Serial ) = @_;
    my $RET = undef;

    return undef unless defined $Serial;

    open BLKID, "/sbin/blkid -l -t LABEL=$Serial|" or die "Unable to run blkid: $!\n";
    while ( <BLKID> ) { if ( m|(/dev/.+):\s+LABEL="$Serial"| ) { $RET = $1; } }
    close BLKID;

    return $RET;
}

sub check_devices {
    foreach my $Unit ( sort keys %Device ) {
        my ( $Port, $Serial ) = split ':', $Device{$Unit};
        my $Dev = get_device($Serial);

        if ( defined $Dev ) {
            printf "%s ( Unit %-3s; Port %-3s ) : %s", $Serial, $Unit, $Port, $Dev;

            if ( $Dev =~ /$DevMap[$Unit]/ ) { print " [OK]"; }
            else { print " [Should be $DevMap[$Unit]]"; }

            my $MountPoint = check_mount($Dev);
            if ( $MountPoint ) { chomp $MountPoint; print " Mounted as $MountPoint"; }
            else { print " NOT Mounted!"; }

            print "\n";
        }
    }
}

sub list_devices {
    foreach my $Unit ( sort keys %Device ) {
        my ( $Port, $Serial ) = split ':', $Device{$Unit};
        my $Dev = get_device($Serial);

        printf "%s ( Unit %-3s; Port %-3s ) : %s\n", $Serial, $Unit, $Port, defined $Dev ? $Dev : "Not Assigned; should be $DevMap[$Unit]";
    }
}

sub mount_devices {
    foreach my $Unit ( sort keys %Device ) {
        my ( $Port, $Serial ) = split ':', $Device{$Unit};
        my $Dev = get_device($Serial);
        my $MountDir = "/rstor/u$Unit";

        if ( defined $Dev ) {
            if ( not check_mount($Dev) ) {
                if ( $opt_verbose ) { print "mounting $Dev on $MountDir\n"; }
                if ( -d "$MountDir" ) { qx(mount -o noatime $Dev $MountDir); }
                else { print "Please create $MountDir first\n"; }
            } else {
                if ( $opt_verbose ) { print "$Dev already mounted on $MountDir\n"; }
            }
        }
    }
}

sub usage {
    print "
Usage:  $0 [options] command

    Options

        -v | --verbose  : Display more output (may be repeated for increated output)
        -h | --help     : This help text

    Commands

        list            : List all 3ware disks and what device it's assigned to
        check           : Check devices against our expected device map
        mount           : Mount any unmounted 3ware devices

";
    exit;
}

# Build our device hash
foreach my $Controller ( &get_3ware_controllers ) {
    open TWCLI, "/usr/local/bin/tw_cli /$Controller show|" or die "Unable to run tw_cli: $1\n";
    while ( <TWCLI> ) {
        next unless /^p(\d+)\s+\w+\s+[u\-](\d*)\s+[\d\.]+\s+GB\s+\d+\s+(\w+)/;
        next if $2 < 2;  # Skip our RAID-1 Arrays
        $Device{$2} = join ':', $1, $3;
    }
    close TWCLI;
}

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "h|help"       => \&usage,
    "v|verbose+"   => \$opt_verbose,
);

if ( not $ARGV[0] ) { &usage; exit; }

if ( $ARGV[0] =~ /list/i  ) { &list_devices; exit; }
if ( $ARGV[0] =~ /check/i ) { &check_devices; exit; }
if ( $ARGV[0] =~ /mount/i ) { &mount_devices; exit; }

&usage;
exit;
