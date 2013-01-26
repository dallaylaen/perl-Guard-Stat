use strict;
use warnings;

package Guard::Stat::Instance;

=head1 NAME

Guard::Stat::instance - guard object base class. See L<Guard::Stat>.

=cut

our $VERSION = 0.01;

use Carp;
use Time::HiRes qw(time);

use fields qw(owner start done id);

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

	my __PACKAGE__ $self = fields::new($class);
	exists $opt{$_} and $self->{$_} = $opt{$_} for qw(id owner);
	$opt{want_time} and $self->{start} = time;

	$self->{owner}->_start($self);
	return $self;
};

=head2 finish ( [$result], ... )

Mark guarded action as finished.

Passing $result will alter the 'result' statistics in owner.

=cut

sub finish {
	my __PACKAGE__ $self = shift;

	if (!$self->{done}++) {
	  return unless $self->{owner};
		$self->{owner}->_finish($self, @_);
		$self->{owner}->_add_time(time - $self->{start})
			if (defined $self->{start});
	} else {
		my $msg = "twice";
		if ($self->{done} == 2) {
			$msg = "once";
		};
		$msg = "Guard::Stat: finish() called more than $msg";
		$msg .= "; id = $self->{id}" if $self->{id};
		carp $msg;
	};
};

sub DESTROY {
	my $self = shift;
	return unless $self->{owner};
	if (!$self->{done}) {
		$self->{owner}->_add_time(time - $self->{start})
			if (defined $self->{start});
		$self->{owner}->_broken($self);
	} else {
		$self->{owner}->_complete($self);
	};
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
