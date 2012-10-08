package Techsafari::DateTime::MooseX;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;
our $DEBUG = 0;

use Carp;
use DateTime;
use File::Find;
use File::Spec;

use Moose;
use Moose::Util::TypeConstraints;

use TechSafari::CustomDateTime;

subtype 'DateTime' => as 'Object' => where { $_->isa('DateTime') };

coerce 'DateTime' => (
  from
    'Str' => via { _convert_Str_to_DateTime($_) },
  from
    'HashRef' => via { _convert_HashRef_to_DateTime($_) },
  from 'Undef' => via { DateTime->now() }
);

my ( @DateTime_Format_Classes, @DateTime_Str_Conversion_Shortcuts );

sub available_datetime_format_classes {
  return @DateTime_Format_Classes;
}

sub conversion_shortcuts {
  return @DateTime_Str_Conversion_Shortcuts;
}

sub add_shortcut {
  return unshift @DateTime_Str_Conversion_Shortcuts,
    grep { ref($_) && ref($_) eq 'CODE' } @_;
}

sub _convert_Str_to_DateTime {
  my $str = shift;

  # try shortcuts
  for my $shortcut ( __PACKAGE__->conversion_shortcuts() ) {
    my $dt = $shortcut->($str);
    if ( $dt && blessed($dt) && $dt->isa('DateTime') ) {
      carp "DateTime ($dt) coerced from shortcut" if $DEBUG;
      return $dt;
    }
  }
  
  # Try custom converter first
  my $dt = TechSafari::CustomDateTime->convert_str_to_datetime($str);
  return $dt if $dt;

  my @possible_instances;

  # check if installed DateTime::Format::X classes can convert the string
  for my $fmt_class ( __PACKAGE__->available_datetime_format_classes() ) {

    # save date manip for later...
    next if $fmt_class =~ m/DateManip/x;

    # load class, if necessary
    my $rc = eval { Class::MOP::load_class($fmt_class) };
    next if $@ || !$rc;

    # try possible format methods as class methods
    for my $method ( 'parse_datetime', 'parse_date', 'parse_timestamp' ) {

      if ( defined &{ $fmt_class . '::' . $method } ) {
        my $dt = eval { $fmt_class->$method($str) };

        if ( !$@ && $dt && blessed($dt) && $dt->isa('DateTime') ) {
        
          carp "DateTime ($dt) coerced from $fmt_class->$method()" if $DEBUG;
          return $dt;
        }
      }
    }

    # if we can instantiate the class, try that next
    if ( defined &{ $fmt_class . '::new' } ){
      push @possible_instances, $fmt_class;
    }

  }
  
  # try to instantiate classes...
  for my $fmt_class ( @possible_instances ) {
    my $obj = eval { $fmt_class->new() };
    next if $@ || ! $obj;
    
    # try possible format methods as instance methods
    for my $method ( 'parse_datetime', 'parse_date', 'parse_timestamp' ) {

      if ( defined &{ $fmt_class . '::' . $method } ) {
        my $dt = eval { $obj->$method($str) };

        if ( !$@ && $dt && blessed($dt) && $dt->isa('DateTime') ) {
        
          carp "DateTime ($dt) coerced from an instance of $fmt_class->$method()" if $DEBUG;
          return $dt;
        }
      }
    }    
    
  }  

  # lastly, try Date::Manip
  my $rc = eval { Class::MOP::load_class('DateTime::Format::DateManip') };

  if ( !$@ && $rc ) {
    Date::Manip::Date_Init('TZ=US/Eastern'); 
    my $dt = eval { DateTime::Format::DateManip->parse_datetime($str) };
   
    if ( ! $@ && $dt && blessed($dt) && $dt->isa('DateTime') ) {
      carp "DateTime ($dt) coerced from Date::Manip" if $DEBUG;
      return $dt;
    }
  }


  Carp::confess "Can't convert string to DateTime: '$str'.  "
    . 'Try to install a corresponding DateTime::Format::XXX module, or '
    . 'Add a conversion shortcut with ' . __PACKAGE__ . "::add_shortcut()\n";

  return;
}

sub _convert_HashRef_to_DateTime {
  my $hr = shift;

  if ( exists $hr->{from_epoch} ) {
    my $dt = DateTime->from_epoch( epoch => $hr->{from_epoch} );

    carp "DateTime ($dt) coerced from epoch" if $DEBUG;
    return $dt;
  }
  elsif ( exists $hr->{last_day_of_month} ) {
    delete $hr->{last_day_of_month};
    my $dt = DateTime->last_day_of_month( %{$hr} );

    carp "DateTime ($dt) coerced from last day of month" if $DEBUG;
    return $dt;
  }

  return DateTime->new( %{$hr} );
}

# find installed DateTime::Format:: objects
find( { wanted => \&wanted, follow_fast => 1, no_chdir => 1 }, grep { -d } @INC );

sub wanted {
  my $name = $_;

  return unless $name =~ m/\.pm$/x;
  return unless $name =~ m/DateTime/x;
  return unless $name =~ m/Format/x;

  my ( $volume, $directories, $file ) = File::Spec->splitpath($name);
  my @dirs = File::Spec->splitdir($directories);

  $file =~ s/\.pm//x;
  my $class = join q{::}, $dirs[-3], $dirs[-2], $file;

  if ( $class =~ m/^ DateTime::Format::\w+ $/x ) {
    push @DateTime_Format_Classes, $class;
  }

  return;
}

