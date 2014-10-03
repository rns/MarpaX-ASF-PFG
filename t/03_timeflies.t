#!/usr/bin/perl
# Copyright 2014 Ruslan Shvedov

# http://en.wikipedia.org/wiki/Time_flies_like_an_arrow;_fruit_flies_like_a_banana

=pod

'Time flies like an arrow.'

# parse trees
(S (NP (NN Time))
   (VP (VBZ flies) (PP (IN like) (NP (DT an) (NN arrow))))
   (period .))
(S (NP (NN Time) (NNS flies))
   (VP (VBP like) (NP (DT an) (NN arrow)))
   (period .))

# literal, parse (sub)trees, cause
time flies
    (NN Time) (VBZ flies)
    (NP (NN Time) (NNS flies))
(VBZ NNS flies)

# literal, parse (sub)trees, cause
like an arrow
    (PP (IN like) (NP (DT an) (NN arrow)))
    (VP (VBP like) (NP (DT an) (NN arrow)))
(IN VPB like)

# Ambiguity markup
(Time (VBZ NNS flies)) ((IN VPB like) an arrow).

# ambiguity: the same literal is parsed differently at different occurrences

$token_intervals = 'start_end1 start_end2' # sorted by start, search by index()
%rule_intervals->{start_end} = literal
interval tree (unique intervals)

# if more than 2 symbol_start_length, ambiguous token or rule literal
$start->{length}->{symbol_start_length1}
$start->{length}->{symbol_start_length2}

my @ambiguous_items = sub $pfg->ambiguous($code)
my $rv = $pfg->ambiguous(sub{ ($pfg, $literal, $cause, @parses) = @_ ... })
# trace all ambiguous literals to ambiguous tokens which caused them
# and show how differently they are parsed
for each $token literal $start
    for each $rule literal which also has $start
    if
        there is a sequence of token intervals starting with $token
        which covers the entire $rule interval
        start with first token
            find next token starting first after end(start+length) of the previous token

        my @intervals = $tree->fetch_window(rule_interval)
        filter out rule intervals (exists $rules_literals->{start})

        if join(' ', @intervals) is part of $token_intervals
            get ambiguous token(s)  # cause(s)
                no ambiguous token(s) -- no ambiguity, return
            get for the rule interval
                parse (sub)trees    # (NP (NN Time) (NNS flies))
                token spans         # (NN Time) (VBZ flies)

            # this should trace all ambiguous literals
            # to ambiguous tokens
            # but there can be trees of ambiguous literals

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

    # print ASTs
#    while ( defined( my $value_ref = $r->value() ) ) {
#        say Dump ${ $value_ref };
#    }

    # reset the recognizer (we used value() above)
    $r->series_restart();

    # abstract syntax forest
    my $asf = Marpa::R2::ASF->new( { slr => $r } );
    die 'No ASF' if not defined $asf;

    # parse forest grammar
    my $pfg = MarpaX::ASF::PFG->new($asf);
    isa_ok $pfg, 'MarpaX::ASF::PFG', 'pfg';

    say $pfg->show_rules;
#    say "# attributes: ", Dump $pfg->{pfg_atts};

    say '---';
    # todo: the below loop must be tests
#    for my $interval ( [0, 25], [ 26, 42 ], [ 43, 69 ], [ 70, 95 ]){
#        say join "\n", map { join ', ', @$_ } @{ $pfg->intervals(  @$interval ) };
#    }

    # VP_82_12
    # todo: the below line must be test
    # say Dump $pfg->ast('VP_82_12');

}

done_testing;
