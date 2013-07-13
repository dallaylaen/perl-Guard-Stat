use strict;
use warnings;

package Guard::Stats;

=head1 NAME

Guard::Stats - Create guard objects and gather averall usage statistics from them.

=head1 SYNOPSIS

Suppose we have a long-running application making heavy use of closures,
and need to monitor the number of executed, not executed, and gone subrefs.

So we put a guard into each closure to update the statistics:

    # in initial section
    use Guard::Stats;
    my $stat = Guard::Stats->new;

    # when running
    my $guard = $stat->guard;
    my $callback = sub {
        $guard->finish("taken route 1");
        # now do useful stuff
    };
    # ... do whatever we need and call $callback eventually

    # in diagnostic procedures triggered by an external event
    my $data = $stat->get_stat;
    warn "$data->{running} callbacks still waiting to be executed";

Of course, alive/dead counts of any objects (not only sub refs) may be
monitored in a similar way.

=head1 DESCRIPTION

A guard is a special object that does something useful in destructor, typically
freeing a resource or lock. These guards however don't free anything. Instead,
they call home to keep their master (YOU) informed.

=head2 The classes

Guard::Stats is a long-lived object that spawns guards and
gathers statistical information.

Its public methods are guard() and various statistic getters.

Guard::Stats::Instance is the guard. When it is DESTROYed, it signals the stat
object which created it.

Its public methods are end( [$result] ) and is_done().

=head2 The counters

When a guard is created, the C<total> counter increases. When it's detroyed,
C<dead> counter increases. C<alive> = C<total> - C<dead> is the number of
guards that still exist.

Additionally, guards implement a C<end()> method which indicates that
the action associates with the guard is complete. Typically a guard should
be destroyed soon afterwards. The guards for which neither DESTROY nor
end were called are considered C<running> (this is used in C<on_level>).

The full matrix or DESTROY()/end() combinations is as follows:

    DESTROY: *        0        1
    end:*    total+   alive    dead
    end:0    ?        running  broken+
    end:1    done+    zombie   complete+

A "+" marks values directly measured by Guard::Stats. They all happen to be
monotonous. Other statistics are derived from these.

Note that counter showing end() NOT called regardless of DESTROY() does not
have a meaningful name (yet?).

=head2 Running count callback

Whenever number of guards in the C<running> state passes given level,
a function may be called. This can be used to monitor load, prevent
uncontrolled memory usage growth, etc.

See C<on_level> below.

=head1 METHODS

=cut

our $VERSION = 0.0208;

use Carp;
use Guard::Stats::Instance;

my @values;
BEGIN { @values = qw( total done complete broken ) };

use fields qw(guard_class time_stat results on_level), @values;

=head2 new (%options)

%options may include:

=over

=item * time_stat - an object or class to store time statistics. The class
should support C<new> and C<add_data( $number )> operations for this to work.
Suitable candidates are L<Statistics::Descriptive::Sparse> and
L<Statistics::Descriptive::LogScale> (both have sublinear memory usage).

=back

=cut

sub new {
	my $class = shift;
	my %opt = @_;

	my $self = fields::new($class);
	if ( my $stat = $opt{time_stat} ) {
		$stat->can("add_data")
			or croak( __PACKAGE__.": time_stat object $stat doesn't have add_data() method" );
		$self->{time_stat} = ref $stat ? $stat : $stat->new;
	};
	$self->{guard_class} = $opt{guard_class} || 'Guard::Stats::Instance';
	$self->{$_} = 0 for @values;

	return $self;
};

=head2 Statistics

The following getters represent numbers of guards in respective states:

=over

=item * total() - all guards ever created;

=item * dead() - DESTROY was called;

=item * alive() - DESTROY was NOT called;

=item * done() - end() was called;

=item * complete() - both end() and DESTROY were called;

=item * zombie() - end() was called, but not DESTROY;

=item * running() - neither end() nor DESTROY called;

=item * broken() - number of guards for which DESTROY was called,
but NOT end().

=back

Growing broken and/or zombie counts usually indicate something went wrong.

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
	return $self->{total} - $self->{done} - $self->{broken};
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
	return $self->{done} - $self->{complete};
};

