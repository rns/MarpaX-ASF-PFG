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
        [qw{    S   A B      }],
        [qw{    S   D E      }],
        [qw{    A   a        }],
        [qw{    B   b C      }],
        [qw{    C   c        }],
        [qw{    D   d F      }],
        [qw{    E   e        }],
        [qw{    F   f D      }]
    ],
    [
        [qw{    Sum_2_3     Sum_2_1 + Sum_4_1       }],
        [qw{    Sum_0_5     Sum_0_3 + Sum_4_1       }],
        [qw{    Sum_4_1     Digit_4_1               }],
        [qw{    Digit_4_1   1                       }],
        [qw{    Sum_0_3     Sum_0_1 + Sum_2_1       }],
        [qw{    Sum_2_1     Digit_2_1               }],
        [qw{    Digit_2_1   5                       }],
        [qw{    Sum_0_1     Digit_0_1               }],
        [qw{    Digit_0_1   3                       }]
    ],
    [
        [qw{    S0  S   }],
        [qw{    S0  X   }],
        [qw{    S0  Z   }],
        [qw{    S   A   }],
        [qw{    A   B   }],
        [qw{    B   C   }],
        [qw{    C   A a }],
        [qw{    X   C   }],
        [qw{    Y   a Y }],
        [qw{    Y   a   }],
        [qw{    Z       }]
    ],

];

for my $g (@$grammars){

    my $pfg = MarpaX::ASF::PFG->new($g);

    say $pfg->show_rules;
    say $pfg->{start};
#    say Dump $pfg->{pfg_index};

    $pfg->cleanup;

    say $pfg->show_rules;
    say $pfg->{start};
#    say Dump $pfg->{pfg_index};
}

done_testing();
