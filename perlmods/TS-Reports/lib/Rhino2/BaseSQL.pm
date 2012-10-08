package Rhino2::BaseSQL;

our ($VERSION) = '$Revision$' =~ m{ \$Revision: \s+ (\S+) }x;

use Carp;
use Moose;

use DateTime::Format::MySQL;
sub format_datetime { return DateTime::Format::MySQL->format_datetime(pop) }

################################################################################
### Attributes
################################################################################

with 'TechSafari::Reports::Attributes::DBH';

has 'last_column_index' => ( is => 'ro', isa => 'HashRef' );
has 'last_column_names' => ( is => 'ro', isa => 'ArrayRef' );
has 'last_column_types' => ( is => 'ro', isa => 'ArrayRef' );

has 'create_temporary_tables' => ( is => 'rw', isa => 'Bool', default => 1 );

## Private attributes
has '_prg_cache' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has '_dsn_cache' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has '_pnm_cache' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

has '_end_user_lookup_table' => (
  is        => 'rw',
  isa       => 'Str',
  lazy      => 1,
  builder   => '_build_end_user_lookup_table',
  predicate => 'has_end_user_lookup_table',
  clearer   => 'clear_end_user_lookup_table',
);


################################################################################
### Instance Methods
################################################################################

sub set_column_info {
  my ( $self, $sth ) = @_;

  # create new data structures, just in case DBI internals try to wipe them out
  my @names = @{ $sth->{NAME} };
  my @types = @{ $sth->{TYPE} };
  my %index = map { $names[$_] => $_ } 0 .. $#names;

  $self->{last_column_names} = \@names;
  $self->{last_column_types} = \@types;
  $self->{last_column_index} = \%index;

  return;
}

sub host_info {
  my ( $self, $host_id ) = @_;

  my $sql = q{ SELECT * FROM `hosts` };

  if ( $host_id =~ m/^\d+$/x ) {
    $sql .= q{ WHERE id = ? };
  }
  elsif ($host_id) {
    $sql .= q{ WHERE h_desc_txt = ? };
  }
  else {
    Carp::confess 'Unable to get host info for undefined host id / host name.';
  }
  
  my $sth = $self->dbh->prepare_cached( $sql, {}, 2 );
  $sth->execute($host_id);
  $self->set_column_info($sth);

  my $hr = $sth->fetchrow_hashref('NAME_lc');
  
  unless ( $hr && %{ $hr } ) {
    Carp::confess "Unable to get host info for host id/name: $host_id'";
  }
  
  return wantarray ? %{$hr} : $hr;
}

sub host_names {
  my $self = shift;

  my $sql = q{ SELECT h_desc_txt FROM `hosts` };
  my $ar  = $self->dbh->selectcol_arrayref($sql);
  return wantarray ? @{$ar} : $ar;
}

sub company_info {
  my ( $self, $company_id ) = @_;

  my $sql = q{ SELECT * FROM `companies` };

  if ( $company_id =~ m/^\d+$/x ) {
    $sql .= q{ WHERE id = ? };
  }
  elsif ($company_id) {
    $sql .= q{ WHERE cp_name_txt = ? };
  }
  else {
    Carp::confess 'Unable to get company info for undefined company id / name.';
  }

  my $sth = $self->dbh->prepare_cached( $sql, {}, 2 );
  $sth->execute($company_id);
  $self->set_column_info($sth);

  my $hr = $sth->fetchrow_hashref('NAME_lc');

  unless ( $hr && %{ $hr } ) {
    Carp::confess "Unable to get company info for company id/name: '$company_id'";
  }

  return wantarray ? %{$hr} : $hr;
}

sub company_names {
  my $self = shift;

  my $sql = q{ SELECT cp_name_txt FROM `companies` };
  my $ar  = $self->dbh->selectcol_arrayref($sql);
  return wantarray ? @{$ar} : $ar;
}

