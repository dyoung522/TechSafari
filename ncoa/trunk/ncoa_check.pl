#!/usr/bin/perl
#
# ncoa_check.pl
#   2007/01 - Donovan C. Young
#
#   ncoa_check.pl [-V][-h][-v][-b build number]
#
#   Checks the status of the NCOA installation
#
#   $Id: ncoa_check.pl,v 1.6 2007/04/11 20:27:19 dyoung Exp $
#
######################################################################
#
#   $Log: ncoa_check.pl,v $
#   Revision 1.6  2007/04/11 20:27:19  dyoung
#   Added JCL testing with option -j
#
#   Revision 1.5  2007/04/11 19:18:51  dyoung
#   Added check to be sure NCOA directory matches the release #
#
#   Revision 1.4  2007/01/23 01:48:57  dyoung
#   Digest::SHA does not exist on the MTC servers, so I had to modify the
#   script to use sha1sum instead (which is installed everywhere).
#
#   Revision 1.3  2007/01/23 01:23:31  dyoung
#   Added SHA digest checking routines (-c|--checksum).
#
#   Revision 1.2  2007/01/23 00:13:22  dyoung
#   Added checks to validate directories before checks
#
#   Revision 1.1  2007/01/22 23:14:17  dyoung
#   Checks NCOA installation directory - initial release
#
#
######################################################################

use strict;
use Getopt::Long;
use File::Basename;

use vars qw( $opt_build $opt_verbose $opt_sha $opt_jcl );

my $ncoa_link = readlink '/usr/local/NCOA';

# Make sure NCOA is installed on this host
if ( not -d $ncoa_link ) {
    print "NCOA is not installed on this host.\n";
    exit 3;
}

my ( $ncoa_file, $ncoa_base ) = fileparse $ncoa_link;

my $hdr_file = undef;
my $error = undef;

Getopt::Long::Configure('bundling', 'no_ignore_case');
GetOptions
        ("V|version"   => \&version,
         "h|help"      => \&help,
         "v|verbose+"  => \$opt_verbose,
         "b|build=s"   => \$opt_build,
         "c|checksum"  => \$opt_sha,
         "j|jcltest"   => \$opt_jcl,
         );

if ( defined $opt_build ) { $ncoa_file = "NCOA-$opt_build"; }
my $ncoa_dir = $ncoa_base . $ncoa_file;

# Check to be sure the ncoa_dir is valid
if ( not -d $ncoa_dir ) {
    print "$ncoa_dir does not exist, please try another directory using --build.\n";
    exit 3;
}

if ( defined $opt_verbose ) {
    print "Checking files in $ncoa_dir ";
    print "for correct file size";
    print " and proper checksum" if defined $opt_sha;
    print "\n";
}

for $hdr_file ( 'dvdhdr01.dat', 'dvdhdr02.dat' ) {
    open DVDHDR, "$ncoa_dir/$hdr_file"
        or die "Unable to open $ncoa_dir/$hdr_file: $!\n";

    while( <DVDHDR> ) {
        # Check release number
        if ( my ( $release ) = /^Release Number:\s+(\d+)/ ) {
            if ( $opt_verbose >= 2 ) { print "header release $release OK\n"; }
            if ( not ( $ncoa_file =~ /^NCOA-$release$/ ) ) {
                die "$ncoa_file does not match NCOA-$release!\n";
            }
            next;
        }

        my ( $filename, $filesize, $filesha ) = /^(\S+)\s+(\d+)\s(.*)$/ or next;

        # Strip any whitespace
        $filesha =~ s/\s//g;

        # Skip .szp and .zip (they no longer exist after install)
        next if $filename =~ /.szp/;
        next if $filename =~ /.zip/;

        # Get the actual file size
        my $real_filesize = -s "$ncoa_dir/$filename";

        if ( $real_filesize != $filesize ) {
            if ( not $real_filesize ) {
                print "$filename is missing!\n";
            } else {
                print "$filename has wrong file size! ";
                print "( actual = $real_filesize; should be $filesize )\n";
            }
            $error++;
            next;
        }

        # Skip SHA check unless requested.
        if ( defined $opt_sha ) {
            # calculate SHA
            my $shasum = qx(sha1sum "$ncoa_dir/$filename" | cut -d' ' -f1);
            chomp $shasum;

            if ( $shasum != $filesha ) {
                print "$filename does not match SHA checksum!\n";
                $error++;
                next;
            }
        }

        # if we got here, everything is OK
        print "$filename OK\n" if $opt_verbose >= 2;
    }
}

if ( not defined $error ) {
    print "All files OK\n" if $opt_verbose;
} else {
    print "There was a problem with $error file(s).\n" if $opt_verbose;
    exit 2;
}

if ( defined $opt_jcl ) {
    my $JCL_TESTDIR = q(/usr/local/CASS_TEST/ncoa);

    my $JCL_CMD  =  q(source $JCL_HOME/jcl.profile; );
       $JCL_CMD .= qq(NCOA_DIR=$ncoa_dir );
       $JCL_CMD .=  q(mtc_jcl -w -m -l LOGFILE -x test_ncoa.jcl > LOGFILE 2>&1);

    if ( $opt_verbose >= 2 ) { print "JCL_CMD = $JCL_CMD\n"; }

    if ( defined $opt_verbose ) { print "Running JCL Tests\n"; }

    chdir $JCL_TESTDIR;

    if ( system $JCL_CMD ) {
        if ( defined $opt_verbose ) { system q(tail /usr/local/CASS_TEST/ncoa/LOGFILE); }
        exit 1;
    }

    if ( defined $opt_verbose ) { print "JCL Test OK\n"; }
}

# If we got this far, everything is OK
exit 0;

sub version($) {
    print "\n";
    print 'ncoa_check $Revision: 1.6 $';
    print "\n\n    Written by Donovan C. Young\n\n";
    exit unless @_ == 1;
}

sub help() {
    version('1');
    print "    ncoa_check [chVv][b <buildno>]

    Checks an NCOA installation against the dvdhdr01 and dvdhdr02 files.

        b|build    : Specify the build directory, otherwise current is used
        c|checksum : Calculate and check the SHA checksums
        h|help     : This help message
        j|jcltest  : Test via the NCOA_TEST JCL process
        v|verbose  : Print more output
        V|version  : Version information

";
    exit 0;
}

