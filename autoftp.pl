#!/usr/bin/perl -w
#
# AutoFTP
#
#   2007/09 - Donovan C. Young
#
#   Automates FTP transfers from MTC requests
#
#   $Id: autoftp.pl,v 1.9 2007/10/23 23:19:40 dyoung Exp $
#
######################################################################

use strict;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use Cwd;
use IO::Interactive qw( is_interactive interactive );

$| = 1; # Don't buffer STDOUT

sub verbose($);
sub output(@);
sub error(@);
sub GetFiles($$@);
sub SendFiles($$@);
sub DoXfer();
sub help();

use vars qw(
    $opt_verbose
    $opt_bookmark
    $opt_logfile
    $opt_source
    $opt_sourcefile
    $opt_dest
    $opt_destdir
    $print_bookmark
);

my $VQUIET = 0; # No output to STDIN
my $VNORM  = 1; # Minimal output
my $VLOUD  = 2; # Extra output
my $VDEBUG = 4; # Debugging output
my $VDEVEL = 5; # Development output

my $VERSION = q(1.2);  # Version Number

# Set some reasonable defaults.
# Some of these may be changed with command line options later.
my $Progname    = "AutoFTP";
my $opt_verbose = $VNORM;
my $HOME        = $ENV{'HOME'};
my $Bookmarks   = "$HOME/.ncftp/bookmarks";
my $Logfile     = "$HOME/" . lc($Progname) . ".log";
my @Files       = ();   # Array of files we've retrieved from the remote server

# Our bookmark hash - holds url/login/password info read from Bookmarks
my %BM = ();
my $Request     = ();

my $Loglevel = 2;  # Don't log messages above this limit.
                   # Will increase if verbosity is incresed from command line

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "V|version"    => \&version,
    "h|help"       => \&help,
    "v|verbose+"   => \$opt_verbose,
    "b|bookmark:s" => \$opt_bookmark,
    "B|showbookmarks" => \$print_bookmark,
    "l|logfile:s"  => \$opt_logfile,
    "s|source:s"   => \$opt_source,
    "S|sourcefile:s"  => \$opt_sourcefile,
    "d|dest:s"     => \$opt_dest,
    "D|destdir:s"  => \$opt_destdir,
);

# Main loop
MAIN: {
    # VAlidate options
    &ValidateOptions;
    &DoXfer;
}

exit 0;

##
## Subs
##
sub verbose($) {
    my ( $Verbose ) = ( @_ );
    return $opt_verbose >= $Verbose;
}

sub output(@) {
    my $Verbose = shift;
    my @Message = ( @_ );

    my @Time = localtime(time);
    my $Year = $Time[5] + 1900;
    my $Month = $Time[4] + 1;
    my $Timestamp = sprintf "[%04d/%02d/%02d %02d:%02d:%02d]", $Year, $Month, @Time[3,2,1,0];
    my $Proginfo  = "[" . lc($Progname) . ":$$]";

    if ( $Loglevel >= $Verbose ) {
        open LOGFILE, ">> $Logfile" or die "Unable to open $Logfile: $!\n";
        print LOGFILE "$Timestamp $Proginfo @Message\n";
        close LOGFILE;
    }

    if ( verbose($Verbose) ) { print @Message; }
}

sub error(@) {
    output 0, "!ERROR! @_\n";
    exit 1;
}

sub version($) {
    my ( $exitval ) = @_;
    my ( $Revision  ) = $VERSION;
    print "\n";
    print "$Progname v$Revision";
    print " - Written by Donovan C. Young\n\n";
    if ( not $exitval ) { exit; }
}

