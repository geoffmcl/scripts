#!/usr/bin/perl -w
# NAME: INIcolors.pl
# AIM: Given an INI file search for color entries, and display them in html
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
my $cwd = cwd();
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
# log file stuff
our ($LF);
my $outfile = $temp_dir."temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.5 2015-07-28";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'C:\GTools\tools\Sudoku\build\Sudoku.ini';
my $def_out = $temp_dir."/tempinic.html";

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

sub html_begin() {
	my $txt =<<"EOF";
<html>
<head>
<title>INI Colors</title>
<style>
body {
margin:1cm 1cm 1cm 1cm;
}
</style>
</head>
<body>
<h1>INI Colors</h1>
EOF
    return $txt;
}

sub html_end() {
    my $txt = <<"EOF";
</body>
</html>
EOF
    return $txt;
}


# Eliminate_Candidate_Bk=255,255,192
sub process_in_file($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($line,$bgn,$lnn,$end,$r,$g,$b,$hr,$hg,$hb,$colr);
    my ($bsty,$fsty);
    $lnn = 0;
    my $html = "<p>Colors found in ini $inf</p>\n";
    my $lcnt = 0;
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        if ($line =~ /^(.+)=(.+)$/) {
            $bgn = trim_all($1);
            $end = trim_all($2);
            if ($end =~ /^(\d+),(\d+),(\d+)$/) {
                $r = $1;
                $g = $2;
                $b = $3;
            	$hr = uc(sprintf("%2.2x", $r));
	            $hg = uc(sprintf("%2.2x", $g));
	            $hb = uc(sprintf("%2.2x", $b));
                $colr = "#$hr$hg$hb";
              	$bsty = "style=\"background-color: $colr\"";
                $fsty = "style=\"color: $colr\"";
                prt("$lnn: $bgn rgb($r,$g,$b) $colr\n") if (VERB5());
                $html .= "<ul>\n" if ($lcnt == 0);
                # $html .= "<li><p $sty>$bgn = $colr</p></li>\n";
                $html .= "<li><p>\n";
                $html .= "<span $bsty> $colr </span>| $bgn = $r,$g,$b |\n";
                $html .= "<span $fsty> $colr </span>\n";
                $html .= "</p></li>\n";
                $lcnt++;
            }
        }
    }
    if ($lcnt) {
        $html .= "</ul>\n";
    }
    if (length($out_file)) {
        if ($os =~ /win/i) {
            $out_file = path_u2d($out_file);
        } else {
            $out_file = path_d2u($out_file);
        }
        $html = html_begin().$html.html_end();
        write2file($html,$out_file);
        prt("HTML written to $out_file\n");
        system($out_file);
    } else {
        prt($html);
    }
}

#########################################
### MAIN ###
parse_args(@ARGV);
process_in_file($in_file);
pgm_exit(0,"");
########################################

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg);
    my $verb = VERB2();
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
            $in_file = $arg;
            prt("Set input to [$in_file]\n") if ($verb);
        }
        shift @av;
    }

    if ($debug_on) {
        prtw("WARNING: DEBUG is ON!\n");
        if (length($in_file) ==  0) {
            $in_file = $def_file;
            prt("Set DEFAULT input to [$in_file]\n");
            ##$load_log = 1;
        }
        if (length($out_file) == 0) {
            $out_file = $def_out;
        }
    }
    if (length($in_file) ==  0) {
        pgm_exit(1,"ERROR: No input files found in command!\n");
    }
    if (! -f $in_file) {
        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
    }
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-file\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>  (-o) = Write output to this file.\n");
    prt("\n");
    prt(" Given an INI file search for entries of form 'option = 1,2,3'\n");
    prt(" These lines will be assume to be RGB colors, and generate some\n");
    prt(" html to show these colors as background and foreground.\n");
    prt(" Just a way to 'see' what the colors 'look' like.\n");
    prt("\n");
}

# eof - INIcolors.pl
