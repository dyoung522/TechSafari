#!/usr/bin/perl -w

use strict;
use File::Copy;
use Getopt::Long;
use Time::localtime;
use vars qw(
            $opt_verbose
            $opt_jcl
            $opt_cid
            $opt_jclonly
            $opt_type
            %Lookup
            %NameHash
           );

sub mydie(@);
sub get_region($);
sub run_efx_jcl($);
sub run_fares_jcl($);
sub help() {
    print qq(
Usage:

$0 --type <efx|fares> [--[no]jcl] < Filename

Provide input data in the following format (read from STDIN):
FIRST_NAME,LAST_NAME,CITY,STATE,ZIP

    --jcl                            : Runs JCL only (Skips data search)
    --nojcl                          : Skips JCL job
    --cid                            : Input contains CID,ZIP instead
    --type=[efx|fares|faresuber|bk]  : Searches Raw EFX (default), FARES, or Bankruptcy records.

    --verbose                        : Turn on more output (primarily for debugging)

);
    exit;
}

$|            = 1;  # Don't buffer STDOUT
$opt_jcl      = 2;

my $TotalRecords = 0;
my $FoundRecords = 0;
my $StartTime;

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "h|help"      => \&help,
    "v|verbose+"  => \$opt_verbose,
    "jcl!"        => \$opt_jcl,
    "cid"         => \$opt_cid,
    "type=s"      => \$opt_type,
);

if ( not defined $opt_type ) { &help; }
if ( $opt_type ne 'efx' and
     $opt_type ne 'fares' and 
     $opt_type ne 'faresuber' and 
     $opt_type ne 'bk' ) {
         &help;
    }

if ( $opt_jcl > 1 ) {
    # Terminate if no input records were found
    if ( not &validate_input ) { &help; }

    printf "%d total records in %d regions are valid\n", $TotalRecords, scalar keys %Lookup;
}

if ( $opt_type eq 'efx'       ) { $FoundRecords = &find_efx_data; }
if ( $opt_type eq 'fares'     ) { $FoundRecords = &find_fares_data; }
if ( $opt_type eq 'faresuber' ) { $FoundRecords = &find_faresuber_data; }
if ( $opt_type eq 'bk'        ) { $FoundRecords = &find_bk_data; }

print "\nSearch complete.\n\n";

if ( $opt_jcl != 1 ) {
    foreach my $Name ( sort keys %NameHash ) {
        if ( not $NameHash{$Name} ) {
            print "Did NOT find $Name\n";
        }
    }
}

if ( not $FoundRecords ) {
    mydie "There were no records found";
}

if ( $opt_jcl == 1 || ( $FoundRecords && $opt_jcl != 0 ) ) {
    print "\nRunning JCL on the $FoundRecords records we found (which may include duplicates)...\n";
    if ( $opt_type eq 'fares'     ) { exit &run_fares_jcl( $FoundRecords ); }
    if ( $opt_type eq 'faresuber' ) { exit &run_faresuber_jcl( $FoundRecords ); }
    if ( $opt_type eq 'bk'        ) { exit &run_bk_jcl( $FoundRecords ); }
    exit &run_efx_jcl( $FoundRecords );
}

exit;
1;

