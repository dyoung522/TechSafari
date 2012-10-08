#!/usr/bin/perl -w

use strict;
use FileHandle;
use POSIX qw(strftime);
use TS::Utils;
use Getopt::Long;
use vars qw( &mylog &mydie &myexit &version &help );
use vars qw( $opt_verbose $opt_date $opt_host $opt_user $opt_pass $opt_pattern $opt_rdir $opt_ldir );

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "V|version"    => \&version,
    "h|help"       => \&help,
    "v|verbose+"   => \$opt_verbose,
    "H|host=s"     => \$opt_host,
    "U|user=s"     => \$opt_user,
    "P|pass=s"     => \$opt_pass,
    "p|pattern=s"  => \$opt_pattern,
    "r|rdir=s"     => \$opt_rdir,
    "l|ldir=s"     => \$opt_ldir,
    "D|date=s"     => \$opt_date,

);

# Set our program variables
#
my ( $PROGNAME )      = ( $0 =~ /(\w+).pl$/ );
my $LOCKFILE          = qq(/var/tmp/${PROGNAME}.pid);
my $logfile           = qq(/var/log/rhino/${PROGNAME}.log);
my $notify_email      = q(support@techsafari.com);
my $problem_email     = q(support-pager@techsafari.com);
my $gpg_password      = q(PASSWORD);
my $processed         = 0;  # gets set true if something was done
my $ispgp             = 0;  # gets set true if files are encrypted

my $working_date      = defined $opt_date    ? $opt_date        : strftime "%y%m%d", localtime(time);
my @filepattern       = defined $opt_pattern ? ( $opt_pattern ) : ( q(*) );
my $working_directory = $opt_ldir;
my $remote_directory  = $opt_rdir;

if ( not defined $opt_host ||
     not defined $opt_user ||
     not defined $opt_pass ) { die "Must supply --host, --user, and --pass\n"; }


my %ftphash = (
    'HOST'   => $opt_host,
    'USER'   => $opt_user,
    'PASS'   => $opt_pass,
    'RDIR'   => $opt_rdir,
);

my ( $ftp, $pgp, $infile, $outfile );

sub help {
    print "

Usage:  $PROGNAME <options>

    -V, --version     :  Print version information and quit.
    -h, --help        :  Print this help information and quit.
    -v, --verbose     :  Increase verbosity (may be supplied more than once).
    -H, --host        :  The remote host URL to connect to
    -U, --user        :  The remote username to use
    -P, --pass        :  The password for username.
    -p, --pattern     :  The filepattern to look for (wildcards OK)
    -r, --rdir        :  The remote directory on HOST
    -l, --ldir        :  The local directory to change to first
    -D, --date        :  The date string to use (for date patterns)

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
    unlink($LOCKFILE) if defined $LOCKFILE;
    close LOGFILE;
    exit;
}

sub mydie {
    my @message = @_;
    mylog( @message );
    send_mail( $problem_email, "Problem in $PROGNAME", @message );
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
    if ( $infile =~ /(.*).pgp/ ) { $outfile = $1; $ispgp = 1; }
    else { $outfile = $infile; };

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
    my $message = "$PROGNAME completed sucessfully on " . scalar localtime(time());
    send_mail( $notify_email, "$PROGNAME OK", $message );
}

myexit();

1;
