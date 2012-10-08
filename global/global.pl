#!/usr/bin/perl -w #
# Author: Donovan Young
#
#  $Id: global.pl,v 1.9 2007/04/20 19:54:32 dyoung Exp $
#
# Description:
# -----------
#
#   Performs remote commands on all systems in a given file.
#
# Implementation Notes:
# ---------------------
#
# Requires Net::SSH::Perl
#
#  Note:  Net::SSH::Perl is extremely slow unless Math::BigInt::GMP
#         is installed!
#
########################################################################
#
#  $Log: global.pl,v $
#  Revision 1.9  2007/04/20 19:54:32  dyoung
#  minor bug fix
#
#  Revision 1.8  2007/04/11 18:53:53  dyoung
#  Added more output to VDEBUG display (informs of running jobs)
#
#  Revision 1.7  2007/03/26 15:36:38  dyoung
#  Changed local_host routine to use sys::hostname
#
#  Revision 1.6  2007/03/23 18:25:25  dyoung
#  Minor code cleanup and changed DEFAULTS to use a hash.
#
#  Revision 1.5  2007/03/22 21:59:31  dyoung
#  Minor fix (logfiles now all lowercase)
#
#  Revision 1.4  2007/03/22 21:47:50  dyoung
#  Multiple line output is now configurable via -l.
#
#  Revision 1.3  2007/03/22 19:58:01  dyoung
#  Added Math::BigInt::GMP as a requirement for Net::SSH::Perl
#
#  Revision 1.2  2007/03/22 17:42:34  dyoung
#  Working release
#
#  Revision 1.1  2007/03/22 15:55:43  dyoung
#  Initial release based on code from global_install.pl
#
########################################################################

require 5.004;

use strict;
use POSIX ":sys_wait_h";
use Getopt::Long;
use Sys::Hostname;

use vars qw($PROGNAME $AUTHOR $SPAT %DEFAULT );
use vars qw(%EVALUE $EOK $EERR $ECONFIG $EAUTH $EUNKNOWN);
use vars qw($VQUIET $VNORM $VLOUD $VDEBUG $VDEVEL $VINSANE);
use vars qw($verbose $command $server_file $opt_server $opt_output $opt_lines $opt_user $opt_pass $opt_threads);
use vars qw(%children %config %status $config_dir $log_dir $max_threads $local_host);

##
## Prototypes
##
sub MyExit(@);
sub ParseConfig();
sub RunSSH($$);
sub GetPassword();
sub Version();
sub Help();
sub SpawnThread($);

$PROGNAME = 'global';
$AUTHOR   = 'Donovan C. Young';

$DEFAULT{'USER'}    = $ENV{'USER'};
$DEFAULT{'THREADS'} = 5;
$DEFAULT{'LINES'}   = 1;

# Globally defines the printf pattern to use for servers.
*SPAT     = \'%-10s';

# Standardize Exit Codes
$EOK      = 0;
$EERR     = 1;
$ECONFIG  = 2;
$EAUTH    = 3;
$EUNKNOWN = 255;
%EVALUE   = (
    $EOK       => 'OK',
    $EERR      => 'Program Error',
    $ECONFIG   => 'Config Error',
    $EAUTH     => 'Authentication Error',
    $EUNKNOWN  => 'Unknown Error',
);

# Standardize Verbose Levels
$VQUIET   = 0;    # Quiet, no output (except errors)
$VNORM    = 1;    # Normal output, provides minimal feedback
$VLOUD    = 2;    # Give more output, feedback on what's going on
$VDEBUG   = 3;    # Gives additional output intended to help diagnose a problem
$VDEVEL   = 4;    # Provides feedback relative mostly to development
$VINSANE  = 5;    # Give an imense amount of feedback, intended for severe
                  # debugging / development
##
## Main()
##
# Initialize our variables and set some defaults
$log_dir     = "$ENV{'HOME'}/.global/";
$config_dir  = "$ENV{'HOME'}/.global/";
$max_threads = $DEFAULT{'THREADS'};

