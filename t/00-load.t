#!perl -T

use Test::More;

BEGIN {
  if (!eval { require "cmis.cfg"; 1 }) {
    BAIL_OUT("WARNING: You need to create a cmis.cfg. See the example file in the inc/ directory.");
  } else {
    plan tests => 1;
  }

  use_ok('WebService::Cmis');
}

diag("Testing WebService::Cmis $WebService::Cmis::VERSION, Perl $], $^X");

