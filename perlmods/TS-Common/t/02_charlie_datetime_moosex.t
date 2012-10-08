
use lib '../lib';

use strict;
use warnings;

use Class::MOP;

use Test::More tests => 3;

BEGIN { use_ok('TechSafari::DateTime::MooseX') };

ok ( Class::MOP::load_class('TechSafari::DateTime::MooseX'), 
     ' trying to load the class more than once' );
     
ok ( Class::MOP::load_class('TechSafari::DateTime::MooseX'), 
     ' trying to load the class more than once' );


{
  package Foo;
  use Moose;
  
  has 'dt' => ( is => 'rw', isa => 'DateTime', coerce => 1 );
  
}

TechSafari::DateTime::MooseX->DEBUG = 1;

my $foo = Foo->new;

$foo->dt('2007-04-20');
$foo->dt('2008-04-20 04:20:00');
$foo->dt('20080420');

$foo->dt('today');
$foo->dt('now'); 
$foo->dt('yesterday');  # seriously.

$foo->dt( { year => 2008, month => 04, day => 20 } );

# 2008-07-31
$foo->dt( { 
    year => 2008, 
    month => 07, 
    last_day_of_month => 1 
  } 
);

$foo->dt( { from_epoch => time() } );

# If you have DateTime::Format::Baby installed, and used this will work.
# TechSafari::DateTime::MooseX
if ( Class::MOP::is_class_loaded( 'DateTime::Format::Baby' ) ) {
  $foo->dt('The big hand is on the twelve and the little hand is on the six.');
}