# Parse command line arguments
Getopt::Long::Configure('bundling', 'no_ignore_case');
GetOptions(
     "c|command=s"   => \$command,
     "V|version"     => \&Version,
     "h|help"        => \&Help,
     "v|verbose+"    => \$verbose,
     "f|config=s"    => \$opt_server,
     "o|output=s"    => \$opt_output,
     "u|user=s"      => \$opt_user,
     "p|password:s"  => \$opt_pass,
     "t|threads=i"   => \$opt_threads,
     "l|lines=i"     => \$opt_lines,
);

# Validate command
if ( not defined $command ) {
    print "\nERROR:  You must supply a <command> to perform.\n";
    Help();
}

# Validate the thread option
if ( defined $opt_threads ) {
    if ( $opt_threads > 0 and $opt_threads < 25 ) {
        $max_threads = $opt_threads;
    } else {
        print "Invalid number of threads provided, using default of $max_threads\n";
    }
}

# Validate username
if ( defined $opt_user and not $opt_user =~ m/^[a-z]+/ ) {
    print "Invalid user supplied, using default ($DEFAULT{'USER'})\n";
    $opt_user = undef;
}

# Validate server file
if ( not defined $opt_server ) {
    MyExit $ECONFIG, "You must supply a server file";
} else {
    if ( not $opt_server =~ /^[\.\/]/ ) { $server_file = $config_dir; }
    $server_file .= $opt_server;
}

# Does our config file exist and is readable?
if ( defined $server_file and not -r $server_file ) {
    MyExit $ECONFIG, "$server_file is not a valid configuration file";
}

# Set global vars based on options passed
( $opt_output ) && ( $log_dir   = $opt_output    );
( $opt_lines  ) || ( $opt_lines = $DEFAULT{'LINES'} );
( $opt_user   ) || ( $opt_user  = $DEFAULT{'USER'}  );

if ( not defined $verbose )   { $verbose = $VQUIET; }
if ( defined $opt_pass and ( not $opt_pass ) ) { GetPassword(); }

# Validate the log_dir variable
if ( not defined $log_dir ) {
    MyExit $ECONFIG, "Output directory is not defined.";
}

