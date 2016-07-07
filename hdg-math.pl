#!/usr/bin/perl -w
# NAME: hdg-math.pl
# AIM: get average, given two heading
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
my $cwd = cwd();
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl'! Check location and \@INC content.\n";
require 'lib_fgio.pl' or die "Unable to load 'lib_fgio.pl'! Check location and \@INC content.\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";

# log file stuff
our ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_hdg1 = '';
my $in_hdg2 = '';
my $verbosity = 0;
my $out_file = '';

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 350;
my $def_file2 = 10;

### program variables
my @warnings = ();

sub VERB1() { return $verbosity >= 1; }
sub VERB2() { return $verbosity >= 2; }
sub VERB5() { return $verbosity >= 5; }
sub VERB9() { return $verbosity >= 9; }

sub show_warnings($) {
    my ($val) = @_;
    if (@warnings) {
        prt( "\nGot ".scalar @warnings." WARNINGS...\n" );
        foreach my $itm (@warnings) {
           prt("$itm\n");
        }
        prt("\n");
    } else {
        prt( "\nNo warnings issued.\n\n" ) if (VERB9());
    }
}

sub pgm_exit($$) {
    my ($val,$msg) = @_;
    if (length($msg)) {
        $msg .= "\n" if (!($msg =~ /\n$/));
        prt($msg);
    }
    show_warnings($val);
    close_log($outfile,$load_log);
    exit($val);
}


sub prtw($) {
   my ($tx) = shift;
   $tx =~ s/\n$//;
   prt("$tx\n");
   push(@warnings,$tx);
}

sub process_in_file($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($line,$inc,$lnn);
    $lnn = 0;
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        if ($line =~ /\s*#\s*include\s+(.+)$/) {
            $inc = $1;
            prt("$lnn: $inc\n");
        }
    }
}

sub process_inputs() {
    my $hdg1 = $in_hdg1;
    my $hdg2 = $in_hdg2;
    my $diff = get_hdg_diff($hdg1,$hdg2);
    my $hdg3 = $hdg1 + ($diff / 2);
    $hdg3 -= 360 if ($hdg3 > 360);
    $hdg3 += 360 if ($hdg3 < 0);
    prt("With hdg1 $hdg1, hdg2 $hdg2, diff $diff, av $hdg3\n");

    $diff = get_hdg_diff($hdg2,$hdg1);
    $hdg3 = $hdg2 + ($diff / 2);
    $hdg3 -= 360 if ($hdg3 > 360);
    $hdg3 += 360 if ($hdg3 < 0);
    prt("With hdg2 $hdg2, hdg1 $hdg1, diff $diff, av $hdg3\n");

}

#########################################
### MAIN ###
parse_args(@ARGV);
#process_in_file($in_hdg1);
process_inputs();
pgm_exit(0,"");
########################################

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg,$cnt);
    my $verb = VERB2();
    $cnt = 0;
    while (@av) {
        $arg = $av[0];
        if ($arg =~ /^-/) {
            $sarg = substr($arg,1);
            $sarg = substr($sarg,1) while ($sarg =~ /^-/);
            if (($sarg =~ /^h/i)||($sarg eq '?')) {
                give_help();
                pgm_exit(0,"Help exit(0)");
            } elsif ($sarg =~ /^v/) {
                if ($sarg =~ /^v.*(\d+)$/) {
                    $verbosity = $1;
                } else {
                    while ($sarg =~ /^v/) {
                        $verbosity++;
                        $sarg = substr($sarg,1);
                    }
                }
                $verb = VERB2();
                prt("Verbosity = $verbosity\n") if ($verb);
            } elsif ($sarg =~ /^l/) {
                if ($sarg =~ /^ll/) {
                    $load_log = 2;
                } else {
                    $load_log = 1;
                }
                prt("Set to load log at end. ($load_log)\n") if ($verb);
            } elsif ($sarg =~ /^o/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_file = $sarg;
                prt("Set out file to [$out_file].\n") if ($verb);
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            if ($cnt == 0) {
                $in_hdg1 = $arg;
                prt("Set input to [$in_hdg1]\n") if ($verb);
            } elsif ($cnt == 1) {
                $in_hdg2 = $arg;
                prt("Set input to [$in_hdg2]\n") if ($verb);
            } else {
                pgm_exit(1,"Error: Already have hdg1 $in_hdg1 and hdg2 $in_hdg2. What is this $arg!\n");
            }
            $cnt++;
        }
        shift @av;
    }

    if ($debug_on) {
        prtw("WARNING: DEBUG is ON!\n");
        if (length($in_hdg1) ==  0) {
            $in_hdg1 = $def_file;
            $in_hdg2 = $def_file2;
            prt("Set DEFAULT input to [$in_hdg1] and [$in_hdg2]\n");
        }
    }
    if (length($in_hdg1) ==  0) {
        pgm_exit(1,"ERROR: No input heading found in command!\n");
    }
    if (length($in_hdg2) ==  0) {
        pgm_exit(1,"ERROR: No input 2nd heading found in command!\n");
    }
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] hdg1 hdg2\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    #prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    #prt(" --out <file>  (-o) = Write output to this file.\n");
    prt(" Given two headings show difference, and 'average' heading\n");
}

# eof - template.pl
