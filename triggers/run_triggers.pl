#!/usr/bin/perl -w

use FileHandle;
use Net::FTP;
use POSIX q(strftime);
use File::Copy;
use GnuPG::Interface;
use Net::SCP q(scp);
use strict;
use vars qw(
    opt_efx
    opt_tu
    opt_verbose
    opt_rerun
);

my $Support_Email = qw(support-triggers@techsafari.com);

Getopt::Long::Configure( 'bundling', 'no_ignore_case' );
GetOptions (
    "h|help"      => \&help,
    "v|verbose+"  => \$opt_verbose,
    "E|efx"       => \$opt_efx,
    "T|tu"        => \$opt_tu,
    "rerun"       => \$opt_rerun,
);

if ( not defined $opt_efx and not defined $opt_tu ) || ( defined $opt_efx and defined $opt_tu ) {
    mydie "Invalid parameters: either --efx or --tu must be used (not both)";
}

# Define local vars
my $base_directory = qw(/data/triggers);
my $completed_dir  = qq($base_directory/completed);

# Define variables based on how we were called
if ( defined $opt_tu ) {
    my $Type              = qw(TU);
    my $lockfile          = qw(/var/tmp/run_triggers:tu.pid);
    my $logfile           = qw(/var/log/rhino2/run_triggers.log);
    my $working_directory = qq($base_directory/tu);
    my $boilerplate       = qw(prm.edtout.dgimrkt.inqtrig.d%02d%02d%02d.new);
    my $pgp_password_file = qq($base_directory/.gpgpass);

    my $ftp_hostname      = qw(ftp.techsafari.com);
    my $ftp_username      = qw(tutrig);
    my $ftp_password      = qw(PASSWORD);

    my $scp_hostname      = qw(mtc01.prod.market-tech.com);
    my $scp_destination   = qw(/fset29/ATOMIC/TU_TRIGGERS/IN/);

    # Processing that's only needed for this Type goes in this sub
    my $Extra_Processing  = \&run_tu;
}

if ( defined $opt_efx ) {
    my $Type              = qw(EFX);
    my $lockfile          = qw(/var/tmp/run_triggers:efx.pid);
    my $working_directory = qq($base_directory/efx);
    my $boilerplate       = qw(prm.edtout.dgimrkt.inqtrig.d%02d%02d%02d.new);
    my $pgp_password_file = qq($base_directory/.gpgpass);

    my $ftp_hostname      = qw(ftp.techsafari.com);
    my $ftp_username      = qw(tutrig);
    my $ftp_password      = qw(PASSWORD);

    my $scp_hostname      = qw(mtc01.prod.market-tech.com);
    my $scp_destination   = qw(/fset29/ATOMIC/TU_TRIGGERS/IN/);

    # Processing that's only needed for this Type goes in this sub
    my $Extra_Processing  = \&run_efx;
}

##
# See if we're already running, if not, create our lock file
##

if ( -f $lockfile ) { exit; }
else {
    open LOCK, ">$lockfile" or die "Unable to create $lockfile: $!\n";
    print LOCK qq{$$};
    close LOCK;
}

open LOGFILE, ">>$logfile" or die "Unable to open $logfile";
LOGFILE->autoflush;

chdir("$working_directory") or mydie("Unable to change to our working directory $working_directory");

##
# So far so good, are any files ready for us?
##

# Opening connection
my $ftp_connection = Net::FTP->new($ftp_hostname, Passive => 0);
if ( ! defined $ftp_connection ) {
    mydie( "Unable to connect to $ftp_hostname: $@" );
}

# logging in
if ( $ftp_connection->login($ftp_username, $ftp_password) == 0 ) {
    mydie( "Failure logging in to $ftp_hostname ($ftp_connection->message)" );
}

# Getting file list
foreach my $NAME ( $ftp_connection->ls() ) {
    $ftp_file{$NAME} = $ftp_connection->size($NAME);
}

# Pause for a moment
sleep 2;

# Checking file sizes
foreach my $NAME ( keys %ftp_file ) {
    if ( $ftp_file{$NAME} != $ftp_connection->size($NAME) ) {
        print LOGFILE "Transfer not complete for $NAME\n";
        myexit;
    }
}

##
# Ok, if we got here, the file(s) appear to be ready
##

# Retrieve and delete the files from FTP
foreach my $NAME ( sort keys %ftp_file ) {
    undef my $status;
    print LOGFILE "Downloading FTP file $NAME\n";

    $ftp_connection->binary();

    $status = $ftp_connection->get($NAME);
    if ( ! defined $status ) {
        mydie( "Problem retrieving file $NAME\n" );
    }

    $status = $ftp_connection->delete($NAME);
    if ( ! defined $status ) {
        mydie( "Problem removing file $NAME\n" );
    }
}

