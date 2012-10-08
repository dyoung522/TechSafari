#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use Date::Manip qw( ParseDate UnixDate );

my $MINIMUM_ARCHIVE_DAYS = 7;  # The default number of days before email is archived.

my $opt_verbose = 0;
my $opt_archive = undef;
my $ArchiveDays = 0;
my $Today = time;
my $OneDay = ( 60 * 60 * 24 );
my $MailDir = $ENV{'HOME'} . '/Maildir';
my %MailDirs = (
    'ALERTS'  => q(.System Monitoring.Alerts),
    'DMESG'   => q(.System Monitoring.Alerts.dmesg),
    'NAGIOS'  => q(.System Monitoring.Alerts.NAGIOS),
    'NIGHTLY' => q(.System Monitoring.Daily Checklist.Nightly),
    'NETWORK' => q(.System Monitoring.Daily Checklist.Network Reports),
    'READ'    => q(.Read Mail),
    );

my @MailPatterns = (
    [ q(From: Perimeter Internetworking), 'NETWORK' ],
    [ q(Subject: \[NAGIOS\]), 'NAGIOS' ],
    [ q(Subject: .*error_report\.txt), 'ALERTS' ],
    [ q(Subject: dmesg from), 'DMESG' ],
    [ q(From: 3ware\@techsafari\.com), 'ALERTS' ],
    [ q(Daily TU Optout processing), 'NIGHTLY' ],
    [ q(Subject: .*Daily Transaction Archive), 'NIGHTLY' ],
    );

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "v|verbose+"   => \$opt_verbose,
    "a|archive:i"  => \$opt_archive,
    );

if ( defined $opt_archive ) {
    if ( $opt_archive < $MINIMUM_ARCHIVE_DAYS ) { $opt_archive = $MINIMUM_ARCHIVE_DAYS; }
    $ArchiveDays = $opt_archive * $OneDay;
    if ( $opt_verbose ) { print "-> Archiving mail older than $opt_archive days\n"; }
}

sub movemail {
    my ( $FileName, $Tag ) = @_;
    my $DirSuffix = q();

    # If the $Tag is a date (starts with a numeral)...
    if ( $Tag =~ /^[0-9]/ ) {
        my ( $Month, $Year ) = ( localtime( $Tag ) )[4,5];
        $Year += 1900;
        my $Quarter = 'Q4';
        if ( $Month < 9 ) { $Quarter = 'Q3'; }
        if ( $Month < 6 ) { $Quarter = 'Q2'; }
        if ( $Month < 3 ) { $Quarter = 'Q1'; }
        $DirSuffix = ".$Year.$Quarter";
        $Tag = 'READ';  # Reset $Tag so we can use our hash as normal below.
    }

    if ( not defined $MailDirs{$Tag} ) {
        print STDERR "$Tag is not defined\n";
        return 0;
    }

    my $Old = "$MailDir/cur/$FileName";
    my $New = "$MailDir/" . $MailDirs{$Tag} . "$DirSuffix/cur/$FileName";

    if ( not -f $Old ) {
        print STDERR "$Old does not exist\n";
        return 0;
    }

    if ( -f $New ) {
        print STDERR "$New already exists\n";
        return 0;
    }

    if ( $opt_verbose ) { print "-> Moving $FileName to $MailDirs{$Tag}$DirSuffix\n"; }

    rename( $Old, $New ) or
        print STDERR "Couldn't move $Old to $New: $!\n";

    return 1;
}

opendir( MAILDIR, "$MailDir/cur" ) or die "Unable to read files in $MailDir: $!\n";

while ( defined ( my $FileName = readdir(MAILDIR) ) ) {
    # Skip unread messages
    next if $FileName =~ /,$/;

    open( FILE, "< $MailDir/cur/$FileName" ) or die "Unable to read $FileName: $!\n";

    while ( <FILE> ) {
        my $Line = $_;

        # Skip the message body
        next if $Line =~ /^$/;

        if ( $opt_verbose >= 5 ) { print "---> Line = $Line"; }

        # Search our array of patterns and process the files if we find a match
        foreach my $Array ( @MailPatterns ) {
            my ( $Pattern, $Tag ) = @{$Array};
            if ( $opt_verbose >= 3 ) { print "---> Looking for [$Tag] $Pattern\n"; }
            if ( $Line =~ /$Pattern/ ) {
                if ( $opt_verbose >= 2 ) { print "--> $FileName matches \"$Pattern\"\n"; }
                movemail( $FileName, $Tag ) and last;
            }
        }

        # Only run if the file hasn't been moved in the above step.
        if ( -f "$MailDir/cur/$FileName" ) {
            if ( my ( $DateString ) = /^Date: (.*)/ ) {
                if ( my $MailDate = UnixDate( ParseDate( $DateString ), '%s' ) ) {
                    if ( $ArchiveDays ) {
                        my $DateDelta = $Today - $MailDate;
                        if ( $DateDelta > $ArchiveDays ) {
                            if ( $opt_verbose >= 2 ) {
                                printf "--> Archiving %s (%s) [%d days old]\n", $FileName, scalar localtime( $MailDate ), ( $DateDelta / $OneDay );
                            }
                            movemail( $FileName, $MailDate );
                        }
                    }
                }
            }
        }

        if ( $opt_verbose >= 3 ) { sleep 1; }
    }

    close( FILE );
}

closedir( MAILDIR );
