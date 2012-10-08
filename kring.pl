#!/usr/bin/perl -w
#
# Checks the kernel buffer with dmesg and emails any contents to admins.
#
#

use diagnostics;
use strict;

sub sendpage {
    my $PageTo = q(oncall@techsafari.com);

    my $Host = qx(hostname -s); chomp($Host);

    open MAIL, qq(|mail -s "dmesg from $Host" $PageTo)
        or die "Unable to run mail: $!\n";
    print MAIL @_;
    close MAIL;
}

my $LogFile = q(/var/log/dmesg);
my @Mesg;

open( LOGFILE, qq(>>$LogFile) )
    or sendpage qq(cant open $LogFile)
        and die "Unable to write to $LogFile: $!\n";

open MESG, q(dmesg -c|)
    or sendpage qq(Unable to run dmesg: $!)
        and die "Unable to run dmesg: $!\n";

while(<MESG>) {
    print LOGFILE;

    # Skip blank lines
    next unless $_;

    # Filter out stuff we don't care about
    next if /nfs_statfs: statfs error = 13/;
    next if /nfs: server netinst (not responding|OK)/;
    next if /cdrom: open failed/i;
    next if /ISO 9660 Extensions: Microsoft Joliet Level 3/;
    next if /cmd_timeout_in_sec/;
    next if /SIGCHLD set to SIG_IGN but calls wait/;
    next if /Workaround activated/;
    next if /Scheduling SCAN for new luns/;
    next if /RESCAN/;
    next if /^\s*audit.*avc: denied/;
    # Ignore some common 3ware notifications
    next if /verify (started|completed)/i;
    next if /3w\-9xxx:.*Battery .* (started|completed)/;
    next if /3w\-9xxx:.*Battery capacity test is overdue/;
    # Poorly worded warning from the LSI kernel module.  Safe to ignore.
    next if /megasas: Failed to alloc kernel SGL buffer for IOCTL/;

    # Push the message into our output array
    push @Mesg, $_;
}

close(MESG);
close(LOGFILE);

# Send the message
sendpage @Mesg if @Mesg;

