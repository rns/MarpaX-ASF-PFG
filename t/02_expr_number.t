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

use YAML;

use MarpaX::ASF::PFG;

#
# Unambiguous grammar to parse expressions on numbers
#
my $ug = Marpa::R2::Scanless::G->new( { source => \(<<'END_OF_SOURCE'),

:default ::= action => [ name, value]
lexeme default = action => [ name, value] latm => 1

    Expr ::=
          Number
       || '(' Expr ')'      assoc => group
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
       | '(' Expr ')'
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
3+5+1**10
6/6/6
6**6**6
3+5+1
6/6/6
6**6**6
42*2+7/3
42*2+7/3-1**5
2**7-3*10
4+5*6+8
2-1+5
2/1*5
};

# parse input with unambiguous and ambiguous grammars
# the results must be the same
for my $input (@input){

    diag $input;
    # unambiguous grammar
    my $expected_ast = ${ $ug->parse( \$input ) };
    say "# expected ast ", Dump $expected_ast;

    # parse with Ambiguous G & R
    my $ar = Marpa::R2::Scanless::R->new( { grammar => $ag } );
    $ar->read(\$input);

    # parse forest grammar (PFG) from abstract syntax forest (ASF)
    my $pfg = MarpaX::ASF::PFG->new( Marpa::R2::ASF->new( { slr => $ar } ) );

    say "# Before pruning:\n", $pfg->show_rules;

    # prune PFG to get the right AST

=pod criterion design

+ operator is left-associative, which means that a+b+c should be parsed as
((a+b)+c) rather than as (a+(b+c)).

The criterion would then be that for each node that has a + operator,
its right operand cannot be a non-terminal that has a node with a + operator.

Take into account that the first four operators are left-associative,
but the exponentiation operator ** is right-associative:
6/6/6 is ((6/6)/6) but 6 ** 6 ** 6 is (6 ** (6 ** 6)).

    + - * and / are left-associative
    ** is right-associative
    + - have higher precedence than * and /
    ** have higher precedence than + - * and /
    () have higher precedence than ** -- highest precedence

# left associativity of + - * or /
a+b+c = ((a+b)+c) != (a+(b+c))
for each node that has a + - * or / operator, its right operand
cannot be a non-terminal that has a node with that operator.

# right associativity of **
6**6**6 = (6**(6**6)) != ((6**6)**6)
for each node that has a ** operator, its left operand
cannot be a non-terminal that has a node with ** operator.

# precedence of * and / over + and -
a+b*c+d = (a+(b*c)+d) != a+b*(c+d) or (a+b)*c+d
a*b+c = ((a*b)+c) != (a*(b+c))
for each node that has a * or / operator, its right and left operands
cannot be a non-terminal that has a node with a + or - operator.

# precedence of ** over + - * and /
a**b+c = ((a**b)+c) != (a**(b+c))
for each node that has a ** operator, its right operand
cannot be a non-terminal that has a node with a + - * / operator.

# precedence of () over ** + - * and /

=cut

    $pfg->prune(
        sub { # return 1 if the rule needs to be pruned, 0 otherwise
            my ($rule_id, $lhs, $rhs) = @_;

            if (   assoc_left  ( $pfg, $rule_id, $lhs, $rhs, qw{ + - } )
                or assoc_left  ( $pfg, $rule_id, $lhs, $rhs, qw{ * / } )
                or assoc_right ( $pfg, $rule_id, $lhs, $rhs, qw{ ** } )
                ){
                return 1
            }

            # precedence of * and / over + and -
            # for each node that has a * or / operator, its right and left operands
            # cannot be a non-terminal that has a node with a + or - operator.
            for my $op_higher (qw{ * / }){
                say "\n# checking R$rule_id $lhs for higher precedence of * and / over + and -";
                if ( $pfg->has_symbol_at ( $rule_id, $op_higher, 1 ) ){
                    for my $op_lower (qw{ + - }){
                        if (    not $pfg->is_terminal( $rhs->[2] )
                            and $pfg->has_symbol_at ( $pfg->rule_id( $rhs->[2] ), $op_lower, 1 )
                            ){
                            say "  ", $pfg->show_rule($rule_id, $lhs, $rhs), " needs pruning because $rhs->[2] has $op_lower";
                            return 1;
                        }
                        elsif (    not $pfg->is_terminal( $rhs->[0] )
                            and $pfg->has_symbol_at ( $pfg->rule_id( $rhs->[0] ), $op_lower, 1 )
                            ){
                            say "  ", $pfg->show_rule($rule_id, $lhs, $rhs), " needs pruning because $rhs->[0] has $op_lower";
                            return 1;
                        }
                    }
                }
            }

            # precedence of ** over + - * and /
            for my $op_higher (qw{ ** }){
                say "\n# checking R$rule_id $lhs for higher precedence of ** over * / + -";
                if ( $pfg->has_symbol_at ( $rule_id, $op_higher, 1 ) ){
                    for my $op_lower (qw{ * / + - }){
                        if (    not $pfg->is_terminal( $rhs->[2] )
                            and $pfg->has_symbol_at ( $pfg->rule_id( $rhs->[2] ), $op_lower, 1 )
                            ){
                            say "  ", $pfg->show_rule($rule_id, $lhs, $rhs), " needs pruning because $rhs->[2] has $op_lower";
                            return 1;
                        }
                        elsif (    not $pfg->is_terminal( $rhs->[0] )
                            and $pfg->has_symbol_at ( $pfg->rule_id( $rhs->[0] ), $op_lower, 1 )
                            ){
                            say "  ", $pfg->show_rule($rule_id, $lhs, $rhs), " needs pruning because $rhs->[0] has $op_lower";
                            return 1;
                        }
                    }
                }
            }

            return 0;
        }
    );
    say "# After pruning:\n", $pfg->show_rules;

    # AST from pruned PFG
    my $ast = $pfg->ast;
    use YAML; say Dump $ast;

    is_deeply $ast, $expected_ast, $input;

}

# check rule $rule_id with $lhs, $rhs in $pfg for
# left associativity of @ops, e.g. + and - (2-1+5)
# for each node that has an operator in @ops, its right operand
# cannot be a non-terminal that has a node with that operator.
# return 1 if left associativity is broken by rule $rule_id, 0 otherwise
sub assoc_left{
    my ($pfg, $rule_id, $lhs, $rhs, @ops) = @_;
    for my $op (@ops){
        if ( $pfg->has_symbol_at ( $rule_id, $op, 1 ) ){
            for my $op_right (@ops){
                if (    not $pfg->is_terminal( $rhs->[2] )
                    and $pfg->has_symbol_at ( $pfg->rule_id( $rhs->[2] ), $op_right, 1 )
                    ){
                    return 1;
                }
            }
        }
    }
    return 0;
}

# check rule $rule_id with $lhs, $rhs in $pfg for
# right associativity of @ops, e.g. ** (6**6**6)
# for each rule that has an operator in @ops, its left operand
# cannot be a non-terminal that has a node with the same operator.
# return 1 if left associativity is broken by rule $rule_id, 0 otherwise
sub assoc_right{
    my ($pfg, $rule_id, $lhs, $rhs, @ops) = @_;
    for my $op (@ops){
        if ( $pfg->has_symbol_at ( $rule_id, $op, 1 ) ){
            for my $op_left (@ops){
                if (    not $pfg->is_terminal( $rhs->[0] )
                    and $pfg->has_symbol_at ( $pfg->rule_id( $rhs->[0] ), $op_left, 1 )
                    ){
                    return 1;
                }
            }
        }
    }
}

done_testing();
