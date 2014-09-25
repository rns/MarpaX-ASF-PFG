package MarpaX::ASF::PFG;

use 5.010;
use strict;
use warnings;

use YAML;

use Marpa::R2;

sub new {
    my ($class, $asf) = @_;

    my $self = {};
    bless $self, $class;

    $self->{asf} = $asf;
    my $g = $asf->grammar();

    my $pfg = $asf->traverse( [], sub{
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
                $self->{start} = $pfg->[0]->[0];
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
    } );

    # delete duplicate rules
    my %rules;
    my @unique_rules;
    for my $i (0..@$pfg-1){
        my $rule = $pfg->[$i];
        my ($lhs, @rhs) = @$rule;
        my $rule_shown = join ' ', $lhs, '::=', @rhs;
#        say "Rule: $rule_shown";
        push @unique_rules, $rule unless exists $rules{$rule_shown};
        $rules{$rule_shown} = undef;
    }
    $self->{pfg} = \@unique_rules;
#    say "# pfg rules before pruning\n", $self->show_rules;

    my $pfg_index = $self->build_index;
#    say "# pfg index ", Dump $pfg_index;

    $self->{pfg_index} = $pfg_index;

    return $self;
}

sub has_symbol_at{
    my ($self, $rule_id, $symbol, $at) = @_;
    return exists $self->{pfg_index}->{$symbol}->{rhs}->{$at}->{$rule_id};
}

sub is_terminal{
    my ($self, $symbol) = @_;
    return not exists $self->{pfg_index}->{$symbol}->{lhs};
}

sub rule_id{
    my ($self, $lhs) = @_;
    return ( keys %{ $self->{pfg_index}->{$lhs}->{lhs} } )[ 0 ];
}

sub build_index{
    my ($self) = @_;

    my $pfg = $self->{pfg};
    my $pfg_index = {};

    $self->enumerate( sub {
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
sub prune_rule{

    my ($self, $rule_id) = @_;
    my $pfg = $self->{pfg};

    my ($lhs, @rhs) = @{ $pfg->[ $rule_id ] };
    say "# pruning:\n", pfg_show_rule(undef, $rule_id, $lhs, \@rhs);

    # remove from the grammar
    splice(@$pfg, $rule_id, 1);

    # rebuild index
    my $pfg_index = $self->{pfg_index} = $self->build_index($pfg);

    # remove other rules which become inaccessible from the top
    for my $i (0..@rhs-1){
        my $rhs_symbol = $rhs[$i];
        # check if $rhs_symbol is not on RHS of any other rule
        my $inaccessible = 1;
        $self->enumerate( sub{
            my ($rule_id, $lhs, $rhs) = @_;
            if ($inaccessible){
                for my $i (0..@$rhs-1){
                    # if $rhs_symbol exist on an RHS of any rule, it's not inaccessible
                    say "checking $rhs_symbol vs. $rhs->[$i]";
                    if ( $rhs_symbol eq $rhs->[$i]){
                        say "$rhs_symbol is accessible, returning...";
                        $inaccessible = 0;
                    }
                }
            }
        });
        # remove $rhs_symbol if it is found to be inaccessible
        if ( $inaccessible ){
            say "$rhs_symbol is inaccessible, pruning...";
            if ( exists $pfg_index->{$rhs_symbol}->{lhs} ){
                $self->prune_rule( (keys %{ $pfg_index->{$rhs_symbol}->{lhs} })[0]);
            }
        }
    }
}

sub prune{
    my ($self, $pruner) = @_;
    my $pfg = $self->{pfg};
    # traverse $pfg calling $pruner for each rule and marking
    # the rule for deletion if $pruner returns 1
    my %rules_to_prune;
    $self->enumerate( sub{
        my ($rule_id, $lhs, $rhs) = @_;
        if ( $pruner->($rule_id, $lhs, $rhs) ){
            $rules_to_prune{$rule_id} = undef;
        }
    });

    say "rules to prune: ", join ', ', map { "R$_" } keys %rules_to_prune;

    # remove rules to prune
    my @new_pfg;
    for my $rule_id (0..@$pfg-1){
        push @new_pfg, $pfg->[$rule_id] unless exists $rules_to_prune{$rule_id};
    }
    $self->{pfg} = \@new_pfg;
    # rebuild index
    $self->{pfg_index} = $self->build_index($pfg);

    # remove symbols inaccessible from the top
#        $self->prune_rule( $rule_id );

#    say "# pfg rules after pruning\n", $self->show_rules;
#    say "# pfg index after pruning", Dump $pfg_index;
}

sub pfg_show_rule{
    my ($pfg, $rule_id, $lhs, $rhs) = @_;
    return "R$rule_id: " . join ' ', $lhs, '::=', @$rhs;
}

sub show_rules{
    my ($self) = @_;
    my $pfg = $self->{pfg};
    my @lines;
    $self->enumerate( sub {
        my ($rule_id, $lhs, $rhs) = @_;
        push @lines, pfg_show_rule($pfg, $rule_id, $lhs, $rhs);
    });
    return join "\n", @lines;
}

sub enumerate{
    my ($self, $enumerator) = @_;
    my $pfg = $self->{pfg};
    for my $i (0..@$pfg-1){
        my $rule = $pfg->[$i];
        my ($lhs, @rhs) = @$rule;
        $enumerator->( $i, $lhs, \@rhs );
    }
}


sub traverse{
    my ($pfg, $enumerator) = @_;
    for my $i (0..@$pfg-1){
        my $rule = $pfg->[$i];
        my ($lhs, @rhs) = @$rule;
        $enumerator->( $i, $lhs, \@rhs );
    }
}

sub rule_to_ast_node{
    my ($self, $rule_id) = @_;

    my ($pfg_lhs, @pfg_rhs) = @{ $self->{pfg}->[ $rule_id ] };

#    say "# Rule $rule_id:\n", pfg_show_rule($pfg, $rule_id, $pfg_lhs, \@pfg_rhs);

    # get ast node_id, start, length
    my @ast_lhs = split /_/, $pfg_lhs;
    my $length = pop @ast_lhs;
    my $start = pop @ast_lhs;
    my $ast_lhs = join('_', @ast_lhs);
#    say join ', ', $ast_lhs, $start, $length;

    return [
        join('_', @ast_lhs),
#        $start,
#        $length,
        map {
            my $pfg_rhs_symbol = $_;
#            say "pfg rhs symbol: $pfg_rhs_symbol";
            if ( not $self->is_terminal( $pfg_rhs_symbol ) ){ # non-terminal

#                say "non-terminal $pfg_rhs_symbol";

                my $next_rule_id = $self->rule_id( $pfg_rhs_symbol );
                $self->rule_to_ast_node( $next_rule_id )
            }
            else{ # terminal
#                say "terminal $pfg_rhs_symbol";
                $pfg_rhs_symbol;
            }
        } @pfg_rhs
    ];
}

sub ast{
    my ($self) = @_;
    my $ast = $self->rule_to_ast_node( $self->rule_id( $self->{start} ) );
    return $ast;
}

1;
