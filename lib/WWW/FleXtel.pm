############################################################
#
#   $Id$
#   WWW::FleXtel - Manipulate FleXtel phone number redirection
#
#   Copyright 2007 Nicola Worthington
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
############################################################

package WWW::FleXtel;
# vim:ts=4:sw=4:tw=78

use 5.6.1;
use strict;
use warnings;
use LWP::UserAgent qw();
use Scalar::Util qw(refaddr);
use Carp qw(croak cluck carp confess);
use vars qw($VERSION $DEBUG);

$VERSION = '0.03' || sprintf('%d', q$Revision$ =~ /(\d+)/g);
$DEBUG ||= $ENV{DEBUG} ? 1 : 0;

my $objstore = {};


#
# Public methods
#

sub new {
	ref(my $class = shift) && croak 'Class name required';
	croak 'Odd number of elements passed when even was expected' if @_ % 2;

	# Conjure up an invisible object 
	my $self = bless \(my $dummy), $class;
	$objstore->{refaddr($self)} = {@_};
	my $stor = $objstore->{refaddr($self)};

	# Define what parameters are valid for this constructor
	$stor->{validkeys} = [qw(password account pin number)];
	my $validkeys = join('|',@{$stor->{validkeys}});

	# Only accept sensible known parameters from punters
	my @invalidkeys = grep(!/^$validkeys$/,grep($_ ne 'validkeys',keys %{$stor}));
	delete $stor->{$_} for @invalidkeys;
	cluck('Unrecognised parameters passed: '.join(', ',@invalidkeys))
		if @invalidkeys && $^W;

	# Set some default values
	$stor->{timeout} ||= 15; # 15 seconds
	$stor->{cache_ttl} ||= 5; # Cache data for 5 seconds
	$stor->{'user-agent'} ||= sprintf('Mozilla/5.0 (X11; U; Linux i686; '.
				'en-US; rv:1.8.1.1) Gecko/20060601 Firefox/2.0.0.1 (%s %s)',
				__PACKAGE__, $VERSION);

	# Create LWP object
	my $ua = new LWP::UserAgent;
	$ua->env_proxy;
	$ua->agent($stor->{'user-agent'});
	$ua->timeout($stor->{timeout});
	$ua->max_size(1024 * 200); # Hard code at 200KB
	$stor->{ua} = $ua;

	DUMP('$self',$self);
	DUMP('$stor',$stor);
	return $self;
}


sub set_destination { &_executeQuery; }
sub get_destination { &_executeQuery; }
sub get_phonebook   { &_executeQuery; }
sub get_email       { &_executeQuery; }




#
# Private methods
#

sub _deepCopy{
	my $this = shift;
	if (!ref($this)) {
		$this;
	} elsif (ref($this) eq 'ARRAY') {
		[ map _deepCopy($_), @{$this} ];
	} elsif (ref($this) eq 'HASH'){
		scalar { map { $_ => _deepCopy($this->{$_}) } keys %{$this} };
	} else {
		confess "What type is $_?";
	}
}


sub _executeQuery {
	my $self = shift;
	local $Carp::CarpLevel = 1;
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	# Retrieve our object data stor and merge
	# parameters from this method and the constructor
	my $stor = $objstore->{refaddr($self)};
	my %params = @_;
	for my $k (@{$stor->{validkeys}}) {
		$params{$k} = $stor->{$k}
			unless defined $params{$k};
	}

	# Figure out what method and personality we're running as
	(my $subr = (caller(1))[3]) =~ s/.*:://;
	my ($readCache,$cacheName) = split(/_/,$subr);
	$readCache = 0 unless $readCache eq 'get';

	# Return from a cache if possible
	if ($readCache) {
		my $cache = $self->_readCache("$cacheName*$params{number}");
		if (defined $cache) {
			TRACE("Returning cache '$cacheName*$params{number}' ...");
			return $cache;
		}
	}

	# Get the post query data required to send to the server
	my ($mode,$query) = _getQueryData($subr);
	TRACE("Running _executeQuery() in $mode mode ...");
	DUMP('$query',$query);

	# Substitute keywords for data values
	while (my ($k,$v) = each %{$query->{data}}) {
		$query->{data}->{$k} =~ s/\@\@(\S+)\@\@/$params{$1}/g;
	}

	# Post the request to the server
	my $ua = $stor->{ua};
	$ua->default_header('Referer' => $query->{referer});

	my $response;
	if ($query->{method} eq 'GET') {
		my $url = join('?',$query->{url}, join('&', map
				{ "$_=$query->{data}->{$_}" } keys %{$query->{data}}));
		TRACE("GET $url");
		$response = $ua->get($url);

	} else { # Default to POST
		TRACE("POST $query->{url}");
		$response = $ua->post($query->{url}, $query->{data});
	};

	# Process and parse the HTML response if the request was successfull
	if ($response->is_success) {
		my $data = _extractData($response->content);
		for my $cacheName (keys %{$data}) {
			if (defined $data->{$cacheName}) {
				$self->_writeCache("$cacheName*$params{number}", $data->{$cacheName});
			}
		}
		return $data->{$cacheName};

	# Otherwise croak and die horribly
	} else {
		croak $response->status_line;
	}
}


