use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'Finance::Bank::LloydsTSB',
    'VERSION_FROM'	=> 'LloydsTSB.pm', # finds $VERSION
    'PREREQ_PM'		=> {
        "WWW::Mechanize" => "0.39"}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'LloydsTSB.pm', # retrieve abstract from module
       AUTHOR     => 'Simon Cozens <simon@cpan.org>') : ()),
);