sub validate_input() {
    my $Region = undef;
    my ( $CID, $FName, $LName, $City, $State, $Zip );

    while(<>) {
        chomp;
        tr/a-z/A-Z/;  # Convert input to uppercase to match EFX data

        if ( defined $opt_cid ) {
            next unless ( $CID, $Zip ) = split ',';
            if ( not $CID =~ /^[0-9A-F]{18}$/   ) { mydie "CID ($CID) doesn't appear valid in record:\n$_"; }
        } else {
            next unless ( $FName, $LName, $City, $State, $Zip ) = split ',';
            if ( not $FName =~ /^[A-Z]+$/   ) { mydie "First Name ($FName) doesn't appear valid in record:\n$_"; }
            if ( not $LName =~ /^[A-Z\-]+$/   ) { mydie "Last Name ($LName) doesn't appear valid in record:\n$_"; }
            if ( not $City  =~ /^[A-Z ]+$/  ) { mydie "City ($City) doesn't appear valid in record:\n$_"; }
            if ( not $State =~ /^[A-Z]{2}$/ ) { mydie "State ($State) doesn't appear valid in record:\n$_"; }
        }
        if ( not $Zip =~ /^\d{5}$/    ) { mydie "Invalid Zip ($Zip) in record:\n$_" ; }

        if ( $opt_type eq 'fares' ) {
            $Region = qq(court_DVDs.txt);
        } else {
            $Region = &get_region($Zip);
        }

        if ( not defined $Region ) { mydie "Could not find a region for Zip $Zip"; }

        push @{$Lookup{$Region}}, ( $_ );
        if ( defined $opt_cid ) { 
            $NameHash{"$CID"} = 0;  # Used to keep track of the records we've found below
        } else {
            $NameHash{"$FName $LName"} = 0;  # Used to keep track of the records we've found below
        }
    }
    $TotalRecords = scalar keys %NameHash;
    return $TotalRecords;
}

sub find_efx_data() {
    my $TEMPLATE = "A18 A15 A1 A25 A2 A57 A20 A2 A5";
    my $RecLen   = 2101;
    my $FileBase = qw(/data/out/efx/current/efxin);
    my $DATAFile = qw(lookup.efx.raw);
    my $RecCount = 0;

    if ( $opt_jcl == 1 ) {
        open DATA, "< $DATAFile" or mydie "Unable to open $DATAFile for reading: $!\n";
        while( <DATA> ) { $RecCount++; }
        close DATA;
        return $RecCount;
    }

    open DATA, "> $DATAFile" or mydie "Unable to open $DATAFile for writing: $!\n";

    foreach my $Region ( sort keys %Lookup ) {

        my $RecordCount  = scalar @{$Lookup{$Region}};
        my $FileSize     = -s "$FileBase.$Region";
        my $TotalRecords = $FileSize / $RecLen;
        my $Found        = 0;
        $RecCount        = 0;
        $StartTime       = time; # Reset after each region for print_stats

        printf "Searching for %d EFX records in %s.%s...\n", scalar $RecordCount, $FileBase, $Region;

        # Open the input file
        open EFX, "< $FileBase.$Region" or mydie "Unable to open $FileBase.$Region for reading: $!\n";

        # Search for our data
        while( <EFX> ) {
            if ( defined $opt_cid and $Found == $RecordCount ) { last; }

            if ( 0 == ( ++$RecCount % 1000 ) ) { print_stats( $Region, "$FileBase.$Region", $RecLen, $RecCount ); }

            my ( $RCID, $RFName, $RMiddle, $RLName, $RSuffix, $RAddress, $RCity, $RState, $RZip ) = unpack $TEMPLATE, $_;
            for my $R ( 0 .. ( $RecordCount - 1 ) ) {
                if ( defined $opt_cid ) {
                    my ( $CID, $Zip ) = split ',', $Lookup{$Region}[$R];
                    next if ( $RCID ne $CID );
                    $NameHash{"$CID"} = 1;
                } else {
                    my ( $FName, $LName, $City, $State, $Zip ) = split ',', $Lookup{$Region}[$R];
                    next if ( $RZip   ne $Zip   );
                    next if ( $RState ne $State );
                    next if ( $RCity  ne $City  );
                    next unless ( $FName eq $RFName && $LName eq $RLName );
                    $NameHash{"$FName $LName"} = 1;
                }
                print "Found $RFName $RLName\n";
                print DATA $_;
                $FoundRecords++;
                $Found++;
            }
        }
        if ( not $Found ) { print "No Records Found\n"; }
        else { print "\n"; }

        close EFX;
    }
    close DATA;

    return $FoundRecords;
}

