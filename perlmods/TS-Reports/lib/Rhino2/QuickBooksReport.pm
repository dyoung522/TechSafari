package Rhino2::QuickBooksReport;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Carp;

use Moose;
extends 'Rhino2::BasicReport';

use Rhino2::QuickBooksSQL;

################################################################################
### Attributes
################################################################################

has 'negative_amounts_flag' => (
  is      => 'rw',
  isa     => 'Bool',
  lazy    => 1,
  builder => '_build_negative_amounts_flag',
);

# Return 0 (which is correct), unless we're running the report for
# Name Seeker, then return 1.  Name Seeker is backwards.
#
# Of course, the negative_amounts_flag can be explicitly set one way or the
# other, but this is a reasonable guess as to the default...
sub _build_negative_amounts_flag {
  my $self = shift;

  if ( $self->has_hosts ) {
    for my $host ( @{ $self->hosts } ) {
      my $host_info = $self->sql->host_info($host);
      if ( $host_info->{h_desc_txt} eq 'Name Seeker Inc.' ) {
        return 1;
      }
    }
  }

  return 0;
}

## Private attribute.  This builds the sql attribute.  It is defined by the
## 'sql' attribute in the super class ( Basic Report ).  See lazy_build.
sub _build_sql {
  my $self = shift;
  return Rhino2::QuickBooksSQL->new( dbh => $self->dbh );
}

################################################################################
### Instance Methods
################################################################################

sub process {
  my $self = shift;

  my %args = $self->process_query_args;

  #$args{debug} = 1;
  $self->generate_invoice_item_query(%args);

  return 1;
}

