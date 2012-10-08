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
my $logfile           = defined $opt_log     ? $opt_log         : qq(/var/log/${PROGNAME}.log);
my $working_date      = defined $opt_date    ? $opt_date        : strftime "%m%d%y", localtime(time);
my $working_directory = defined $opt_ldir    ? $opt_ldir        : qq(/util01/optin);
my $notify_email      = defined $opt_email   ? $opt_email       : q(support@techsafari.com);
my $problem_email     = defined $opt_pager   ? $opt_pager       : $opt_email;

my @filepattern       = qq(tuoptout.d${working_date}.pgp);
my $gpg_password      = q(PASSWORD);
my $processed         = 0;  # gets set true if something was done
my $ispgp             = 0;  # gets set true if files are encrypted
my ( $ftp, $pgp, $infile, $outfile );

my %ftphash = (
    'HOST'   => q(ftp1.market-tech.com),
    'USER'   => q(USER),
    'PASS'   => q(PASSWORD),
    'RDIR'   => q(tuoptout),
    'RENAME' => q(.UPLOADED),
);

sub help {
    print "
Usage:  $PROGNAME [h][-d date]

    -h | --help                  : Display this message

    -d | --date <yymmdd>         : Specify the date to use for processing (should be in MMDDYY format)
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
    mylog( @message );
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
chdir($working_directory) or mydie "Could not cd to $working_directory";

$ftp = TS::Utils::FTP->new( \%ftphash ) or mydie TS::Utils::FTP->error;

if ( $opt_verbose ) { mylog "Checking FTP site for @filepattern"; }
my $ready = $ftp->is_ready( @filepattern );
if ( not defined $ready or $ready == 0 ) { myexit "@filepattern does not exist on the remote server"; }
if ( $ready == 2 ) { myexit "@filepattern is still being transferred to the remote server"; }

##
# If we made it here, there are files on the ftp site and they are ready for download
##
if ( $opt_verbose ) { mylog "Starting FTP transfer"; }
foreach $infile ( $ftp->ls( @filepattern ) ) {
    $outfile = $infile;

    if ( $infile =~ /(.*).pgp/ ) { $outfile = $1; $ispgp = 1; }
    
    if ( $opt_verbose ) { mylog "Currently working with $infile --> $outfile"; }

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
    my $message = "Daily TU Optout processing of @filepattern sucessfully completed on " . scalar localtime(time());
    send_mail( $notify_email, '[ Daily TU Optout ]', $message );
}

myexit();

1;
