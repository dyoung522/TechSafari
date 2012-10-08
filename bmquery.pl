#!/usr/bin/perl -w
#
# BMQuery
#
#   2008/07 - Donovan C. Young
#
#   Queries the ncftp bookmark file
#
######################################################################

use strict;
use Getopt::Long;
use Data::Dumper;
use File::Basename;
use Cwd;
use IO::Interactive qw( is_interactive interactive );

$| = 1; # Don't buffer STDOUT

use vars qw(
    $opt_verbose
    $opt_quiet
    $opt_bookmark
);

my $VQUIET = 0; # No output to STDIN
my $VNORM  = 1; # Minimal output
my $VLOUD  = 2; # Extra output
my $VDEBUG = 4; # Debugging output
my $VDEVEL = 5; # Development output

my $VERSION = q(1.0);  # Version Number

# Set some reasonable defaults.
# Some of these may be changed with command line options later.
my $Progname    = "bmquery";
my $opt_verbose = $VNORM;
my $Bookmarks   = $ENV{HOME} . "/.ncftp/bookmarks";

# Our bookmark hash - holds url/login/password info read from Bookmarks
my %BM = ();

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "V|version"    => \&version,
    "h|help"       => \&help,
    "v|verbose+"   => \$opt_verbose,
    "q|quiet"      => \$opt_quiet,
    "b|bookmark:s" => \$opt_bookmark,
);

# Main loop
MAIN: {
    # VAlidate options
    &ValidateOptions;
    &PrintBookmarks( @ARGV );
}

exit 0;

##
## Subs
##
sub verbose {
    my ( $Verbose ) = ( @_ );
    return $opt_verbose >= $Verbose;
}

sub output {
    my $Verbose = shift;
    my @Message = ( @_ );

    if ( verbose($Verbose) ) { print @Message; }
}

sub error {
    output 0, "!ERROR! @_\n";
    exit 1;
}

sub version {
    my ( $exitval ) = @_;
    my ( $Revision  ) = $VERSION;
    print "\n";
    print "$Progname v$Revision";
    print " - Written by Donovan C. Young\n\n";
    if ( not $exitval ) { exit; }
}

sub help {
    &version(1);

    print "Usage:  $Progname [options] [regex]

    b | --bookmark     : Use <bookmark> file instead of: \"$Bookmarks\"
    h | --help         : This help text
    q | --quiet        : Display minimal output
    v | --verbose      : Show more output (may be repeated for greater output)
    V | --version      : Display version information

    if [regex] is supplied, only display entries which match ID, User, or URL

";
    exit 0;
}

sub ValidateOptions {
    if ( defined $opt_quiet ) { $opt_verbose = $VQUIET; }

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
}

sub parse_csv {
    use Text::ParseWords;
    return quotewords(",",0, $_[0]);
}

sub BuildHash {
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

sub PrintBookmarks {
    my ( $pattern ) = ( @_ );

    if ( $opt_verbose >= $VNORM ) {
        printf "%-20s %20s @ %-40s", "Bookmark ID", "User", "URL";
        if ( $opt_verbose >= $VLOUD ) { printf "%-15s", "Password"; }
        print "\n~~~~~~~~~~~~~~~~~~~~ ";
        print "~~~~~~~~~~~~~~~~~~~~ ~ ";
        print "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~";
        if ( $opt_verbose >= $VLOUD ) { print " ~~~~~~~~~~~~~~~"; }
        print "\n";
    }

    foreach my $ID ( sort keys %BM ) {
        if ( defined $pattern ) {
            next unless $ID =~ m/$pattern/io or
                        $BM{$ID}{'USER'} =~ m/$pattern/io or
                        $BM{$ID}{'URL'} =~ m/$pattern/io;
        }

        printf "%-20s %20s @ %-40s", $ID, $BM{$ID}{'USER'}, $BM{$ID}{'URL'};
        if ( $opt_verbose >= $VLOUD ) { printf "%-15s", $BM{$ID}{'PASS'}; }
        print "\n";
    }
}

