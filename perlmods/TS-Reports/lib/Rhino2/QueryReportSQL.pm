package Rhino2::QueryReportSQL;

our ($VERSION) = '$Revision: 133 $' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
use Carp;
extends 'Rhino2::BaseSQL';

### ATTRIBUTES ###

## METHODS ###

sub qr_invoice_query {
  my ( $self, %args ) = @_;

  my ( $where, @bind ) = $self->_parse_conditional_args(%args);

  my $end_user_lookup_table = $self->_end_user_lookup_table;

  my $sql = qq{
    SELECT
      inv.id                 AS 'Invoice',
      DATE(o.o_order_dt)     AS 'Invoice Date',
      cn.c_name_txt          AS 'Dealer',
      cp.cp_name_txt         AS 'Marketing Company',
      p.p_name_txt           AS 'Description',
      o.o_final_cnt_num      AS 'Record Count',
      SUM(ii.ii_total_num)   AS 'Billed Amount',

      c.product_id           AS 'product_id',
      c.host_id              AS 'host_id',
      bi.bi_bill_cd          AS 'bi_bill_cd'

    FROM
      invoices             AS inv
      JOIN invoice_items   AS ii  ON ii.invoice_id = inv.id
      JOIN orders          AS o   ON o.id          = ii.order_id
      JOIN counts          AS c   ON c.order_id    = o.id
      JOIN companies       AS cp  ON cp.id         = inv.company_id
      JOIN products        AS p   ON p.id          = c.product_id
      JOIN bill_items      AS bi  ON bi.id         = ii.bill_item_id      
      
      -- Sub query for "End User" contact.  Left join with NULL if none...
      LEFT JOIN $end_user_lookup_table AS cn ON cn.cc_count_id = c.id

    WHERE
      (o.o_no_bill_fg is null or o.o_no_bill_fg != '1')
      AND c.count_status_id >= 100

      AND $where
    
    GROUP BY inv.id  
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

Rhino2::QueryReportSQL - Custom queries for QueryReport 

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

=item B<qr_invoice_query> ( %conditionals )

Copied from BaseSQL::invoice_query

=head1 DEPENDENCIES

L<Rhino2::BaseSQL>

=head1 AUTHOR

$Author: calderman $

