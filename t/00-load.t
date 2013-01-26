#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Guard::Stat' ) || print "Bail out!\n";
}

diag( "Testing Guard::Stat $Guard::Stat::VERSION, Perl $], $^X" );
