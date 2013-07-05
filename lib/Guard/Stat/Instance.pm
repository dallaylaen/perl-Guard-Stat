use strict;
use warnings;

package Guard::Stat::Instance;

=head1 NAME

Guard::Stat::Instance - guard object base class. See L<Guard::Stat>.

=cut

our $VERSION = 0.0201;

use Carp;
use Time::HiRes qw(time);

# use fields qw(owner start done id);
# fields removed - not portable

=head2 new (%options)

Normally, new() is called by Guard::Stat->guard.

Options may include:

=over

=item * owner - the calling Guard::Stat object.

=item * want_time - whether to track execution times.

=item * id - optional context identifier.

=back

=cut

sub new {
	my $class = shift;
	my %opt = @_;

#	my __PACKAGE__ $self = fields::new($class);
	# fields::new is removed as it consumes too much CPU time

	my __PACKAGE__ $self = bless {}, $class;
	$self->{owner} = $opt{owner};
	$opt{want_time} and $self->{start} = time;

	$self->{owner}->add_stat_new($self);
	return $self;
};

=head2 end ( [$result], ... )

Mark guarded action as finished. Finish may be called only once, subsequent
calls only produce warnings.

Passing $result will alter the 'result' statistics in owner.

=cut

sub end {
	my __PACKAGE__ $self = shift;

	if (!$self->{done}++) {
	  return unless $self->{owner};
		$self->{owner}->add_stat_end($self, @_);
		# guarantee time is only written once
		if (defined (my $t = delete $self->{start})) {
			$self->{owner}->add_stat_time(time - $t);
		};
	} else {
		my $msg = $self->{done} == 2 ? "once" : "twice";
		$msg = "Guard::Stat: end() called more than $msg";
		$msg .= "; id = $self->{id}" if $self->{id};
		carp $msg;
	};
};

=head2 is_done

Tell if finish() was called on this particular guard.

=cut

sub is_done {
	my $self = shift;
	return $self->{done};
};

sub DESTROY {
	my $self = shift;
	return unless $self->{owner};

	$self->{owner}->add_stat_destroy($self, $self->{done});
	$self->{owner}->add_stat_time(time - $self->{start})
		if (defined $self->{start});
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

1;
