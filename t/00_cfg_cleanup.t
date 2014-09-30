#!/usr/bin/perl
# Copyright 2014 Ruslan Shvedov

# 2.9.5 Cleaning up a Context-Free Grammar from
# Parsing Techniques: A Practical Guide by Grune and Jacobs 2008 (G&J)

# S ---> AB|DE
# A ---> a
# B ---> bC
# C ---> c
# D ---> dF
# E ---> e
# F ---> fD
# Fig. 2.27. A demo grammar for grammar cleaning

use 5.010;
use strict;
use warnings;

use Test::More;

use Marpa::R2;

use YAML;

use_ok 'MarpaX::ASF::PFG';

my $tests = [
    [
        [
            [ 'S', [qw{ A B }] ],
            [ 'S', [qw{ D E }] ],
            [ 'A', [qw{ a   }] ],
            [ 'B', [qw{ b C }] ],
            [ 'C', [qw{ c   }] ],
            [ 'D', [qw{ d F }] ],
            [ 'E', [qw{ e   }] ],
            [ 'F', [qw{ f D }] ],
        ],
    q{
R0: S ::= A B
R1: A ::= a
R2: B ::= b C
R3: C ::= c
R4: E ::= e
}
    ],
    [
        [
            [ 'Sum_2_3',    [qw{ Sum_2_1 + Sum_4_1  }] ],
            [ 'Sum_0_5',    [qw{ Sum_0_3 + Sum_4_1  }] ],
            [ 'Sum_4_1',    [qw{ Digit_4_1          }] ],
            [ 'Digit_4_1',  [qw{ 1                  }] ],
            [ 'Sum_0_3',    [qw{ Sum_0_1 + Sum_2_1  }] ],
            [ 'Sum_2_1',    [qw{ Digit_2_1          }] ],
            [ 'Digit_2_1',  [qw{ 5                  }] ],
            [ 'Sum_0_1',    [qw{ Digit_0_1          }] ],
            [ 'Digit_0_1',  [qw{ 3                  }] ],
        ],
    q{
R0: Sum_2_3 ::= Sum_2_1 + Sum_4_1
R1: Sum_4_1 ::= Digit_4_1
R2: Digit_4_1 ::= 1
R3: Sum_2_1 ::= Digit_2_1
R4: Digit_2_1 ::= 5
}
    ],
    [
        [
            [ 'S', [qw{ B b }] ],
            [ 'S', [qw{ C c }] ],
            [ 'S', [qw{ E e }] ],
            [ 'B', [qw{ B b }] ],
            [ 'B', [qw{ b   }] ],
            [ 'C', [qw{ C c }] ],
            [ 'C', [qw{ c   }] ],
            [ 'D', [qw{ B d }] ],
            [ 'D', [qw{ C d }] ],
            [ 'D', [qw{ d   }] ],
            [ 'E', [qw{ E e }] ]
        ],
    q{
R0: S ::= B b
R1: S ::= C c
R2: B ::= B b
R3: B ::= b
R4: C ::= C c
R5: C ::= c
}
    ]
];

for my $test (@$tests){
    my ($rules, $expected_rules) = @$test;

    $expected_rules =~ s/^\s+//s;
    $expected_rules =~ s/\s+$//s;

    my $pfg = MarpaX::ASF::PFG->new($rules);

    $pfg->cleanup;

    is $pfg->show_rules, $expected_rules, "grammar cleanup";
}

done_testing();
