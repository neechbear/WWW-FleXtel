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

$VERSION = '0.01' || sprintf('%d', q$Revision: 809 $ =~ /(\d+)/g);
$DEBUG ||= $ENV{DEBUG} ? 1 : 0;

my $objstore = {};


#
# Public methods
#

sub new {
	ref(my $class = shift) && croak 'Class name required';
	croak 'Odd number of elements passed when even was expected' if @_ % 2;

	my $self = bless \(my $dummy), $class;
	$objstore->{refaddr($self)} = {@_};
	my $stor = $objstore->{refaddr($self)};

	$stor->{validkeys} = [qw(password account pin number)];
	my $validkeys = join('|',@{$stor->{validkeys}});
	my @invalidkeys = grep(!/^$validkeys$/,grep($_ ne 'validkeys',keys %{$stor}));
	delete $stor->{$_} for @invalidkeys;
	cluck('Unrecognised parameters passed: '.join(', ',@invalidkeys))
		if @invalidkeys && $^W;

	DUMP('$self',$self);
	DUMP('$stor',$stor);
	return $self;
}


sub set_destination { &_executeQuery->{destination}; }
sub get_destination { &_executeQuery->{destination}; }
sub get_phonebook { &_executeQuery->{phonebook}; }




#
# Private methods
#

sub _getQueriesData {
	my %queries = (
		'&set_destination' => 'reroute',
		'&get_destination' => 'destination',
		'&get_phonebook' => 'destination',

		'destination' => {
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

		'reroute' => {
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

	return \%queries;
}


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
	croak 'Not called as a method by parent object'
		unless ref $self && UNIVERSAL::isa($self, __PACKAGE__);

	my $stor = $objstore->{refaddr($self)};
	my %postDataPairs = @_;

	(my $subr = (caller(1))[3]) =~ s/.*:://;
	my $queries = _getQueriesData();
	my $mode = $queries->{"&${subr}"};
	my $query = _deepCopy($queries->{$mode});

	while (my ($k,$v) = each %{$query->{data}}) {
		$query->{data}->{$k} =~ s/\@\@(\S+)\@\@/$postDataPairs{$1}/g;
	}

	my $ua = new LWP::UserAgent;
	$ua->env_proxy;
	$ua->agent('Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.8.1.1) Gecko/20060601 Firefox/2.0.0.1');
	$ua->default_header('Referer' => $query->{referer});
	$ua->timeout(10);

	my $response = $ua->post($query->{url}, $query->{data});
	if ($response->is_success) {
		my $data = _extractData($response->content);
		my $memory = _memoryLookup($data,$data->{destination});

		my $destination = '';
		$destination .= "$data->{destination}" if $data->{destination};
		$destination .= " ($memory->{title})" if $memory->{title};

		return {
				#html => $response->content,
				data => $data,
				memory => $memory,
				phonebook => $data->{memory},
				destination => $destination,
			}

	} else {
		die $response->status_line;
	}
}


sub _memoryLookup {
	my ($data, $lookup) = @_;
	$lookup = '' unless defined $lookup;
	my $memory = { destination => '', title => '', memory => '' };
	return $memory unless $lookup =~ /\S/;

	for (my $i = 1; $i < @{$data->{memory}}; $i++) {
		my $mem = $data->{memory}->[$i];
		$mem->{memory} = $i;

		if ($lookup =~ /^\d+$/ && $i == $lookup) {
			$memory = $mem;
		} elsif ($lookup =~ /\d{8,}/ && $lookup eq $mem->{number}) {
			$memory = $mem;
		} elsif ($lookup eq $mem->{title}) {
			$memory = $mem;
		}
	}

	return $memory;
}


sub _extractData {
	my $html = shift;
	my %data = (destination => '', email => '');

	for (split(/[\n\r]/,$html)) {
		chomp;
		if (my ($key,$num,$val) = $_ =~
				/^\s*FN.(email|dest_(?:no|nrb)|mem(\d+)(?:text)?)\s*=\s*(.+?)\s*;\s*$/) {
			$val =~ s/^\s*"\s*//g;
			$val =~ s/\s*"\s*$//g;

			if ($key =~ /^mem\d+$/) {
				$val =~ s/[^0-9]//g;
				$data{memory}->[$num]->{number} = $val;

			} elsif ($key =~ /^mem\d+text$/) {
				$data{memory}->[$num]->{title} = $val;

			} elsif ($key eq 'email' && $val =~ /"(\S+?)"/) {
				$data{email} = $1;

			} elsif ($key =~ /^dest_no$/) {
				($data{destination}) = $val =~ /([0-9\+\- ]{8,})/;
				$data{destination} =~ s/[^0-9]//g;
			}
		}
	}

	return \%data;
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
         account  => "A99999",
         number   => "0701773355",
         pin      => 21234",
         password => "password",
     );
 
 printf("Diverted to %s\n", $flextel->get_destination);
 $flextel->set_destination(destination => "0800883322");
 printf("Diverted to %s\n", $flextel->get_destination);
 
 print Dumper($flextel->phonebook);

=head1 DESCRIPTION

This module provides an OO interface to FleXtel telephone number
redirection webpage.

This module is still actively under development, is not yet
feature complete and still needs to be fully documented. There is
a possibility accessor method names may change before the final
release.

=head1 METHODS

=head2 new

 my $flextel = WWW::FleXtel->new(
         account  => "A99999",
         number   => "0701773355",
         pin      => 21234",
         password => "password",
     );

=head2 get_destination

 my $destination = $flextel->get_destination;
 print "Diverted to $destination\n";

=head2 set_destination

 my $destination = $flextel->set_destination(destination => "0800883322");
 print "Diverted to $destination\n";

=head2 get_phonebook

 my $phonebook = $flextel->get_phonebook;
 use Data::Dumper qw(Dumper);
 print Dumper($phonebook);

=head1 SEE ALSO

L<http://www.flextel.ltd.uk>

=head1 VERSION

$Id: DMIDecode.pm 809 2006-10-22 12:47:45Z nicolaw $

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


