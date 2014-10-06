package MarpaX::ASF::PFG;

use 5.010;
use strict;
use warnings;

use YAML;

use Data::Dumper;
$Data::Dumper::Indent = 0;
$Data::Dumper::Terse = 1;
$Data::Dumper::Deepcopy = 1;

use Marpa::R2;

use Set::IntervalTree; # broken on windows
# use Set::IntervalTree for efficiency
#   my $results = $tree->fetch_window($low, $high)
#   Return an arrayref of perl objects whose ranges are completely contained
#   within the specified range.

sub new {
    my ($class, $asf) = @_;

    my $self = {};
    bless $self, $class;

    # new from array of arrays in Marpa NAIF format
    if (ref $asf eq "ARRAY"){
        my $rules = $asf;
        $self->{pfg} = $rules;
        $self->{start} = $rules->[0]->[0];
        $self->{pfg_index} = $self->build_index;
        return $self;
    }

    # new from abstract syntax forest
    $self->{asf} = $asf;
    my $g = $asf->grammar();

    my $ints = Set::IntervalTree->new;
    my $ints_seen = {};

    my %token_spans;
    my %rule_spans;

    my $pfg = [];
    $asf->traverse( $pfg, sub{
        # This routine converts the glade into PFG rules.  It is called recursively.
        my ($glade, $pfg)     = @_;

        my $rule_id     = $glade->rule_id();
        my $symbol_id   = $glade->symbol_id();
        my $symbol_name = $g->symbol_name($symbol_id);
        my $literal     = $glade->literal();

        # get span
        my ( $start, $length ) = $glade->span();
        my $suffix   = '_' . $start . '_' . ($start + $length);

#        say "$symbol_name '$literal' ($start, $length)";

        # insert interval to tree
        $ints->insert( $literal, $start, $start + $length )
            unless exists $ints_seen->{ $suffix };
        $ints_seen->{ $suffix } = $literal;

        # Our result will be dummy, we will save PFG rules to the scratch pad
        my $return_value = [];

        # A token is a single choice
        # We save PFG rule to the scratch pad and return PFG symbol name
        # unless it is internal to the parse grammar in which case
        # we just return literal
        if ( not defined $rule_id ) {

            # don't prepend internal symbol names
            # todo: symbol_is_internal( $symbol_id ) method for SLG
            my $literal_symbol_name = $symbol_name =~ /\[Lex/ ? '' : "$symbol_name$suffix";

            # save PFG rule unless the literal's symbol is internal
            # which means it has no symbol name in the parse grammar
            # todo: wrap literals to avoid exceptions thrown by Marpa NAIF
            # on, e.g. rule name ) ends in ")"
            if ($literal_symbol_name ne ''){
                # attributes
                my $atts = { start => $start, length => $length, literal => $literal };
                # save PFG rule: lhs, rhs1, rhs2 ...
                unshift @$pfg, [ $literal_symbol_name, $literal, $atts ];
                $token_spans{$start}->{$start+$length}->{$literal}->{$literal_symbol_name} = undef;
                return [ $literal_symbol_name ];
            }
            else{ # return literal for internal symbols
                $token_spans{$start}->{$start+$length}->{$literal} = undef;
                return [ $literal ];
            }
        } ## end if ( not defined $rule_id )

        CHOICE: while (1) {

            # The results at each position are a list of choices
            # (PFG symbols or literals), so to produce a new result list,
            # we need to take a Cartesian product of all the choices
            # todo: refactor the below code to a sub
            my $rh_length = $glade->rh_length();
            my @results = ( [] );
            for my $rh_ix ( 0 .. $rh_length - 1 ) {
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
            # The list of PFG symbols will be returned to form further PFG rules.
            # unshift is used to avoid further reverse()ing because
            # the traverse order is depth-first
            my @rv = map {
    #            say "# return value item", Dump $_;
                my $pfg_symbol = $symbol_name . $suffix;
                # attributes
                my $atts = { start => $start, length => $length, literal => $literal };
                # save PFG rule
                unshift @$pfg, [ $pfg_symbol, @{$_}, $atts ];
                # save rule span
                $rule_spans{$start}->{$start+$length}->{$literal}->{$pfg_symbol} = undef;
                # return PFG symbol name
                $pfg_symbol
            } @results;
    #        say "# return value: ", Dump \@rv;
            push @$return_value, @rv;

            # Look at the next alternative in this glade, or end the
            # loop if there is none
            last CHOICE if not defined $glade->next();

        } ## end CHOICE: while (1)

        # Return the list of elements for this glade
        return $return_value;
    } );

#    say Dump $ints_seen;

    $self->{token_spans} = \%token_spans;
    $self->{rule_spans} = \%rule_spans;

#    say Dump $self->{token_spans};
#    say Dump $self->{rule_spans};

    # delete duplicate rules
    my %rules;
    my @rules;
    my $atts = {};
    for my $i (0..@$pfg-1){
        my $rule = $pfg->[$i];
        my $att = pop @$rule;
        my ($lhs, @rhs ) = @$rule;
        $atts->{$lhs} = $att;
        my $rule_shown = join ' ', $lhs, '::=', @rhs;
#        say "Rule: $rule_shown";
        push @rules, [ $lhs, \@rhs ] unless exists $rules{$rule_shown};
        $rules{$rule_shown} = undef;
    }
    $self->{pfg} = \@rules;
    $self->{pfg_index} = $self->build_index;
    $self->{pfg_atts} = $atts;
    $self->{pfg_ints} = $ints;

    # handle s1 ::= s2 s2 ::= s3 as s1 s2 s3 on the same span
    # for two symbols s1 and s2 covering the same span
    # if they are only in s1 ::= s2 rules, then s2 must be deleted
    # so that the only the top node remain
    # todo: this is very naive and quadratic; some graph voodoo requried
    #       like: given a set of vertices (s1, s2, s3 ... sn),
    #             find if a path s1 ::= s2, s2 ::=  s3, s3 ::= ... sn-1 ::= sn exists
    my $pfgi = $self->{pfg_index};
    for my $start (keys %{ $self->{rule_spans} }){
        for my $length ( keys %{ $self->{rule_spans}->{$start} } ){
            for my $literal (keys %{ $self->{rule_spans}->{$start}->{$length} }){
                my $rule_symbols = $self->{rule_spans}->{$start}->{$length}->{$literal};
#                say Dumper $rule_symbols;
                my @rule_symbols = keys %{ $rule_symbols };
#                say "# rule symbols:\n", join ", ", @rule_symbols;
                my @rule_symbols_to_delete;
                for my $i (0..$#rule_symbols){
                    for my $j (0..$#rule_symbols){
                        next if $i == $j;
                        # check if there is a rule s1 ::= s2
                        my ($s1, $s2) = @rule_symbols[$i, $j];
#                        say "# checking for rule $s1 ::= $s2";
#                        say "$_: ", Dumper $pfgi->{$_} for ($s1, $s2);
                        if (
                                exists $pfgi->{$s1}->{lhs}
                            and exists $pfgi->{$s2}->{rhs}->{0}
                            and (
                                (keys %{ $pfgi->{$s1}->{lhs}      })[0]
                                ==
                                (keys %{ $pfgi->{$s2}->{rhs}->{0} })[0]
                            )
                        ){
#                            say "  rule exists.";
                            push @rule_symbols_to_delete, $s2;

                        }
                    }
                }
#                say "# deleting:\n", join ", ", @rule_symbols_to_delete
#                    if @rule_symbols_to_delete;
                delete $self->{rule_spans}->{$start}->{$length}->{$literal}->{$_}
                    for @rule_symbols_to_delete;
#                say Dumper $self->{rule_spans}->{$start}->{$length}->{$literal}
#                    if @rule_symbols_to_delete;
            }
        }
    }

    # reindex, some rules might have been deleted
    $self->{pfg_index} = $self->build_index;

    return $self;
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

sub is_terminal{
    my ($self, $symbol) = @_;
    return not exists $self->{pfg_index}->{$symbol}->{lhs};
}

# todo: handle the case when lhs is an LHS of several rules, e.g. warn
sub rule_id{
    my ($self, $lhs) = @_;
    return ( sort { $a <=> $b } keys %{ $self->{pfg_index}->{$lhs}->{lhs} } )[ 0 ];
}

sub start{ $_[0]->{start} }

sub has_symbol_at{
    my ($self, $rule_id, $symbol, $at) = @_;
    return exists $self->{pfg_index}->{$symbol}->{rhs}->{$at}->{$rule_id};
}

# return tokens and their ranges within $from, $to interval
# sorted by start position
sub intervals{
    my ($self, $from, $to) = @_;
    my $itr = $self->{pfg_ints};
    my @ints;
    $itr->remove($from, $to, sub{
        if (    $from <= $_[1] and $_[2] <= $to
            and not ($_[1] == $from and $_[2] == $to) ){
#            say join ', ', @_;
            push @ints, [ @_ ];
        }
        return 0; # don't remove
     });
     return [ sort { $a->[1] <=> $b->[1] } @ints ];
}


# my @ambiguous_items = $pfg->ambiguous();
# my $rv = $pfg->ambiguous(sub{ ($pfg, $literal, $cause, @parses) = @_ ... });
# trace all ambiguous literals to ambiguous tokens which caused them
# and show differences in how they are parsed
=pod
for each token literal start
    for each rule literal which starts at token literal start
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

=cut
sub ambiguous{
    my ($self, $code) = @_;
    my $token_spans = $self->{token_spans};
    my $rule_spans = $self->{rule_spans};
    my %tokens_seen;
    # for each token start
TOKEN_START:
    for my $token_start (sort keys %{ $token_spans }){
        # check if token is marked as seen and already occurs in a rule
        next TOKEN_START if exists $tokens_seen{$token_start};
        # for the shortest (with the nearest end position) rule starting at $token_start
RULE_END:
        for my $rule_end
        (
            (
                # skip tokens
                grep { not exists $token_spans->{$token_start}->{$_} }
                # closest rule end is the least
                sort keys %{ $rule_spans->{$token_start} }
            )[0]
        )
        {
            my $rule_literal = (keys %{ $rule_spans->{$token_start}->{$rule_end} })[0];
            my @rule_symbols =
                keys %{ $rule_spans->{$token_start}->{$rule_end}->{$rule_literal} };
#            say "# token intervals in $token_start-$rule_end (", keys $rule_spans->{$token_start}->{$rule_end}, "): ";
#            say "Ambiguous rule" if @rule_symbols > 1;
#            say "  ", join ', ', @rule_symbols;
            # get token intervals within nearest rule range
            my $token_intervals =
            [
                grep
                {
                    # skip rule intervals
                    exists $token_spans->{$_->[1]}->{$_->[2]}
                }
                @{ $self->intervals( $token_start, $rule_end ) }
            ];
#            say "# token intervals", Dump $token_intervals;
            # at least one token must be ambiguous
            my $unambiguous = 1;
            for my $token_interval (@{ $token_intervals }){
                my ($literal, $start, $end) = @$token_interval;
#                say "$literal: ", Dump $token_spans->{$start}->{$end}->{$literal};
                $unambiguous = 0 if keys %{ $token_spans->{$start}->{$end}->{$literal} } > 1;
            }
            # even if all tokens are unambiguous
            # we must continue if the rule is ambiguous
            next RULE_END if $unambiguous and @rule_symbols < 2;
            # by now only ambiguous rule and token intervals must have remained
            # and we can find ambiguous literal, parse (sub)trees, cause
            say "# ambiguous tokens in literal:\n'$rule_literal' ($token_start-$rule_end): ";
            for my $rs (@rule_symbols){
                say $rs;
#                say Dumper $self->ast( $rs );
            }
            # find if ambiguous token symbols exist in rule's ast
            for my $ti (@$token_intervals){
                my ($literal, $start, $end) = @$ti;
                my @token_symbols =
                    keys %{ $token_spans->{$start}->{$end}->{$literal} };
                say join "\n", map { "'$literal' ($start-$end): $_" } @token_symbols;
#                say join "\n", map { "$start-$end: " . Dumper $self->ast($_) } @token_symbols;
            }
            # now define literal, parse (sub)trees, and cause
            # ...

            # todo: renaming (5.3 Lists when the same literal span)
            # n1 ::= n2 n2 ::= n3 n4 ::= n5 n5 ~ 'n5'
            # must not be treated as ambiguity

            # mark the tokens as seen to avoid their occurrence in further rules
            $tokens_seen{$_->[1]} = undef for @$token_intervals;
        }
    }
}

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

=cut

# remove unproductive and unaccessible symbols and rules
sub cleanup{
    my ($self) = @_;
    my $pfg = $self->{pfg};

    # cleanup the grammar using Marpa NAIF
    my $grammar = Marpa::R2::Grammar->new({
        start => $self->{start},
        rules => $self->{pfg},
        # todo: boolean args to the below options are undocumented
        # file issue and try to patch the doc
        unproductive_ok => 1,
        inaccessible_ok => 1,
    });
    $grammar->precompute();
    my $rules = $grammar->show_rules;
#    say $rules;
    my @cleaned_pfg;
    for my $rule (grep {!/unproductive|inaccessible/} split /\n/m, $rules){
#        say $rule;
        my (undef, $lhs, @rhs) = split /^\d+:\s+|\s+->\s+|\s+/, $rule;
#        say $lhs, ' -> ', join ' ', @rhs;
        push @cleaned_pfg, [ $lhs, \@rhs ];
    }
    # save and rebuild index
    $self->{pfg} = \@cleaned_pfg;
    $self->{pfg_index} = $self->build_index;
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

    # todo: check if all start rules will be pruned
#    say "rules to prune: ", join ', ', map { "R$_" } keys %rules_to_prune;

    # remove rules to prune
    my @pruned_pfg;
    for my $rule_id (0..@$pfg-1){
        push @pruned_pfg, $pfg->[$rule_id] unless exists $rules_to_prune{$rule_id};
    }
    $self->{pfg} = \@pruned_pfg;

    $self->cleanup;
}

sub show_rule{
    my ($self, $rule_id, $lhs, $rhs) = @_;
    return "R$rule_id: " . join ' ', $lhs, '::=', @$rhs;
}

sub show_rules{
    my ($self) = @_;
    my $pfg = $self->{pfg};
    my @lines;
    $self->enumerate( sub {
        my ($rule_id, $lhs, $rhs) = @_;
        push @lines, $self->show_rule( $rule_id, $lhs, $rhs);
    });
    return join "\n", @lines;
}

sub enumerate{
    my ($self, $enumerator) = @_;
    my $pfg = $self->{pfg};
    for my $i (0..@$pfg-1){
        my $rule = $pfg->[$i];
        my ($lhs, $rhs) = @$rule;
        $enumerator->( $i, $lhs, $rhs );
    }
}

sub do_traverse{
    my ($self, $rule_id, $traverser) = @_;
    my ($lhs, @rhs) = @{ $self->{pfg}->[ $rule_id ] };
    $traverser->($self, $rule_id, $lhs, \@rhs);
    for my $rhs_symbol (@rhs){
        if ( not $self->is_terminal( $rhs_symbol ) ){
            $self->do_traverse( $self->rule_id( $rhs_symbol ), $traverser );
        }
        else{
            $traverser->($self, $rule_id, $rhs_symbol);
        }
    }
}

sub traverse{
    my ($self, $traverser) = @_;
    my $pfg = $self->{pfg};
    my $start_rule_id = $self->rule_id( $self->{start} );
    return $self->do_traverse( $start_rule_id, $traverser );
}

sub rule_to_ast_node{
    my ($self, $rule_id) = @_;

    my ($pfg_lhs, $pfg_rhs) = @{ $self->{pfg}->[ $rule_id ] };

#    say "# Rule $rule_id:\n", $self->show_rule( $rule_id, $pfg_lhs, $pfg_rhs);

    # get ast node_id, start, length
    my @ast_lhs = split /_/, $pfg_lhs;
    # possible todo: for efficiency use PFG as an attribute grammar
    # attributes may include start, length and span literal for each symbol/rule
    # accessible via lhs/rule_id or as a hash ref
    # [ $lhs, $rhs_aref, $attributes_href ]
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
        } @$pfg_rhs
    ];
}

sub ast{
    my ($self, $root) = @_;
    $root //= $self->{start};
    my $ast = $self->rule_to_ast_node( $self->rule_id( $root ) );
    return $ast;
}

1;
