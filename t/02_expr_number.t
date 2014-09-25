#!/usr/bin/perl
# Copyright 2014 Ruslan Shvedov

# Problem 3.10 from Parsing Techniques: A Practical Guide by Grune and Jacobs 2008 (G&J)
# adapted to Marpa::R2 SLIF

use 5.010;
use strict;
use warnings;

use Test::More;

use Marpa::R2;

use_ok 'MarpaX::ASF::PFG';

#
# Unambiguous grammar to parse expressions on numbers
#
my $ug = Marpa::R2::Scanless::G->new( { source => \(<<'END_OF_SOURCE'),

:default ::= action => [ name, start, length, value ]
lexeme default = action => [ name, start, length, value ] latm => 1

    Expr ::=
          Number
        | '(' Expr ')'      assoc => group
       || Expr '**' Expr    assoc => right
       || Expr '*' Expr     # left associativity is by default
        | Expr '/' Expr
       || Expr '+' Expr
        | Expr '-' Expr

        Number ~ [\d]+

END_OF_SOURCE
} );

#
# Ambiguous grammar
#
my $ag = Marpa::R2::Scanless::G->new( { source => \(<<'END_OF_SOURCE'),

:default ::= action => [ name, start, length, value]
lexeme default = action => [ name, start, length, value] latm => 1

    Expr ::=
          Number
       | '(' Expr ')'
       | Expr '**' Expr
       | Expr '*' Expr
       | Expr '/' Expr
       | Expr '+' Expr
       | Expr '-' Expr

    Number ~ [\d]+

END_OF_SOURCE
} );

my $input = q{4+5*6+8};

# parse input with unambiguous and ambiguous grammars
# the results must be the same
for my $in ($input){

    # parse with Unambiguous G & R
    my $ur = Marpa::R2::Scanless::R->new( { grammar => $ug } );
    $ur->read(\$input);
    my $expected_ast = ${ $ur->value };
    use YAML; say Dump $expected_ast;

    # parse with Ambiguous G & R
    my $ar = Marpa::R2::Scanless::R->new( { grammar => $ag } );
    $ar->read(\$input);

    # parse forest grammar (PFG) from abstract syntax forest (ASF)
    my $pfg = MarpaX::ASF::PFG->new( Marpa::R2::ASF->new( { slr => $ar } ) );
    say $pfg->show_rules;

    # prune PFG to get the right AST
    # + - * and / are left-associative, while ** is right-associative
    $pfg->prune(
        sub {
            my ($rule_id, $lhs, $rhs) = @_;
            # The criterion would then be that for each node that has a + operator,
            # its right operand cannot be a non-terminal that has a node with a + operator.
            return (
                        $pfg->has_symbol ( $rule_id, '+') # rule has + and its right
                and not $pfg->is_terminal( $rhs->[2]    ) # operand is a non-terminal
                and     $pfg->has_symbol ( $pfg->rule_id( $rhs->[2] ), '+' ) # and has +
            );
        }
    );

    # AST from pruned PFG
    my $ast = $pfg->ast;

    is_deeply $ast, $expected_ast, "expression of numbers";

}



done_testing();
