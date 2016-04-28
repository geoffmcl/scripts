#!/usr/bin/perl -w
# NAME: f2m.pl
# AIM: Convert feet input to meters...
# 28/04/2016 - Add this converter...
use strict;
use warnings;

my $FG_F2M = 0.3048;

sub prt($) { print shift; }

sub is_decimal($) {
    my $num = shift;
    return 1 if ($num =~ /^[-+]?[0-9]*\.?[0-9]+$/);
    return 0;
}

sub help() {
    prt("Given feet input, will output meters.\n");
}

if (@ARGV) {
    my $f = $ARGV[0];
    if (is_decimal($f)) {
        my $m = $f * $FG_F2M;
        prt("$f feet equals $m meters.\n");
    } else {
        help();
        prt("Input '$f' is not a decimal\n");
    }
} else {
    help();
}

# eof
