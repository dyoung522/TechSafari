#!/usr/bin/perl

use lib qw{ lib ../lib };

use strict;
use warnings;

use Test::More tests => 4;
use Test::Exception;

use TechSafari::Reports::Worksheet;
use TechSafari::Reports::Workbook;

ok( my $sheet = TechSafari::Reports::Worksheet->new(name => 'poo', table => []),
    ' ... creating worksheet ' );
ok( my $book  = TechSafari::Reports::Workbook->new(), ' ... creating workbook');

ok ( $book->add_worksheet( $sheet ), ' ... adding worksheet to workbook' );
  
lives_ok ( 
  sub{ 
    $book->add_worksheet( { name => 'foobar', table => [ [ 3, 4, 5 ] ] } )
  },
  ' ... coercing a hashref into a worksheet ' 
);



