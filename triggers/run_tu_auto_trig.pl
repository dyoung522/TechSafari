#!/usr/bin/perl -w

use strict;
use FileHandle;
use POSIX qw(strftime);
use TS::Utils;
use vars qw( &mylog &mydie &myexit );

# Set our program variables
#
my ( $PROGNAME )      = ( $0 =~ /(\w+).pl$/ );
my $LOCKFILE          = qq(/var/tmp/${PROGNAME}.pid);
my $logfile           = qq(/var/log/rhino/${PROGNAME}.log);
my $working_directory = q(/data/triggers/tu/auto);
my $notify_email      = q(tutrig@techsafari.com);
my $problem_email     = $notify_email;
my @filepattern       = q(PRM.EDTOUT.DGIMRKT.TULTRIG*.pgp);
my $gpg_password      = q(PASSWORD);
my $processed         = 0;  # gets set true if something was done
my $problem_message   = q(Problem with daily TU Auto Triggers);
my $completed_message = q(Daily TU Auto Trigger processing sucessfully completed on );
my $completed_subject = q(Daily TU Auto Triggers OK);
my ( $ftp, $pgp, $infile, $outfile );

my %ftpIn = (
    'HOST'   => q(ftp.techsafari.com),
    'USER'   => q(tutrig),
    'PASS'   => q(PASSWORD),
    'RENAME' => q(.DONE),
);

my %ftpOut = (
    'HOST'   => q(mtc01.prod.market-tech.com),
    'USER'   => q(tuser),
    'PASS'   => q(PASSWORD),
    'RDIR'   => q(/fset36/MTC/TRIGGERS/DAILY_BUILDS/TU_AUTO_BUYER/IN),
);

sub mylog {
    my @message = @_ or return;
    my $hostname = qx(hostname -s); chomp $hostname;

    if ( &istty ) {
        printf "[%s %s] %s\n",
            $hostname,
            strftime("%Y/%m/%d %H:%M:%S", localtime(time())),
            @message;
    }

    printf LOGFILE "[%s %s] %s\n",
        $hostname,
        strftime("%Y/%m/%d %H:%M:%S", localtime(time())),
        @message;
}

sub myexit {
    unlink($LOCKFILE) if defined $LOCKFILE;
    close LOGFILE;
    exit;
}

sub mydie {
    my @message = @_;
    mylog( @message );
    send_mail( $problem_email, $problem_message, @message );
    myexit;
}

open LOGFILE, ">>$logfile" or die "Unable to open $logfile";
LOGFILE->autoflush;

##
# See if we're already running, if not, create our lock file
##
if ( -f $LOCKFILE ) {
    # Check for stale lockfile, exit if the process is running otherwise
    # remove the old lockfile and continue.
    if ( system( "cat $LOCKFILE | xargs ps -o comm= -p > /dev/null" ) == 0 ) { exit; }
    mylog( "A stale lock file was found, please check for errors during the previous run." );
    mylog( "Removing stale lock file and continuing processing." );
    unlink( $LOCKFILE );
}

# Create our lockfile
open LOCK, ">$LOCKFILE" or die "Unable to create $LOCKFILE: $!\n";
print LOCK qq{$$};
close LOCK;

##
# So far so good, is the file ready for us?
##
chdir($working_directory);

$ftp = TS::Utils::FTP->new( \%ftpIn ) or mydie TS::Utils::FTP->error;

myexit( "Some files matching @filepattern are not ready to download yet" ) unless $ftp->is_ready( @filepattern );

##
# If we made it here, there are files on the ftp site and they are ready for download
##
foreach $infile ( $ftp->ls( @filepattern ) ) {
    ( $outfile ) = $infile =~ /(.*).pgp/;
    if ( not -f $outfile ) {
        mylog "Downloading $infile";
        $ftp->get( $infile ) or mydie( $ftp->error );
        if ( $ftp->error_count ) { map { mylog( $_ ) } $ftp->error; }

        mylog "Decrypting $infile -> $outfile";
        $pgp = TS::Utils::PGP->new( $infile ) or mydie( $ftp->error );
        $pgp->decrypt( $gpg_password ) or mydie( $ftp->error );
        undef $pgp;
        if ( $ftp->error_count ) { map { mylog( $_ ) } $ftp->error; }

        unlink( $infile ) or mydie "Unable to remove $infile";

        $processed = 1;
    }
}

$ftp = undef;
$processed = 0;

$ftp = TS::Utils::FTP->new( \%ftpOut ) or mydie TS::Utils::FTP->error;

##
# If we made it here, files are ready for remote transfer
##
foreach $outfile ( glob( '*[0-9]' ) ) {
    if ( not $ftp->list( $outfile ) ) {
        mylog "Transferring $outfile to " . $ftp->host;
        $ftp->put( $outfile ) or mydie( $ftp->error );
    }

    mylog "Compressing $outfile";
    qx(gzip -f -9 $outfile);

    $processed = 1;
}

# clean up and exit
if ( $processed ) {
    my $message = $completed_message . scalar localtime(time());
    send_mail( $notify_email, $completed_subject, $message );
}

myexit();

1;