sub _readCache {
	my ($self,$cacheName) = @_;
	my $stor = $objstore->{refaddr($self)};

	TRACE("Checking age of cache '$cacheName' ...");
	if (defined $stor->{cache}->{$cacheName}->{'last_updated'} &&
			time - $stor->{cache}->{$cacheName}->{'last_updated'}
			< $stor->{'cache_ttl'}) {
		TRACE("Reading cache '$cacheName' ...");
		return $stor->{cache}->{$cacheName}->{'data'};
	}
	return;
}


sub _writeCache {
	my ($self,$cacheName,$ref) = @_;
	my $stor = $objstore->{refaddr($self)};

	TRACE("Writing cache '$cacheName' ...");
	$stor->{cache}->{$cacheName}->{'last_updated'} = time;
	$stor->{cache}->{$cacheName}->{'data'} = $ref;
}


sub _phonebookLookup {
	my ($phonebook, $lookup) = @_;
	$lookup = '' unless defined $lookup;
	my $memory = { destination => '', title => '', memory => '' };
	return $memory unless $lookup =~ /\S/;

	for (my $i = 1; $i < @{$phonebook}; $i++) {
		my $mem = $phonebook->[$i];
		$mem->{memory} = $i;

		if ($lookup =~ /^\d+$/ && $i == $lookup) {
			$memory = $mem;
		} elsif ($lookup =~ /[0-9\#\+]{8,}/ && $lookup eq $mem->{number}) {
			$memory = $mem;
		} elsif ($lookup eq $mem->{title}) {
			$memory = $mem;
		}
	}

	return $memory;
}


sub _extractData {
	my $html = shift;
	my %data;

	if ($html =~ /^\s*([0-9\#\+]{8,})\s*$/s) {
		$data{destination} = $1;
		return \%data;
	}

	for (split(/[\n\r]/,$html)) {
		chomp;
		if (my ($key,$num,$val) = $_ =~
				/^\s*FN.(email|dest_(?:no|nrb)|mem(\d+)(?:text)?)\s*=\s*(.+?)\s*;\s*$/) {
			$val =~ s/^\s*"\s*//g;
			$val =~ s/\s*"\s*$//g;

			if ($key =~ /^mem\d+$/) {
				$val =~ s/[^0-9\#]//g;
				$data{phonebook}->[$num]->{number} = $val;

			} elsif ($key =~ /^mem\d+text$/) {
				$data{phonebook}->[$num]->{title} = $val;

			} elsif ($key eq 'email' && $val =~ /"(\S+?)"/) {
				$data{email} = $1;

			} elsif ($key =~ /^dest_no$/) {
				($data{destination}) = $val =~ /([0-9\#\+]{8,})/;
				$data{destination} =~ s/[^0-9\#]//g;
			}
		}
	}

	return \%data;
}


sub _getQueryData {
	my $subr = shift;

	my %subrMap = (
			'set_destination' => 'divert_simple',
			'get_destination' => 'getpin_simple',
			'get_phonebook'   => 'getpin_post',
			'get_email'       => 'getpin_post',
		);

	my %queries = (
		'getpin_simple' => {
			'method' => 'GET',
			'url' => 'https://www.flextel.ltd.uk/cgi-bin/reroute.sh',
			'referer' => '',
			'data' => {
				'mode'    => 'getpin',
				'flextel' => '@@number@@',
				'pin'     => '@@pin@@',
				'alt'     => 'simple',
			},
		},
		'getpin_post' => {
			'method' => 'POST',
			'url' => 'https://www.flextel.ltd.uk/cgi-bin/reroute.sh',
			'referer' => 'https://www.flextel.ltd.uk/cgi-bin/reroute.sh?flextel=',
			'data' => {
				'mode'    => 'getpin',
				'flextel' => '@@number@@',
				'cust_id' => '',
				'pwd'     => '',
				'flexnum' => '@@number@@',
				'pin'     => '@@pin@@',
				'Logon'   => 'Logon',
			},
		},
		'divert_simple' => {
			'method' => 'GET',
			'url' => 'https://www.flextel.ltd.uk/cgi-bin/reroute.sh',
			'referer' => '',
			'data' => {
				'mode'     => 'divert',
				'flextel'  => '@@number@@',
				'pin'      => '@@pin@@',
				'new_dest' => '@@destination@@',
				'dest_nrb' => '',
				'alt'      => 'simple',
			},
		},
		'divert_post' => {
			'method' => 'POST',
			'url' => 'https://www.flextel.ltd.uk/cgi-bin/reroute.sh',
			'referer' => 'https://www.flextel.ltd.uk/cgi-bin/reroute.sh',
			'data' => {
				'f'               => '',
				'h'               => '',
				'alt'             => '',
				'source'          => '',
				'mode'            => 'divert',
				'flextel'         => '@@number@@',
				'pin'             => '@@pin@@',
				'pwd'             => '',
				'new_dest'        => '@@destination@@',
				'dest_nrb'        => '',
				'nba'             => '3Ba',
				'start'           => '',
				'present'         => 'false',
				'mask'            => 'false',
				'SelectDest'      => '@@destination@@',
				'SelectNRB'       => 'null',
				'checkboxBusy'    => 'checkbox',
				'selectTimeoutNR' => '3',
			},
		},
	);

	my $mode = $subrMap{$subr};
	return ($mode, _deepCopy($queries{$mode}));
}


sub DESTROY {
	my $self = shift;
	delete $objstore->{refaddr($self)};
}


sub TRACE {
	return unless $DEBUG;
	carp(shift());
}


sub DUMP {
	return unless $DEBUG;
	eval {
		require Data::Dumper;
		no warnings 'once';
		local $Data::Dumper::Indent = 2;
		local $Data::Dumper::Terse = 1;
		carp(shift().': '.Data::Dumper::Dumper(shift()));
	}
}


1;



=pod

=head1 NAME

WWW::FleXtel - Manipulate FleXtel phone number redirection

=head1 SYNOPSIS

 use strict;
 use WWW::FleXtel qw();
 use Data::Dumper qw(Dumper);
 
 my $flextel = WWW::FleXtel->new(
         number   => "0701776655",
         pin      => "1234",
         account  => "A99999",
         password => "password",
     );
 
 printf("Diverted to %s\n", $flextel->get_destination);
 $flextel->set_destination(destination => "01923001122");
 printf("Diverted to %s\n", $flextel->get_destination);
 
 print Dumper($flextel->get_phonebook);

=head1 DESCRIPTION

This module provides a very basic OO interface to FleXtel telephone
number redirection webpage.

=head1 METHODS

=head2 new

 my $flextel = WWW::FleXtel->new(
         number   => "0701776655",
         pin      => "1234",
         account  => "A99999",
         password => "password",
     );

Create a new WWW::FleXtel object. Currently the I<account> and
I<password> parameters are unsed and therefor do not need to be passed
to this constructor method.

This method does have any mandatory parameters. However values passed
this constructor method will be used as default fallback values if they
are not passed to the subsequent accessor methods detailed below.

=head2 get_destination

 my $destination = $flextel->get_destination;
 print "Diverted to $destination\n";

Retrieves the destination telephone number that your FleXtel number is
currently diverted to.

=head2 set_destination

 my $destination = $flextel->set_destination(destination => "01923001122");
 print "Diverted to $destination\n";

Sets the destination telephone number that your FleXtel number is
diverted to.

=head2 get_phonebook

 my $phonebook = $flextel->get_phonebook;
 use Data::Dumper qw(Dumper);
 print Dumper($phonebook);
 
 my $destination = $flextel->get_destination;
 my ($person) = grep(/\S/, map {
         $_->{title} if defined $_ && $_->{number} eq $destination
     } @{$phonebook}) || "*not recorded*";
 print "$destination is $person in your phonebook\n";

This method extracts the indexes, names and numbers from your FleXtel
number's phonebook. This method has the potential to stop working in
the future since it gathers the information by performing very basic
parsing of the JavaScript object assignments on your FleXtel number's
rerouting webpage.

=head2 get_email

 my $notification_address = $flextel->get_email;

This method returns the notification email address currently assigned
to your FleXtel number. Like the I<get_phonebook> method, this method
has the potential to stop working in the future if your FleXtel
number's rerouting webpage changes significantly.

=head1 SEE ALSO

L<http://www.flextel.ltd.uk>

=head1 VERSION

$Id$

=head1 AUTHOR

Nicola Worthington <nicolaw@cpan.org>

L<http://perlgirl.org.uk>

If you like this software, why not show your appreciation by sending the
author something nice from her
L<Amazon wishlist|http://www.amazon.co.uk/gp/registry/1VZXC59ESWYK0?sort=priority>? 
( http://www.amazon.co.uk/gp/registry/1VZXC59ESWYK0?sort=priority )

=head1 COPYRIGHT

Copyright 2007 Nicola Worthington.

This software is licensed under The Apache Software License, Version 2.0.

L<http://www.apache.org/licenses/LICENSE-2.0>

=cut


__END__


