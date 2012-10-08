#!/usr/bin/perl -w
#
# Checks the Rhino2 error log and emails any contents to admins.
#
#

use diagnostics;
use strict;
use File::Basename;
use Getopt::Long;
use vars qw( $VERSION $opt_verbose $opt_notify $opt_pattern_file $opt_watch_file $PatternFile $WatchFile );
$VERSION = q(2.0);

sub istty { return -t STDIN && -t STDOUT; }

sub sendpage {
    my $PageTo = defined $opt_notify ? $opt_notify : q(support-r2mon@techsafari.com);
    my $Host = qx(hostname -s); chomp($Host);

    open MAIL, qq(|mail -s "$WatchFile output on $Host" $PageTo)
        or die "Unable to run mail: $!\n";
    print MAIL @_;
    close MAIL;

    if ( &istty and defined $opt_verbose ) { print "@_\n"; };
}

sub mydie {
    sendpage @_;
    exit 1;
}

sub help {
    print "\n";
    &version;
    print "
    -h | --help     :  This help message
    -V | --version  :  Display the program version and quit.
    -v | --verbose  :  Increase the output verbosity.

    -n | --notify <email address>     :  Send notifications to this email address
    -p | --pattern <pattern file>     :  The file containing the patterns to exclude
  * -w | --watchfile <file to check>  :  The file to watch for messages

* == Required

";
    exit;
}

sub version {
    print "$0 v$VERSION\n";
}

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "V|version"         => \&version,
    "h|help"            => \&help,
    "v|verbose+"        => \$opt_verbose,
    "n|notify:s"        => \$opt_notify,
    "p|patternfile:s"   => \$opt_pattern_file,
    "w|watchfile:s"     => \$opt_watch_file,
);

$PatternFile = defined $opt_pattern_file ? $opt_pattern_file : q(/usr/local/rhino2/conf/monitor_r2.exclude); 
$WatchFile   = defined $opt_watch_file ? $opt_watch_file : q(/var/log/rhino2/error_report.txt); 

my ( $InFile, $InPath, $InExt ) = fileparse($WatchFile, qr/\.[^.]*/);
my $TmpFile = $InPath . $InFile . ".tmp";
my $OutFile = $InPath . $InFile . "_checked" . $InExt;
my @Mesg;
my @Patterns;

# If the WatchFile doens't exist, exit silently.
if ( not -f $WatchFile ) {
    if ( defined $opt_verbose ) { print "$WatchFile does not exist, nothing to do.  Exiting with status 255.\n"; }
    exit 255;
}

if ( -f $PatternFile ) {
    open( PATTERNFILE, $PatternFile ) or mydie qq($PatternFile exists, but we can't read it! \($!\));
    @Patterns = <PATTERNFILE>;
    close( PATTERNFILE );
}

# Move the current file to a temporary file to avoid a race condition
#   e.g. file is written to while we're parsing it.
if ( system( "mv $WatchFile $TmpFile" ) != 0 ) { mydie qq(Unable to mv $WatchFile to $TmpFile: $!); }

# Open the input and output files
open( OUTFILE, qq(>>$OutFile) ) or mydie qq(Unable to open $OutFile for write: $!);
open( WATCHFILE,  qq(<$TmpFile)  ) or mydie qq(Unable to open $WatchFile for read: $!);

LOOP: while(<WATCHFILE>) {
    # Append all lines to our output file
    print OUTFILE;

    # Skip blank lines
    next unless $_;

    # Filter out stuff we don't care about
    for my $Pattern ( @Patterns ) {
        next LOOP if /$Pattern/;
    }

    # Push the message into our output array
    push @Mesg, $_;
}

close(WATCHFILE);
close(OUTFILE);

unlink($TmpFile) or mydie qq(Unable to truncate $WatchFile: $!\n);

# Send any messages in our stack
sendpage @Mesg if @Mesg;

exit 0;
