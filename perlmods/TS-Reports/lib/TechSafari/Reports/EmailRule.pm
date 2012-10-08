
package TechSafari::Reports::EmailRule;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
use Moose::Util qw/does_role/;
use Moose::Util::TypeConstraints;

subtype 'TechSafari::Reports::EmailRule' => as 'Object' => where { 
  $_->isa('TechSafari::Reports::EmailRule')
};

coerce 'TechSafari::Reports::EmailRule' => from 'HashRef' => via {
  TechSafari::Reports::EmailRule->new( %{ $_ } )
};

subtype 'TSR::EmailRule::Report' => as 'HashRef' => where {
  exists $_->{class} 
  && does_role( $_->{class}, 'TechSafari::Reports::Interface' )
};

has 'report'    => ( is => 'rw', isa => 'TSR::EmailRule::Report', required => 1 );
has 'output_to' => ( is => 'rw', isa => 'HashRef', required => 1 );
has 'email'     => ( is => 'rw', isa => 'HashRef', required => 1 );
has 'filename'  => ( is => 'rw', isa => 'Str', required => 1 );
has 'tags'      => ( is => 'rw', isa => 'HashRef' );

1;
__END__

=head1 NAME

TechSafari::Reports::EmailRule - Definition of an email rule, as defined 
in the yaml configuration files.

=head1 VERSION

=over

=item $Id$

=item $Revision$

=item $HeadURL$

=item $Date$

=item $Source$

=back

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$


