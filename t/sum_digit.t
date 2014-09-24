use 5.010;
use strict;
use warnings;

use YAML;

use Marpa::R2;

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
#    trace_terminals => 1
} );
eval {$r->read(\$input)} || warn "Parse failure, progress report is:\n" . $r->show_progress;

my $ast = $r->value;

unless (defined $ast){
    die "No parse";
}

my $pfg_index;

if ( $r->ambiguity_metric() > 1 ){

    # gather parses
    my @asts;
    my $v = $ast;
    do {
        push @asts, ${ $v };
    } until ( $v = $r->value() );
    push @asts, ${ $v };
    # print parse trees
    say "Ambiguous: ", $#asts + 1, " parses.";
    for my $i (0..$#asts){
        say "# Parse Tree ", $i+1, ":\n", Dump $asts[$i];
    }

    # reset the recognizer (we used value() above)
    $r->series_restart();

    # create abstract syntax forest as a parse forest grammar
    my $pfg = pfg_build($r);
    say "# pfg rules before pruning\n", pfg_show_rules($pfg);

    $pfg_index = pfg_build_index($pfg);
#    say "# pfg index ", Dump $pfg_index;

    pfg_prune($pfg, \&right_associative_pruner);

    my $ast = pfg_to_ast( $pfg );
    say "# ast ", Dump $ast;
}
else{
    # print the unambiguous ast
    say Dump $ast;
}

sub pfg_build_index{
    my ($pfg) = @_;
    my $pfg_index = {};
    pfg_traverse($pfg, sub {
        my ($rule_id, $lhs, $rhs) = @_;
        # Symbol on the LHS of Rule $rule_id
        $pfg_index->{$lhs}->{lhs}->{$rule_id} = undef;
        for my $i (0..@$rhs-1){
            my $rhs_symbol = $rhs->[$i];
            # $i-th Symbol on the RHS of Rule $rule_id
            $pfg_index->{$rhs_symbol}->{rhs}->{$i}->{$rule_id} = undef;
        }
    });
    return $pfg_index;
}

# recursively remove rule $rule_id
sub pfg_prune_rule{

    my ($pfg, $rule_id) = @_;

    my ($lhs, @rhs) = @{ $pfg->[ $rule_id ] };
#    say "# pruning:\n", pfg_show_rule(undef, $rule_id, $lhs, \@rhs);

    # remove from the grammar
    splice(@$pfg, $rule_id, 1);

    # rebuild index
    $pfg_index = pfg_build_index($pfg);

    # remove other rules which become inaccessible from the top
    for my $i (0..@rhs-1){
        my $rhs_symbol = $rhs[$i];
        # check if $rhs_symbol is not on RHS of any other rule
        my $inaccessible = 1;
        pfg_traverse($pfg, sub{
            my ($rule_id, $lhs, $rhs) = @_;
            if ($inaccessible){
                for my $i (0..@$rhs-1){
                    # if $rhs_symbol exist on an RHS of any rule, it's not inaccessible
#                    say "checking $rhs_symbol vs. $rhs->[$i]";
                    if ( $rhs_symbol eq $rhs->[$i]){
#                        say "$rhs_symbol is accessible, returning...";
                        $inaccessible = 0;
                    }
                }
            }
        });
        # remove $rhs_symbol if it is found to be inaccessible
        if ( $inaccessible ){
#            say "$rhs_symbol is inaccessible";
            if ( exists $pfg_index->{$rhs_symbol}->{lhs} ){
                pfg_prune_rule( $pfg, (keys %{ $pfg_index->{$rhs_symbol}->{lhs} })[0]);
            }
        }
    }
}

sub pfg_prune{
    my ($pfg, $pruner) = @_;
    # traverse $pfg calling $pruner for each rule and marking
    # the rule for deletion if $pruner returns 1
    my @rules_to_prune;
    pfg_traverse($pfg, sub{
        my ($rule_id, $lhs, $rhs) = @_;
        if ( $pruner->($rule_id, $lhs, $rhs) ){
            push @rules_to_prune, $rule_id;
        }
    });

#    say "rules to prune: ", join ', ', map { "R$_" } @rules_to_prune;

    # remove rules to prune
    for my $rule_id (@rules_to_prune){
        pfg_prune_rule( $pfg, $rule_id );
    }

    say "# pfg rules after pruning\n", pfg_show_rules($pfg);
#    say "# pfg index after pruning", Dump $pfg_index;
}

