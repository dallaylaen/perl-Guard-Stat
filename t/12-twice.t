#!/usr/bin/perl -w

use strict;
use Test::More tests => 9;

use Guard::Stat;

my $G = Guard::Stat->new;

my $g = $G->guard;

my @oldwarn;
my @warn;
$SIG{__WARN__} = sub { push @warn, shift };

$g->end;
is (scalar @warn, 0, "No warn");
push @oldwarn, [@warn];

$g->end;
is (scalar @warn, 1, "Warning");
like ($warn[0], qr(Guard::Stat.*end.*once), "Warn as expected(2)");
push @oldwarn, [@warn];
@warn = ();

$g->end;
is (scalar @warn, 1, "Warning");
like ($warn[0], qr(Guard::Stat.*end.*twice), "Warn as expected(3)");
push @oldwarn, [@warn];
@warn = ();

$g->end;
is (scalar @warn, 1, "Warning");
like ($warn[0], qr(Guard::Stat.*end.*twice), "Warn as expected(4)");
push @oldwarn, [@warn];
@warn = ();

note "warnings were: ", explain @oldwarn;

is( $G->finished, 1, "Only one end() made through");
is_deeply( $G->get_stat_result, { '' => 1 }, "Check result stat");
