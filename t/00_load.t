#!/usr/bin/perl
# Copyright 2014 Ruslan Shvedov

use 5.010;
use warnings;
use strict;

use Test::More;

if (not eval { require MarpaX::ASF::PFG; 1; }) {
    Test::More::diag($@);
    Test::More::BAIL_OUT('Could not load MarpaX::ASF::PFG');
}

use_ok 'MarpaX::ASF::PFG';

done_testing();
