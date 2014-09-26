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

use MarpaX::ASF::PFG;

my $grammars = [
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
    [
        [ 'S0', [qw{ S   }] ],
        [ 'S0', [qw{ X   }] ],
        [ 'S0', [qw{ Z   }] ],
        [ 'S',  [qw{ A   }] ],
        [ 'A',  [qw{ B   }] ],
        [ 'B',  [qw{ C   }] ],
        [ 'C',  [qw{ A a }] ],
        [ 'X',  [qw{ C   }] ],
        [ 'Y',  [qw{ a Y }] ],
        [ 'Y',  [qw{ a   }] ],
        [ 'Z',  [qw{     }] ],
    ],
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
    ]
];

for my $rules (@$grammars){
    my $pfg = MarpaX::ASF::PFG->new($rules);
    say "# Source CFG\n", $pfg->show_rules;
    $pfg->cleanup;
    say "# Cleaned CFG\n", $pfg->show_rules, "\n";
}

done_testing();
