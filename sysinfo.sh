#!/usr/bin/perl -w

use strict;

my $HostName = qx(hostname -s);
chomp $HostName;
my %ProcInfo = procinfo();

printf "
%s:

Total CPUs      : %s
CPU Description : %s
Total Memmory   : %0.0f Gigabytes
Total Space     : %s

", $HostName,
   $ProcInfo{INFO},
   $ProcInfo{DESC},
   &meminfo,
   &diskinfo;

exit 0;

sub procinfo {
    my ( $TotProcs, $TotCPUs, $ProcID ) = 0;
    my %CPUs  = ();
    my %Cores = ();
    my %Return = ();

    open PROCINFO, "/proc/cpuinfo" or die "Unable to open /proc/cpuinfo";
    while ( <PROCINFO> ) {
        $ProcID          = $1 if /processor\s+: (\d+)/;
        $Cores{$ProcID}  = $1 if /cpu cores\s+: (\d+)/;
        $CPUs{$1}       += 1  if /physical id\s+: (\d+)/;
        $Return{DESC}    = $1 if /model name\s+: (.*)/;
    }
    close PROCINFO;

    $TotProcs = $ProcID + 1;
    $TotCPUs = scalar keys %CPUs;

    if ( not %Cores ) { $Return{INFO} = "$TotProcs Processors"; }
    else {
        $Return{INFO} = "$TotProcs Logical Processors ( $TotCPUs Physical CPUS ";
        if ( $Cores{0}  > 1 ) { $Return{INFO} .= "x $Cores{0} Cores "; }
        if ( $TotProcs > ( $TotCPUs * $Cores{0} ) ) { $Return{INFO} .= "x 2 Hyper-Threads "; }
        $Return{INFO} .= ")";
    }

    return %Return;
}

sub meminfo {
    my $TotMem = 0;

    open MEMINFO, "/proc/meminfo" or die "Unable to open /proc/meminfo";
    while ( <MEMINFO> ) {
        $TotMem = $1 if /MemTotal:\s+(\d+)/;
    }
    close MEMINFO;

    return $TotMem / ( 1024 * 1024 );
}

sub diskinfo {
    my $TotKBytes = 0;

    open DF, "df -l 2>/dev/null |" or die "Unable to run df";
    while ( <DF> ) {
        next unless my ( $Bytes ) = ( /(\d+)\s+\d+\s+\d+\s+\d+%/ );
        $TotKBytes += $Bytes;
    }
    close DF;

    return calcspace( $TotKBytes );
}

sub calcspace {
    my $KBytes = shift;
    my $Megabytes = 1024;
    my $Gigabytes = 1024 * 1024;
    my $Terabytes = 1024 * 1024 * 1024;

    return undef unless $KBytes > 0;

    if ( $KBytes / $Terabytes > 0 ) { return sprintf "%0.1f %s", $KBytes / $Terabytes , 'Terabytes'; }
    if ( $KBytes / $Gigabytes > 0 ) { return sprintf "%0.1f %s", $KBytes / $Gigabytes , 'Gigabytes'; }
    if ( $KBytes / $Megabytes > 0 ) { return sprintf "%0.1f %s", $KBytes / $Megabytes , 'Megabytes'; }

    return undef;
}


