use strict;
use warnings;

package Guard::Stat::Instance::Scalar;

=head1 NAME

Guard::Stat::Instance::Scalar - Guard::Stat implementation w/o hashes.

head1 HOW IT WORKS

Guard is a blessed reference to a simple scalar (\$value). The value of
the scalar is either time, -1 if none given, or empty string if the guard
was ended. The package to which the scalar is blessed is generated on the
fly once per owner object.

So the end() and DESTROY() subs are really closed over the main stat object.

=head1 CAVEATS

The reference to the owner lives forever. This is bad and leaky.

Calling can() on the module may have misleading result
(foo->can != foo->new->can).

This module is ugly hack and highly experimental.

=cut

our $VERSION = 0.01;

use Time::HiRes qw(time);
use Carp;
use Scalar::Util qw(refaddr);

=head2 new ( owner => $object, want_time => 0|1 )

Return guard object. This is NOT really a constructor, as returned object's
type will be not match the package and actually may look like
Guard::Stat::Instance::Scalar::generated::1234567

The generated object will, however, conform to the Guard::Stat::Instance
interface.

=cut

sub new {
	my $class = shift;
	my %opt = @_;

	my $owner = $opt{owner} or die "No owner supplied";

	my $real_class = $class->_get_class( $owner );
	my $scalar = $opt{want_time} ? time : -1;
	return bless \$scalar, $real_class;
};

=head2 end ( [ $result ] )

Signal the main object that the guard has finished, optionally providing a
string denoting what was node in the end.

=head2 is_done

Return true if end() was ever called on this particular guard.

=cut


my %owners;
sub _get_class {
	my $metaclass = shift;
	my $owner = shift;

	return $owners{refaddr $owner} ||= $metaclass->_create_class( $owner );
};

sub _create_class {
	my $metaclass = shift;
	my $owner = shift;

	my $uniq = refaddr $owner;

	# create methods for metaclass
	my $end = sub {
		my $self = shift;
		if ($$self) {
			$$self > 0 and $owner and $owner->add_stat_time( time - $$self);
			$owner->add_stat_end( @_ );
			$$self = '';
		} else {
			carp( "Guard::Stat: end() called more than once (owner = $uniq)" );
		};
	};
	my $is_done = sub {
		my $self = shift;
		return !$$self;
	};
	my $destroy = sub {

		my $self = shift;
		$$self and $$self > 0
			and $owner->add_stat_time( time - $$self);
		$owner->add_stat_destroy( !$$self );
	};

	# setup metaclass - black magic be here!
	my $pkg = __PACKAGE__."::generated::".$uniq;
	no strict 'refs'; ## no critic
	*{$pkg."::end"} = $end;
	*{$pkg."::is_done"} = $is_done;
	*{$pkg."::DESTROY"} = $destroy;
	$pkg;
}; # end metaclass generator

1;
