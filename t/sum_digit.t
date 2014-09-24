use 5.010;
use strict;
use warnings;

use YAML;

use Marpa::R2;

use Test::More;

my $g = Marpa::R2::Scanless::G->new( {
    source => \(<<'END_OF_SOURCE'),
:default ::= action => [ name, start, length, value]
lexeme default = action => [ name, start, length, value] latm => 1

    Sum ::= Digit
    Sum  ::= Sum '+' Sum
    Digit ~ '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'

:discard ~ whitespace
whitespace ~ [\s]+
END_OF_SOURCE
} );

my $input = <<EOI;
3+5+1
EOI

my $r = Marpa::R2::Scanless::R->new( {
    grammar => $g,
} );
eval {$r->read(\$input)} || warn "Parse failure, progress report is:\n" . $r->show_progress;

my $expected_ast = $r->value;

unless (defined $expected_ast){
    die "No parse";
}

if ( $r->ambiguity_metric() > 1 ){

    # gather parses
    my @asts;
    my $v = $expected_ast;
    do {
        push @asts, ${ $v };
    } until ( $v = $r->value() );
    push @asts, ${ $v };
    # print parse trees
#    diag "Ambiguous: ", $#asts + 1, " parses.";
    for my $i (0..$#asts){
#        say "# Parse Tree ", $i+1, ":\n", Dump $asts[$i];
    }

    # reset the recognizer (we used value() above)
    $r->series_restart();

    my $asf = Marpa::R2::ASF->new( { slr => $r } );
    die 'No ASF' if not defined $asf;

    # create abstract syntax forest as a parse forest grammar
    use MarpaX::ASF::PFG;
    my $pfg = MarpaX::ASF::PFG->new($asf);
    my $pfg_index = $pfg->{pfg_index};

    $pfg->prune(
        # GJ:
        # + operator is left-associative, which means that a+b+c should be parsed as
        # ((a+b)+c) rather than as (a+(b+c)).
        # The criterion would then be that for each node that has a + operator,
        # its right operand cannot be a non-terminal that has a node with a + operator.
        sub {
            my ($rule_id, $lhs, $rhs) = @_;
        #    say "# pruning rule: ", pfg_show_rule(undef, $rule_id, $lhs, $rhs);
            # check if the node has a + operator (literals are wrapped in ''s)
            if ( exists $pfg_index->{"+"}->{rhs}->{1}->{$rule_id} ){
        #        say "# has '+':\n", pfg_show_rule(undef, $rule_id, $lhs, $rhs);
                # its right operand cannot be a non-terminal that has a node with a + operator.
                my $r_op = $rhs->[2];
        #        say "# right operand:\n", $r_op;
                # check if $r_op is a non-terminal
                if (exists $pfg_index->{$r_op}->{lhs}){
        #            say "is a non-terminal.";
                    # check if $r_op has a + operator
                    my $r_op_rule_id = (keys %{ $pfg_index->{$r_op}->{lhs} })[0];
        #            say "right operand rule id: $r_op_rule_id";
                    if ( exists $pfg_index->{"+"}->{rhs}->{1}->{$r_op_rule_id} ){
        #                say "right operand has +!";
                        return 1;
                    }
                }
            }
            return 0;
        }
    );

    my $ast = $pfg->ast;
#    say "# ast ", Dump $ast;
    is_deeply $ast, ${ $expected_ast }, "Sum of digits grammar";
}

done_testing();
