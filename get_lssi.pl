#!/usr/bin/perl -w

use strict;
use FileHandle;
use POSIX qw(strftime);
use TS::Utils;
use Getopt::Long;
use vars qw( &mylog &mydie &myexit $opt_date );

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "d|date" => \$opt_date,
);

# Set our program variables
#
my ( $PROGNAME )      = ( $0 =~ /(\w+).pl$/ );
my $LOCKFILE          = qq(/var/tmp/${PROGNAME}.pid);
my $logfile           = qq(/var/log/rhino/${PROGNAME}.log);
my $working_date      = defined $opt_date    ? $opt_date        : strftime "%y%m", localtime(time);
my $working_directory = qq(/data/in/lssi/${working_date});
my $notify_email      = q(support@techsafari.com);
my $problem_email     = q(support-pager@techsafari.com);
my @filepattern       = qq(*${working_date}*.pgp);
my $gpg_password      = q(PASSWORD);
my $processed         = 0;  # gets set true if something was done
my $ispgp             = 0;  # gets set true if files are encrypted
my ( $ftp, $pgp, $infile, $outfile );

my %ftphash = (
    'HOST'   => q(ftp.lssi.net),
    'USER'   => q(USER),
    'PASS'   => q(PASSWORD),
    'RDIR'   => q(/LSSiDATA_CSVFeed),
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
    send_mail( $problem_email, 'Problem with Weekly Move Signal Trigger Update', @message );
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

$ftp = TS::Utils::FTP->new( \%ftphash ) or mydie TS::Utils::FTP->error;

myexit( "Some files matching @filepattern are not ready to download yet" ) unless $ftp->is_ready( @filepattern );

##
# If we made it here, there are files on the ftp site and they are ready for download
##
foreach $infile ( $ftp->ls( @filepattern ) ) {
    $outfile = $infile;

    if ( $infile =~ /(.*).pgp/ ) { $outfile = $1; $ispgp = 1; }

    if ( not -f $outfile ) {
        mylog "Downloading $infile";
        $ftp->get( $infile ) or mydie( $ftp->error );
        if ( $ftp->error_count ) { map { mylog( $_ ) } $ftp->error; }

        if ( $ispgp ) {
            mylog "Decrypting $infile -> $outfile";
            $pgp = TS::Utils::PGP->new( $infile ) or mydie( $ftp->error );
            $pgp->decrypt( $gpg_password ) or mydie( $ftp->error );
            undef $pgp;
            if ( $ftp->error_count ) { map { mylog( $_ ) } $ftp->error; }

            unlink( $infile ) or mydie "Unable to remove $infile";
        }

        $processed = 1;
    }
}

# clean up and exit
if ( $processed ) {
    my $message = 'Weekly move signals trigger processing sucessfully completed on ' . scalar localtime(time());
    send_mail( $notify_email, 'MoveSignal Triggers OK', $message );
}

myexit();

1;
