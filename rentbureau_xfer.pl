#!/usr/bin/perl -w

use strict;
use FileHandle;
use POSIX qw(strftime);
use TS::Utils;
use Getopt::Long;
use vars qw( &mylog &mydie &myexit &help );
use vars qw( $opt_verbose $opt_date $opt_log $opt_ldir $opt_email $opt_pager );

my ( $PROGNAME )      = ( $0 =~ /(\w+).pl$/ );
my $LOCKFILE          = qq(/var/tmp/${PROGNAME}.pid);

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "h|help"   => \&help,
    "d|date:i" => \$opt_date,
    "l|log:s"  => \$opt_log,
    "dir:s"    => \$opt_ldir,
    "e|email:s" => \$opt_email,
    "p|pager:s" => \$opt_pager,
    "v|verbose+" => \$opt_verbose,
);

# Set our program variables
#
my $logfile           = defined $opt_log     ? $opt_log         : qq(/var/log/rhino2/${PROGNAME}.log);
my $usedate           = defined $opt_date    ? $opt_date        : undef;
my $working_directory = defined $opt_ldir    ? $opt_ldir        : qq(/data/rhino2/rent_bureau/in);
my $notify_email      = defined $opt_email   ? $opt_email       : q(support@techsafari.com);
my $problem_email     = defined $opt_pager   ? $opt_pager       : $notify_email;

my @filepattern       = qq(techsafari_full_*.csv.asc*);
my $gpg_password      = q(PASSWORD);
my $ispgp             = 0;  # gets set true if files are encrypted
my $processed         = 0;  # gets set true if files have been processed
my ( $pgp, $infile, $outfile, $filedate );

open LOGFILE, ">>$logfile" or die "Unable to open $logfile";
LOGFILE->autoflush;

sub file_is_ready {
    my $file = shift;
    my $filesize = -s $file; sleep 5;
    return $filesize == -s $file;
}

sub help {
    print "
Usage:  $PROGNAME [h][-d date]

    -h | --help                  : Display this message

    -d | --date <yyyymmdd>       : Specify the date to use for processing (should be in MMMMDDYY format)
    -l | --log  <logfile>        : Specify what log file to use
    -e | --email <email_address> : Specify which email address to use for notifications
    -p | --pager <email_address> : Specify which email address to use for pages

    --dir <working_dir>          : Specify what directory we should put the files in

";
    exit;
}

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
    my @message = @_;
    mylog( @message ) if @message;
    unlink($LOCKFILE) if defined $LOCKFILE;
    close LOGFILE;
    exit;
}

sub mydie {
    my @message = @_;
    mylog( @message );
    send_mail( $problem_email, 'Problem with Daily RentBureau Transfer', @message );
    myexit;
}

##
# See if we're already running, if not, create our lock file
##
if ( -f $LOCKFILE ) {
    # Check for stale lockfile, exit if the process is running otherwise
    # remove the old lockfile and continue.
    if ( system( "cat $LOCKFILE | xargs ps -o comm= -p > /dev/null" ) == 0 ) {
        if ( $opt_verbose ) { print "$PROGNAME is already running with PID " . qx(cat $LOCKFILE) . "\n"; }
        exit;
    }
    mylog( "A stale lock file was found, please check for errors during the previous run." );
    mylog( "Removing stale lock file and continuing processing." );
    unlink( $LOCKFILE );
}

# Create our lockfile
open LOCK, ">$LOCKFILE" or die "Unable to create $LOCKFILE: $!\n";
print LOCK qq{$$};
close LOCK;

chdir($working_directory) or mydie "Could not cd to $working_directory";

##
# Process files
##
foreach $infile ( <@filepattern> ) {
    $outfile = $infile;

    if ( $infile =~ /(.*).asc/ ) { $outfile = $1; $ispgp = 1; }
    ( $filedate ) = ( $outfile =~ /(\d{8})/ );

    # If we're given a date to use, skip files that don't match
    if ( defined $usedate and not $filedate == $usedate ) { next; }

    if ( $opt_verbose ) { mylog "Processing $infile --> $outfile"; }

    if ( -f $outfile and not defined $usedate ) {
        if ( $opt_verbose ) { mylog( "$outfile already exists, skipping" ); }
        next;
    }

    ##
    # So far so good, is the file ready for us?
    ##
    next unless file_is_ready( $infile );

    ##
    # Let's do it
    ##
    mylog "Decrypting $infile --> $outfile";
    $pgp = TS::Utils::PGP->new( $infile ) or mydie( "Unable to create PGP object" );
    $pgp->decrypt( $gpg_password, $outfile ) or mylog( $pgp->error ) and next;
    #unlink( $infile ) or mylog( "Unable to remove $infile" );
    if ( not $infile =~ /processed/ ) {
        rename( $infile, "$infile.processed" ) or mylog "Unable to rename $infile";
    }

    # Call the next phase of the RentBureau process and wait for it to complete.  0 == success
    if ( $opt_verbose ) { mylog( "Running run_rent_bureau.pl process using $filedate" ); }
    system( "/usr/local/rhino2/scripts/cron_wrap.sh /usr/local/rhino2/scripts/run_rent_bureau.pl $filedate >> $logfile" )
        and mydie( "Error with RentBureau Data Processing; see $logfile" );

    # Ok, we got this far... let everyone know we ran sucessfully.
    my $message = "Daily RentBureau processing of $outfile sucessfully completed on " . scalar localtime(time());
    send_mail( $notify_email, "Daily RentBureau for $filedate", $message );

    $processed = 1;
}

if ( not $processed ) { if ( $opt_verbose ) { mylog( "No files processed" ); } }
# clean up and exit
myexit();

1;