sub find_fares_data() {
    my $TEMPLATE = 'A578 A40 A2 A5 A13 A59 A1 A30';
    my $RecLen   = 3284;
    my $RecCount = 0;
    my $FileBase = qw(/data/in/court/court_monthly/current);
    my $DATAFile = qw(lookup.fares.raw);

    if ( $opt_jcl == 1 ) {
        open DATA, "< $DATAFile" or mydie "Unable to open $DATAFile for reading: $!\n";
        while( <DATA> ) { $RecCount++; }
        close DATA;
        return $RecCount;
    }

    open DATA, "> $DATAFile" or mydie "Unable to open $DATAFile for writing: $!\n";

    foreach my $Region ( sort keys %Lookup ) {

        my $RecordCount = scalar @{$Lookup{$Region}};
        my $FileSize = -s "$FileBase/$Region";
        my $TotalRecords = $FileSize / $RecLen;
        my $Found        = 0;
        $RecCount        = 0;
        $StartTime       = time; # Reset after each region for print_stats

        printf "Searching for %d FARES records in %s/%s...\n", scalar $RecordCount, $FileBase, $Region;

        # Open the input file
        open FARES, "< $FileBase/$Region" or mydie "Unable to open $FileBase/$Region for reading: $!\n";

        # Search for our data
        while( <FARES> ) {
            if ( 0 == ( ++$RecCount % 1000 ) ) { print_stats( $Region, "$FileBase.$Region", $RecLen, $RecCount ); }

            my ( $JUNK1, $RCity, $RState, $RZip, $JUNK2, $RFName, $RMi, $RLName ) = unpack $TEMPLATE, $_;
            #print "RAW: $_";
            #print "DATA:  \"$RFName\" \"$RMi\". \"$RLName\" \"$RCity\" \"$RState\", \"$RZip\"\n";
            for my $R ( 0 .. ( $RecordCount - 1 ) ) {
                my ( $FName, $LName, $City, $State, $Zip ) = split ',', $Lookup{$Region}[$R];
                next if ( $RZip   ne $Zip   );
                next if ( $RState ne $State );
                next if ( $RCity  ne $City  );
                if ( $FName eq $RFName && $LName eq $RLName ) {
                    print "Found $FName $LName\n";
                    print DATA $_;
                    $FoundRecords++;
                    $NameHash{"$FName $LName"} = 1;
                }
            }
        }
        close FARES;
    }
    close DATA;

    return $FoundRecords;
}

sub find_faresuber_data() {
    my $TEMPLATE = 'x22 A1 A25 A5 x4 A50 A25 A2 A5 x415 A9 A15';
    my $RecLen   = 579;
    my $RecCount = 0;
    my $FileBase = qw(/data/jfw/out/fares_uber/current/fares_uber);
    my $DATAFile = qw(lookup.faresuber.raw);

    if ( $opt_jcl == 1 ) {
        open DATA, "< $DATAFile" or mydie "Unable to open $DATAFile for reading: $!\n";
        while( <DATA> ) { $RecCount++; }
        close DATA;
        return $RecCount;
    }

    open DATA, "> $DATAFile" or mydie "Unable to open $DATAFile for writing: $!\n";

    foreach my $Region ( sort keys %Lookup ) {

        my $RecordCount = scalar @{$Lookup{$Region}};
        my $FileSize = -s "$FileBase.$Region";
        my $TotalRecords = $FileSize / $RecLen;
        my $Found        = 0;
        $RecCount        = 0;
        $StartTime       = time; # Reset after each region for print_stats

        printf "Searching for %d FARES UBER records in %s.%s...\n", scalar $RecordCount, $FileBase, $Region;

        # Open the input file
        open FARES, "< $FileBase.$Region" or mydie "Unable to open $FileBase.$Region for reading: $!\n";

        # Search for our data
        while( <FARES> ) {
            if ( defined $opt_cid and $Found == $RecordCount ) { last; }

            if ( 0 == ( ++$RecCount % 10000 ) ) { print_stats( $Region, "$FileBase.$Region", $RecLen, $RecCount ); }

            my ( $RMiddle, $RLName, $RSuffix, $RAddress, $RCity, $RState, $RZip, $RCID, $RFName ) = unpack $TEMPLATE, $_;
            if ( $opt_verbose ) {
                print qq(--> "$RCID" "$RFName" "$RMiddle" "$RLName" "$RAddress" "$RCity" "$RState" "$RZip"\n);
            }

            for my $R ( 0 .. ( $RecordCount - 1 ) ) {
                if ( defined $opt_cid ) {
                    my ( $CID, $Zip ) = split ',', $Lookup{$Region}[$R];
                    next if ( $RCID ne $CID );
                    $NameHash{"$CID"} = 1;
                } else {
                    my ( $FName, $LName, $City, $State, $Zip ) = split ',', $Lookup{$Region}[$R];
                    next if ( $RZip   ne $Zip   );
                    next if ( $RState ne $State );
                    next if ( $RCity  ne $City  );
                    next unless ( $FName eq $RFName && $LName eq $RLName );
                    $NameHash{"$FName $LName"} = 1;
                }
                print "Found $RFName $RLName\n";
                print DATA $_;
                $FoundRecords++;
                $Found++;
            }
        }
        if ( not $Found ) { print "No Records Found\n"; }
        else { print "\n"; }

        close FARES;
    }
    close DATA;

    return $FoundRecords;
}

