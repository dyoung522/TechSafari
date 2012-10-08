package TS::FtpTools;

use 5.008005;
use strict;
use warnings;

require Exporter;

use Carp;
use Net::FTP;
use Net::SCP q(scp);
use Cwd;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

our $VERSION     = '0.28';

our @EXPORT      = qw( );

our @EXPORT_OK   = ( 
    qw( &get_bookmarks &print_bookmarks ),
    qw( &get_ftp &put_ftp &list_ftp &ls_ftp &is_ftp_ready ),
    qw( &get_scp &put_scp &list_scp &ls_scp &is_scp_ready ),
    qw( &pgp_decrypt &pgp_encrypt ),
    qw( &send_mail ),
);

our %EXPORT_TAGS = (
    'all'       => [ @EXPORT, @EXPORT_OK                                      ],
    'bookmarks' => [ qw( &get_bookmarks &print_bookmarks )                    ],
    'ftp'       => [ qw( &get_ftp &put_ftp &ls_ftp &list_ftp &is_ftp_ready )  ],
    'scp'       => [ qw( &get_scp &put_scp &ls_scp &list_scp &is_scp_ready )  ],
    'pgp'       => [ qw( &pgp_decrypt &pgp_encrypt )                          ],
    'utils'     => [ qw( &send_mail )                                         ],
);

=pod

=head1 NAME

TS::FtpTools - Perl extension for transferring files between two systems

=head1 SYNOPSIS

use TS::FtpTools qw(:ftp :bookmarks :pgp);

=head1 DESCRIPTION

Provides a wrapper for the Net::FTP and Net::SCP CPAN modules for easier use in
perl scripts.

Use of perl's warning flag (-w) will cause some functions to display error
messages when encoutered.  Remove the -w when running in production if you
don't wish this output.

=head1 STRUCTURES

=over

=item Bookmark Hash

The Bookmark hash is a hash of hashes which is used by many of the fuctions
within this module to provide input.  It can be user created, or built via
an ncftp bookmark file (using get_bookmarks).

It's constructed as follows:

    $HASH = {
          ID => {              The ID for this entry
                    URL     => The URL or IP address to connect to
                    USER    => The Username to log in as
                    PASS    => The Password to use
                    PASV    => 0 == off, 1 == on
                    PORT    => The FTP port to use (default is 21)
                    RDIR    => The remote directory to CD to once connected
                    LDIR    => The local directory to CD to once connected
                    COMMENT => A Freeform text comment for this entry
                    RENAME  => If defined, any source files that are
                               sucessfully retrieved or sent are renamed to
                               include this as a suffix.  (used to rename files
                               after a transfer so we don't get them again on
                               the next run)
                }
        };

B<Please Note> most of the functions listed below only accept a single hash
reference, so you'll need to pass just the entry you wish to work with
( e.g. $HASH{ID} ).

=item @files list

This is just a normal array which contains a list of files you want to work
with.  The list may include paths relative to RDIR, absolute paths, and/or
any valid ftp file patterns.

=back

=head1 FUNCTIONS

=over

=cut

# Start of private Subroutines

# Checks for interactive terminal
sub istty() { return -t STDIN && -t STDOUT; }

# open_ftp
# 
#   Returns a Net::FTP object
#
sub open_ftp(%) {
    my %BM = %{(shift)};
    my ( $ftp, $ldir, $rdir );

    if ( not defined $BM{'URL'}  ) { croak "Invalid bookmark entry passed to " . (caller(0))[3]; }
    if ( not defined $BM{'PORT'} ) { $BM{'PORT'} = 21; }
    if ( not defined $BM{'PASV'} ) { $BM{'PASV'} = 0; }

    # Open a connection to URL
    unless ( $ftp = Net::FTP->new( $BM{'URL'}, Timeout => 30, Port => $BM{'PORT'}, Passive => $BM{'PASV'} ) ) {
        carp "Unable to connect to $BM{'URL'}\n";
        return;
    }

    # Log in
    unless ( $ftp->login( $BM{'USER'}, $BM{'PASS'} ) ) {
        carp "Unable to authenticate to $BM{'URL'}: " . $ftp->message . "\n";
        return;
    }

    $ftp->binary;  # Use binary mode

    # If we were provided with an LDIR, attempt to cwd to that directory.
    if ( defined $BM{'LDIR'} and $BM{'LDIR'} ne '' ) {
        $ldir = $BM{'LDIR'};
        chdir $ldir;
        if ( not cwd =~ /[\/]?$ldir[\/]?$/ ) {
            carp "Problem trying to CWD to $ldir on the local machine.";
        }
    }

    # If we were provided with an RDIR, attempt to cwd to that directory.
    if ( defined $BM{'RDIR'} and $BM{'RDIR'} ne '' ) {
        $rdir = $BM{'RDIR'};
        $ftp->cwd( $rdir );
        if ( not $ftp->pwd =~ /[\/]?$rdir[\/]?$/ ) {
            carp "Problem trying to CWD to $rdir on $BM{'URL'}: " . $ftp->message;
        }
    }

    return $ftp;
}

