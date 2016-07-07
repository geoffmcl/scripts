#!/usr/bin/perl -w
# NAME: m2f.pl
# AIM: Convert meter input to feet...
# 28/04/2016 - Add this converter...
use strict;
use warnings;

my $FG_M2F = 3.28083989501312335958;

sub prt($) { print shift; }

sub is_decimal($) {
    my $num = shift;
    return 1 if ($num =~ /^[-+]?[0-9]*\.?[0-9]+$/);
    return 0;
}

sub help() {
    prt("Given meters input, will output feet.\n");
}

if (@ARGV) {
    my $m = $ARGV[0];
    if (is_decimal($m)) {
        my $f = $m * $FG_M2F;
        prt("$m meters equals $f feet.\n");
    } else {
        help();
        prt("Input '$m' is not a decimal\n");
    }
} else {
    help();
}

# eof
