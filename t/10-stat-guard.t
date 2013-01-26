#!/usr/bin/perl -w

use strict;
use Test::More tests => 17;
use Test::Exception;
use Data::Dumper;
use Time::HiRes qw(sleep);

use Guard::Stat;

my $G = Guard::Stat->new( want_time => 1 );
lives_ok {
	$G->get_stat;
} "get_stat() is OK on empty guard";

my $pos = 0;
my $neg = 0;
is ($G->on_level(2, sub {not "POS"; $pos++}), $G, "on_level return self");
$G->on_level(-1, sub {note "NEG"; $neg++});

is ($pos, 0, "on_level(2) not called");
my $g = $G->guard;

is ($pos, 0, "on_level(2) still not called");
my $g2 = $G->guard;
is ($pos, 1, "on_level(2) called once");
is ($neg, 0, "on_level(-1) not called yet");

# sleep 0.001;
$g->finish;

note Dumper($G->get_stat);

is ($G->alive, 2, "2 items alive");
is ($G->finished, 1, "1 done");

is ($neg, 1, "on_level(-1) called once");

undef $g;
# note Dumper($G->get_time_stat);
is ($G->alive, 1, "1 item alive");
is ($neg, 1, "on_level(-1) called once");

undef $g2;
# note Dumper($G->get_time_stat);
is ($G->alive, 0, "none alive");
is ($G->finished, 1, "1 done (still)");
is ($neg, 1, "on_level(-1) called once");

note Dumper($G->get_stat);

my $stat = $G->get_stat;
is (ref $stat->{results}, 'HASH', "Fetched results");
is_deeply($stat->{results}, { ""=>1 }, "results as expected");

my $stime = 0;
$stime += $_ for values %{ $G->get_times };
is ($stime, 2, "2 time measurements");
