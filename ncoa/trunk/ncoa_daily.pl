#!/usr/bin/perl -w
#
# Get daily delete file for NCOA
#
#   rewritten by Donovan Young, original author unknown.
#
#   $Id: ncoa_daily.pl,v 1.11 2007/06/12 13:56:24 dyoung Exp $
#
use strict;
use POSIX qw/strftime/;
use Getopt::Long;
use vars qw($opt_verbose $opt_force $opt_delete $opt_dir $opt_logfile $opt_notify);

# Our various error/exit codes
my $EOK      = 0;    # Sucess
my $EERR     = 1;    # Error
my $ENOOP    = 2;    # Cannot proceed at this time, but not an error.
my $EEXIST   = 4;    # File Exists
my $EUNKNOWN = 255;  # Unknown (catch all)

my $hostname = qx(hostname -s); chomp $hostname;

# The main config hash (used a hash so we only have to define one var using
# strict).
my %daily          = ();
$daily{'URL'}      = q(http://ribbs.usps.gov/files/ncoalink/DAILYDEL.DAT);
$daily{'PREFIX'}   = q(dailydel);

sub help() {
    print "
ncoa_daily.pl <d <directory>> [vf] [D <#days>] [l <logfile>] [n <email-address[,email-address[,...]]>]

    v|verbose           : logs to STDOUT
    f|force             : download and install file even if it already exists.
    d|dir <directory>   : Use <directory> for file installs (must already exist).
    D|delete <#days>    : # of days of files to keep (will delete any dailydel.*.dat files in <directory> older than this #).
    l|logfile <logfile> : Log to <logfile> (appends to this file if it exists).
    n|notify <email>    : Sends an email to <email> address upon successful completion.

";
    exit $ENOOP;
}

# Parse options
Getopt::Long::Configure('bundling', 'no_ignore_case');
GetOptions(
    "h|help"      => \&help,
    "v|verbose+"  => \$opt_verbose,
    "f|force"     => \$opt_force,
    "d|dir=s"     => \$opt_dir,
    "directory=s" => \$opt_dir,
    "D|delete=i"  => \$opt_delete,
    "l|logfile=s" => \$opt_logfile,
    "n|notify=s"  => \$opt_notify,
) or exit $EERR;

# Validate options

# Set our working directory
if ( not defined $opt_dir ) {
    print "You must supply a directory\n";
    help;
}
$opt_dir =~ s/\/$//;  # Strip trailing '/' if present.
$daily{'DIR'} = $opt_dir;
if ( not -d $daily{'DIR'} ) { die "$daily{'DIR'} does not exist\n"; }

# validate --delete option
if ( $opt_delete < 2 ) { die "Invalid --delete option (must be an integer greater than 1)\n"; }

# If we're given a logfile on the command line, make sure we can open it for
# writing.
if ( defined $opt_logfile ) {
    open LOGFILE, ">> $opt_logfile" or die "Unable to open $opt_logfile for writing: $!\n";
    close LOGFILE;
}

# Configure timestamp files
$daily{'SYMLINK'}  = "$daily{'DIR'}/$daily{'PREFIX'}.dat";
$daily{'0DAYFILE'} = "$daily{'DIR'}/$daily{'PREFIX'}." . strftime('%Y%m%d', localtime( time()                            )) . ".dat";
$daily{'1DAYFILE'} = "$daily{'DIR'}/$daily{'PREFIX'}." . strftime('%Y%m%d', localtime( time() - ( ( 24 * 60 * 60 ) * 1 ) )) . ".dat";

sub mylog($) {
    my ( $message ) = @_;
 
    if ( defined $opt_verbose ) {
        printf "[%s %s] %s\n",
            $hostname,
            strftime("%Y/%m/%d %H:%M:%S", localtime(time())),
            $message;
    }

    if ( defined $opt_logfile ) {
        open LOGFILE, ">> $opt_logfile" or die "Unable to open $opt_logfile for writing: $!\n";

        printf LOGFILE "[%s %s] %s\n",
            $hostname,
            strftime("%Y/%m/%d %H:%M:%S", localtime(time())),
            $message;

        close LOGFILE;
    }
}

# Downloads the DAILYDEL.DAT file from the usps.gov website
#   Returns immediately if today's file already exists.
#   Checks to be sure the file has changed from the previous day using md5sum.
#   Will retry the tranmission $threshold times if an error is encountered
#   (404, etc).
sub daily_download() {
    my $retries      = 1;      # our retry counter
    my $threshold    = 10;     # how many times should we try?
    my $current_md5  = undef;  # current file md5sum holder
    my $previous_md5 = undef;  # previous file md5sum holder
    my $ecode        = undef;  # the exit code of the system call

    # Return immediately if the file exists.
    if ( -s $daily{'0DAYFILE'} and not defined $opt_force ) {
        if ( $opt_verbose ) { mylog "$daily{'0DAYFILE'} already exists."; }
        return $EEXIST;
    }
    
    while( 1 ) {
        if ( $retries >= $threshold ) {
            mylog "ERROR:  Failed after $threshold attempts, giving up";
            return $EERR;
        };

        mylog "Downloading $daily{'0DAYFILE'}";

        # use wget to retrieve the file from the website defined above.
        system("/usr/bin/wget -q -nH -O $daily{'0DAYFILE'} $daily{'URL'}");
        $ecode = $?;
        if ( $ecode != 0 ) {
            mylog "wget returned exit code $ecode:  $!";
            $retries++;
            sleep 60;
            next;
        }

        # make sure the file isn't 0 bytes (had this happen in the past)
        if ( -z $daily{'0DAYFILE'} ) {
            mylog "$daily{'0DAYFILE'} is Zero Bytes";
            return $EERR;
        }

        # Check to see if the file has changed from before.  The date may
        # have changed but there the remote file hasn't been updated yet.
        mylog "Checking File ($retries of $threshold)";

        if ( -s $daily{'1DAYFILE'} ) {
            my ( $current_md5  ) = split(/ /, `md5sum $daily{'0DAYFILE'}`);
            my ( $previous_md5 ) = split(/ /, `md5sum $daily{'1DAYFILE'}`);

            if ( $current_md5 eq $previous_md5 ) {
                mylog "File Has not changed.";
                unlink $daily{'0DAYFILE'};
                return $ENOOP;
            }
        }

        # If we've gotten this far, everything is good.
        return $EOK;
    }
}

# Re-creates dailydel.dat symlink to point to the new file
#   Returns immediately if the symlink is already pointing to
#   todays date.  This lets us run this routine even if the download
#   already exists (to correct the symlink if necessary).
sub daily_symlink() {
    my $retries      = 1;      # our retry counter
    my $threshold    = 10;     # how many times should we try?

    # Return if the file already exists and points to the correct
    # file name.
    if ( readlink( $daily{'SYMLINK'} ) eq $daily{'0DAYFILE'} and not defined $opt_force ) {
        if ( $opt_verbose ) { mylog "$daily{'SYMLINK'} already points to $daily{'0DAYFILE'}"; }
        return $EEXIST;
    }

    # Loop so we can retry transmission errors
    while( 1 ) {
        if ( $retries >= $threshold ) {
            mylog "ERROR: Failed after $threshold attempts, giving up";
            return $EERR;
        };

        # Check to be sure our source file exists.
        if ( not -f $daily{'0DAYFILE'} ) {
            mylog "ERROR:  $daily{'0DAYFILE'} does not exist!";
            return $EERR;
        }

        # Make sure the current symlink is really a symlink
        if ( -f $daily{'SYMLINK'} and not -l $daily{'SYMLINK'} ) {
            mylog "ERROR:  $daily{'SYMLINK'} exists but is not a symlink!";
            return $EERR;
        }

        mylog "Recreating $daily{'SYMLINK'} ($retries of $threshold)";

        # make sure it's not in use.
        my @procs = system("/sbin/fuser $daily{'SYMLINK'}");
        if ( $#procs != 0) {
            mylog "CURRENT FILE IN USE, will retry.";
            $retries++;
            sleep 30;
            next;
        }

        # remove the old link
        if ( -l $daily{'SYMLINK'} ) {
            unlink( $daily{'SYMLINK'} )
                or die "ERROR:  Unable to remove existing symlink $daily{'SYMLINK'}: $!\n";
        }

        # create the new.
        symlink( $daily{'0DAYFILE'}, $daily{'SYMLINK'} )
            or die "ERROR:  Unable to recreate the $daily{'SYMLINK'} symlink:  $!\n";

        return $EOK;
    }
}

# Removes any dailydel.*.dat files older than $days_to_keep days old.
sub daily_removeold() {
    return $ENOOP if not defined $opt_delete;
    my $days_to_keep = ( $opt_delete - 1 );  # How many days should we keep?

    # Get the list of files.
    open FIND, qq(/usr/bin/find $daily{'DIR'} -type f -name "$daily{'PREFIX'}.*.dat" -maxdepth 1 -mtime +$days_to_keep |)
        or die "Unable to run find:  $!\n";

    # Read the list
    while ( <FIND> ) {
        chomp;
        my $filename = $_;

        mylog "Removing $filename (more than $opt_delete days old)";

        # Remove the file.
        unlink $filename or die "Unable to remove $filename: $!\n";
    }

    close FIND;
    return $EOK;
}

# Sends an email notification to let us know the download has completed.
sub daily_notification() {
    return $ENOOP unless defined $opt_notify;

    mylog "NCOA Daily Delete successfull";

    open MAIL, qq(| mail -s "Daily ncoa - $hostname" $opt_notify)
        or die "Unable to send mail: $!\n";

    print MAIL "The NCOA daily delete file $daily{'0DAYFILE'}\nhas been succesfully installed on $hostname.\n";

    close(MAIL);

    return $EOK;
}

# Main 
MAIN: {
    my $status = undef;

    # First, run the daily_download routine.
    #  Upon success (EOK), run the daily_removeold() routine
    #  otherwise either exit on error or continue to the next subroutine
    $status = daily_download();
    if ( $status == $EOK      ) { daily_removeold();    }
    if ( $status == $EERR     ) { exit $EERR;           }
    if ( $status == $ENOOP    ) { exit $ENOOP;          }
    if ( $status == $EEXIST   ) { 1;                    } # Do nothing
    if ( $status  > $EEXIST   ) { exit $EUNKNOWN;       }

    # Run the daily_symlink() routine to check and re-create the symlink
    #  Upon sucess (EOK) run the daily_notification() routine, otherwise
    #  exit on error.
    $status = daily_symlink();
    if ( $status == $EOK      ) { daily_notification(); }
    if ( $status == $EERR     ) { exit $EERR;           }
    if ( $status == $ENOOP    ) { exit $ENOOP;          }
    if ( $status == $EEXIST   ) { exit $EEXIST;         }
    if ( $status  > $EEXIST   ) { exit $EUNKNOWN;       }
        
    exit $EOK;
}

exit $EUNKNOWN; # Should never be reached, but catch-all just in case.

