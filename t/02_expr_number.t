#!/usr/bin/perl
# Copyright 2014 Ruslan Shvedov

# Problem 3.10 from Parsing Techniques: A Practical Guide by Grune and Jacobs 2008 (G&J)
# adapted to Marpa::R2 SLIF

use 5.010;
use strict;
use warnings;

use Test::More;

use Marpa::R2;

use Carp::Always;

use_ok 'MarpaX::ASF::PFG';

#
# Unambiguous grammar to parse expressions on numbers
#
my $ug = Marpa::R2::Scanless::G->new( { source => \(<<'END_OF_SOURCE'),

:default ::= action => [ name, value]
lexeme default = action => [ name, value] latm => 1

    Expr ::=
          Number
       || Expr '**' Expr    assoc => right
       || Expr '*' Expr     # left associativity is by default
        | Expr '/' Expr
       || Expr '+' Expr
        | Expr '-' Expr

    Number ~ [\d]+

:discard ~ whitespace
whitespace ~ [\s]+

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
       | Expr '**' Expr
       | Expr '*' Expr
       | Expr '/' Expr
       | Expr '+' Expr
       | Expr '-' Expr

    Number ~ [\d]+

:discard ~ whitespace
whitespace ~ [\s]+

END_OF_SOURCE
} );

my @input = qw{
2**7-3*10
3+5+1
6/6/6
6**6**6
3+5+1
6/6/6
6**6**6
42*2+7/3
4+5*6+8
};

# parse input with unambiguous and ambiguous grammars
# the results must be the same
for my $input (@input){

    diag $input;
    # unambiguous grammar
    my $expected_ast = ${ $ug->parse( \$input ) };
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
        sub { # return 1 if the rule needs to be pruned, 0 otherwise
            my ($rule_id, $lhs, $rhs) = @_;
            # for each rule that has a + - * / operator,
            # its right operand cannot be a non-terminal
            # that has a node with any such operator.
            for my $op (qw{ + * - / }){
                say "# checking R$rule_id for $op";
                if ( $pfg->has_symbol_at ( $rule_id, $op, 1 ) ){
                    say "$lhs has $op";
#                    for my $op_right (qw{ + * - / }){
                    for my $op_right (qw{ + * - / }){
                        if (    not $pfg->is_terminal( $rhs->[2] )
                            and $pfg->has_symbol_at ( $pfg->rule_id( $rhs->[2] ), $op_right, 1 )
                            ){
                            say "Needs pruning because $rhs->[2] has $op_right";
                            return 1;
                        }
                    }
                }
            }

            # for each rule that has a ** operator,
            # its left operand cannot be a non-terminal
            # that has a node with the same operator.
            say "# checking R$rule_id for **";
            if ( $pfg->has_symbol_at ( $rule_id, '**', 1 ) ){
                say "R$rule_id has **";
                if ( not $pfg->is_terminal( $rhs->[0] )
                    and     $pfg->has_symbol_at ( $pfg->rule_id( $rhs->[0] ), '**', 1 )
                    ){
                    say "Needs pruning";
                    return 1;
                }
            }

            return 0;
        }
    );

    say "# PFG after pruning:\n", $pfg->show_rules;

    # AST from pruned PFG
    my $ast = $pfg->ast;
    use YAML; say Dump $ast;

    is_deeply $ast, $expected_ast, $input;
}



done_testing();