# add custom shortcuts
add_shortcut(
  sub {
    my $str = shift;

    if ( $str =~ m{^ ((?:20|19)\d{2}) [/\-]? (\d{2}) [/\-]? (\d{2}) $}x ) {
      return DateTime->new( year => $1, month => $2, day => $3 );
    }
    elsif (
      $str =~ m{^ 
                 ((?:20|19)\d{2}) [/\-]?  #year
                 (\d{2})          [/\-]?  #month
                 (\d{2})          \s+     #day
                 (\d{1,2})        [:-]    #hour
                 (\d{1,2})        [:-]    #minute
                 (\d{1,2})                #sec
               }x
      )
    {
      return DateTime->new(
        year   => $1,
        month  => $2,
        day    => $3,
        hour   => $4,
        minute => $5,
        second => $6
      );
    }

    return;
  },

  sub {
    my $str = shift;

    if ( lc $str eq 'now' ) {
      return DateTime->now();
    }
    elsif ( lc $str eq 'yesterday' ) {
      return DateTime->today - DateTime::Duration->new( days => 1);
    }

    return;
  },

  
);

1;

__END__

=head1 NAME

TechSafari::DateTime::MooseX - Charlie's DateTime Moose Coercions.  These are WAY
useful

=head1 VERSION

=over

=item $Id$

=item $Revision$

=item $HeadURL$

=item $Date$

=item $Source$

=back

=head1 SYNOPSIS

  # Don't define DateTime as a Moose Type constraint anywhere else.
  use TechSafari::DateTime::MooseX;

  # somewhere else, define an attribute that is a DateTime type ...
  has 'run_date' => (
    is      => 'rw',
    isa     => 'DateTime',
    coerce  => 1,  # this is important.  don't forget it
  );

  # now you can stick anything into that run_date, and b/c of this GD module
  # it should Do What You Mean

  $obj->run_date('2007-04-20');
  $obj->run_date('2008-04-20 04:20:00');
  $obj->run_date('20080420');

  $obj->run_date('today');
  $obj->run_date('now'); 
  $obj->run_date('yesterday');  # seriously.
  
  $obj->run_date( { year => 2008, month => 04, day => 20 } );
  
  # 2008-07-31
  $obj->run_date( { 
      year => 2008, 
      month => 07, 
      last_day_of_month => 1 
    } 
  );
  
  $obj->run_date( { from_epoch => time() );

  # assuming you have DateTime::Format::Baby installed, this will work.
  $obj->run_date('The big hand is on the twelve and the little hand is on the six.');


=head1 DESCRIPTION

Charlie's Moose coercions of DateTime values.  This is the way I want to handle 
it, as I think the MooseX coercions on cpan are insufficient in a number of 
ways.  

Of course, this module is over-sufficient in a number of ways, so much so that
I don't want to spend the effort of trying to write a sufficient test suite
for it.  And, in your opinion, this class probably takes up too much initial
load time, but that's only depending on the perl installation.  But, I'll have 
you know, this module burns through some cycles and memory everytime you try
to coerce a new unknown string into a DateTime attribute.  It's lazy about 
loading the modules it finds on compile time.  Another But, I think I 
shortcutted enough common datetime formats, that this module will be 
sufficiently efficient.  This is the most-awesome paragraph I've written in the
last five years.

Because this module is in the Charlie::* namespace, don't change it unless you 
are me.  Just trust that I did the right thing when you use this, and hope that 
I continue my godly benevolence.

Anyway, this module started because I am so sick of writing datetime 
code.  DateTime and DateTime::Duration are now the lingua-franca standard way of 
doing anything date related in Perl.  Quit f'n around, damnit!

=head1 ATTRIBUTES

There are a couple of read only / hard to get at class attributes that contain
available datetime formatting classes and conversion shortcuts.  Access the
attributes using the following methods.

=head1 METHODS

=head2 available_datetime_format_classes 

returns a list of all the datetime format classes found installed / in the 
PERL5LIB path (@INC)

=head2 conversion_shortcuts

Returns a list of the conversion shortcuts.  "Conversion shortcuts" are methods
that expect a string and try to convert that into a DateTime object.  They are
tried before dynamically loading any DateTime Format modules.

A few conversion shorcuts have already been defined.

=head2 add_shortcut

This adds the shortcut to the front of the list.

example (this shortcut has already been defined, BTW:

  TechSafari::DateTime::MooseX::add_shortcut( 
    sub {
      my $str = shift;
      
      if ( $str =~ m/^ (\d{4}) - (\d{2}) - (\d{2}) ^/x ) {
        return DateTime->new( year => $1, month => $2, day => $day );
      }
    
      return;  # undef = fail, try the next shortcut...
    }
  );

Don't die() or confess() in your shortcut.  Catch any exceptions that could
pop up.  I'm going to let them propagate through.  It would be best to just 
return undef if you can't convert correctly.

=head1 DEPENDENCIES

=head2 Obviously, Moose.

=head2 DateTime

=head1 AUTHOR

$Author$

