use 5.008005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'TS::FtpTools',
    VERSION_FROM      => 'lib/TS/FtpTools.pm', # finds $VERSION
    PREREQ_PM         => { 'Net::FTP' => 0, 'Net::SCP' => 0 }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/TS/FtpTools.pm', # retrieve abstract from module
       AUTHOR         => 'Donovan C. Young <dyoung@techsafari.com>') : ()),
);
