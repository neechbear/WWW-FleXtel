#!/usr/bin/perl -w
############################################################
#
#   $Id$
#   example.pl - WWW::FleXtel example script
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
# vim:ts=4:sw=4:tw=78

use 5.6.1;
use strict;
use warnings;
use WWW::FleXtel qw();
use Data::Dumper qw(Dumper);

my %acct = (
		account  => 'A999999',
		password => 'password',
		number   => '07010000000',
		pin      => '1234',
	);

my $flextel = WWW::FleXtel->new(%acct);

printf("Diverted to %s\n", $flextel->get_destination);
my $destination = $flextel->set_destination(destination => "0800883322");
printf("Diverted to %s\n", $destination);
    
print Dumper($flextel->phonebook);

exit;

__END__

