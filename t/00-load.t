#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'WebService::Cmis' ) || print "Bail out!
";
}

diag( "Testing WebService::Cmis $WebService::Cmis::VERSION, Perl $], $^X" );