# remove the trailing '/' on our log directory if it exists
if ( $log_dir =~ /\/$/ ) { $log_dir =~ s/\/$//; }

# Validate the output directory
if ( not -d $log_dir ) {
    MyExit $ECONFIG, "$log_dir is not a valid directory";
}

if ( $verbose >= $VLOUD ) { print "Writing log files to $log_dir\n"; }
if ( $verbose >= $VDEBUG ) { print "Reading config from $server_file\n"; }

# Get the local installation host
if ( not ( ( $local_host ) = ( hostname() =~ /^([^\.]*)\.?/ ) ) ) {
    MyExit $ECONFIG, "Unable to determine the local hostname!";
}
$local_host = ucfirst $local_host;
if ( $verbose >= $VDEBUG ) { printf "[$SPAT] local host\n", $local_host; }

ParseConfig();

##
## Main loop
##
while ( 1 ) {
    for my $server ( sort keys %config ) {
        # Display status of still-running jobs
        if ( $config{$server}{'PID'} ) {    # We're still running
            if ( $verbose >= $VDEBUG ) {
                printf "[$SPAT] Job $config{$server}{'PID'} is still running\n", $server;
            }
            next;
        }

        if ( ( keys %children ) >= $max_threads ) {
            if ( $verbose >= $VDEBUG ) { print "Maximum threads ($max_threads) reached, waiting for some processes to complete\n"; }
            last;
        }

        SpawnThread( $server );
    }

    # Wait for and reap child processes
    while ( ( my $pid = waitpid(-1, &WNOHANG) ) >= 1 ) {
        # Determine the real exit status
        my $exit = $? >> 8;

        if ( $verbose >= $VLOUD ) {
            printf "[$SPAT] Returned with exit code $exit", $children{$pid};
            if ( defined $EVALUE{$exit} ) { print " ($EVALUE{$exit})"; }
            print "\n";
        }

        # Track our progress
        $status{$children{$pid}} = $exit;

        # Delete the hash entries
        delete $config{$children{$pid}};
        delete $children{$pid};
    }

    # Check and display status of returned jobs
    for my $server ( sort keys %status ) {
        # only return errors if no verbosity has been defined
        if ( $verbose == $VQUIET ) {
            if ( $status{$server} ) { printf "[$SPAT] Exited with non-zero status ($status{$server})\n", $server; }
        }

        # Prevent it from displaying again
        delete $status{$server};
    }

    # Exit once all the processes complete.
    last if not %config;

    # Pause betwen runs
    if ( $verbose >= $VDEBUG ) { sleep 5; }
}

##
## Subroutines
##
# MyExit <exit value> [optional message to display]
sub MyExit(@) {
    my $exit = shift;
    my $message = shift;
    if ( defined $message ) {
        if ( $verbose >= $VLOUD ) { printf "$message\n", @_; }
    }
    exit $exit;
}

sub ParseConfig() {
    my $fqdn = q{};
    my $line = 0;

    # We've previously validated the server_file variable
    open CONFIG, "<$server_file" or MyExit( $ECONFIG, "Could not open $server_file: $!");

    while( <CONFIG> ) {
        $line++;

        # Skip comments and blank lines
        next if /^\s*#/;
        next if /^\s*$/;

        # Drop the trailing newline
        chomp;

        if ( $verbose >= $VDEBUG ) { print "==> $_\n"; }

        $fqdn = $_;

        if ( not defined $fqdn ) {
            MyExit( $ECONFIG, "Problem in config file (line $line): Line does not contain the proper syntax" );
        }

        # Get the server name from the FQDN
        my ( $server ) = ( $fqdn =~ m/^(\w+)\.|$/ );
        $server = ucfirst $server;

        # Validate entries
        if ( not $server ) {
            MyExit( $ECONFIG, "Error in config file (line $line): FQDN is wrong ($fqdn)" );
        }

        # If this is the local host, use 127.0.0.1 instead
        if ( $server eq $local_host ) {
            $fqdn = "127.0.0.1";
        }

        # Load the hash
        $config{$server} = {
            'FQDN'  => $fqdn,
            'PID'   => '',
        };
    } # End While

    close CONFIG;
} # End ParseConfig

sub RunSSH($$) {
    require Math::BigInt::GMP;  # Needed for Net::SSH::Perl.
    use Net::SSH::Perl;

    my ( $server, $ssh_cmd ) = ( @_ );
    my ( $ssh, $ssh_stdout, $ssh_stderr, %ssh_options ) = undef;
    my $fqdn     = $config{$server}{'FQDN'};
    my $ssh_user = $opt_user;
    my $ssh_pass = ( defined $opt_pass ) ? "$opt_pass" : '';
    my $ssh_exit = $EUNKNOWN;
    my $logfile  = lc "$log_dir/$server.output";

    %ssh_options = (
        'protocol'       => 2,
        'port'           => 22,
        'debug'          => ( $verbose >= $VINSANE ),
        'identity_files' => [ "$ENV{'HOME'}/.ssh/identity" ],
    );

    # Run the command
    $ssh = Net::SSH::Perl->new($fqdn, %ssh_options);

    # Need to wrap this in eval because the login call will die if it can't
    # authenticate... stupid!
    eval { $ssh->login($ssh_user, $ssh_pass); };

    # Check if we errored above, otherwise run the command.
    if ( $@ ) {
        if ( $verbose >= $VDEBUG ) {
            MyExit $EAUTH, "[$SPAT] ERROR:  $@", $server;
        } else {
            MyExit $EAUTH, "[$SPAT] ERROR:  Could not authenticate", $server;
        }
    }

    ( $ssh_stdout, $ssh_stderr, $ssh_exit ) = $ssh->cmd($ssh_cmd);

    # Print any errors
    if ( defined $ssh_stderr ) {
        chomp $ssh_stderr;
        printf "[$SPAT] (stderr) $ssh_stderr\n", $server;
    }

    # Send stdout to the logfile and screen (if requested)
    if ( defined $ssh_stdout ) {
        my $linenum = 1;
        chomp $ssh_stdout;
        print LOG "$ssh_stdout\n";

        if ( $verbose >= $VNORM ) {
            foreach my $line ( split '\n', $ssh_stdout ) {
                if ( ( $verbose < $VLOUD ) and ( $linenum > $opt_lines ) ) {
                    printf "[$SPAT] Please see %s for remaining output\n", $server, $logfile;
                    last;
                }
                printf "[$SPAT] (stdout) %2d: %s\n", $server, $linenum++, $line;
            }
        }
    }

    return $ssh_exit;
} # End RunSSH

sub SpawnThread($) {
    my ( $server ) = ( @_ );
    my ( $pid, $status );

    if ( not defined ( $pid = fork() ) ) {
        die "Could not fork:  $!\n";
    }

    if ( $pid ) {
        # Parent process
        $children{$pid} = $server;
        $config{$server}{'PID'} = $pid;
        return;
    }

    # Child Process
    my $logfile  = lc "$log_dir/$server.output";

    if ( $verbose >= $VDEBUG ) { printf "[$SPAT] Process Starting\n", $server; }

    # Open the log file for writing
    open LOG, ">>$logfile" or die "Unable to write to $logfile: $!\n";

    # Print a header to our log file
    printf LOG "-=-=-=-=-=-=-=-=-=-=-=-=-\n";
    printf LOG "[%s] Running command \"%s\"\n", scalar localtime(time), $command;
    printf LOG "-=-=-=-=-=-=-=-=-=-=-=-=-\n";

    if ( $verbose >= $VDEBUG ) { printf "[$SPAT] Output being saved to $logfile\n", $server; }

    $status = RunSSH( $server, $command );

    if ( $verbose >= $VDEBUG ) { printf "[$SPAT] Process Completed\n", $server; }

    # Close any open file descriptors
    close;

    # We *MUST* exit from the child
    exit $status;
} # End SpawnThread

sub GetPassword() {
    use Term::ReadKey;
    my $NOTOK = 1;
    my @pass = ();
    
    ReadMode( 'noecho' );

    while ( $NOTOK ) {
        print "Please enter a password for $opt_user: ";
        $pass[0] = ReadLine(0);
        chomp $pass[0];
        print "\n";

        print "      Re-enter password for $opt_user: ";
        $pass[1] = ReadLine(0);
        chomp $pass[1];
        print "\n";

        last if $pass[0] eq $pass[1];
        print "Passwords do not match, please try again\n";
    }
    ReadMode( 'normal' );
    $opt_pass = $pass[0];
} # End GetPassword

sub Version() {
    printf "%s v%s - %s\n", $PROGNAME, ( '$Revision: 1.9 $' =~ /\s(.*)\s/ ), $AUTHOR;

    # GetOpt will set @_ to 'V 1', so we exit if @_ is defined.
    exit $EOK if @_;
}

sub Help() {
    print "\n";
    Version;
    print <<EOM;

Usage:  $PROGNAME [options] <required>

Where [options] are any combination of the following:

    -V, --version             : Display the Version string and exit

    -h, --help                : This help message

    -l, --lines=number        : Specify how many lines to output to the display
                                in normal verbosity (-v).  Default is $DEFAULT{'LINES'}.

    -o, --output=dir          : Use an alternate output directory for log files
                                Default is: $log_dir

    -p, --password[=password] : Supply a password for remote SSH (SSH keys are
                                presumed if not supplied).  Prompted if this
                                option is supplied but no password is provided
                                on the command line.

    -t, --threads=#           : Run command on # servers concurently.
                                Be careful!  We'll fork a separate process for
                                each thread.  Default is $DEFAULT{'THREADS'}.

    -u, --user=username       : Use an alternate user to run the command

    -v, --verbose             : Display more feedback during run.
                                If given more than once, display additional
                                verbosity (e.g. -vv).

And where <required> includes the following:

    -f, --config=file         : points to a file containing a list of servers to
                                run our command remotely

    -c, --command="command"   : Is any valid command which could normally be run
                                from the shell prompt.


$PROGNAME runs a remote command on each server listed in a configuration file.

EOM

    exit $EOK;
}

1;
