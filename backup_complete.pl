#!/usr/bin/perl -w

use strict;
use Sys::Hostname;
my ( $TicketNo, $LogFile ) = @ARGV; 
my ( $PROGNAME ) = $0 =~ m{.*/(.*)$};
my %Media = ();
my @Dir = ();
my $MailRecipient = q(help-masada@techsafari.com);

sub Usage() {
    print "\n$PROGNAME <Ticket_Number> [Log_File]\n\n";
    exit 1;
}

Usage unless defined $TicketNo;

if ( not defined $LogFile ) {
    my ( $CurDay, $CurMon, $CurYear ) = (localtime(time))[3,4,5];
    $LogFile = sprintf "%s_backup.%4d%02d%02d.log", hostname(), ( $CurYear + 1900 ) , ( $CurMon + 1 ) , $CurDay;
}

my $BackupLog = $LogFile;
my $TicketRef = "[TS_Support #$TicketNo]";

# Make sure the log is uncompressed
if ( $BackupLog =~ /.gz$/ ) {
    print "Decompressing $BackupLog... ";
    qx(gunzip -f $BackupLog);
    print "OK\n";
    $BackupLog =~ s/.gz//;
}

open LOGFILE, "cat $BackupLog|" or die "Unable to open $BackupLog: $!\n";
open NEWLOG,  "| gzip -9 > $BackupLog.gz" or die "Unable to open $BackupLog.gz: $!\n";

while( <LOGFILE> ) {
    next if m/Waiting in NetBackup scheduler work queue/;
    if ( m/media id (.*) on/ ) { $Media{$1} = $1; }
    push @Dir, m/INF - Processing (.*)/;
    print NEWLOG;
}
close NEWLOG;
close LOGFILE;

unlink $BackupLog or die "Unable to remove $BackupLog: $!\n";

open MAIL, "| /usr/bin/mutt -s '$TicketRef' -a $BackupLog.gz $MailRecipient" or die "Unable to run the mail command: $!\n";

if ( @Dir ) {
    print MAIL "This job included the following " . scalar @Dir . " directories on " . qx(hostname) . "\n";
    foreach my $ID ( @Dir ) { print MAIL "$ID\n"; }
    print MAIL "\n";
} else {
    print MAIL "Hmmm... how odd, I couldn't find any directories in $BackupLog\n";
}

if ( %Media ) {
    print MAIL "The following tapes were used for this backup job:\n\n";
    foreach my $ID ( sort keys %Media ) { print MAIL "$ID\n"; }
} else {
    print MAIL "We couldn't determine which tapes were used for this backup job.\n";
    print MAIL "Please consult the Veritas job manager for more details\n";
}

print MAIL "\nThe Logfile for this job ($BackupLog.gz) is attached to this ticket\n";
close MAIL;

print "Mail sent to $MailRecipient for Ticket #$TicketNo\n";
1;