sub generate_invoice_item_query {
  my ( $self, %args ) = @_;

  my $invoice_items = $self->sql->quickbooks_invoice_items_query(%args);

  # Get column info from query results
  my $cols   = $self->sql->last_column_names;
  my $cindex = $self->sql->last_column_index;

  # Collect invoice items into invoices
  my %invoices;
  for my $item ( @{$invoice_items} ) {
    my $invoice_id = $item->[ $cindex->{'Invoice'} ];

    if ( not exists $invoices{$invoice_id} ) {
      $invoices{$invoice_id} = [];
    }

    push @{ $invoices{$invoice_id} }, $item;
  }

  my @table;

  # Add IIF headers to the main table.
  push @table,
    [
    '!TRNS',  'TRNSID', 'TRANSTYPE', 'DATE',  'DUEDATE', 'NAME',
    'DOCNUM', 'ACCNT',  'PONUM',     'TERMS', 'AMOUNT',  'ADDR1',
    'ADDR2',  'ADDR3',  'ADDR4'
    ];
  push @table,
    [
    '!SPL', 'SPLID',   'TRANSTYPE', 'ACCNT', 'AMOUNT', 'PRICE',
    'QNTY', 'INVITEM', 'MEMO'
    ];
  push @table, [ '!ENDTRNS', map { q{} } 1 .. 9 ];

  ## Loop through invoices to create the quickbooks table ##

  # invoices are not sorted
  while ( my ( $invoice_id, $items ) = each %invoices ) {

    # The record is created backwards, then reversed when pushed into the table
    # That's because we're iterating through the invoice items:
    #  the SPL  is an invoice item (there can be more than one)
    #  the TRNS is essentially a summary of the invoice items
    #    (there can be only one, highlander).

    # So, put the ending first
    my @qb_record = ( [ 'ENDTRNS', map { q{} } 1 .. 9 ] );

    my $amount_sum = 0;
    my $first_item = $items->[0];

    ### ADD the SPL rows ###
    for my $item ( @{$items} ) {

      $amount_sum += $item->[ $cindex->{'Billed Amount'} ];

      # Calculate price - divide by 1000 if bill item type eq 'Per 1000'
      my $price = $item->[ $cindex->{'Billed Price'} ];
      if ( $item->[ $cindex->{'Bill Item Type'} ] eq 'Per 1000' ) {

        $price = sprintf '%.03f', ( $price / 1000 ); #round price to 3 decimals
        $price += 0;                                 #cut trailing 0's
      }

      # Account text
      # If the account name is null - use 'Unknown'
      my $account_text = $item->[ $cindex->{'Account Text'} ];
      if ( !$account_text ) {
        $account_text = 'Unknown';
      }

      # Negate amounts if necessary
      my $amt = $item->[ $cindex->{'Billed Amount'} ];
      if ( $self->negative_amounts_flag ) {
        $amt *= -1;
      }

      # Add SPL row
      push @qb_record, [
        'SPL',
        $item->[ $cindex->{'Bill Item Code'} ],
        'INVOICE',
        $account_text,
        $amt,
        $price,
        $item->[ $cindex->{'Record Count'} ],
        $item->[ $cindex->{'Bill Item Code'} ],
        $item->[ $cindex->{'Bill Item Description'} ],

      ];
    }

    ### Add the TRNS row ###

    # Look up main contact info for the invoice, based on invoice company id
    my $contact_info =
      $self->sql->main_contact_info(
      $first_item->[ $cindex->{'inv_company_id'} ] );

    ## Determine the due date based on the payment terms and order date ##

    # Order Date
    my $order_dt = DateTime::Format::MySQL->parse_date(
      $first_item->[ $cindex->{'Invoice Date'} ] );

    my $due_dt;
    my $terms = $first_item->[ $cindex->{'Payment Terms'} ];

    # Parse payment terms
    if ( $terms =~ m/ Net \s+ (\d+) /x ) {
      my $days = $1;
      my $duration = DateTime::Duration->new( days => $days );
      $due_dt = $order_dt + $duration;
    }
    elsif ( $terms eq 'Upon Receipt' ) {
      $due_dt = $order_dt;
    }
    else {
      carp "Unknown payment type: '$terms'";
      $due_dt = $order_dt;
    }

    # Round amount sum to 2 decimals
    $amount_sum = sprintf '%.02f', $amount_sum;

    # Negate amounts if necessary
    if ( !$self->negative_amounts_flag ) {
      $amount_sum *= -1;
    }

    # Create Location City / State / Zip string #
    my $location = join q{ }, $contact_info->{'City'}, $contact_info->{'State'},
      $contact_info->{'Zip5'};

    # Create Overall TRNS record
    push @qb_record, [
      'TRNS',
      $first_item->[ $cindex->{'Invoice'} ],
      'INVOICE',
      $order_dt->mdy(q{/}),
      $due_dt->mdy(q{/}),
      $contact_info->{'Business Name'},
      $first_item->[ $cindex->{'Invoice'} ],
      'ACCOUNTS RECEIVABLE',
      $first_item->[ $cindex->{'PO Number'} ],
      $terms,
      $amount_sum,
      $contact_info->{'Business Name'},
      $contact_info->{'Address 1'},
      $contact_info->{'Address 2'},
      $location

    ];

    push @table, reverse @qb_record;
  }

  my $worksheet = TechSafari::Reports::Worksheet->new(
    name  => 'Quick Books Report',
    table => \@table,
  );

  return $self->add_worksheet($worksheet);
}

1;

__END__

=head1 NAME

Rhino2::QuickBooksReport - quick books report

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

This report is a subclass of the basic report.  Basically, that report provides
the process method, which parses through the report_period, run_date, hosts,
and companies atttributes.

The process method calls the generate_invoice_item_query.  A workbook with
only one worksheet is created.

All of the quickbooks, IIF import data is stored in the table of the first
worksheet in the workbook.

=head1 ATTRIBUTES

See L<Rhino2::BasicReport> for common attributes

Additional attribute:  

negative_amounts_flag.  Negates debits/credits depending on how the customer
wants their quickbooks to work.

This tries to have a reasonable default value: nameseeker is one way, 
everyone else is the other...


=head1 METHODS

=head1 DEPENDENCIES

=head1 AUTHOR

$Author$