# select info
sub select_info {
  my ( $self, $select_id ) = @_;

  my $sql = q{ SELECT * FROM `selects` };

  if ( $select_id =~ m/^\d+$/x ) {
    $sql .= q{ WHERE id = ? };
  }
  elsif ($select_id) {
    $sql .= q{ WHERE s_display_txt = ? };
  }
  else {
    Carp::confess 'Unable to get select info for undefined select id / name.';
  }

  my $sth = $self->dbh->prepare_cached( $sql, {}, 2 );
  $sth->execute($select_id);
  $self->set_column_info($sth);

  my $hr = $sth->fetchrow_hashref('NAME_lc');
  
  unless ( $hr && %{ $hr } ) {
    Carp::confess "Unable to get select info for select id/name: '$select_id'";
  }  
  
  return wantarray ? %{$hr} : $hr;
}

sub select_names {
  my $self = shift;

  my $sql = q{ SELECT s_display_txt FROM `selects` };
  my $ar  = $self->dbh->selectcol_arrayref($sql);
  return wantarray ? @{$ar} : $ar;
}

sub royalty_groups {
  my $self = shift;

  my $sql = q{ SELECT rg_desc_txt FROM royalty_groups };
  my $ar  = $self->dbh->selectcol_arrayref($sql);
  return wantarray ? @{$ar} : $ar;
}

sub selects_royalty_groups {
  my ( $self, $count_id ) = @_;

  my $sql = q{
    SELECT DISTINCT
      rg.rg_desc_txt
    
    FROM
      counts_select_options       AS cso
      JOIN select_options         AS so  ON so.id         = cso.select_option_id
      JOIN product_groups_selects AS pgs ON pgs.select_id = so.select_id
      JOIN royalty_groups         AS rg  ON rg.id         = pgs.royalty_group_id
    
    WHERE
      cso.count_id = ?  
  };

  my $sth = $self->dbh->prepare_cached( $sql, {}, 2 );
  $sth->execute($count_id);
  $self->set_column_info($sth);

  my @col;
  while ( my $row = $sth->fetch ) {
    push @col, $row->[0];
  }

  return wantarray ? @col : \@col;
}

sub products_royalty_group {
  my ( $self, $product_id ) = @_;

  if ( exists $self->_prg_cache->{$product_id} ) {
    return $self->_prg_cache->{$product_id};
  }

  my $sql = q{
    SELECT rg.rg_desc_txt
    FROM products AS p
    JOIN royalty_groups AS rg ON rg.id = p.royalty_group_id
    WHERE p.id = ?
  };

  my $sth = $self->dbh->prepare_cached( $sql, {}, 2 );
  $sth->execute($product_id);
  $self->set_column_info($sth);

  my $row = $sth->fetch();
  my $prg = $row->[0];

  $self->_prg_cache->{$product_id} = $prg;

  return $prg;
}

sub product_name {
  my ( $self, $product_id ) = @_;

  if ( exists $self->_pnm_cache->{$product_id} ) {
    return $self->_pnm_cache->{$product_id};
  }

  my $sql = q{ SELECT p_name_txt FROM products WHERE id = ? };

  my $sth = $self->dbh->prepare_cached( $sql, {}, 2 );
  $sth->execute($product_id);
  $self->set_column_info($sth);

  my $row = $sth->fetch();
  my $pnm = $row->[0];

  $self->_pnm_cache->{$product_id} = $pnm;

  return $pnm;
}

sub data_source_name {
  my ( $self, %args ) = @_;

  my $val;

  if ( $args{'product_id'} ) {

    my $cache_key = 'product_id:' . $args{'product_id'};

    if ( exists $self->_dsn_cache->{$cache_key} ) {
      return $self->_dsn_cache->{$cache_key};
    }
    else {

      my $sql = q{
        SELECT DISTINCT ds.ds_name_txt
        FROM data_sources AS ds
          JOIN selects AS s ON s.data_source_id = ds.id
          JOIN product_groups_selects AS pgs ON pgs.select_id = s.id
          JOIN product_groups AS pg ON pg.id = pgs.product_group_id
        WHERE pg.product_id = ?
      };

      my $sth = $self->dbh->prepare_cached( $sql, {}, 2 );
      $sth->execute( $args{'product_id'} );
      my $ar = $sth->fetchrow_arrayref;

      if ($ar) {
        $val = $ar->[0];
        $self->_dsn_cache->{$cache_key} = $val;
      }
    }

  }

  if ( !$val && $args{'count_id'} ) {

    my $cache_key = 'count_id:' . $args{'count_id'};

    if ( exists $self->_dsn_cache->{$cache_key} ) {
      return $self->_dsn_cache->{$cache_key};
    }
    else {

      my $sql = q{
        SELECT DISTINCT ds.ds_name_txt
        FROM data_sources AS ds
          JOIN selects AS s ON s.data_source_id = ds.id
          JOIN select_options AS so ON so.select_id = s.id
          JOIN counts_select_options AS cso ON cso.select_option_id = so.id
        WHERE cso.count_id = ?
      };

      my $sth = $self->dbh->prepare_cached( $sql, {}, 2 );
      $sth->execute( $args{'count_id'} );
      my $ar = $sth->fetchrow_arrayref;

      if ($ar) {
        $val = $ar->[0];
        $self->_dsn_cache->{$cache_key} = $val;
      }
    }
  }

  return $val;
}

