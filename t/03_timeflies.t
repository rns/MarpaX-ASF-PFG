#!/usr/bin/perl
# Copyright 2014 Ruslan Shvedov

# http://en.wikipedia.org/wiki/Time_flies_like_an_arrow;_fruit_flies_like_a_banana

=pod

# ambiguity: the same literal is parsed differently at different occurrences

'Fruit flies like a banana.'

    (S (NP (NN Fruit))
       (VP (VBZ flies) (PP (IN like) (NP (DT a) (NN banana))))
       (period .))
    (S (NP (NN Fruit) (NNS flies))
       (VP (VBP like) (NP (DT a) (NN banana)))
       (period .))

=cut

use 5.010;
use strict;
use warnings;

use Test::More;

use Marpa::R2;

use YAML;

use MarpaX::ASF::PFG;

my $g = Marpa::R2::Scanless::G->new( { source => \(<<'END_OF_SOURCE'),

:default ::= action => [ name, values ]
lexeme default = action => [ name, value ]

    P   ::= S+

    S   ::= NP  VP  period

    NP  ::= NN
        |   JJ  NN
        |   DT  NN
        |   NN  NNS

    VP  ::= VBP NP
        |   VBP PP
        |   VBZ PP
        |   VBZ RB

    PP  ::= IN  NP

    DT  ~ 'a' | 'an'
    NN  ~ 'arrow' | 'banana'
    NNS ~ 'flies'
    NNS ~ 'bananas'
    VBZ ~ 'flies'
    NN  ~ 'fruit':i
    VBP ~ 'fruit':i
    IN  ~ 'like'
    VBP ~ 'like'
    NN  ~ 'time':i
    VBP ~ 'time':i
    RB  ~ 'fast'
    VBP ~ 'fast'
    JJ  ~ 'fast'
    NN  ~ 'fast'
    VBP ~ 'spoil'

    period ~ '.'

:discard ~ whitespace
whitespace ~ [\s]+
END_OF_SOURCE
});

my $expected = <<'EOS';
[To be written]
EOS

# these can be used in disambiguation
# based on non-contiguous segments and morphology
#
# In addition, time flies fast.
# Time also flies fast.
# Fruit flies can spoil bananas.

my $paragraph = <<END_OF_PARAGRAPH;
Time flies like an arrow.
Time flies fast.
Fruit flies like a banana.
Fruit flies spoil banana.
END_OF_PARAGRAPH

my $r = Marpa::R2::Scanless::R->new( { grammar => $g  } );
$r->read( \$paragraph );

if ( $r->ambiguity_metric() > 1 ) {

    # abstract syntax forest
    my $asf = Marpa::R2::ASF->new( { slr => $r } );
    die 'No ASF' if not defined $asf;

    # parse forest grammar
    my $pfg = MarpaX::ASF::PFG->new($asf);
    isa_ok $pfg, 'MarpaX::ASF::PFG', 'pfg';

    say $pfg->show_rules;

    # todo: the below loop must be tests probably in a separate file
#    for my $interval ( [0, 25], [ 26, 42 ], [ 43, 69 ], [ 70, 95 ]){
#        say join "\n", map { join ', ', @$_ } @{ $pfg->intervals(  @$interval ) };
#    }

    # todo: the below line must be test for a parse subtree for symbol
#    say Dump $pfg->ast('VP_82_12');

    # todo: the below lines must be test for token and rule spans
#    say Dump $pfg->{token_spans};
#    say Dump $pfg->{rule_spans};
    say Dump $pfg->ambiguous();
}

done_testing;
