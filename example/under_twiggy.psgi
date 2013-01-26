#!/usr/bin/perl -w

use strict;

# A semi-real example for Guard::Stat
# Run as `twiggy -Ilib --listen :<port> <this_file>`

# Then access the script:
# http://localhost:<port>/stat for statustics
# http://localhost:<port>/stat for time distribution
# http://localhost:<port>/ for random delay (0..1 sec)
# http://localhost:<port>/?delay=<n.n> for specific delay

# This one is quick and dirty wrt handling request. Sorry for that.

# See search.cpan.org/perldoc?PSGI for how everything works here.

use AE;
use YAML;

use Guard::Stat;
my $stat = Guard::Stat->new( want_times => 1 );

my $app = sub {
	my $env = shift;

	warn "Serving: $env->{REQUEST_URI}";

	# Diagnostic uris /stat.* for statistics, /time.* for time distribution
	if ($env->{REQUEST_URI} =~ /stat/) {
		return [200, 
			[ "Content-Type" => "text/plain" ],
			[Dump($stat->get_stat)]];
	} elsif ($env->{REQUEST_URI} =~ /time/) {
		return [200, 
			[ "Content-Type" => "text/plain" ],
			[Dump($stat->get_times)]];
	};

	# The requests - sleep for random/specific time, then say OK
	# so measure time from here!
	my $guard = $stat->guard;
	return sub {
		my $answer = shift;
		my $writer = $answer->([ 200, [ "Content-Type" => "text/plain" ]]);

		$env->{QUERY_STRING} =~ /delay=(\d+\.?\d*)/;
		my $delay = $1 || rand();
		my $timer; $timer=AE::timer $delay, undef, sub {
			$writer->write("OK $delay sec\n");
			$writer->close;
			$guard->finish();
			undef $timer;
		}; # end inner callback
	}; # end callback
};
