use 5.010;
use strict;
use warnings;
use Test::More;

use YAML;
use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Terse = 1;
$Data::Dumper::Deepcopy = 1;

use Marpa::R2;

my $g = Marpa::R2::Scanless::G->new( {
        source => \(<<'END_OF_SOURCE'),
:default ::= action => [ name, value ]
lexeme default = action => [ name, value ] latm => 1

    # Markdown
    document ::= block+

    # 3.2 Container blocks and leaf blocks
    block ::= container_block

    # 5 Container blocks
    container_block ::= list

    # 5.1 Block quotes

    # 5.2 List items
    # 5.3 Lists
    list ::= ordered_list
    list ::= bullet_list

    ordered_list ::= ordered_list_items_period [\n] [\n]
    ordered_list ::= ordered_list_items_period
    ordered_list ::= ordered_list_items_bracket [\n] [\n]
    ordered_list ::= ordered_list_items_bracket

    ordered_list_items_period ::= ordered_list_item_period+
    ordered_list_item_period ::= ordered_list_marker_period (list_marker_spaces) line

    ordered_list_items_bracket ::= ordered_list_item_bracket+
    ordered_list_item_bracket ::= ordered_list_marker_bracket (list_marker_spaces) line

    ordered_list_marker_period ~ digits '.'
    ordered_list_marker_bracket ~ digits ')'

    digits ~ [0-9]+

    bullet_list ::= bullet_list_items [\n] [\n] rank => 1
    bullet_list ::= bullet_list_items

    bullet_list_items ::= bullet_list_items_hyphen
    bullet_list_items ::= bullet_list_items_plus
    bullet_list_items ::= bullet_list_items_star

    bullet_list_items_hyphen ::= bullet_list_item_hyphen+
    bullet_list_item_hyphen ::= (bullet_list_marker_hyphen) (list_marker_spaces) line
    bullet_list_marker_hyphen ::= '-'

    bullet_list_items_plus ::= bullet_list_item_plus+
    bullet_list_item_plus ::= (bullet_list_marker_plus) (list_marker_spaces) line
    bullet_list_marker_plus  ~ '+'

    bullet_list_items_star ::= bullet_list_item_star+
    bullet_list_item_star ::= (bullet_list_marker_star) (list_marker_spaces) line
    bullet_list_marker_star ~ '*'

    list_marker_spaces ~ ' ' | '  ' | '   ' | '    '

    # line of non-newlines up to an including newline
    line ::= non_nl [\n]
    non_nl ::= [^\n]+

END_OF_SOURCE
    } );

my @lists = (
q{- foo
- bar
+ baz
},
q{1. foo
2. bar
3) baz
}
);

for my $list (@lists){
    my $r = Marpa::R2::Scanless::R->new( {
        grammar => $g,
    #        trace_terminals => 99,
    } );
    $r->read(\$list);

    my $i = 0;
    while ( defined( my $v = $r->value() ) ) {
        warn Dumper ${ $v };
        $i++;
    }
    say "$i parses.";

    if ( $r->ambiguity_metric() > 1 ){
        $r->series_restart();
        use lib qw{/home/Ruslan/MarpaX-ASF-PFG/lib};
        use MarpaX::ASF::PFG;
        my $pfg = MarpaX::ASF::PFG->new( Marpa::R2::ASF->new( { slr => $r } ) );
#        say $pfg->show_rules();
        $pfg->ambiguous();
        $r->series_restart();
    }
}
