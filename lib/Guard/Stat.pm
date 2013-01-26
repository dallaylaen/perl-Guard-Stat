use strict;
use warnings;
use 5.010;

package Guard::Stat;

=head1 NAME

Guard::Stat - Guard object generator with utilisation meters.

=head1 SYNOPSIS

Suppose we have a long-running application making heavy use of closures,
and need to monitor the lifetimes of those. So...

    # in initial section
    use Guard::Stat;
    my $stat = Guard::Stat->new;

    # when running
    my $guard = $stat->guard;
    my $callback = sub {
        $guard->finish("taken route 1");
        # now do useful stuff
    };
    # ... do whatever I need and call $callback eventually

    # in diagnostic procedures started via external event
    my $data = $stat->get_stat;
    warn "$data->{running} instances still running";

=head1 METHODS

=cut

our $VERSION = '0.0101';

use Guard::Stat::Instance;

my @values;
BEGIN { @values = qw( total finished complete broken ) };

use fields
	qw(times want_time results on_level),
	@values,
	qw(log_base grades min_time);

=head2 new (%options)

%options may include:

=over

=item * want_time - gather guard lifetime statistics. See C<get_times>.

=item * log_base, grades, min_time - configure time statistics.
See C<get_times>.

=back

=cut

sub new {
	my $class = shift;
	my %opt = @_;

	$opt{log_base} ||= 10;
	$opt{grades} ||= 10;
	$opt{min_time} ||= 10**-6;

	my $self = fields::new($class);
	exists $opt{$_} and $self->{$_} = $opt{$_}
		for qw(log_base grades min_time want_time);
	$self->{$_} = 0 for @values;
	$self->{times} = [0];

	return $self;
};

=head2 Statistics

=over

=item * total - all guards ever created;

=item * dead - DESTROY was called;

=item * alive - DESTROY was NOT called;

=item * finished - finish() was called;

=item * complete - both finish() and DESTROY were called;

=item * zombie - finish() was called, but not DESTROY;

=item * running - neither finish() nor DESTROY called;

=item * broken - number of guards for which DESTROY was called,
but NOT finish().

Both broken and zombie counts usually indicate something went wrong.

=back

=cut

# create lots of identic subs
foreach (@values) {
	my $name = $_;
	my $code = sub { return shift->{$name} };
	no strict 'refs'; ## no critic
	*$name = $code;
};

sub running {
	my __PACKAGE__ $self = shift;
	return $self->{total} - $self->{finished} - $self->{broken};
};
sub alive {
	my __PACKAGE__ $self = shift;
	return $self->{total} - $self->{complete} - $self->{broken};
};
sub dead {
	my __PACKAGE__ $self = shift;
	return $self->{complete} + $self->{broken};
};
sub zombie {
	my __PACKAGE__ $self = shift;
	return $self->{finished} - $self->{complete};
};

=head2 guard()

Create a guard object.

=cut

sub guard {
	my __PACKAGE__ $self = shift;
	my %opt = @_;
	return Guard::Stat::Instance->new(
		%opt,
		want_time => $self->{want_time},
		owner => $self,
	);
};

=head2 get_stat

Get all statistics as a single hashref.

This also includes results - a hash of counts of first argument to finish().

=cut

sub get_stat {
	my __PACKAGE__ $self = shift;
	my %ret;
	$ret{$_} = $self->{$_} for @values;
	$ret{dead} = $ret{complete} + $ret{broken};
	$ret{zombie} = $ret{finished} - $ret{complete};
	$ret{alive} = $ret{total} - $ret{dead};
	$ret{running} = $ret{alive} - $ret{zombie};

	$ret{results} = { %{$self->{results} || {}} };
		# deep copy - keep encapsulation

	return \%ret;
};

=head2 on_level( $n, CODEREF )

Set on_level callback. If $n is positive, run CODEREF->($n)
when number of running guard instances is increased to $n.

If $n is negative or 0, run CODEREF->($n) when it is decreased to $n.

Normally, CODEREF should not die as it may be called within destructor.

=cut

sub on_level {
	my __PACKAGE__ $self = shift;
	my ($level, $code) = @_;
	$self->{on_level}{$level} = $code;
	return $self;
};


# Guard instance callbacks
sub _start {
	my __PACKAGE__ $self = shift;
	$self->{total}++;
	my $running = $self->running;
	if (my $code = $self->{on_level}{$running}) {
		$code->($running, $self);
	};
};

sub _finish {
	my __PACKAGE__ $self = shift;
	my ($guard, $result, @rest) = @_;
	$result //= "";

	$self->{finished}++;
	$self->{results}{$result}++;

	my $running = $self->running;
	if (my $code = $self->{on_level}{-$running}) {
		$code->($running, $self);
	};
};

# called on DESTROY if finish() called
sub _complete {
	my __PACKAGE__ $self = shift;
	$self->{complete}++;
};

# called on DESTROY if finish() NOT called
sub _broken {
	my __PACKAGE__ $self = shift;
	$self->{broken}++;
};

sub _add_time {
	my __PACKAGE__ $self = shift;
	my ($elapsed) = @_;

	my ($base, $grades, $floor) = @$self{qw(log_base grades min_time)};
	my $logtime = $elapsed
		? int(0.5 + $grades * log( $elapsed / $floor ) / log($base))
		: -1;
	if ($logtime < 0) {
		$logtime = 0;
	} else {
		$logtime++;
	};
	$self->{times}[$logtime]++;
};

=head2 get_times

Get time statistics as a hashref of
{ 0 => count0, approx_time1 => count1, approx_time2 => count2, ... }.

If want_time => 1 option is given to new, all guards will memoize the time of
their creation (via Time::HiRes::time) and send it back on finish()/DESTROY
(whichever comes first, but only once per guard).

Since average values are meaningless, and precise distribution will take up too
much memory, the following approach is used.

All received times are divided into fixed logarithmic buckets. For each bucket,
a hit count is held. These values can be then used to study the distribution,
i.e. build centiles, find peaks, and calculate average and dispersion.

Of cource, those numbers would be imprecise by a factor of bucket width,
but this is probably OK for performance analysis.

The following values are used to define the buckets:

=over

=item * min_time - all times below this are considered to be miniscule
and add up to the 0th bucket. Default: 10**-6 (1 us).

=item * log_base - logarithm base for calculating further buckets. Default: 10

=item * grades - number of buckets per base.  Default: 10

=back

The bucket width is equal to (log_base ** (1/grades)). base and grades are
only separated for convenience.

=cut

sub get_times {
	my __PACKAGE__ $self = shift;

	my ($base, $grades, $floor) = @$self{qw(log_base grades min_time)};
	my %ret;
	for (my $i = @{ $self->{times} }; $i-->1; ) {
		my $count = $self->{times}[$i] or next;
		my $key = sprintf "%0.3g", $base**(($i-1) / $grades) * $floor;
		$ret{$key} = $count;
	};
	$ret{0} = $self->{times}[0] // 0;
	return \%ret;
};

=head1 AUTHOR

Konstantin S. Uvarin, C<< <khedin at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-guard-stat at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Guard-Stat>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

		perldoc Guard::Stat


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Guard-Stat>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Guard-Stat>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Guard-Stat>

=item * Search CPAN

L<http://search.cpan.org/dist/Guard-Stat/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2013 Konstantin S. Uvarin.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Guard::Stat