##
# Ok, files should be in our local dir.
##

my $Encrypted     = 0;
my $pgp_file_name = qw();
my $prm_file_name = qw();

# Process each file
foreach $pgp_file_name ( sort qx(ls prm* 2>/dev/null) ) {
    chomp $pgp_file_name;

    my $prm_test_record_count = 0;
    my $prm_orig_record_count = 0;

    if ( $pgp_file_name =~ /.pgp$/xms ) {
        $Encrypted = 1;
        ( $prm_file_name ) = ( $pgp_file_name =~ /(.*).pgp/xms );
    }
    else { $prm_file_name = $pgp_file_name; }
    
    print LOGFILE "Processing TU Trigger File $prm_file_name...\n";

    # Remove and Skip the file if we've already processed it
    if ( -s "${completed_dir}/${prm_file_name}.gz" ) {
        print LOGFILE "\talready processed, skipped\n";
        unlink( $pgp_file_name );
        next;
    }
 
    # Decrypt the file if necessary
    if ( $Encrypted ) {
        print LOGFILE "\tDecrypting... ";

        my $gpg = qq(/usr/bin/gpg --skip-verify --passphrase-fd 0 --no-tty --openpgp -o $prm_file_name -d $pgp_file_name < $pgp_password_file);

        system($gpg);
        if ( $? != 0 ) { mydie "Unable to decrypt $pgp_file_name: $!\n" };

        unlink("$pgp_file_name");
        print LOGFILE "OK\n";
    }

    # Get the original record count for this file
    ( $prm_orig_record_count ) = split / /, qx(wc -l $prm_file_name);

    # Split the file into multiple files if necessary
    open( PRMFILE, $prm_file_name )
        or mydie "Unable to open $prm_file_name: $!\n";

    # Spin through the file, creating the necessary temp output files
    print LOGFILE "\tSplitting... ";
    while( <PRMFILE> ) {
        my ( $prm_year, $prm_month, $prm_day ) = m/20(\d{2})-(\d{2})-(\d{2})/xms;

        next unless $prm_day;

        my $prm_output = sprintf( $prm_boilerplate, $prm_year, $prm_month, $prm_day);

        open( prm_output, ">>$prm_output" ) or mydie "Unable to open $prm_output: $!\n";
        print prm_output;
        close( prm_output );
    }
    print LOGFILE "OK\n";

    # Rename our temp files back to the correct filename format
    foreach $move_from_file ( sort qx(ls prm*.new 2>/dev/null) ) {
        chomp $move_from_file;

        my ( $prm_temp_record_count ) = split / /, qx(wc -l $move_from_file);
        $prm_test_record_count += $prm_temp_record_count;

        my ( $move_to_file ) = ( $move_from_file =~ m/(.*).new/xms );
        move( $move_from_file, $move_to_file )
            or mydie "Unable to move $move_from_file to $move_to_file: $!\n";
    }

    print LOGFILE "\tValidating Counts... ";
    if ( $prm_test_record_count != $prm_orig_record_count ) {
        my $logmsg = qq{Counts are off: $prm_orig_record_count <-> $prm_test_record_count};
        qx(echo "$logmsg" | mail -s "Problem with TU Trigger Update" support-pager\@techsafari.com);
        print LOGFILE "$logmsg\n";
        myexit();
    }
    print LOGFILE "OK\n";
}

# The file(s) are decrypted and split in the current dir
# so send all files to Market Tech

foreach $prm_file_name ( sort qx(ls prm* 2>/dev/null) ) {
    chomp $prm_file_name;

    # Send the file to the destination server
    print LOGFILE "\tSending $prm_file_name... ";

    scp( "$prm_file_name", "$scp_hostname:$scp_destination" )
        or mydie( "Unable to copy $prm_file_name to $scp_destination: $!\n" );

    move( $prm_file_name, $completed_dir );
    qx(/bin/gzip -f "$completed_dir/$prm_file_name");

    print LOGFILE "OK\n";

    $mail_message .=
        "TU Trigger update $prm_file_name has been downloaded and sent to $scp_hostname:$scp_destination at "
        . scalar localtime() . "\n";
}

# Send mail
if ( $mail_message ) {
    qx(echo "$mail_message" | mail -s "TU Trigger Update" tutrig\@techsafari.com);
    print LOGFILE "Completed " . scalar localtime() . "\n";
}

# clean up and exit
&myexit;

sub myexit() {
    unlink($lockfile) if defined $lockfile;
    close LOGFILE;
    exit;
}

sub mydie(@) {
    print LOGFILE "@_\n";
    qx(echo "@_" | mail -s "Problem in Trigger Processing" $Support_Email);
    close LOGFILE;
    myexit;
}