sub find_bk_data() {
    print "Not yet implemented!\n";
    return undef;
}

sub run_efx_jcl($) {
    my $FoundRecords = shift;
    my $NotifyEmail  = qw(support-jcl@techsafari.com);
    my $JCLBase      = qw(lookup.efx);
    my $JCLDef       = qq($JCLBase.def);
    my $JCLFile      = qq($JCLBase.jcl);
    my $JCLOutput    = qq($JCLBase.jclout);

    open JCL, "> $JCLFile" or die "Unable to open $JCLFile for writing: $!\n";

    print JCL qq(
#define IN_LOC /home/tuser/lookups/
job number: 666
notify_long: $NotifyEmail
tempspace: /data/jfw/jcl

#include "$JCLDef"

process print_it
begin
        input stream $JCLBase
        generate layout for $JCLBase with $FoundRecords records
end
);
    close JCL;

    system( "/usr/local/mtc_jcl/mtc_jcl -x -w $JCLFile > $JCLOutput 2>&1" );

    if ( $? == 0 ) {
        if ( -f "${JCLBase}_in_def.html" ) { move( "${JCLBase}_in_def.html", "$JCLBase.html" ); }
        print "JCL Terminated normally.  $JCLBase.html created.\n";
    } else {
        print STDERR "JCL Terminated abnormally with exit code $?.  Please see $JCLOutput for more info\n";
    }
    return $?;
}

sub run_fares_jcl($) {
    my $FoundRecords = shift;
    my $NotifyEmail  = qw(support-jcl@techsafari.com);
    my $JCLBase      = qw(lookup.fares);
    my $JCLFile      = qq($JCLBase.jcl);
    my $JCLOutput    = qq($JCLBase.jclout);

    open JCL, "> $JCLFile" or die "Unable to open $JCLFile for writing: $!\n";

    print JCL qq(
job number: 666
notify_long: $NotifyEmail
tempspace: /data/out1/jcl, /data/out2/jcl

describe input file $JCLBase
begin
        location: /home/tuser/lookups
        filename: $JCLBase.raw
        regionalized: no
        format: fixed-lf
        record length: 3297
    remove unprintable characters
        layout
        begin
#include "court_layout.jcl"
        end
end

process print_it
begin
        input stream $JCLBase
        generate layout for $JCLBase with $FoundRecords records
end
);
    close JCL;

    system( "/usr/local/mtc_jcl/mtc_jcl -x -w $JCLFile > $JCLOutput 2>&1" );

    if ( $? == 0 ) {
        if ( -f "${JCLBase}_in_def.html" ) { move( "${JCLBase}_in_def.html", "$JCLBase.html" ); }
        print "JCL Terminated normally.  $JCLBase.html created.\n";
    } else {
        print STDERR "JCL Terminated abnormally with exit code $?.  Please see $JCLOutput for more info\n";
    }
    return $?;
}

