#!/usr/bin/perl
# Copyright 2014 Ruslan Shvedov

# Adapted from balanced parenthesis example in
# http://marvin.cs.uidaho.edu/Teaching/CS445/grammar.html

use 5.010;
use strict;
use warnings;

use Test::More;

use Marpa::R2;

use MarpaX::ASF::PFG;

my $g = Marpa::R2::Scanless::G->new( { source => \(<<'END_OF_SOURCE'),

:default ::= action => [ name, values ]
lexeme default = action => [ name, value ] latm => 1

    S       ::= '"' quoted '"'
    quoted  ::= item | quoted item
    item    ::= S | unquoted

    unquoted ~ [^"]+ # "


END_OF_SOURCE
} );

my @input = (
    '"these are "words in typewriter double quotes" and then some"',
    '"these are "words in "nested typewriter double" quotes" and then some"',
    '"these are "words in "nested "and even more nested" typewriter double" quotes" and then some"'
);

for my $input (@input){
    warn "# $input";

    my $r = Marpa::R2::Scanless::R->new( { grammar => $g } );
    $r->read(\$input);

    # this will need to use to define pruning criterion
    #
    # abstract syntax forest (ASF)
    my $asf = Marpa::R2::ASF->new( { slr => $r } );
    die 'No ASF' if not defined $asf;

    # parse-forest grammar (PFG) from ASF
    my $pfg = MarpaX::ASF::PFG->new($asf);
    isa_ok $pfg, 'MarpaX::ASF::PFG', 'pfg';

    say "# before pruning:\n", $pfg->show_rules;
}

done_testing();
