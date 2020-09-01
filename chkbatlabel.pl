#!/usr/bin/perl -w
# NAME: chkbatlabels.pl
# AIM: Given a batch file check each 'goto' statement has a corresponding label
# 01/09/2020 - Deal with some more UNPROCESSED lines
# 2018-06-29 - Move to public 'scripts'
# 27/02/2016 - More tidy up of missed call targets
# 13/08/2014 - Fix some missed 'goto' statements
# 14/06/2014 - Add verbosity to see labels with no call or goto
# 01/06/2012 - Fix for 'special' goto :EOF label, and [@(] call [:]CHKIT
# 20/05/2012 geoff mclane http://geoffair.net/mperl
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "/temp";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
# log file stuff
our ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.5 2020-09-01";  # deal with some more UNPROCESSED commands
###my $VERS = "0.0.4 2018-06-29";  # move to public scripts
###my $VERS = "0.0.3 2016-02-27";
###my $VERS = "0.0.2 2014-03-11";
###my $VERS = "0.0.1 2012-05-20";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $show_labels = 0;

my $debug_on = 0;
my $def_file = 'def_file';
my $out_xml = '';
my @in_files = ();

### program variables
my @warnings = ();
my $cwd = cwd();

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

sub trim_label($) {
    my $lab = shift;
    if (substr($lab,0,1) eq ':') {
        $lab = trim_all(substr($lab,1));
    }
    return $lab;
}

sub get_goto_label($) {
    my $line = shift;
    my $lcl = lc($line);
    my $ind = index($lcl,"goto");
    pgm_exit(1,"\nSTUPID: Can NOT find 'goto' in [$lcl] [$line] BAH!\n\n") if ($ind < 0);
    $lcl = substr($line,$ind+4);
    $lcl = trim_all($lcl);
    return trim_label($lcl);
}

sub get_call_label($) {
    my $line = shift;
    my $lcl = lc($line);
    my $ind = index($lcl,"call");
    pgm_exit(1,"\nSTUPID: Can NOT find 'goto' in [$lcl] [$line] BAH!\n\n") if ($ind < 0);
    $lcl = substr($line,$ind+4);
    $lcl = trim_all($lcl);
    $lcl =~ s/^://;
    my @arr = split(/\b/,$lcl);
    $lcl = trim_all($arr[0]);
    return trim_label($lcl);
}

sub is_call_label($) {
    my $line = shift;
    my $lcl = lc($line);
    my $ind = index($lcl,"call");
    pgm_exit(1,"\nSTUPID: Can NOT find 'goto' in [$lcl] [$line] BAH!\n\n") if ($ind < 0);
    $lcl = substr($line,$ind+4);
    $lcl = trim_all($lcl);
    return 1 if ($lcl =~ /^:/);
    return 0;
}


