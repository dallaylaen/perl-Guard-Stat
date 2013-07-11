#!/usr/bin/perl -w

use strict;
use Test::More tests => 15;
use Carp;

use Guard::Stats;
use Guard::Stats::Instance::Scalar;

$SIG{__WARN__} = \&Carp::confess;

my $G = Guard::Stats->new( guard_class => 'Guard::Stats::Instance::Scalar' );

my $g = $G->guard;
consistent_ok($G);
my $class = ref $g;
like ($class, qr(^Guard::Stats::Instance::Scalar::), "guard type is set");
is ($G->running, 1, "1 running instance");
ok (!$g->is_done, "is_done=0");

undef $g;
consistent_ok($G);
is ($G->running, 0, "0 running instances");
is ($G->broken, 1, "was unfinished");

$g = $G->guard;
$g->end("foo");
consistent_ok($G);
is (ref $g, $class, "Instance class is the same");
ok ( $g->is_done, "is_done=1");
is ($G->zombie, 1, "1 zombie");
is ($G->running, 0, "0 running");

undef $g;
consistent_ok($G);
is ($G->zombie, 0, "0 zombies");

is ($G->dead, 2, "All guards gone");

sub consistent_ok {
	my $stat = shift;
	my $hash = $stat->get_stat;
	note explain $hash;

	my @neg = grep { $hash->{$_} < 0 } keys %$hash;
	ok (!@neg, "No negative counters")
		or diag "Negative: @neg";
};