sub run_faresuber_jcl($) {
    my $FoundRecords = shift;
    my $NotifyEmail  = qw(support-jcl@techsafari.com);
    my $JCLBase      = qw(lookup.faresuber);
    my $JCLFile      = qq($JCLBase.jcl);
    my $JCLOutput    = qq($JCLBase.jclout);

    open JCL, "> $JCLFile" or die "Unable to open $JCLFile for writing: $!\n";

    print JCL qq(
job number: 666
notify_long: $NotifyEmail
tempspace: /data/out1/jcl, /data/out2/jcl

describe input file $JCLBase
begin
        location: /home/tuser/lookups
        filename: $JCLBase.raw
        regionalized: no
        format: fixed-lf
        record length: 579
    remove unprintable characters
        layout
        begin
#include "fares_uber_layout.jcl"
        end
end

process print_it
begin
        input stream $JCLBase
        generate layout for $JCLBase with $FoundRecords records
end
);
    close JCL;

    system( "/usr/local/mtc_jcl/mtc_jcl -x -w $JCLFile > $JCLOutput 2>&1" );

    if ( $? == 0 ) {
        if ( -f "${JCLBase}_in_def.html" ) { move( "${JCLBase}_in_def.html", "$JCLBase.html" ); }
        print "JCL Terminated normally.  $JCLBase.html created.\n";
    } else {
        print STDERR "JCL Terminated abnormally with exit code $?.  Please see $JCLOutput for more info\n";
    }
    return $?;
}

sub get_region($) {
    my $Zip = shift;
    my @Regions = ( "076", "122", "194", "273", "309", "341", "407", "469", "539", "609", "716", "773", "849", "916", "946", "999" );
    my $ZipSub = substr($Zip, 0, 3);

    foreach my $Index ( 0 .. @Regions ) { return $Regions[$Index] if ( $ZipSub le $Regions[$Index] ); }

    return undef;
}

sub get_old_region($) {
    my $Zip = shift;
    my @Regions = (
                    [ '05', '69' ],
                    [ '01', '25', '69' ],
                    [ '04', '59' ],
                    [ '02', '35', '69' ],
                    [ '04', '57', '89' ],
                    [ '09' ],
                    [ '02', '39' ],
                    [ '04', '56', '79' ],
                    [ '04', '59' ],
                    [ '01', '23', '45', '69' ],
                  );

    my $Zip1 = substr($Zip, 0, 1);
    my $Zip2 = substr($Zip, 1, 1);

    for my $R1 ( 0 .. ( @{$Regions[$Zip1]} - 1 ) ) {
        for my $R2 ( $Regions[$Zip1][$R1] ) {
            my $Pattern = substr( $R2, 0, 1) . '-' . substr( $R2, 1, 1 );
            if ( $Zip2 =~ /[$Pattern]/ ) { return "${Zip1}r${R2}"; }
        }
    }

    return undef;
}

sub print_stats($$$$) {
    my ( $Region, $FileName, $RecLen, $RecCount ) = @_;

    my $RecordCount = scalar @{$Lookup{$Region}};
    my $FileSize = -s "$FileName" or return;
    my $TotalRecords = $FileSize / $RecLen;
    my $ETA          = "";
    my $ETAsecs      = 0;
    my $ETAmins      = 0;
    my $ETAhour      = 0;

    my $RecsPerSec = ( time - $StartTime ) ? ( $RecCount / ( time - $StartTime ) ) : 0;
    if ( $RecsPerSec ) {
        $ETAsecs = ( $TotalRecords - $RecCount ) / $RecsPerSec;
        if ( $ETAsecs < 0 ) { $ETAsecs = 0; }
        while ( $ETAsecs >= 60 ) { $ETAmins += 1; $ETAsecs -= 60; }
        while ( $ETAmins >= 60 ) { $ETAhour += 1; $ETAmins -= 60; }
        $ETA = sprintf "ETA: %0.2d:%0.2d:%0.2d ", $ETAhour, $ETAmins, $ETAsecs;
    } else { return 0; }

    printf STDERR "\r%d of %d Records Scanned [%d%%] ( %d KR/s %s)    ", $RecCount, $TotalRecords, ( $RecCount / $TotalRecords ) * 100, int( $RecsPerSec / 1000 ), $ETA;

    return $ETAsecs;
}

sub mydie(@) {
    print STDERR "@_\n";
    exit 1;
}
