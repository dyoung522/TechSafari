#!/usr/bin/perl -w

##
## This script will continuously retrieve a URL based upon options given on the command line
##
## It checks to see if it's already running and will time out individual wgets so they don't
## hang the process.
##
## Written by Donovan C. Young, 09/2008
##
use strict;
use FileHandle;
use POSIX qw(strftime);
use Getopt::Long;
use vars qw( &mylog &mydie &myexit &help );
use vars qw(
            $opt_freq
            $opt_help
            $opt_log
            $opt_pass
            $opt_url
            $opt_user
            $opt_timeout
            $opt_tempdir
            $opt_verbose
        );

my ( $PROGNAME ) = ( $0 =~ /(\w+).pl$/ );
my $LOCKFILE;

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "h|help"      => \$opt_help,
    "u|user:s"    => \$opt_user,
    "p|pass:s"    => \$opt_pass,
    "U|url:s"     => \$opt_url,
    "l|log:s"     => \$opt_log,
    "f|freq:i"    => \$opt_freq,
    "t|timeout:i" => \$opt_timeout,
    "T|tempdir:s" => \$opt_tempdir,
    "v|verbose+"  => \$opt_verbose,
);

##
# Set defaults on variables
##
my $frequency = defined $opt_freq    ? $opt_freq    : 10;
my $timeout   = defined $opt_timeout ? $opt_timeout : 5;
my $verbose   = defined $opt_verbose ? $opt_verbose : 0;
my $tempdir   = defined $opt_tempdir ? $opt_tempdir : '/tmp/fetchaprice_get';
my $logfile   = defined $opt_log     ? $opt_log     : qq($tempdir/${PROGNAME}.log);

##
# Subroutines
##

#
# help() print out the help text
#
sub help {
    print "
Usage:  $PROGNAME [options] --user <username> --pass <password> --url <URL>

    [Options]

    -h | --help                  : Display this message

    -l | --log  <logfile>        : Specify what log file to use (default: $logfile)
    -f | --freq <frequency>      : The frequency in which to run our wgets (in seconds) (default: $frequency)
    -t | --timeout <timeout>     : How long before we time out the wget (in seconds) (default: $timeout)
    -T | --tempdir <dir>         : What directory should we use for our temp files (default: $tempdir)
    -v | --verbose               : Generate output to the screen if running interactively (more -v's = more output)

    <Required>

    -p | --pass <username>       : Specify the Password
    -u | --user <username>       : Specify the Username
    -U | --url <URL>             : Specify the URL

";
    exit;
}

#
# Return true if running from a termina
#
sub istty { return -t STDIN && -t STDOUT; }

#
# Our signal handler
#
sub sig_quit { myexit( 'Terminate Signal Caught; Exiting' ); }

#
# mylog() will print a message to our log file (and screen if running interactively)
#
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

#
# Clean up and exit the program cleaning (removing lockfiles and closing logs)
#
sub myexit {
    my @message = @_;
    mylog( @message );
    unlink $LOCKFILE if defined $LOCKFILE;
    close LOGFILE;
    exit;
}

#
# Exit the program abnormally, printing a message before we terminate
#
sub mydie {
    my @message = @_;
    mylog( @message );
    myexit;
}

##
## Start of Program
##

##
# Create our temp directory and cd into it
##
if ( not -d $tempdir ) { mkdir $tempdir or myexit( "Unable to create $tempdir" ); }
chdir $tempdir or myexit( "Unable to change to $tempdir" );

##
# See if we're already running, if not, create our lock file
##
# Create a unique lockfile based upon the url we were asked to fetch
my $url_unique;
( $url_unique ) = ( $opt_url =~ m|http://.*/(.*)\..*$| ) or $url_unique = "unknown";
$LOCKFILE = qq($tempdir/${PROGNAME}.$url_unique.lock);

if ( -f $LOCKFILE ) {
    # Check for stale lockfile, exit if the process is running otherwise
    # remove the old lockfile and continue.
    if ( system( "cat $LOCKFILE | xargs ps -o comm= -p > /dev/null" ) == 0 ) { mylog( 'Lockfile exists, exiting' ); exit; }
    mylog( "A stale lock file was found, please check for errors during the previous run." );
    mylog( "Removing stale lock file and continuing processing." );
    unlink $LOCKFILE;
}

#
# Print help if requested
#
if ( defined $opt_help ) { &help; }

##
# Open LOGFILE for writing
##
open LOGFILE, ">>$logfile" or die "Unable to open $logfile";
LOGFILE->autoflush;

##
# Check our program variables and set defaults
##
if ( not defined $opt_user ) { mylog( 'Missing Username (-u|--user)' ); &help; }
if ( not defined $opt_pass ) { mylog( 'Missing Password (-p|--pass)' ); &help; }
if ( not defined $opt_url  ) { mylog( 'Missing URL (-U|--url)' ); &help; }

##
# Create our lockfile
##
open LOCK, ">$LOCKFILE" or die "Unable to create $LOCKFILE: $!\n";
print LOCK qq{$$};
close LOCK;

#
# Create our command line
#
my $wget_command       = "wget -q --user=$opt_user --password=$opt_pass $opt_url";
my $wget_command_print = "wget -q --user=$opt_user --password=*HIDDEN* $opt_url";

##
# So far so good, let's do it
##

##
# Log our start-up
##
mylog( "$PROGNAME starting for $wget_command_print" );

while ( 1 ) {   # Loop forever
    ##
    # Set our signal handlers
    ##
    # Timeout handler
    $SIG{ALRM} = sub { die "timeout" };             # What to do on timeout

    # CTRL-C or kill handler (so we can exit cleanly)
    $SIG{INT}  = \&sig_quit;
    $SIG{TERM} = \&sig_quit;

    if ( $verbose >= 2 ) { mylog "Executing $wget_command_print"; }

    ##
    # Run in eval so that our alarm signal can interrupt the wget without terminating the program
    ##
    eval {
        alarm($timeout);            # Time out in $timeout seconds
        system( $wget_command );    # Run command
        alarm(0);                   # Disable alarm
    };

    ##
    # If we timed out, print an error in the log so we know
    ##
    if ( defined $@ and $@ =~ /timeout/ ) { mylog( "Timeout occurred" ); }

    ##
    # Remove any downloaded files
    ##
    my ( $filename ) = ( $opt_url =~ m|http://.*/(.*)$| );
    if ( -f $filename ) {
        if ( $verbose >= 2 ) { mylog( "Removing $filename" ); }
        unlink $filename;
    }
    
    ##
    # Wait for the next loop cycle
    ##
    sleep $frequency;
}

# clean up and exit, theoretically we should never get here.
myexit();

1;