# Start of Exported Subroutine Definitions

=item get_bookmarks( <bookmark file> [, pattern [, ...]] )

Reads an NcFTP bookmark file and returns a reference to a Bookamrk Hash containing either
all bookmarks or only those matching the given pattern(s).

Returns undef if no entries are found.

=begin comment: this is the layot of the ncftp bookmarks version 8

             0 == ID,
             1 == URL,
             2 == User,
             3 == Pass,
             4 == Account,
             5 == RDir,
             6 == xferType,
             7 == Port,
             8 == Lastcall,
             9 == hasSIZE,
            10 == hasMDTM,
            11 == hasPASV,
            12 == isUnix,
            13 == lastIP,
            14 == Comment,
            15 == xferMode,
            16 == hasUTIME,
            17 == Unknown,
            18 == Unknown,
            19 == Unknown,
            20 == Unknown,
            21 == LDir,

=end

=cut

sub get_bookmarks(@) {
    require MIME::Base64;

    my ( $Bookmark_File, @Bookmark_Entries ) = @_;
    my %Bookmark = ();
    my $Bookmark_Version = 0;
    my ( $ID, $URL, $User, $Pass, $RDir, $LDir, $Port, $hasPASV, $Comment ) = ();

    if ( not defined $Bookmark_File ) { croak "usage:  get_bookmarks( <file> [entry] );"; }

    open( BM, $Bookmark_File ) or croak "Unable to open $Bookmark_File:  $!";

    while( <BM> ) {
        chomp;

        # Look for the version of the bookmark file.
        if ( /^NcFTP bookmark-file version[:]?\s+(\d+)/i ) {
            $Bookmark_Version = $1;
            next;
        }

        # Skip this line
        next if /Number of bookmarks/;

        # Read our bookmark array
        my @Bookmarks = ( split ',' );

        # Check for supported versions of the bookmark file (in case layout has changed).
        if ( $Bookmark_Version == 8 ) {
            next unless ( $ID, $URL, $User, $Pass, $RDir, $Port, $hasPASV, $Comment, $LDir ) = (@Bookmarks)[0,1,2,3,5,7,11,14,21];
        } else {
            carp "$Bookmark_File is not a supported verion (this file is version $Bookmark_Version)";
            return;
        }

        # Apply pattern matching if we were given any.
        if ( @Bookmark_Entries ) {
            my $Found = 0;
            foreach my $Entry ( @Bookmark_Entries ) {
                if ( $ID =~ /$Entry/i ) { $Found = 1; }  # Got a hit
            }
            next unless $Found;
        }

        # Validate and assign defaults to critical items

        if ( $ID eq '' ) {              # No blank ID's
            carp "Bookmark contains an invalid ID";
            next;
        }
        if ( $URL eq '' ) {             # No blank URL
            carp "URL may not be blank, record skipped";
            next;
        }

        $User    = '' if not defined $User;
        $Pass    = '' if not defined $Pass;
        $RDir    = '' if not defined $RDir;
        $LDir    = '' if not defined $LDir;
        $Comment = '' if not defined $Comment;
        $Port    = 21 unless $Port;             # Default to port 21 if it's not set
        $hasPASV = 0  unless $hasPASV;          # Default to non-passive if it's not set

        $Pass =~ s/\*encoded\*//;               # Strip off the *encoded* portion of the password.
        $Pass = MIME::Base64::decode($Pass);    # Decrypt the password via simple Base64 decode.

        $Bookmark{lc($ID)} = {
            'URL'    => "$URL",
           'USER'    => "$User",
           'PASS'    => "$Pass",
           'RDIR'    => "$RDir",
           'LDIR'    => "$LDir",
           'PORT'    => $Port,
           'PASV'    => $hasPASV,
           'COMMENT' => "$Comment",
        };
    }

    # If we found at least one bookmark, then return a reference to it.
    if ( %Bookmark ) { return \%Bookmark; }

    # Nothing found, return undef.
    return;
}

=item print_bookmarks( %bookmarks )

Prints a report of all bookmarks in Bookmark Hash to STDOUT.  Useful for looking up bookmarks.

I<Note that neither get_bookmarks nor print_bookmarks are exported by default, use :bookmarks to include them in your code>