sub help() {
    &version(1);

    print "Usage:  $Progname [options] <required>

    s | --source       : Use this bookmark entry for the source files
  * S | --sourcefile   : Get these files (shell file patterns OK, but may need to escape from shell within \"quotes\")

  * d | --dest         : Send files to this bookmark entry
    D | --destdir      : Send files to this directory on the remote FTP server

    h | --help         : This help text
    v | --verbose      : Show more output (may be repeated for greater output)
    V | --version      : Display version information

    b | --bookmark     : Use <bookmark> file instead of: \"$Bookmarks\"
    B | --showbookmark : Display all the bookmark entries in a human readable format
    l | --logfile      : Use <logfile> file instead of: \"$Logfile\"

  * Required entry

";
    exit 0;
}

sub ValidateOptions() {
    # Our logfile test must come first so output and error will work properly
    if ( defined $opt_logfile ) {
        $Logfile = $opt_logfile;
        output $VLOUD, "Logfile now == $Logfile\n";
    }

    unless ( $Logfile =~ /^([.\/\w]?.*[^\/.])$/ ) {
        error "$Logfile is not a valid filename";
    }
    $Logfile = $1;

    if ( open TEST, ">> $Logfile" ) {
        close TEST;
        output $VLOUD, "Logging to $Logfile\n";
    } else {
        die "\"$Logfile\" could not be opened for writing:  $!";
    }

    if ( defined $opt_bookmark ) {
        if ( -f $opt_bookmark ) {
            $Bookmarks = $opt_bookmark;
            output $VLOUD, "Bookmarks now == $Bookmarks\n";
        } else {
            output $VNORM, "\"$opt_bookmark\" is not a valid bookmark file, using default.\n";
        }
    }

    # Read in the NcFTP bookmark file and build our internal %BM hash
    &BuildHash;
    if ( verbose($VDEBUG) ) { print Dumper(%BM); }
    if ( defined $print_bookmark ) { &print_bookmarks; exit; }

    if ( $opt_verbose >= $Loglevel ) { $Loglevel = $opt_verbose; }

    # Check source bookmark entry
    if ( defined $opt_source and not defined $BM{lc($opt_source)} ) {
        error "The source server entry \"$opt_source\" is not listed in your NcFTP bookmarks file, please check and try again";
    }

    # Check the source file pattern
    if ( not defined $opt_sourcefile ) { error "Please provide a filename or pattern for the source file(s)."; }
    output $VLOUD, "Will attempt to retrieve $opt_sourcefile from " . $BM{lc($opt_source)}{'URL'};

    # Check destination bookmark entry
    if ( not defined $opt_dest ) { error "Please provide a destination in the form of an NcFTP bookmark entry."; }
    if ( not defined $BM{lc($opt_dest)} ) { error "The destination entry \"$opt_dest\" is not listed in your NcFTP bookmarks file, please check and try again"; }
    output $VLOUD,  " and send them to " . $BM{lc($opt_dest)}{'URL'} . ":$opt_destdir\n";
}

sub parse_csv($) {
    use Text::ParseWords;
    return quotewords(",",0, $_[0]);
}

sub BuildHash() {
    use MIME::Base64;

    output $VLOUD, "Parsing $Bookmarks\n";

    open( BM, $Bookmarks ) or error "Unable to open $Bookmarks:  $!\n";

    while( <BM> ) {
        next if /^NcFTP bookmark-file version/i;
        next if /Number of bookmarks/;

        my @BM_Fields = parse_csv($_);

        next unless $BM_Fields[0];

        my ( $ID, $URL, $User, $Pass ) = @BM_Fields;

        $Pass =~ s/\*encoded\*//;
        $Pass = MIME::Base64::decode($Pass);

        $BM{lc($ID)} = {
            'URL' => "$URL",
           'USER' => "$User",
           'PASS' => "$Pass",
        };

        output $VDEVEL, "$ID => $URL:$User:$Pass\n";
    }
}

sub print_bookmarks() {
    if ( $opt_verbose >= $VLOUD ) {
        printf "%-25s %25s @ %s\n", "Bookmark ID", "User", "URL";
        print "~~~~~~~~~~~~~~~~~~~~~~~~~ ";
        print "~~~~~~~~~~~~~~~~~~~~~~~~~ ~ ";
        print "~~~~~~~~~~~~~~~~~~~~~~~~~\n";
    }

    foreach my $ID ( sort keys %BM ) {
        printf "%-25s %25s @ %s", $ID, $BM{$ID}{'USER'}, $BM{$ID}{'URL'};
        if ( $opt_verbose >= $VLOUD ) { print " ($BM{$ID}{'PASS'})" };
        print "\n";
    }
}

sub DoXfer() {
    output $VNORM, sprintf "Beginning $Progname process on %s\n", scalar localtime(time);

    if ( defined $opt_source ) {
        my $TempDir = "/tmp/$Progname-$$";
        mkdir $TempDir or error "Unable to create to $TempDir: $!";
        chdir $TempDir or error "Unable to cd to $TempDir: $!";
        output $VNORM, "The files will be stored in $TempDir\n";

        output $VLOUD, "\nBeginning Request to retrieve $opt_sourcefile from " . $BM{lc($opt_source)}{'USER'} . '@' . $BM{lc($opt_source)}{'URL'} . "\n";
        GetFiles( lc($opt_source), undef, $opt_sourcefile );
    } else {
        foreach my $File ( glob $opt_sourcefile ) {
            push @Files, $File;
        }
    }

    if ( not @Files ) { return 1; }

#foreach my $File ( @Files ) { print "$File\n"; }
#exit;
    output $VLOUD, "\nBeginning Request to send files to " . $BM{lc($opt_dest)}{'USER'} . '@' . $BM{lc($opt_dest)}{'URL'} . ":$opt_destdir\n";
    SendFiles( lc($opt_dest), $opt_destdir, @Files );

    output $VNORM, sprintf "\n$Progname completed sucessfully on %s\n", scalar localtime(time);
}

sub GetFiles($$@) {
    use Net::FTP;

    my ( $Server, $Dir, @Glob ) = ( @_ );

    # Validate the server names, error out if we can't find them in our bookmark hash
    if ( not defined $BM{$Server} ) {
        error "Unable to find $Server in our server database!";
    }

    my $ftp = Net::FTP->new( $BM{$Server}{'URL'}, Timeout => 30, )
        or error "Unable to connect to $BM{$Server}{'URL'}";

    $ftp->login($BM{$Server}{'USER'}, $BM{$Server}{'PASS'})
        or error "Unable to authenticate to $Server: " . $ftp->message;

    $ftp->binary;  # Use binary mode

    if ( defined $Dir ) {
        $ftp->cwd($Dir )
            or error "Unable to cd to $Dir on $Server: " . $ftp->message;
    }

    foreach my $File ( $ftp->ls(@Glob) ) {
        # Check for recursive directories
        if ( $ftp->cwd($File) ) { 
            my ( $NewDir ) = $File =~ /\/(.*)$/;
            mkdir $NewDir or error "Unable to create to $NewDir: $!";
            chdir $NewDir or error "Unable to cd to $NewDir: $!";
            GetFiles( lc($opt_source), $ftp->pwd(), "*" );
            $ftp->cdup();
            chdir "..";
            next;
        }

        if ( verbose($VDEBUG) ) { $ftp->hash(1024 * 1024); }
        output $VNORM, sprintf "Retrieving %-50s ", $ftp->pwd() . "/" . $File;
        if ( not $ftp->get($File) ) {
                output $VNORM, "Error: " . $ftp->message;
                next;
        }
        output $VNORM, sprintf "OK (received %d bytes)\n", $ftp->size($File);
        push @Files, cwd() . "/" . basename($File);
    }

    $ftp->quit;

    return 0;
}

sub SendFiles($$@) {
    use Net::FTP;

    my ( $Server, $Dir, @Glob ) = ( @_ );

    # Validate the server names, error out if we can't find them in our bookmark hash
    if ( not defined $BM{$Server} ) {
        error "Unable to find $Server in our server database!";
    }

    my $ftp = Net::FTP->new( $BM{$Server}{'URL'}, Timeout => 30, )
        or error "Unable to connect to $BM{$Server}{'URL'}";

    $ftp->login($BM{$Server}{'USER'}, $BM{$Server}{'PASS'})
        or error "Unable to authenticate to $Server: " . $ftp->message;

    $ftp->binary;  # Use binary mode

    if ( defined $Dir ) {
        if ( not $ftp->cwd($Dir ) ) {
            $ftp->mkdir($Dir)
                or error "$Dir does not exist and we were unable to create it on $Server: " . $ftp->message;
            $ftp->cwd($Dir)
                or error "Unable to cd to $Dir on $Server: " . $ftp->message;
        }
    }

    foreach my $File ( @Glob ) {
        # Check for recursive directories
        if ( -d $File ) { 
            SendFiles( $Server, $Dir, glob "$File/*" );
            next;
        }

        if ( verbose($VDEBUG) ) { $ftp->hash(1024 * 1024); }
        output $VNORM, sprintf "Sending %-53s ", $File;
        if ( not $ftp->put($File) ) {
                output $VNORM, "Error: " . $ftp->message;
                next;
        }
        output $VNORM, sprintf "OK (sent %d bytes)\n", $ftp->size(basename($File));
    }

    $ftp->quit;

    return 0;
}