sub invoice_query {
  my ( $self, %args ) = @_;

  my ( $where, @bind ) = $self->_parse_conditional_args(%args);

  my $end_user_lookup_table = $self->_end_user_lookup_table;

  my $sql = qq{
    SELECT
      inv.id                 AS 'Invoice',
      DATE(o.o_order_dt)     AS 'Invoice Date',
      SUM(ii.ii_total_num)   AS 'Billed Amount',
      o.o_final_cnt_num      AS 'Record Count',
      cn.c_name_txt          AS 'End User',
      cn.c_biz_name_txt      AS 'End User Company',
      cp.cp_name_txt         AS 'Marketing Company',

      c.id                   AS 'count_id',
      c.product_id           AS 'product_id'

    FROM
      invoices             AS inv
      JOIN invoice_items   AS ii  ON ii.invoice_id = inv.id
      JOIN orders          AS o   ON o.id          = ii.order_id
      JOIN counts          AS c   ON c.order_id    = o.id
      JOIN companies       AS cp  ON cp.id         = inv.company_id

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

sub non_billed_orders_query {
  my ( $self, %args ) = @_;

  my ( $where, @bind ) = $self->_parse_conditional_args(%args);

  my $end_user_lookup_table = $self->_end_user_lookup_table;

  my $sql = qq{
    SELECT
      c.id               AS 'Count ID',
      DATE(o.o_order_dt) AS 'Order Date',
      c.c_final_cnt_num  AS 'Record Count',
      cn.c_name_txt      AS 'End User',
      cn.c_biz_name_txt  AS 'End User Company',
      cp.cp_name_txt     AS 'Marketing Company',
      c.id               AS 'count_id',
      c.product_id       AS 'product_id'

    FROM
      orders         AS o
      JOIN counts    AS c   ON c.order_id    = o.id
      JOIN companies AS cp  ON cp.id         = o.company_id
      
      -- Sub query for "End User" contact.  Left join with NULL if none...
      LEFT JOIN $end_user_lookup_table AS cn ON cn.cc_count_id = c.id

    WHERE
      o.o_no_bill_fg = 1
      AND c.count_status_id >= 100
    
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

sub ordered_selects_query {
  my ( $self, %args ) = @_;

  my ( $where, @bind ) = $self->_parse_conditional_args(%args);

  my $end_user_lookup_table = $self->_end_user_lookup_table;

  # Additional conditional (hey that rhymes!)
  my $where2 = '';
  if ( $args{select_id} ) {
    my @ids;
    if ( ref( $args{select_id} ) eq 'ARRAY' ) {
      @ids = @{ $args{select_id} };
    }
    else {
      @ids = ( $args{select_id} );
    }

    $where2 = '(' . join( ' OR ', map { ' s.id = ? ' } @ids ) . ')';
    push @bind, @ids;
  }
  else {
    confess q{Query results would be too big.  No 'select_id's specified};
  }

  my $sql = qq{
    SELECT
      inv.id                 AS 'Invoice Id',
      DATE(o.o_order_dt)     AS 'Order Date',
      o.o_final_cnt_num      AS 'Records',
      cn.c_name_txt          AS 'End User',
      cn.c_biz_name_txt      AS 'End User Company',
      cp.cp_name_txt         AS 'Marketing Company',      
      s.s_display_txt        AS 'Select Name'

    FROM
      invoice_items        AS ii
      JOIN orders          AS o   ON o.id   = ii.order_id
      JOIN invoices        AS inv ON inv.id = ii.invoice_id
      JOIN companies       AS cp  ON cp.id  = inv.company_id

      JOIN counts                AS c   ON o.id  = c.order_id
      JOIN counts_select_options AS cso ON c.id  = cso.count_id
      JOIN select_options        AS so  ON so.id = cso.select_option_id
      JOIN selects               AS s   ON s.id  = so.select_id

      -- Sub query for "End User" contact.  Left join with NULL if none...
      LEFT JOIN $end_user_lookup_table AS cn ON cn.cc_count_id = c.id

    WHERE c.count_status_id >= 100
      
      AND $where
      AND $where2
      
    GROUP BY s.id, inv.id
    ORDER BY inv.id
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

### PRIVATE Methods ###

# So far, the following query methods are using this to parse the conditional
# args:
#   invoice_query,
#   non_billed_orders_query,
#   detailed_invoice_items_query,
#   ordered_selects_query
#
# We're kind of relying on some common practices for aliasing table names.
# Potentially, could be replace with long names for more widespread use.
#
# If this gets any more complicated, I'm redoing all the queries w/ DBIx::Class
#
sub _parse_conditional_args {
  my ( $self, %args ) = @_;

  my ( @cond, @bind );

  if ( $args{start_dt} ) {
    push @cond, ' o.o_order_dt >= ? ';
    push @bind, format_datetime( $args{start_dt} );
  }

  if ( $args{end_dt} ) {
    push @cond, ' o.o_order_dt <= ? ';
    push @bind, format_datetime( $args{end_dt} );
  }

  if ( $args{host_id} ) {
    my @ids;
    if ( ref( $args{host_id} ) eq 'ARRAY' ) {
      @ids = @{ $args{host_id} };
    }
    else {
      @ids = ( $args{host_id} );
    }

    push @cond, '(' . join( ' OR ', map { ' c.host_id = ? ' } @ids ) . ')';
    push @bind, @ids;
  }

  if ( $args{company_id} ) {
    my @ids;
    if ( ref( $args{company_id} ) eq 'ARRAY' ) {
      @ids = @{ $args{company_id} };
    }
    else {
      @ids = ( $args{company_id} );
    }

    push @cond, '(' . join( ' OR ', map { ' cp.id = ? ' } @ids ) . ')';
    push @bind, @ids;
  }

  if ( $args{invoice_id} ) {
    my @ids;
    if ( ref( $args{invoice_id} ) eq 'ARRAY' ) {
      @ids = @{ $args{invoice_id} };
    }
    else {
      @ids = ( $args{invoice_id} );
    }

    push @cond, '(' . join( ' OR ', map { ' inv.id = ? ' } @ids ) . ')';
    push @bind, @ids;
  }

  unless (@cond) {
    confess 'Query results would be too big.  '
      . 'No conditionals specified in query';
  }

  my $where = join ' AND ', @cond;

  return ( $where, @bind );
}

################################################################################
# Experimental - _end_user_lookup_table temporary table stuff...
################################################################################

sub _build_end_user_lookup_table {
  my $self = shift;

  my ( $table, $is_privileged );
  my $rc = 0;

  # no need to check for privileges if create_temporary_tables is false
  if ( $self->create_temporary_tables ) {
    $is_privileged = $self->dbh_has_create_temporary_table_privilege;
  }

  if ($is_privileged) {
    $table = 'temporary_end_user_lookup_table';
    $rc    = $self->create_temporary_end_user_lookup_table($table);
  }

  if ( !$is_privileged || $rc <= 0 ) {
    $table = q{
      (
        SELECT 
          cc.count_id          AS 'cc_count_id',
          cns.id               AS 'cn_id',
          cns.c_name_txt       AS 'c_name_txt',
          cns.c_biz_name_txt   AS 'c_biz_name_txt'
        FROM 
          contacts_counts    AS cc
          JOIN contacts      AS cns ON cns.id  = cc.contact_id
          JOIN contact_types AS ct  ON ct.id   = cns.contact_type_id
        WHERE
          ct.ct_desc_txt = 'End user'
      )    
    };
  }

  return $table;
}

# only a guess... maybe this is too hackish
sub dbh_has_create_temporary_table_privilege {
  my $self = shift;

  my $sql    = 'SHOW GRANTS FOR CURRENT_USER';
  my $grants = $self->dbh->selectcol_arrayref($sql);

  for my $grant ( @{$grants} ) {
    if ( $grant =~ m/GRANT ALL PRIVILEGES/
      || $grant =~ m/GRANT CREATE TEMPORARY TABLES/ )
    {
      return 1;
    }
  }
  
  carp 'Trying to create temporary table, but db user does not have '
       . 'CREATE TEMPORARY TABLES privilege.';
 
  return;
}

sub create_temporary_end_user_lookup_table {
  my ( $self, $table_name ) = @_;

  # If the temp table doesn't exist, try to create it...
  local $self->dbh->{RaiseError} = 1;
  local $self->dbh->{PrintError} = 0;
  
  my $rc1 = eval{ $self->dbh->do("SELECT * FROM $table_name LIMIT 1") };
  if ( $rc1 && ! $@ ) {
    carp 'No need to create temporary table, it seems to already exist ... '; 
    return 1;
  }

  my $sql = qq{
    CREATE TEMPORARY TABLE IF NOT EXISTS $table_name
      ( 
        cc_count_id INT PRIMARY KEY,
        c_name_txt VARCHAR(80),
        c_biz_name_txt VARCHAR(80)
      )
        SELECT DISTINCT
          cc.count_id          AS 'cc_count_id',
          cns.c_name_txt       AS 'c_name_txt',
          cns.c_biz_name_txt   AS 'c_biz_name_txt'
        FROM
          contacts_counts    AS cc
          JOIN contacts      AS cns ON cns.id  = cc.contact_id
          JOIN contact_types AS ct  ON ct.id   = cns.contact_type_id
        WHERE
          cc.count_id IS NOT NULL
          AND ct.ct_desc_txt = 'End user'
  };

  carp 'Creating temporary table...';
  
  my $start_tm = DateTime->now();
  my $rc2 = $self->dbh->do($sql);
  my $end_tm = DateTime->now();
  my $dur = $end_tm - $start_tm;
  
  carp sprintf "Elapsed time: %d:%.2d:%.2d\n", 
    $dur->hours, $dur->minutes, $dur->seconds;
    
  return $rc2;
}

1;

__END__

=pod

=head1 NAME

Rhino2::BaseSQL - Main / Common Rhino2 report queries.

=head1 VERSION

=over

=item $Id$

=item $Revision$

=item $HeadURL$

=item $Date$

=item $Source$

=back

=head1 SYNOPSIS

  my $sql = Rhino2::BaseSQL->new( dbh => $dbh );
  $sql->host_info('Name Seeker Inc.');
  ...
 
  # To Subclass...
  package Rhino2::ActivitySQL;  
  use Moose;
  extends 'Rhino2::BaseSQL';
  
=head1 DESCRIPTION

Rhino2::BaseSQL contains the majority of useful queries.  It can also be sub
classed for other reports, where the queries may be less general.

=head1 ATTRIBUTES

=over

=item B<dbh> - database handle.  required.

=item B<last_column_index> - auto generated after running a query

=item B<last_column_names> - auto generated after running a query

=item B<last_column_types> - auto generated after running a query

=item B<create_temporary_tables> - Boolean.

Try to create temporary tables ( if the user has that privilege set ).
Default is TRUE.  Set to 0 for true.

Actually, at first glance, creating a temporary table for the end user lookups
for the invoice query did not seem to improve performance.  Quite the opposite:
it seemed to slow down the query be a whole lot.  However, as soon as I indexed
the temporary table, everything sped up greatly.

You're going to take an upfront performance hit using the indexed subquery:
last I checked, it took around 20 seconds to build the temporary table.  But,
becuase the temporary table remains for the duration of the db connection,
every invoice query run for a report ( and series of reports, if you're running
all the queries in a batch off one db connection ) will run considerably 
faster.

Sweet.  I hope this keeps working...

=back

=head1 METHODS 

=over

=item B<set_column_info> ( $sth ) 

This is a private method that users of this object don't need to use.  Only
subclasses should worry about setting the column info after preparing and
executing a sql statement.

Given a DBI statement handle, this sets the last_column attributes: 
last_column_names, last_column_types, last_column_index.

=item B<host_info> ( $host_name | $host_id )

Given a host name or host id, return a hash with info about that particular
host.  The hash is keyed by the column name (lowercase).

=item B<host_names>

returns a list of all the host names (h_desc_txt)

=item B<company_info> ( $company_name | $company_id )

See host_info

=item B<company_names> 

returns a list of all the company names (cp_name_txt)

=item B<select_info> ( $select_name | $select_id )

See host_info

=item B<select_names>

returns a list of the select names ( s_display_txt )

=item B<royalty_groups> 

returns a list of all the royalty group names (rg_desc_txt)

=item B<selects_royalty_groups> ( $count_id )

Return all of the selects royalty group names (rg_desc_txt) for a particular 
count.  Returns an array or ref to an array, depending on context.

=item B<product_royalty_group> ( $product_id ) 

Returns a product royalty group name for a particular product id.

Some application level caching is done on this query for speedyups.

=item B<product_name> ( $product_id )

Returns a product name (p_name_txt) for a particular product id.

Some application level caching is done on this query for speedyups.

=item B<data_source_name> ( product_id => $product_id, count_id => $count_id ) 

Expects either a product_id or a count_id.  (Specify w/hash keys in the 
arguments.)  Returns the data source name.  

If both product_id and count_id are specified, this method first tries to get 
to the data source name through the product id. If that doesn't work ( b/c of 
a baked in select for example ), it goes through the count id.

Some application level caching is done on this query for speedyups.

=item B<monthly_invoices> ( $host_id, $date isa DateTime )

REMOVED.  Use the invoice_query instead.

=item B<invoice_query> ( %conditionals )

Main invoice query with invoice / billing information.  Only includes ordered
counts that were billed (no_bill_fg == 0). 

DateTime objects are required, and they are matched directly to the DateTime 
Mysql columns.  Usually the end_dt should include the last second of the day, to 
pull in every invoice from a particular day. 

The DateTime stuff should be easy to use if you are using the Report Period 
attribute b/c that properly handles creating start and end datetimes.

Potential Conditional Args (construed as limitations to the query): 

  start_dt  - isa DateTime, 
  end_dt    - isa DateTime, should include h/m/s, usually 23:59:59
  host_id
  company_id
  invoice_id - used to look up specific invoices
  
  # Ex:
  $sql->invoice_query( 
    start_dt   => '2008-04-20 00:00:00', # Not a string but a DateTime 
    end_dt     => '2008-04-20 23:59:59', # Not a string but a DateTime
    company_id => [ 1, 2, 3, 4 ],
    host_id    => 2,
  );

=item B<non_billed_orders_query> ( %conditionals )

Similar to Invoice query, but returns non billed orders instead.  Same 
conditional args.

=item B<ordered_selects_query> ( %conditionals )

Provides orders along with specified selects.  An additional conditional is
select_id.  If a particular count uses multiple specified selects, the count
will be included in the results more than once.  Both billed and non billed
orders are included. 

The resultset is grouped on two columns: select_id and invoice_id.

Here's an example of the nameseeker triggers query (See also, 
L<Rhino2::TriggerReport>):

  $sql->ordered_selects_query(
    start_dt   => '2008-04-20 00:00:00',
    end_dt     => '2008-04-20 23:59:59',
    host_id    => 2,
    select_id  => [ 164, 464, 207, 208 ],
  );

=item B<create_temporary_end_user_lookup_table>

This came from an experiment.  This creates a temporary table for end user 
contacts in the hopes of speeding up the invoice query.  It may be especially
useful in the Activity report which runs the invoice query 3 times.

The BaseSQL object queries the privileges of the current user logged in, 
and will only try to create a temporary table if the user has the proper 
privileges.  (There is room for some error in the privilege query).

=back

=head1 DEPENDENCIES

=over

=item B<DateTime>

=item B<DateTime::Format::MySQL>

=item B<DBD::mysql>

=item B<DBI>

=item B<Moose>

=back

=head1 AUTHOR

$Author$