=cut

sub print_bookmarks(%) {
    my %BM = %{$_[0]};

    return unless &istty;   # No point outputting if there's no one to see.

    if ( not %BM ) {
        carp 'usage:  print_bookmarks( \%bookmark_hash );' if $^W;
        return;
    }

    printf "%-25s %25s @ %s\n", "Bookmark ID", "User", "URL";
    print "~~~~~~~~~~~~~~~~~~~~~~~~~ ";
    print "~~~~~~~~~~~~~~~~~~~~~~~~~ ~ ";
    print "~~~~~~~~~~~~~~~~~~~~~~~~~\n";

    foreach my $ID ( sort keys %BM ) {
        printf "%-25s %25s @ %s\n", $ID, $BM{$ID}{'USER'}, $BM{$ID}{'URL'};
    }
}

=item get_ftp( \%bookmark, @files )

=item put_ftp( \%bookmark, @files )

Transfers all files in the @Files list to either the current or remote
directory using the information in bookmark reference.

@Files is a standard list of files to retrieve and may include the absolute
path or a relative path.

Returns undef on error, 1 on success and > 1 if non-fatal errors were encountered
(e.g. Local file already exists).

=cut

sub get_ftp(%@) {
    my %BM = %{(shift)};
    my @Files = @_;
    my @Valid_Files = ();
    my ( $rtime, $rsize, $ltime, $lsize ) = ();
    my $exitcode = 1;   # Our exit counter.  We'll return > 1 if a non-fatal error occurred.

    # Simple check for valid bookmark entry (i.e. not a hash of hashes).
    if ( not defined $BM{'URL'} ) { croak "Invalid bookmark entry passed to " . (caller(0))[3]; }

    # Validate our file list
    @Valid_Files = ls_ftp( \%BM, @Files );

    # Get an open Net::FTP object or return undef.
    my $ftp = open_ftp(\%BM) or return;

    # Process each file in our array
    foreach my $File ( @Valid_Files ) {

        # Get the size and modification time of the local file (if it exists)
        ( $lsize, $ltime ) = stat($File) ? (stat(_))[7,9] : (0,0);

        # Get the size and modification time of the remote file, issue an error and proceed
        # to the next file if it doesn't exist.
        unless ( $rtime = $ftp->mdtm($File) ) {
            carp "$File does not exist on $BM{'URL'}";
            $exitcode++;
            next;
        }
        $rsize = $ftp->size($File);

        # Check to be sure the remote file is different from the local file.
        if ( ( defined $rtime and defined $rsize )
               and ( ( $rtime >  $ltime )
               or  (   $rsize != $lsize ) ) ) {

            # Start the download.
            $ftp->get($File)
                or carp "Error retrieving $File: " . $ftp->message;

            if ( defined $BM{'RENAME'} ) {
                my $newFile = "$File.$BM{'RENAME'}";
                $ftp->rename( $File, $newFile )
                    or carp "Error renaming $File to $newFile: " . $ftp->message;
            }

        } else {
            print STDERR "Local file $File appears to be the same or newer than the remote, skipping download.\n" if ( &istty and $^W );
            $exitcode++;
            next;
        }

    }

    # Close the connection.
    $ftp->quit;

    # If we made it this far, return true.
    return $exitcode;
}

sub put_ftp(%@) {
    my %BM = %{(shift)};
    my @Files = @_;
    my @Valid_Files = ();
    my ( $rtime, $rsize, $ltime, $lsize ) = ();
    my $exitcode = 1;   # Our exit counter.  We'll return > 1 if a non-fatal error occurred.

    # Simple check for valid bookmark entry (i.e. not a hash of hashes).
    if ( not defined $BM{'URL'} ) { croak "Invalid bookmark entry passed to " . (caller(0))[3]; }

    # Validate our file list
    @Valid_Files = ls_ftp( {}, @Files );

    # Get an open Net::FTP object or return undef.
    my $ftp = open_ftp(\%BM) or return;

    # Process each file in our array
    foreach my $File ( @Valid_Files ) {

        # Check to be sure the local file exists
        unless ( -f $File ) {
            carp "$File does not exist in the current directory";
            $exitcode++;
            next;
        }

        # Get the size and modification time of the local file
        ( $lsize, $ltime ) = stat($File) ? (stat(_))[7,9] : (0,0);

        # Get the size and modification time of the remote file
        $rtime = $ftp->mdtm($File) or $rtime = 0;
        $rsize = $ftp->size($File) or $rsize = 0;

        # Check to be sure the local file is different from the remote file.
        if (    ( $ltime >  $rtime )
             or ( $lsize != $rsize ) ) {

            # Start the upload.
            $ftp->put($File)
                or carp "Error uploading $File: " . $ftp->message;

            if ( defined $BM{'RENAME'} ) {
                rename( $File, "$File.$BM{'RENAME'}" )
                    or carp "Error renaming $File to $File.$BM{'RENAME'}: " . $ftp->message;
            }

        } else {
            print STDERR "The remote file $File appears to be the same or newer, skipping upload.\n" if ( &istty and $^W );
            $exitcode++;
            next;
        }

    }

    # Close the connection.
    $ftp->quit;

    # If we made it this far, return true.
    return $exitcode;
}

