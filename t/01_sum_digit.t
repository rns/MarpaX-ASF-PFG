#!/usr/bin/perl
# Copyright 2014 Ruslan Shvedov

# Example from Parsing Techniques: A Practical Guide by Grune and Jacobs 2008 (G&J)
# 3.7.4 Parse-Forest Grammars

use 5.010;
use strict;
use warnings;

use Test::More;

use Marpa::R2;

#
# Unambiguous grammar
#
my $ug = Marpa::R2::Scanless::G->new( { source => \(<<'END_OF_SOURCE'),
:default ::= action => [ name, start, length, value]
lexeme default = action => [ name, start, length, value] latm => 1

    Sum ::= Sum '+' Sum assoc => left
    Sum ::= Digit
    Digit ~ '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'

END_OF_SOURCE
} );

#
# Ambiguous grammar (G&J Fig. 3.1.)
#
my $ag = Marpa::R2::Scanless::G->new( { source => \(<<'END_OF_SOURCE'),
:default ::= action => [ name, start, length, value]
lexeme default = action => [ name, start, length, value] latm => 1

    Sum ::= Sum '+' Sum
    Sum ::= Digit
    Digit ~ '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'

END_OF_SOURCE
} );

my $input = q{3+5+1};

# parse input with unambiguous and ambiguous grammars
# the results must be the same
for my $in ($input){

    # Unambiguous Grammar and Recognizer
    my $ur = Marpa::R2::Scanless::R->new( { grammar => $ug } );
    $ur->read(\$input);
    my $expected_ast = $ur->value;

    # Ambiguous Grammar and Recognizer
    my $ar = Marpa::R2::Scanless::R->new( { grammar => $ag } );
    $ar->read(\$input);

    # abstract syntax forest
    my $asf = Marpa::R2::ASF->new( { slr => $ar } );
    die 'No ASF' if not defined $asf;

    # prune Marpa::R2's ASF to get the right AST
    use_ok 'MarpaX::ASF::PFG';

    # parse forest grammar
    my $pfg = MarpaX::ASF::PFG->new($asf);
    isa_ok $pfg, 'MarpaX::ASF::PFG', 'pfg';

    my $pfg_index = $pfg->{pfg_index};

    # G&J 3.7.3.2 Retrieving Parse Trees from a Parse Forest:
    # + operator is left-associative, which means that a+b+c should be parsed as
    # ((a+b)+c) rather than as (a+(b+c)).
    $pfg->prune(
        # the below sub checks the PFG's rules against the above criterion
        # returning 1 if a rule meets them, 0 otherwise
        sub {
            my ($rule_id, $lhs, $rhs) = @_;
            # The criterion would then be that for each node that has a + operator,
            # its right operand cannot be a non-terminal that has a node with a + operator.
            if (        $pfg->has_symbol ( $rule_id, '+') # rule has +, its
                and not $pfg->is_terminal( $rhs->[2]    ) # right operand is a non-terminal
                and     $pfg->has_symbol ( $pfg->rule_id( $rhs->[2] ), '+' ) # and has +
                ){
                return 1;
            }
            return 0;
        }
    );

    # get AST from pruned PFG
    my $ast = $pfg->ast;
#    use YAML; say "# ast ", Dump $ast;
    is_deeply $ast, ${ $expected_ast }, "Sum of digits grammar";

}



done_testing();
