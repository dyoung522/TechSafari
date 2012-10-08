#!/usr/bin/perl
#
# cass_check.pl
#   2007/07 - Donovan C. Young
#
#   Checks the status of the CASS installation
#
#   $Id: cass_check.pl,v 1.3 2007/11/14 16:33:46 dyoung Exp $
#
######################################################################

use strict;
use Getopt::Long;
use File::Basename;

use vars qw( $opt_build $opt_verbose $opt_sha );

if ( not defined $ENV{'JCL_HOME'} ) { die "JCL_HOME is not set\n"; }

my $cass_link = readlink '/usr/local/mdata';

# Make sure CASS is installed on this host
if ( not -d $cass_link ) {
    print "CASS is not installed on this host.\n";
    exit 3;
}

my ( $cass_file, $cass_base ) = fileparse $cass_link;

my $hdr_file = undef;
my $error = undef;

Getopt::Long::Configure('bundling', 'no_ignore_case');
GetOptions
        ("V|version"   => \&version,
         "h|help"      => \&help,
         "v|verbose+"  => \$opt_verbose,
         "b|build=s"   => \$opt_build,
         );

if ( defined $opt_build ) { $cass_file = "mdata.$opt_build"; }
my $cass_dir        = $cass_base . $cass_file;

# Check to be sure the cass_dir is valid
if ( not -d $cass_dir ) {
    print "$cass_dir does not exist, please try another directory using --build.\n";
    exit 3;
}

JCL: {
    my $name_dir = "$cass_dir/name";
    my $JCL_TESTDIR = q(/usr/local/CASS_TEST/cass);
    if ( ! -d $JCL_TESTDIR ) { die "$JCL_TESTDIR does not exist\n"; }

    my $JCL_CMD  = qq(cd $JCL_TESTDIR; );
       $JCL_CMD .=  q(mtc_jcl -w -m -l LOGFILE -x test_cass.jcl > LOGFILE 2>&1);

    # Set our Environment
    $ENV{'JCL_LD_OPTIONS'} =~ s|-L /\S*mdata|-L $cass_dir|;
    $ENV{'JCL_LD_OPTIONS'} =~ s|-L /\S*name|-L $name_dir|;
    $ENV{'JCL_CC_OPTIONS'} =~ s|-I /\S*mdata|-I $cass_dir|;
    $ENV{'JCL_CC_OPTIONS'} =~ s|-I /\S*name|-I $name_dir|;
    $ENV{'LD_LIBRARY_PATH'} = "$cass_dir:$name_dir:$ENV{'ORACLE_HOME'}/lib:";
    $ENV{'CASS_DATA'} = "$cass_dir";
    $ENV{'CASS_LIB'} = "$cass_dir";
    $ENV{'NAME_DATA'} = "$name_dir";
    $ENV{'NAME_LIB'} = "$name_dir";
    $ENV{'DPV_DATA'} = "$cass_dir/DPV";
    $ENV{'LACS_DATA'} = "$cass_dir/LACSlink";

    if ( $opt_verbose >= 3 ) {
        print "JCL_LD_OPTIONS  = $ENV{'JCL_LD_OPTIONS'}\n";
        print "JCL_CC_OPTIONS  = $ENV{'JCL_CC_OPTIONS'}\n";
        print "LD_LIBRARY_PATH = $ENV{'LD_LIBRARY_PATH'}\n";
        print "CASS_DATA       = $ENV{'CASS_DATA'}\n";
        print "CASS_LIB        = $ENV{'CASS_LIB'}\n";
        print "NAME_DATA       = $ENV{'NAME_DATA'}\n";
        print "NAME_LIB        = $ENV{'NAME_LIB'}\n";
        print "DPV_DATA        = $ENV{'DPV_DATA'}\n";
        print "LACS_DATA       = $ENV{'LACS_DATA'}\n";
    }

    if ( $opt_verbose >= 2 ) { print "JCL_CMD = $JCL_CMD\n"; }

    if ( defined $opt_verbose ) { print "Running JCL Tests\n"; }

    system $JCL_CMD;
    if ( $? != 0 ) {
        if ( defined $opt_verbose ) { system q(tail /usr/local/CASS_TEST/cass/LOGFILE); }
        exit 1;
    }

    if ( defined $opt_verbose ) { print "JCL Test OK\n"; }
}

# If we got this far, everything is OK
exit 0;

sub version($) {
    print "\n";
    print 'cass_check $Revision: 1.3 $';
    print "\n\n    Written by Donovan C. Young\n\n";
    exit unless @_ == 1;
}

sub help() {
    version('1');
    print "    cass_check [hVv][b <buildno>]

    Checks an CASS installation against the dvdhdr01 and dvdhdr02 files.

        b|build    : Specify the build directory, otherwise current is used
        h|help     : This help message
        v|verbose  : Print more output
        V|version  : Version information

";
    exit 0;
}