=item ls_ftp( \%hash, @filelist )
 
Validates the files given in @filelist and Returns an array of filenames
which exist on the server specified in the %bookmark_hash.

Returns undef on error.

=cut

sub ls_ftp(%@) {
    my %BM = %{(shift)};
    my @Files = @_;
    my ( $file, $pattern, @filelist ) = ();

    # Simple check for valid bookmark entry (i.e. not a hash of hashes).
    if ( not defined $BM{'URL'} ) {     # Assume local listing

        # Check for valid files and/or patterns
        foreach $pattern ( @Files ) {
            foreach $file ( glob $pattern ) {
                if ( -f $file ) { push @filelist, $file; }
                else { carp "$file does not exist in the local dir" if $^W; }
            }
        }

    } else {                            # Remote listing

        # Get an open Net::FTP object or return undef.
        my $ftp = open_ftp(\%BM) or return;

        # Check for valid files and/or patterns
        foreach $file ( $ftp->ls(@Files) ) {
            if ( $ftp->size($file) ) { push @filelist, $file; }
            else { carp "$file on $BM{'URL'}:" . $ftp->pwd if $^W; }
        }

        # Close the connection.
        $ftp->quit;
    }

    # return the array (which may be empty).
    return @filelist;
}


=item list_ftp( \%bookmark, @files )

Returns a reference to an array of long listings (ls -lg) of each file in
@Files or every file if @Files is empty or omitted.

@Files is a standard list of files to retrieve and may include the absolute
path or a relative path and shell patterns.

Returns undef on error or an array ref on success.

=cut

sub list_ftp(%@) {
    my %BM = %{(shift)};
    my @Files = @_;

    # Simple check for valid bookmark entry (i.e. not a hash of hashes).
    if ( not defined $BM{'URL'} ) { croak "Invalid bookmark entry passed to " . (caller(0))[3]; }

    # Get an open Net::FTP object or return undef.
    my $ftp = open_ftp(\%BM) or return;

    # Fill our array with the remote listing or return undef
    my @listing = $ftp->dir(@Files) or return;

    # Close the connection.
    $ftp->quit;

    # If we made it this far, return the listing.
    return @listing;
}

=item is_ftp_ready( \%bookmark, @files )

Checks a remote FTP site for any files that may still be changing.

This is useful when watching a remote FTP site for new files, it can
be used to be sure the transfer has completed on the remote end before
we download.

@Files is a standard list of files to retrieve and may include the absolute
path or a relative path.

Returns:
undef if there was an error.
0 if there were no files.
1 if the files are ready.
2 if files are still growing.

=cut

sub is_ftp_ready(%@) {
    my %BM = %{(shift)};
    my @Files = @_;
    my %ftp_file = ();
    my $file;

    # Simple check for valid bookmark entry (i.e. not a hash of hashes).
    if ( not defined $BM{'URL'} ) { croak "Invalid bookmark entry passed to " . (caller(0))[3]; }

    # Get an open Net::FTP object or return undef.
    my $ftp = open_ftp(\%BM) or return;

    # Getting file list
    foreach $file ( $ftp->ls(@Files) ) {
        $ftp_file{$file} = $ftp->size($file);
    }

    if ( not scalar keys %ftp_file ) {
        $ftp->quit;
        return 0;
    }

    # Pause for a moment
    sleep 2;

    # Checking file sizes
    foreach $file ( keys %ftp_file ) {
        if (defined $ftp_file{$file} ) {
            if ( $ftp_file{$file} != $ftp->size($file) ) {
                print STDERR "Transfer not complete for $file\n" if ( &istty and $^W );
                $ftp->quit;
                return 2;
            }
        }
    }

    # Close the connection.
    $ftp->quit;

    # Return true if we've made it this far
    return 1;
}

=item pgp_encrypt( $pgpfile, $key )

Encrypts the file named in $pgpfile using $key.
The proper pgp key must exist on the calling users's keyring.

Returns true on sucess, undef on failure.

=cut

