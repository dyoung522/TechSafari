#!/usr/bin/perl 
#########################################################
# This program is used by eject_tape.sh to update the 	#
# NetBackup database with off-site information.		#
#########################################################

use Time::localtime;

$date=`/bin/date +%m/%d/%y`;

$current_date=time();
$future_date=$current_date+1209600;
$lt=localtime($future_date);

$month=$lt->mon;
$month++;
$day=$lt->mday;
$year=$lt->year;
$newyear=($year-100);
$return="$month\/$day\/0$newyear";

$RDATE=`date +%Y%m%d`;

# Now update the NetBackup offsite information.

open (LIST, "/usr/local/backups/tapelist.$RDATE") || die "Can't open input file.\n";
while (<LIST>) {
	chomp;
	`/usr/openv/volmgr/bin/vmchange -m $_ -vltsent $date`;
	`/usr/openv/volmgr/bin/vmchange -m $_ -vltname RECALL`;
	#`/usr/openv/volmgr/bin/vmchange -m $_ -vltreturn $return`;
}
