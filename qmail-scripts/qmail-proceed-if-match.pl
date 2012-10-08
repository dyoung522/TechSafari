#!/usr/bin/perl

##
#  This is the address to forward messages to if we find a match.
##
#my $forward_address = q(reubenkennedy@mycingular.blackberry.net);
my $forward_address = q(dyoung522@tmo.blackberry.net);

##
#  This is the list of patterns to look for
##
my @search_list = qw(
    dyoung522@gmail.com
    techsafari.com
    market-tech.com
    ceturytel.com
    joneskolb.com
    waypointdatasolutions.com
    bobbrody@aol.com
    dbinns@aol.com
    mbadler
    ahigginbotham
);

##
#  If the SENDER environment variable matches anything in our
#  @search_list, exit with 0 telling .qmail to continue to 
#  the next line in .qmail
##
if ( grep { /$ENV{SENDER}/ } @search_list ) { exit 0; };

##
#  We didn't match, so don't proceed with the .qmail file
##
exit 99;