sub process_in_file($) {
    my ($inf) = @_;
    pgm_exit(1,"ERROR: Unable to open file [$inf]\n") if (! open INF, "<$inf");
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($j,$i2,$line,$inc,$lnn,$ra,$label,$tmp,$msg,$cnt,$i,$plnn,$pline,$missed,$flg);
    my ($len,$fnd);
    $lnn = 0;
    my %g_gotos = ();   # goto OR call
    my %g_labels = ();
    my $gcnt = 0;
    my $ccnt = 0;
    my $tcnt = 0;
    for ($j = 0; $j < $lncnt; $j++) {
        $i2 = $j + 1;
        $line = $lines[$j];
        chomp $line;
        $lnn = $j + 1;
        $line = trim_all($line);
        #while (($line =~ /^$/)&&($i2 < $lncnt)) {
        #    $line =~ s/^$//;
        #    $j++;
        #    $i2 = $j + 1;
        #    $tmp = $lines[$j];
        #    chomp $tmp;
        #    $lnn++;
        #    $tmp = trim_all($tmp);
        #    $line .= $tmp;
        #}
        $len = length($line);
        next if ($len == 0);
        prt("[v9] $i2: $line\n") if (VERB9());
        next if ($line =~ /^\s*\@*\s*REM\b/i);
        next if ($line =~ /^\s*\@*\s*ECHO\b/i);
        next if ($line =~ /^\s*\@*\s*SET\b/i);
        next if ($line =~ /^\s*\@*\s*SHIFT\b/i);
        next if ($line =~ /^\s*\@*\s*SETLOCAL\b/i);
        next if ($line =~ /^\s*\@*\s*ENDLOCAL\b/i);
        next if ($line =~ /^\s*\@*\s*PAUSE\b/i);
        next if ($line =~ /^\s*\@*\s*CD\b/i);
        if ($line =~ /\bgoto\b/i) {
        ### if ($line =~ /^\s*\@*\s*goto\b/i) {
            $inc = get_goto_label($line);
            $label = uc($inc);
            prt("[v5] $lnn: GOTO $inc [$line]\n") if (VERB5());
            next if ($label eq 'EOF');  # 20160227 - Ignore :EOF
            next if ($label =~ /^\s*:\s*EOF\b/i);
            next if ($label =~ /^\%+/);
            $g_gotos{$label} = [] if (! defined $g_gotos{$label});
            $ra = $g_gotos{$label};
            #             0     1     2      3
            push(@{$ra}, [$lnn, $line, $inc, 0]);
            $gcnt++;
        # } elsif (($line =~ /^\s*\@*\s**\s*call\b/i) && (is_call_label($line))) {
        # } elsif (($line =~ /^\s*\@*\s*\(*\s*call\b/i) && (is_call_label($line))) {
        } elsif (($line =~ /\@*\s*\(*\s*call\b/i) && (is_call_label($line))) {
            $inc = get_call_label($line);
            $label = uc($inc);
            prt("[v5] $lnn: CALL $inc [$line]\n") if (VERB5());
            next if ($label eq 'EOF');  # 20160227 - Ignore :EOF
            $g_gotos{$label} = [] if (! defined $g_gotos{$label});
            $ra = $g_gotos{$label};
            #             0     1     2      3
            push(@{$ra}, [$lnn, $line, $inc, 1]);
            $ccnt++;
        } elsif ($line =~ /^\s*:\s*(\w+)\b/) {
            $inc = $1;
            $label = uc($inc);
            if (defined $g_labels{$label}) {
                $ra = $g_labels{$label};
                $cnt = scalar @{$ra};
                $msg = '';
                for ($i = 0; $i < $cnt; $i++) {
                    $plnn = ${$ra}[$i][0];
                    $pline = ${$ra}[$i][1];
                    $msg .= "\n$plnn: $pline";
                }
                prtw("WARNING: $lnn: LABEL [$inc] is duplicated [$line] $cnt $msg\n");
            } else {
                $g_labels{$label} = [];
                prt("[v5] $lnn: LABEL $inc [$line]\n") if (VERB5() || $show_labels);
            }
            $ra = $g_labels{$label};
            push(@{$ra}, [$lnn, $line, $inc]);
        } elsif ($line =~ /^\s*\@*exit\s+/i) {
            # ignore exit command
        } elsif ($line =~ /^\s*\@*cmake\s+/i) {
            # ignore cmake command
        } elsif ($line =~ /^\s*\@*call\s+/i) {
            # ignore call command
        } elsif ($line =~ /^\s*\@*rd\s+/i) {
            # ignore rd command
        } elsif ($line =~ /^\s*\@*if\s+/i) {
            # ignore if command
        } elsif ($line =~ /^\s*\)/) {
            # ignore closing brackets
        } else {
            prtw("[v2] WARNING $lnn: UNPROCESSED [$line]! *** FIX ME ***\n") if (VERB2());
        }
    }

    # get lists of LABELS and GOTO or CALL targets
    my @larr = keys %g_labels;
    my @garr = keys %g_gotos;
    if (VERB5()) {
        prt("[v5] LABELS: ".join(" ",sort @larr)."\n");
        prt("[v5] GOorCA: ".join(" ",sort @garr)."\n");
    }
    # CHECK LABELS HAVE AT LEAST ONE GOTO
    $cnt = scalar @larr;
    prt("\nCheck each $cnt 'label' has a 'goto' $gcnt, or 'call' $ccnt statement...\n");
    $missed = 0;
    foreach $label (@larr) {
        $ra = $g_labels{$label};
        $cnt = scalar @{$ra};
        $msg = '';
        $fnd = 0;
        if (defined $g_gotos{$label}) {
            $fnd = 1;
        } else {
            if ($label =~ /^:/) {
                $tmp = substr($label,1);
                if (defined $g_gotos{$tmp}) {
                    $fnd = 1;
                } else {
                    prt("Why was label '$label', and '$tmp' NOT FOUND?\n");
                }
            } else {
                $tmp = ':'.$label;
                prt("Label '$label' without leading ':'! Trying '$tmp'\n");
                if (defined $g_gotos{$tmp}) {
                    $fnd = 1;
                } else {
                    prt("Why was label '$label', and '$tmp' NOT FOUND?\n");
                }
            }
        }
        if (!$fnd) {
            for ($i = 0; $i < $cnt; $i++) {
                $plnn = ${$ra}[$i][0];
                $pline = ${$ra}[$i][1];
                $msg .= "\n$plnn: $pline";
            }
            prt("WARNING: Appears 'label' [$label] WITHOUT a 'goto' or 'call'! $msg\n") if (VERB1());
            $missed++;
        }
    }
    $cnt = scalar @larr;
    if ($missed) {
        prt("Of $cnt labels, appears $missed target labels without 'goto' or 'call' statement!\n");
        prt("These are no problems, but it is not very tidy...\n");
    } else {
        prt("Of $cnt labels, there appears to be NO target labels without 'goto' or 'call'.\n");
    }

    # CHECK GOTO HAS A TARGET LABEL
    my $kcnt = scalar @garr;
    $gcnt = 0;
    $ccnt = 0;
    $tcnt = 0;
    foreach $label (@garr) {
        ##             0     1     2      3
        #push(@{$ra}, [$lnn, $line, $inc, 0]);
        $ra = $g_gotos{$label};
        $cnt = scalar @{$ra};
        $tcnt += $cnt;
        for ($i = 0; $i < $cnt; $i++) {
            $flg = ${$ra}[$i][3];
            if ($flg) {
                $ccnt++;
            } else {
                $gcnt++;
            }
        }
    }

    prt("\nCheck $kcnt keys, total $tcnt, $gcnt 'goto' and $ccnt 'call' has a target label...\n");
    $missed = 0;
    foreach $label (keys %g_gotos) {
        $ra = $g_gotos{$label};
        $cnt = scalar @{$ra};
        $msg = '';
        $fnd = 0;
        if (defined $g_labels{$label}) {
            $fnd = 1;
        } else {
            $msg = "Label '$label' ";
            if ($label =~ /^:/) {
                $tmp = substr($label,1);
            } else {
                $tmp = ':'.$label;
            }
            $msg .= "alt '$tmp' ";
            if (defined $g_gotos{$tmp}) {
                $fnd = 1;
                $msg .= "found ";
            } else {
                $msg .= "NOT FOUND ";
                prt("$msg\n");
            }
            $msg = "";
        }
        if (!$fnd) {
            for ($i = 0; $i < $cnt; $i++) {
                $plnn = ${$ra}[$i][0];
                $pline = ${$ra}[$i][1];
                $msg .= "\n$plnn: $pline";
            }
            prt("WARNING: Appears 'goto' [$label] WITHOUT a target! $msg\n");
            $missed++;
        }
    }
    if ($missed) {
        prt("Of $kcnt keys, appear to be $missed missing target labels!\n");
        prt("These **MUST** be fixed in the file [$inf]\n");
    } else {
        prt("Of $kcnt keys, there appears to be NO missing target labels in [$inf]!\n");
    }
}

