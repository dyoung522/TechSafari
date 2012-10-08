#!/usr/bin/perl
use Net::FTP;
use POSIX qw/strftime/;
use File::Copy;

# Equifax FTP Information
my $eHost = "transport7.ec.equifax.com";
my $eUser = "NorthAmericanIC_TECH";
my $ePass = "PASSWORD";
my $eWorkDir = "/CMS/manual/outbound/2318/";
my $eSchid = "2318";
my $eDate = strftime( '%Y%m%d', localtime(time) );
#$eDate = "20060422";
my $eFile = "O".$eDate.".pgp";
my $eDone = "O".$eDate.".DONE";
my $gpgOut = "O".$eDate;

# Marge FTP Information
#my $mHost = "marge.prod.market-tech.com";
my $mHost = "mtc01.prod.market-tech.com";
my $mUser = "tuser";
my $mPass = 'PASSWORD';
#my $mWorkDir = "/fset14/REF/efxtrig";
my $mWorkDir = "/fset29/ATOMIC/EFX_TRIGGERS/IN/";

# ChoicePoint FTP info
#my $cHost = "ftps.cp-direct.com";
#my $cHost = "cppmftp.choicepoint.com";
#my $cUser = "techsafari";
#my $cPass = "PASSWORD";
#my $cWorkDir = "/inbound/";
#my $cWorkDir = "/dl/inbound/";

# DataPartners FTP info
my $cHost = "ftp.datapartners.com";
my $cUser = "NSdaily";
my $cPass = "PASSWORD";
my $cWorkDir = "./";
my $cDate = strftime( '%y%m%d', localtime(time) );
my $scrubOut = "AS".$cDate.".txt";
my $scrubZip = "AS".$cDate.".zip";
my $scrubDate = strftime( '%m/%d/%Y', localtime(time) );

# Local Info
my $lWorkDir = "/data/rhino2/triggers/";
my $gpgPass = "/data/rhino2/triggers/.gpgpass";
my $yDate = strftime( '%Y%m%d', localtime( time - 86400 ) );
my $link_name='trigger_input.link';
#
# Sub Usage
#
# getfile:  getfile("filename", "username", "password", "ftp hostname", "remote directory");
#
# putfile: putfile("filename", "username", "password", "ftp hostname", "remote directory");
#
# send_mail: send_mail("recipient", "subject", "body", "cc");
#

# Check for the .DONE file on the EFX ftp server

chdir("$lWorkDir");
unless(-f "$eDone") {
	getfile("$eDone", "$eUser", "$ePass", "$eHost", "$eWorkDir");
} else {
	exit;
}
print "\n\n## Got File ##\n\n";

# If the .DONE file exists download todays auto trigger
if($? == 0) {
	getfile("$eFile", "$eUser", "$ePass", "$eHost", "$eWorkDir");
} else {
	exit;
}

print "\n\n## Got File ##\n\n";

# Decrypt the EFX file
system("gpg --skip-verify --no-tty -o $gpgOut --passphrase-fd 0 -d $eFile < $gpgPass 2>> ./efx_auto_gpg.log");
unlink("$eFile");

print "\n\n## Decrypted ##\n\n";

# Create symlink
unlink($link_name);
symlink($gpgOut,$link_name);


# If everything looks ok compress and upload it to Masada
if($? == 0) {
	system("gzip -c $gpgOut > $gpgOut.gz");
	if($? == 0) {
		putfile("$gpgOut".".gz", "$mUser", "$mPass", "$mHost", "$mWorkDir", "$lWorkDir");
        move("$gpgOut.gz",  "./completed");
	}
} else {
	send_mail("support\@techsafari.com", "Run_Efx error: masada upload", "couldnt upload to masada", "");
	exit(1);
}


print "\n\n## Uploaded to Masada ##\n\n";


# Scrub file for DataPartners
system("/usr/local/rhino2/scripts/efx_auto_scrub.pl $gpgOut > /$lWorkDir/auto_scrub/$scrubOut");
if($? == 0) {
	sleep(5);
} else { die "I died"; }

print "\n\n## Ran scrub ##\n\n";

if($? == 0) {
	chdir("/$lWorkDir/auto_scrub");
	system("/usr/bin/zip $scrubZip $scrubOut");
} else {
	send_mail("support\@techsafari.com", "EFX Auto Triggers: Scrub Error", "There was an issue while scrubbing the triggers file for DataPartners.\n", "");
	exit(1);
}

print "\n\n## Zipped ##\n\n";

putfile("$lWorkDir/auto_scrub/$scrubZip", "$cUser", "$cPass", "$cHost", "$cWorkDir");

# Get Num Recs
my $scrubRecNum = `wc -l $lWorkDir/auto_scrub/$scrubOut | awk \'{ print \$1 }\'`;
my $mail_body = "The following file has been uploaded to the DataPartners. FTP server.\n\n$scrubZip - $scrubRecNum records\n\n$0 EOF";