# GJ:
# + operator is left-associative, which means that a+b+c should be parsed as
# ((a+b)+c) rather than as (a+(b+c)).
# The criterion would then be that for each node that has a + operator,
# its right operand cannot be a non-terminal that has a node with a + operator.
sub right_associative_pruner{
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

sub pfg_build{
    my ($slr) = @_;
    my $asf = Marpa::R2::ASF->new( { slr => $r } );
    die 'No ASF' if not defined $asf;
    return $asf->traverse( [], \&pfg_building_traverser );
}

sub pfg_building_traverser {

    # This routine converts the glade into a list of elements.  It is called recursively.
    my ($glade, $pfg)     = @_;

    my $rule_id     = $glade->rule_id();
    my $symbol_id   = $glade->symbol_id();
    my $symbol_name = $g->symbol_name($symbol_id);

    my ( $start, $length ) = $glade->span();
    my $suffix = '_' . $start . '_' . $length;

    # Our result will be a list of PFG rules
    my @return_value = ();

    # A token is a single choice
    # We save PFG rule to the scratch pad and return PFG symbol name
    # unless it is internal to the parse grammar in which case
    # we just return literal
    if ( not defined $rule_id ) {
        # get and wrap literal
        #my $literal = "'" . $glade->literal() . "'";
        my $literal = $glade->literal();

        # don't prepend internal symbol names
        # todo: symbol_is_internal( $symbol_id ) method for SLG
        my $literal_symbol_name = $symbol_name =~ /\[Lex/ ? '' : "$symbol_name$suffix";
        my $rv = [$literal_symbol_name];

        # save PFG rule unless the literal's symbol is internal
        # which means it has no symbol name in the parse grammar
        if ($literal_symbol_name ne ''){
            # lhs, rhs1, rhs2 ...
            unshift @$pfg, [ $literal_symbol_name, $literal ];
            return [ $literal_symbol_name ];
        }
        else{ # return literal for internal symbols
            return [ $literal ];
        }
    } ## end if ( not defined $rule_id )

    CHOICE: while (1) {

        # The results at each position are a list of choices
        # (PFG symbols or literals), so to produce a new result list,
        # we need to take a Cartesian product of all the choices
        # todo: refactor the below code to a sub
        my $length = $glade->rh_length();
        my @results = ( [] );
        for my $rh_ix ( 0 .. $length - 1 ) {
            my @new_results = ();
            for my $old_result (@results) {
                my $child_value = $glade->rh_value($rh_ix);
                for my $new_value ( @{ $child_value } ) {
                    push @new_results, [ @{$old_result}, $new_value ];
                }
            }
            @results = @new_results;
        } ## end for my $rh_ix ( 0 .. $length - 1 )

#        say "# results: ", Dump \@results;

        # Special case for the start rule
        # All PFG rules must be in the scratch pad now so we just return them
        # assuming the the first PFG's symbol is its start
        if ( $symbol_name eq '[:start]' ) {
            return $pfg;
        }

        # Now we have a list of PFG symbols, as a list of lists.  Each sub list
        # is the RHS of a PFG rule, to which we need to add the LHS
        # by PFGizing the current glade's symbol (adding _start_length)
        # and the save the PFG rule to the scratch pad (list of PFG rules).
        # The list of PFG symbols will be returned to form further PFG rules
        # unshift is used to avoid further reverse()ing because
        # the traverse order is depth-first
        my @rv = map {
#            say "# return value item", Dump $_;
            my $pfg_symbol = $symbol_name . $suffix;
            # save PFG rule
            unshift @$pfg, [ $pfg_symbol, @{$_} ];
            # return PFG symbol name
            $pfg_symbol
        } @results;
#        say "# return value: ", Dump \@rv;
        push @return_value, @rv;

        # Look at the next alternative in this glade, or end the
        # loop if there is none
        last CHOICE if not defined $glade->next();

    } ## end CHOICE: while (1)

    # Return the list of elements for this glade
    return \@return_value;
} ## end sub pfg_building_traverser

sub pfg_show_rule{
    my ($pfg, $rule_id, $lhs, $rhs) = @_;
    return "R$rule_id: " . join ' ', $lhs, '::=', @$rhs;
}

sub pfg_show_rules{
    my ($pfg) = @_;
    my @lines;
    pfg_traverse($pfg, sub {
        my ($rule_id, $lhs, $rhs) = @_;
        push @lines, pfg_show_rule($pfg, $rule_id, $lhs, $rhs);
    });
    return join "\n", @lines;
}

sub pfg_traverse{
    my ($pfg, $traverser) = @_;
    for my $i (0..@$pfg-1){
        my $rule = $pfg->[$i];
        my ($lhs, @rhs) = @$rule;
        $traverser->( $i, $lhs, \@rhs );
    }
}

sub pfg_rule_to_ast_node{

    my ($pfg, $rule_id) = @_;
    my ($pfg_lhs, @pfg_rhs) = @{ $pfg->[ $rule_id ] };

#    say "# Rule $rule_id:\n", pfg_show_rule($pfg, $rule_id, $pfg_lhs, \@pfg_rhs);

    # get ast node_id, start, length
    my @ast_lhs = split /_/, $pfg_lhs;
    my $length = pop @ast_lhs;
    my $start = pop @ast_lhs;
    my $ast_lhs = join('_', @ast_lhs);
#    say join ', ', $ast_lhs, $start, $length;

    return [
        join('_', @ast_lhs),
        $start,
        $length,
        map {
            my $pfg_rhs_symbol = $_;
#            say "pfg rhs symbol: $pfg_rhs_symbol";
            if ( exists $pfg_index->{$pfg_rhs_symbol}->{lhs} ){ # non-terminal

#                say "non-terminal $pfg_rhs_symbol";

                my $next_rule_id = (keys %{ $pfg_index->{$pfg_rhs_symbol}->{lhs} })[0];
                pfg_rule_to_ast_node( $pfg, $next_rule_id )
            }
            else{ # terminal
#                say "terminal $pfg_rhs_symbol";
                $pfg_rhs_symbol;
            }
        } @pfg_rhs
    ];
}

sub pfg_to_ast{
    my ($pfg) = @_;
    $ast = pfg_rule_to_ast_node( $pfg, 0 );
    return $ast;
}
