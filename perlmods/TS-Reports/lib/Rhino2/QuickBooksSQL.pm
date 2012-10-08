package Rhino2::QuickBooksSQL;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Moose;
use Carp;
extends 'Rhino2::BaseSQL';

### ATTRIBUTES ###

has '_mci_cache' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

### METHODS ###

sub quickbooks_invoice_items_query {
  my ( $self, %args ) = @_;

  my ( $where, @bind ) = $self->_parse_conditional_args(%args);

  # There's really no reason to have the ORDER BY clause other than to create
  # a matching diff with the old quickbooks rpt.  The Report collects up the
  # invoice items by invoice id in a hash, which it then sorts again, anyway...
  
  my $sql = qq{
   SELECT
      inv.id                 AS 'Invoice',
      DATE(o.o_order_dt)     AS 'Invoice Date',
      ii.ii_total_num        AS 'Billed Amount',
      ii.ii_amount_num       AS 'Billed Price',
      ii.ii_qty_num          AS 'Record Count',
      o.o_po_number_txt      AS 'PO Number',
      pt.pt_desc_txt         AS 'Payment Terms',

      bi.bi_bill_cd          AS 'Bill Item Code',
      bi.bi_desc_txt         AS 'Bill Item Description',
      bt.bit_desc_txt        AS 'Bill Item Type',
      rcbi.ria_ext_acct_txt  AS 'Account Text',

      inv.company_id         AS 'inv_company_id'

    FROM
      invoices             AS inv
      JOIN invoice_items   AS ii  ON ii.invoice_id = inv.id
      JOIN orders          AS o   ON o.id          = ii.order_id
      JOIN counts          AS c   ON c.order_id    = o.id
      JOIN companies       AS cp  ON cp.id         = inv.company_id
           
      JOIN payment_types   AS pt  ON pt.id         = cp.payment_type_id
      JOIN bill_items      AS bi  ON bi.id         = ii.bill_item_id
      JOIN bill_item_types AS bt  ON bt.id         = bi.bill_item_type_id

      JOIN companies_products AS cpp
        ON  cpp.product_id = c.product_id
        AND cpp.company_id = cp.id

      LEFT JOIN rate_cards_bill_items AS rcbi
        ON  rcbi.bill_item_id = bi.id
        AND rcbi.rate_card_id = cpp.rate_card_id

    WHERE
      (o.o_no_bill_fg is null or o.o_no_bill_fg != '1')
      AND c.count_status_id >= 100

      AND $where

    ORDER BY inv.id, ii.id ASC 
  };

  if ( $args{debug} ) {
    Carp::carp( "---- SQL ----\n$sql\n---- BIND VARS ----\n"
        . ( join "\n", map { "$_ => $bind[$_]" } 0 .. $#bind )
        . "\n---- END ----\n" );
  }

  my $sth = $self->dbh->prepare($sql);
  $sth->execute(@bind);
  $self->set_column_info($sth);

  return $sth->fetchall_arrayref;
}

sub main_contact_info {
  my ( $self, $company_id ) = @_;

  if ( exists $self->_mci_cache->{$company_id} ) {
    return $self->_mci_cache->{$company_id};
  }

  # Contact types: 1 = main contact, 3 = bill to contact
  # The query should return the bill to before the main contact,
  # then we only use the first contact type returned.
  
  my $sql = q{
    SELECT
      c.c_biz_name_txt  AS 'Business Name',
      c.c_addr1_txt     AS 'Address 1',
      c.c_addr2_txt     AS 'Address 2',
      c.c_city_txt      AS 'City',
      c.c_state_txt     AS 'State',
      c.c_zip5_txt      AS 'Zip5'

    FROM contacts AS c
   
    WHERE c.company_id = ?
      AND c.contact_type_id IN ( 1, 3 )
      
    ORDER BY c.contact_type_id DESC
  };

  my $sth = $self->dbh->prepare($sql);
  $sth->execute($company_id);
  $self->set_column_info($sth);

  # return the first row -- which is ordered properly, if not mysteriously
  my @row  = $sth->fetchrow_array;
  my $cols = $self->last_column_names;

  my %h = map { $cols->[$_] => $row[$_] } 0 .. $#row;

  $self->_mci_cache->{$company_id} = \%h;

  return \%h;
}

1;

__END__

=head1 NAME

Rhino2::QuickBooksSQL - Custom queries for Quick Books.  Extends 
L<Rhino2::BaseSQL>

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

=item B<quickbooks_invoice_items_query> ( %conditionals )

This pulls all the invoice items for the given conditionals.  The quickbooks
report then goes and looks up contact info for the main contact based on the
invoice company id.

=item B<main_contact_info> ( $company_id )

Look up the main contact info to use for a particular company.  If the 
"Bill to" contact is not available, use the "Company main contact info" contact.  
Hopefully, one of those is available.

This returns a hash ref keyed by the column name specified in the query.

Some application level caching is done on the main contact info for speedyups.

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$

