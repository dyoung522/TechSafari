package Rhino2::OrdersSQL;

our ($VERSION) = '$Revision: 133 $' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
use Carp;
extends 'Rhino2::BaseSQL';

### ATTRIBUTES ###

## METHODS ###

sub orders_query {
  my ( $self, %args ) = @_;

  my ( $where, @bind ) = $self->_parse_conditional_args(%args);

  my $end_user_lookup_table = $self->_end_user_lookup_table;

  my $sql = qq{
    SELECT
      c.id               AS 'Count ID',
      DATE(o.o_order_dt) AS 'Order Date',
      c.c_final_cnt_num  AS 'Record Count',
      
      c.user_id          AS 'User ID',
      u.u_name_txt       AS 'User Name',

      c.product_id       AS 'Product ID',
      p.p_name_txt       AS 'Product Name',
            
      cp.cp_name_txt     AS 'Company Name',
      
      c.host_id          AS 'Host ID',
      h.h_name_txt       AS 'Host Name',

      cn.c_name_txt      AS 'End User',
      cn.c_biz_name_txt  AS 'End User Company',
      cp.cp_name_txt     AS 'Marketing Company'
      
      -- o.o_no_bill_fg     AS 'o_no_bill_fg'

    FROM
      orders         AS o
      JOIN counts    AS c   ON c.order_id    = o.id
      JOIN companies AS cp  ON cp.id         = o.company_id
      JOIN hosts     AS h   ON h.id          = c.host_id
      JOIN products  AS p   ON p.id          = c.product_id
      JOIN users     as u   ON u.id          = c.user_id
      
      -- Sub query for "End User" contact.  Left join with NULL if none...
      LEFT JOIN $end_user_lookup_table AS cn ON cn.cc_count_id = c.id

    WHERE
      c.count_status_id >= 100
    
      AND $where   
    
    ORDER BY
      DATE(o.o_order_dt),
      cp.cp_name_txt,
      c.id   
  };

  if ( $args{debug} ) {
    carp( "---- SQL ----\n$sql\n---- BIND VARS ----\n"
        . ( join "\n", map { "$_ => $bind[$_]" } 0 .. $#bind )
        . "\n---- END ----\n" );
  }

  my $sth = $self->dbh->prepare($sql);
  $sth->execute(@bind);
  $self->set_column_info($sth);

  return $sth->fetchall_arrayref;
}



1;

__END__

=head1 NAME

Rhino2::OrdersSQL - Custom queries for Orders - Specifically created for GE 
Health / anyone using the wizard.

Extends L<Rhino2::BaseSQL>

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

=item B<orders_query> ( %conditionals )

This pulls orders, status ordered or shipped, whether or not the order has been
billed

=head1 DEPENDENCIES

L<Rhino2::BaseSQL>

=head1 AUTHOR

$Author: calderman $

