#!/usr/bin/perl -w
# NAME: knows2mps.pl
# AIM: Given speed in knots, show in meters per second
use strict;
use warnings;

# 1 knots = 1.85200 kph
my $K2KPH = 1.85200;
my $Km2NMiles = 1 / $K2KPH; # Nautical Miles.
#my $Km2NMiles = 0.53995680346; # Nautical Miles.

my $knots = -1;

sub prt($) { print shift; }

sub pgm_exit($$) {
    my ($val,$msg) = @_;
    if (length($msg)) {
        $msg .= "\n" if (!($msg =~ /\n$/));
        prt($msg);
    }
    #fgfs_disconnect();
    #show_warnings($val);
    #close_log($outfile,$load_log);
    exit($val);
}

sub do_conversion() {
    my $len = length($knots);
    my $ind = index($knots,'.');
    my $kph = $knots * $K2KPH;
    my $mps = ($kph * 1000) / 3600;
    if ($ind > 1) {
        my $dec = $len - ($ind + 1);
        if ($dec . 0) {
            my $form = sprintf(".%d",$dec);
            my $frm = '%'.$form.'f';
            $kph = sprintf($frm, $kph);
            $mps = sprintf($frm, $mps);
        }

    } else {
        $kph = int($kph + 0.5);
        $mps = int($mps + 0.5);
    }
    prt("Knots $knots = $kph kph, $mps mps\n");
}

#########################################
### MAIN ###
parse_args(@ARGV);
do_conversion();
exit 0;
#########################################

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg);
    while (@av) {
        $arg = $av[0];
        if ($arg =~ /^-/) {
            pgm_exit(1,"Only argument is a positive decimal being KNOTS (Nautical miles per hour)\n");
        } else {
            $knots = $arg;
        }
        shift @av;
    }
    if ($knots == -1) {
        pgm_exit(1,"Error: positive decimal being KNOTS not found!\n");
    }
}

