#!/usr/bin/perl

use lib qw{ lib ../lib };

use strict;
use warnings;

use Test::More qw(no_plan);
use Test::Exception;

use DirHandle;
use YAML;

use vars qw/ @config_files /;

{
  my $config_folder = '../conf';

  lives_ok (
    sub { 
      my $config_dh = DirHandle->new($config_folder);
      @config_files = $config_dh->read();
    },
    " ... reading configuration files from config folder: '$config_folder'"
  );
  
  #only test files with the correct naming convention 
  @config_files = map { "$config_folder/$_" } 
                    grep { m/^ tsr_ .* \.yml $/x } 
                    @config_files;  
  
  ok ( scalar @config_files > 1, ' ... found more than one file.' );
}

for my $config_file ( @config_files ) {
 
  lives_ok ( 
    sub {
      YAML::LoadFile( $config_file );
    },
    " ... parsing yaml configuration file: '$config_file' "
  );
  
}