=head2 guard()

Create a guard object.

=cut

sub guard {
	my __PACKAGE__ $self = shift;
	my %opt = @_;

	my $g = $self->{guard_class}->new(
		%opt,
		owner => $self,
		want_time => $self->{time_stat} ? 1 : 0,
	);
	$self->{total}++;
	my $running = $self->running;
	if (my $code = $self->{on_level}{$running}) {
		$code->($running, $self);
	};
	return $g;
};

=head2 get_stat

Get all statistics as a single hashref.

=cut

sub get_stat {
	my __PACKAGE__ $self = shift;
	my %ret;
	$ret{$_} = $self->{$_} for @values;
	$ret{dead} = $ret{complete} + $ret{broken};
	$ret{zombie} = $ret{done} - $ret{complete};
	$ret{alive} = $ret{total} - $ret{dead};
	$ret{running} = $ret{alive} - $ret{zombie};

	return \%ret;
};

=head2 get_stat_result

Provide statistics on agruments provided to end() method.

=cut

sub get_stat_result {
	my __PACKAGE__ $self = shift;

	my %ret = %{ $self->{results} };
	return \%ret;
};

=head2 get_stat_time

Return time statistics object, if any.

=cut

sub get_stat_time {
	my __PACKAGE__ $self = shift;
	return $self->{time_stat};
};

=head2 on_level( $n, CODEREF )

Set on_level callback. If $n is positive, run CODEREF->($n)
when number of running guard instances is increased to $n.

If $n is negative or 0, run CODEREF->($n) when it is decreased to $n.

CAVEAT: Normally, CODEREF should not die as it may be called within
a destructor.

=cut

sub on_level {
	my __PACKAGE__ $self = shift;
	my ($level, $code) = @_;
	$self->{on_level}{$level} = $code;
	return $self;
};


=head1 Guard instance callbacks

The following methods are called by the guard object in different stages of
its life. They should NOT be called directly (unless there's a need to fool
the stat object) and are only described for people who want to extend
the instance object.

=head2 add_stat_end( $guard, [ $result ])

=head2 add_stat_destroy( $guard, $end_was_called )

=head2 add_stat_time( $time )

=cut

sub add_stat_end {
	my __PACKAGE__ $self = shift;
	my ($result, @rest) = @_;
	$result = "" unless defined $result;

	$self->{done}++;
	$self->{results}{$result}++;

	my $running = $self->running;
	if (my $code = $self->{on_level}{-$running}) {
		$code->($running, $self);
	};
};

sub add_stat_destroy {
	my $self = shift;
	my ($is_done) = @_;

	if ($is_done) {
		$self->{complete}++;
	} else {
		$self->{broken}++;
	};
};

sub add_stat_time {
	my __PACKAGE__ $self = shift;
	my $t = shift;
	return unless $self->{time_stat};
	$self->{time_stat}->add_data($t);
};

=head1 AUTHOR

Konstantin S. Uvarin, C<< <khedin at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-guard-stat at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Guard-Stats>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

		perldoc Guard::Stats


You can also look for information at:

=over 4

=item * Github:

L<https://github.com/dallaylaen/perl-Guard-Stats>

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Guard-Stats>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Guard-Stats>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Guard-Stats>

=item * Search CPAN

L<http://search.cpan.org/dist/Guard-Stats/>

=back

=head1 ACKNOWLEDGEMENTS

This module was initially written as part of my day job at
L<http://sms-online.com>.

Vadim Vlasov was the first user of this package, and proposed
the C<zombie> counter.

=head1 SEE ALSO

L<AnyEvent> - This module was created for monitoring callback
usage in AnyEvent-driven application. However, it allows for a broadeer usage.

L<Twiggy> - A single-threaded web-server handling multiple simultaneous
requests is probably the most natural environment for callback counting. See
C<example/under_twiggy.psgi> in this distribution.

L<Devel::Leak::Cb> - Another module for finding leaked callbacks.

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Konstantin S. Uvarin.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut

1; # End of Guard::Stats