send_mail("Jodi.Smith\@datapartners.com,nsorders\@tampabay.rr.com,Kathy.weise\@datapartners.com,John.mahan\@datapartners.com", "Auto Trigger file for $scrubDate", "$mail_body", "autotrig\@techsafari.com");

if($? == 0) {
    unlink("/$lWorkDir/auto_scrub/$scrubOut");
#    move("$lWorkDir/auto_scrub/$scrubZip", "$lWorkDir/auto_scrub/completed/");
} else {
	send_mail("support\@techsafari.com", "Scrub upload problem", "Issue uploading scrub file.", "");
}

print "/usr/local/rhino2/scripts/run_triggers.sh $yDate";

my $ret=system("/usr/local/rhino2/scripts/run_triggers.sh $yDate >> /var/log/rhino2/run_triggers.$yDate.log");

if ( $ret ne '0' ) {
        print "/usr/local/rhino2/scripts/run_triggers.sh $yDate\n";
	sendmail("support\@techsafari.com", "Auto trigger for $yDate $gpgOut failed", "Auto trigger for $yDate $gpgOut failed look in /var/log/rhino2/run_triggers.$yDate.log","");
}
else
{
	get_stats();
}
exit;


###############################################################################
#
# Subs
#
###############################################################################

sub getfile {
	
	# Get info for login
	my $fname = "$_[0]";
	my $user = "$_[1]";
	my $pass = "$_[2]";
	my $host = "$_[3]";
	my $remoteDir = "$_[4]";
	my $debug = 0;
	
	my $ftp = Net::FTP->new("$host", Debug => $debug, Passive => 1)
	or die "Cannot connect to $ftpaddr: $@";
	
	$ftp->login("$user","$pass")
	or die "Cannot login ", $ftp->message;
	
	$ftp->pwd;
	
	$ftp->cwd("$remoteDir")
	or die "Cannot change working directory ", $ftp->message;
	
	$ftp->binary;
	
	$ftp->get("$fname")
	or die "get failed ", $ftp->message;
	
	$ftp->quit;

} # getfile

sub putfile {
	
	my $fname = "$_[0]";
	my $user = "$_[1]";
	my $pass = "$_[2]";
	my $host = "$_[3]";
	my $remoteDir = "$_[4]";
	my $localFile = "$_[5]/$fname";
	my $debug = 0;
	
	my $ftp = Net::FTP->new("$host", Debug => $debug, Passive => 1)
	or die "Can not connect to $host", $@;
	
	$ftp->login("$user","$pass")
	or die "Can not login.", $@;
	
	$ftp->pwd;

	$ftp->cwd("$remoteDir") or die "Can not change to dir $remoteDir";
	
	$ftp->binary;
	
	$ftp->put("$localFile")
	or die "Can not put file.", $@;
	
} # putfile

sub send_mail {

	my $recipient = $_[0];
	my $subject = $_[1];
	my $body = $_[2];
	my $cc = $_[3];

	system("echo -e \"$body\" | mail -s \"$subject\" $recipient -c \"$cc\"");
	if( $? != "0" ) { die "Can't send email.\nError: $@\nEOF"; }

}

sub get_stats {
        my $mesg1='';        
	my $mesg2='';        
	my $tot_src=0;        
	my $tot_missed=0;        
	my $tot_updated=0;        
	open(STATS, "< /var/log/rhino2/run_triggers.$yDate.log");        
	while(<STATS>)        
	{                
		$temp=$_;                
		if ($temp =~ m/Partition \'([0-9]*)\' found ([0-9]*) src rows, missed ([0-9]*) src rows, updated ([0-9]*) dest rows, deleted ([0-9]*) dest rows/)                
		{
                        $partition=$1;
                        $src_rows=$2;
                        $missed_rows=$3;
                        $updates=$4;
                        $mesg2=$mesg2."partition: $partition, src_rows:$src_rows, missed_rows: $missed_rows, updates:$updates\n";
                        $tot_src=$tot_src+$src_rows;
                        $tot_missed=$tot_missed+$missed_rows;
                        $tot_updated=$tot_updated+$updates;
                }

                if ($temp =~ m/starting on (.*)$/)
                {
                        $start = $1;
                }

                if ($temp =~ m/ended on (.*)$/)
                {
                        $end = $1;
                }
        }

        $tot_cids=$tot_src+$tot_missed;
        $mesg1=$mesg1."EFX auto trigger processing is complete\n";
        $mesg1=$mesg1."Stats:\n";
        $mesg1=$mesg1."Total CIDs:$tot_cids\n";
        $mesg1=$mesg1."Updated CIDS:$tot_updated\n";
        $mesg1=$mesg1."Start: $start\n";
        $mesg1=$mesg1."End: $end\n\n";

        $mesg1=$mesg1.$mesg2;
	send_mail("mdaoptout\@techsafari.com", "Trigger data update $yDate $gpgOut ", "$mesg1","");
}
