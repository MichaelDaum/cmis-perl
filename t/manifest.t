#!perl -T

use strict;
use warnings;
use Test::More;
use Test::DistManifest;

#unless ( $ENV{RELEASE_TESTING} ) {
#    plan( skip_all => "Author tests not required for installation" );
#}

manifest_ok();
