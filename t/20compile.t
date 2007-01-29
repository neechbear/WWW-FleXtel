# $Id: 20compile.t 816 2006-11-26 19:09:52Z nicolaw $

chdir('t') if -d 't';
use lib qw(./lib ../lib);
use Test::More tests => 2;

use_ok('WWW::FleXtel');
require_ok('WWW::FleXtel');

1;