sub pgp_encrypt($$) {
    my ( $pgp_file, $pgp_key ) = @_;
    my $pgp_out = "${pgp_file}.pgp";
    my $pgp_bin = q(/usr/bin/gpg);
    my @pgp_cmd = ();

    if ( not -f "$pgp_bin" ) { croak "$pgp_bin not found"; }

    # Validate the key
    if ( system("$pgp_bin --quiet --list-key $pgp_key >/dev/null") != 0 ) {
        carp "$pgp_key is not a valid GnuPG key for this user.";
        return;
    }

    if ( not -f "$pgp_out" ) {  # Skip this if the output file already exists.
        @pgp_cmd = "$pgp_bin --batch --no-tty --quiet --always-trust --recipient $pgp_key --output $pgp_out --encrypt $pgp_file";
        return if ( system( @pgp_cmd ) != 0);
    } else {
        print STDERR "$pgp_out already exists, skipping encrypt.\n" if ( &istty and $^W );
    }

    return 1;
}

=item pgp_decrypt( $pgpfile, $password )

Decrypts a pgp encrypted file named in $pgpfile using $password.
The proper pgp key must exist on the calling users's keyring.

Returns true on sucess, undef on failure.

=cut

sub pgp_decrypt($$) {
    my ( $pgp_file, $pgp_pass ) = @_;
    my ( $pgp_out ) = ( $pgp_file =~ /(.*).pgp/ );
    my $pgp_bin = q(/usr/bin/gpg);
    my @pgp_cmd = ();

    if ( not -f "$pgp_bin" ) { croak "$pgp_bin not found"; }

    if ( not -f "$pgp_out" ) {  # Skip this if the output file already exists.
        @pgp_cmd = qq($pgp_bin --no-tty --skip-verify --passphrase-fd 0 --output $pgp_out --decrypt $pgp_file);
        open PGP, "|@pgp_cmd > /dev/null 2>&1" or return;
        print PGP "$pgp_pass\n";
        close PGP;
        if ( $? != 0 ) { return; }
    } else {
        print STDERR "$pgp_out already exists, skipping decrypt.\n" if ( &istty and $^W );
    }

    return 1;
}

=back

=head1 UTILITY FUNCTIONS

=over

=item send_mail( $recipient, $subject, @message );

Sends an email to $recipient with the subject $subject and @message in the body.

returns true on success, undef on failure.  Only checks the status of the
system call, does not (can not) guarantee the mail will actually be delivered.

=cut

sub send_mail($$@) {
    my ( $mail_to, $mail_subject, @mail_message ) = @_;
    my $mail_bin = q(/bin/mail);

    if ( not -x $mail_bin ) {
        carp "$mail_bin does not exist on this system, cannot send mail";
        return;
    }

    return if not defined $mail_to;
    return if not defined $mail_subject;
    return if not @mail_message;

    open MAIL, "|$mail_bin -s '$mail_subject' $mail_to"
        or croak "Error executing $mail_bin";
    print MAIL "@mail_message\n";
    close MAIL;

    return 1;
}

1;

__END__

=back

=head1 EXAMPLES

=over

=item Bookmarks example

Prints the URL associated with all bookmark entries in the file ".ncftp/bookmarks"

    #!/usr/bin/perl -w

    use TS::FtpTools q(:bookmarks);

    my $Bookmark = get_bookmarks( '.ncftp/bookmarks' );

    foreach my $Key ( sort keys %{$Bookmark} ) {
        print "The URL for $Key is $Bookmark->{$Key}{'URL'}\n";
    }

=item get_ftp example

Retrives all files ending in .pgp from /some/directory on the ftp.somedomain.com ftp site.

    #!/usr/bin/perl -w

    use TS::FtpTools q(:ftp);

    my @filepattern = q(*.pgp);
    my %ftphash = (
        'URL'  => q(ftp.somedomain.com),
        'USER' => q(ftpuser),
        'PASS' => q(ftppassword),
        'RDIR' => q(/some/directory),
    );

    my $ready = is_ftp_ready( \%ftphash, @filepattern )
            or die "Error checking files";

    print "There aren't any files matching @filepattern\n" if not $ready;

    get_ftp( \%ftphash, @filepattern ) or mydie "Unable to retrieve @filepattern" if $ready == 1;

    print "One or more files aren't ready." if $ready == 2;

=back

=head1 SEE ALSO

This modules relies heavily on Net::FTP & Net::SCP to provide the core functionality.


=head1 AUTHOR

Donovan C. Young, E<lt>dyoung@techsafari.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Donovan C. Young & TechSafari, LLC

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.5 or,
at your option, any later version of Perl 5 you may have available.


=cut