sub process_in_files() {
    my ($file);
    foreach $file (@in_files) {
        process_in_file($file);
    }
}


#########################################
### MAIN ###
parse_args(@ARGV);
process_in_files();
pgm_exit(0,"");
########################################

sub has_wild_cards($) {
    my $fil = shift;
    return 1 if ($fil =~ /(\?|\*)/);
    return 0;
}

sub set_input_files($) {
    my $file = shift;
    if (has_wild_cards($file)) {
        my @arr = glob $file;
        my $cnt = scalar @arr;
        if ($cnt) {
            prt("Wild card [$file] returned $cnt files, added to input.\n") if (VERB1());
            push(@in_files,@arr);
            return $arr[0];
        } else {
            pgm_exit(1,"ERROR: File mask [$file] returned NO entries!\n");
        }
    } elsif (-f $file) {
        push(@in_files,$file);
        return $file;
    } else {
        pgm_exit(1,"ERROR: Unable to locate [$file]!\n");
    }
}


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
                prt("Verbosity = $verbosity\n") if (VERB1());
            } elsif ($sarg =~ /^l/) {
                $load_log = 1;
                prt("Set to load log at end.\n") if (VERB1());
            } elsif ($sarg =~ /^s/) {
                $show_labels = 1;
                prt("Set to show labels when found.\n") if (VERB1());
            } elsif ($sarg =~ /^o/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_xml = $sarg;
                prt("Set out file to [$out_xml].\n") if (VERB1());
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            $in_file = set_input_files($arg);
            prt("Set input to [$in_file]\n") if (VERB1());
        }
        shift @av;
    }

    if ((length($in_file) ==  0) && $debug_on) {
        $in_file = $def_file;
        prt("Set DEFAULT input to [$in_file]\n");
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
    prt("Usage: $pgmname [options] in-file [file2 *.c *.h]\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --show        (-s) = Show labels when found. (def=$show_labels)\n");
    prt(" --out <file>  (-o) = Write output to this file.\n");
}

# eof - chkbatlabel.pl
