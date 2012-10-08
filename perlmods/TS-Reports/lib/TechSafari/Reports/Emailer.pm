

package TechSafari::Reports::Emailer;
use Moose;
use Moose::Util::TypeConstraints;

use File::Spec;
use MIME::Lite;

##
subtype 'TS::EmailAddress' => as 'Str' => where { 1 };
coerce  'TS::EmailAddress' => from 'ArrayRef' => via { join q{, }, @{$_} };
##

has 'mailhost' => ( is => 'rw', isa => 'Str' );
has 'username' => ( is => 'rw', isa => 'Str' );
has 'password' => ( is => 'rw', isa => 'Str' );

has 'to'      => ( is => 'rw', isa => 'TS::EmailAddress', coerce => 1, required => 1 );
has 'from'    => ( is => 'rw', isa => 'TS::EmailAddress', coerce => 1 );
has 'cc'      => ( is => 'rw', isa => 'TS::EmailAddress', coerce => 1 );
has 'subject' => ( is => 'rw', isa => 'Str' );
has 'body'    => ( is => 'rw', isa => 'Str', 
                   default => 'Report is attached to this email.');
                   
has 'dropoff_dir' => ( is => 'rw', isa => 'Str', default => '.' );
has 'attachments' => ( is => 'rw', isa => 'ArrayRef[Str]',
                       default => sub{[]} );  # Array of filenames

sub add_attachment {
  my ( $self, $filename ) = @_;
  my @a = @{ $self->attachments };
  push @a, $filename;
  $self->attachments(\@a);
}

sub send {
  my $self = shift;
  my $msg = MIME::Lite->new( Type =>'multipart/mixed' );

  for my $attr ( qw/ from to cc subject / ) {
    if ( $self->$attr ) {
      $msg->add( $attr, $self->$attr );
    }
  }
  
  # Add body
  $msg->attach( 
    Type => 'text/plain',
    Data => $self->body,
    Datestamp => 1,
    Disposition => 'inline',
  );
  
  # Add attachments
  for my $attachment ( @{ $self->attachments } ) {
    my $type;
    
    if ( $attachment =~ m/\.xls$/i ) {
      $type = 'application/vnd.ms-excel';
    }
    elsif ( $attachment =~ m/\.html$/i ) {
      $type = 'text/html';
    }
    elsif ( $attachment =~ m/\.xml$/i ) {
      $type = 'text/xml';
    }
    elsif ( $attachment =~ m/\.iif$/i ) {
      $type = 'application/qbooks';
    }
    else {
      $type = 'text/plain';
    }
    
    $msg->attach(
      Type => $type,
      Path => File::Spec->catfile($self->dropoff_dir, $attachment),
      Filename => $attachment,
      Disposition => 'attachment',
    )
  }
  
  if ( $self->mailhost and ($self->username or $self->password) ) {
    MIME::Lite->send('smtp', $self->mailhost, 
                       AuthUser => $self->username,
                       AuthPass => $self->password,
                       Debug => 1);
  }
  elsif( $self->mailhost ) {
    MIME::Lite->send('smtp', $self->mailhost, Debug => 1);
  }
  
  $msg->send || Carp::confess "Unable to send email!";
  
}

no Moose;
no Moose::Util::TypeConstraints;

1;
__END__;


