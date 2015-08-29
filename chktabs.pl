#!/usr/bin/perl -w
# NAME: chktabs.pl
# AIM: Read a file and report number of lines containing a tab character
# 29/08/2015 - Add a check for leading and trailing new lines
# 29/08/2015 - Add to script repo, and extend to input directories
# 15/03/2015 - Allow multiple files, and wild cards...
# #####################################################################
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
my $os = $^O;
my $cwd = cwd();
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
my $PATH_SEP = '/';
if ($os =~ /win/i) {
    $PATH_SEP = "\\";
}
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
# log file stuff
our ($LF);
my $outfile = $temp_dir.$PATH_SEP."temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.7 2015-08-29";
#my $VERS = "0.0.6 2015-03-15";
#my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_file = '';
my @in_files = ();
my $verbosity = 0;
my $out_file = '';
my $g_recurse = 0;

my %files_with_tab = ();
my %files_with_htb = ();

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'F:\Projects\tidy-html5\src\*.c';

### program variables
my @warnings = ();
my $usr_input = '';

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

my %done_files = ();
my $total_files = 0;
my $total_lines = 0;
my $total_bytes = 0;
sub process_in_file($) {
    my ($inf) = @_;
    if (defined $done_files{$inf}) {
        return;
    }
    $done_files{$inf} = 1;
	my $oinf = $inf;
	if (($inf =~ /\.(\\|\/)/)||($inf =~ /(\\|\/)\.\.(\\|\/)/)) {
		$inf = fix_rel_path($inf);
		if (defined $done_files{$inf}) {
			return;
		}
	    $done_files{$inf} = 1;
	}
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf] ($oinf)\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    $total_files++;
    $total_lines += $lncnt;
    prt("Processing $lncnt lines, from [$inf]...\n") if (VERB5());
    my ($line,$ch,$lnn,$i,$len,$txt,$tline);
    my $lnswtab = 0;
    my $tabcount = 0;
    $lnn = 0;
    my $gottab = 0;
    my $lnswtsp = 0;
    my $spcount = 0;
    my $leadblks = 0;
    my $tailblks = 0;
    my $had_len = 0;
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        $len = length($line);
        $total_bytes += $len + 1;
        $gottab = 0;
        for ($i = 0; $i < $len; $i++) {
            $ch = substr($line,$i,1);
            if ($ch eq "\t") {
                $gottab++;
            }
        }
        if ($gottab) {
            $tabcount += $gottab;
            $lnswtab++;
        }
        if ($line =~ /(\s+)$/) {
            $txt = $1;
            $lnswtsp++;
            $spcount += length($txt);
        }

		# add a leading and tailing NEWLINE count
        $tline = trim_all($line);	# trim ALL leading/trailing SPACE
        $len = length($tline);		# get length of result
        if ($len) {
            $had_len = 1;		# has a LENGTH
            $tailblks = 0;		# restart tail counter
        } else {
            # is a blank line...
            if ($had_len) {
                $tailblks++;	# had a length, count a tailing newline only
            } else {
                $leadblks++;	# no line with length yet, add a leading newline only
            }
        }
    }
    if ($lnswtab || $lnswtsp) {
        #                        0    1        2         3        4
        $files_with_tab{$inf} = [$lnn,$lnswtab,$tabcount,$lnswtsp,$spcount];
        prt("$inf: Have $lnswtab lines contain a 'tab'. Total of $tabcount tabs. $lnswtsp end w/space\n") if (VERB2());
    }
	# keep leading and tailing newline stats
    if ($tailblks | $leadblks) {
        $files_with_htb{$inf} = [$lnn,$leadblks,$tailblks];
    }
}

sub show_results() {
    my $have_out = length($out_file);
    my @arr = keys %files_with_tab;
    my ($ra,$lns,$wtab,$tcnt,$tscnt,$endsp,$pct,$tsp,$pct2,$tmp,$len);
    my $txt = '';
    $tmp = "\nFrom user input '$usr_input'\n".
        "processed $total_files files, $total_lines lines, appx $total_bytes bytes...\n";
    if ($have_out) {
        $txt .= $tmp;
    } else {
        prt($tmp);
    }
    my $cnt = scalar @arr;
    $tcnt = 0;
    $endsp = 0;
    my $total_tabs = 0;
    my $total_lwtsp = 0;
    my $total_tsp = 0;
	my $min_len = 0;
    #                         0    1        2         3        4
    #$files_with_tab{$inf} = [$lnn,$lnswtab,$tabcount,$lnswtsp,$spcount];
    foreach $in_file (@arr) {
        $ra = $files_with_tab{$in_file};
        $lns = ${$ra}[0];
        $wtab = ${$ra}[1];
        $cnt = ${$ra}[2];
        $tscnt = ${$ra}[3];
        $total_tsp += ${$ra}[4];
        if ($cnt) {
            $tcnt++;
            $total_tabs += $cnt;
        }
        if ($tscnt) {
            $endsp++;
            $total_lwtsp += $tscnt;
        }
    }
    $pct = ($total_tabs / $total_bytes) * 100;
    $pct = int($pct * 100) / 100;
    $tmp = "\nFound $tcnt files with tabs... $total_tabs total tabs, $pct \%...\n";
    if ($have_out) {
        $txt .= $tmp;
    } else {
        prt($tmp);
    }
	$min_len = 0;
    foreach $in_file (@arr) {
        $ra = $files_with_tab{$in_file};
        $cnt = ${$ra}[2];
        if ($cnt) {
			$len = length($in_file);
			$min_len = $len if ($len > $min_len);
        }
        $cnt = ${$ra}[3];
        if ($cnt) {
			$len = length($in_file);
			$min_len = $len if ($len > $min_len);
        }
    }
    foreach $in_file (@arr) {
        $ra = $files_with_tab{$in_file};
        $lns = ${$ra}[0];
        $wtab = ${$ra}[1];
        $cnt = ${$ra}[2];
        if ($cnt) {
			$in_file .= ' ' while (length($in_file) < $min_len);
            $tmp = "$in_file - $lns lines, $wtab w/tab, $cnt tabs\n";
            if ($have_out) {
                $txt .= $tmp;
            } else {
                prt($tmp);
            }
        }
    }
    $pct = ($total_lwtsp / $total_lines) * 100;
    $pct = int($pct * 10) / 10;
    $pct2 = ($total_tsp / $total_bytes) * 100;
    $pct2 = int($pct2 * 100) / 100;
    $tmp = "\nFound $endsp files with trailing spaces... $total_lwtsp total lines end space, $pct \%, tot.sp $total_tsp, $pct2 \%\n";
    if ($have_out) {
        $txt .= $tmp;
    } else {
        prt($tmp);
    }

    foreach $in_file (@arr) {
        $ra = $files_with_tab{$in_file};
        $cnt = ${$ra}[3];
        if ($cnt) {
			$len = length($in_file);
			$min_len = $len if ($len > $min_len);
		}
	}
    foreach $in_file (@arr) {
        $ra = $files_with_tab{$in_file};
        $lns = ${$ra}[0];
        $wtab = ${$ra}[1];
        $tcnt = ${$ra}[2];
        $cnt = ${$ra}[3];
        $tsp = ${$ra}[4];
        if ($cnt) {
			$in_file .= ' ' while (length($in_file) < $min_len);
            $tmp = "$in_file - $lns lines, $wtab w/tab, $tcnt tabs, $cnt lines with trailing spaces $tsp\n";
            if ($have_out) {
                $txt .= $tmp;
            } else {
                prt($tmp);
            }
        }
    }

    @arr = keys %files_with_htb;    # {$inf} = [$lnn,$leadblks,$tailblks];
    $cnt = scalar @arr;
    my $t_leadblks = 0;
    my $t_tailblks = 0;
    foreach $in_file (@arr) {
        $ra = $files_with_tab{$in_file};
        $lns = ${$ra}[0];
        $wtab = ${$ra}[1];
        $tcnt = ${$ra}[2];
        $t_leadblks += $wtab;
        $t_tailblks += $tcnt;
    }

    if ($cnt | $t_leadblks | $t_tailblks) {
        $tmp = "\nHave $cnt with leading $t_leadblks tailing $t_tailblks blank lines\n";
        if ($have_out) {
            $txt .= $tmp;
        } else {
            prt($tmp);
        }
		foreach $in_file (@arr) {
			$ra = $files_with_tab{$in_file};
			$lns = ${$ra}[0];
			$wtab = ${$ra}[1];
			$tcnt = ${$ra}[2];
			$in_file .= ' ' while (length($in_file) < $min_len);
			$tmp = "$in_file: leading $wtab, tailing $tcnt\n";
			if ($have_out) {
				$txt .= $tmp;
			} else {
				prt($tmp);
			}
		}
    }

    if ($have_out) {
        $txt .= "\n";
    } else {
        prt("\n");
    }
    if ($have_out) {
        rename_2_old_bak($out_file);
        write2file($txt,$out_file);
        prt("Results written to $out_file\n");
    }

}

sub process_in_files() {
    foreach $in_file (@in_files) {
        process_in_file($in_file);
    }
}

#########################################
### MAIN ###
parse_args(@ARGV);
process_in_files();
show_results();
pgm_exit(0,"");
########################################

sub got_wild($) {
    my $fil = shift;
    return 1 if ($fil =~ /\*/);
    return 1 if ($fil =~ /\?/);
    return 0;
}
sub glob_wild($) {
    my $fil = shift;
    my @files = glob($fil);
    my $cnt = scalar @files;
    if ($cnt) {
        prt("Adding $cnt files, from [$fil] input.\n");
        push(@in_files,@files);
        $in_file = $files[0];
    } else {
        pgm_exit(1,"ERROR: Got no files, from [$fil] input.\n");
    }
}

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub process_in_dir($$);

sub add_a_file($) {
    my $arg = shift;
    my $verb = VERB2();
    if (got_wild($arg)) {
        glob_wild($arg);
    } elsif (-d $arg) {
        process_in_dir($arg,0);
    } else {
        $in_file = $arg;
        push(@in_files,$in_file);
        if (-f $in_file) {
            prt("Set input to [$in_file]\n") if ($verb);
        } else {
            pgm_exit(1,"Error: Can NOT stat '$in_file'!\n");
        }
    }
}

sub process_in_dir($$) {
    my ($dir,$lev) = @_;
    if (!opendir(DIR,$dir)) {
        prtw("WARNING: Unable to open dir $dir\n");
        return;
    }
    my @files = readdir(DIR);
    closedir(DIR);
    my ($file,$ff);
    ut_fix_directory(\$dir);
    my @dirs = ();
    foreach $file (@files) {
        next if ($file eq '.');
        next if ($file eq '..');
        $ff = $dir.$file;
        if (-d $ff) {
            push(@dirs,$ff);
        } elsif (-f $ff) {
            $in_file = $ff;
            push(@in_files,$ff);
        } else {
            pgm_exit(1,"What is this $ff! ($file)!\n *** FIX ME ***\n");
        }
    }
    if ($g_recurse) {
        foreach $dir (@dirs) {
            process_in_dir($dir,($lev+1));
        }
    }
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
            } elsif ($sarg =~ /^r/) {
                $g_recurse = 1;
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            $usr_input .= ' ' if (length($usr_input));
            $usr_input .= $arg;
            add_a_file($arg);
        }
        shift @av;
    }

    if ($debug_on) {
        prtw("WARNING: DEBUG is ON!\n");
        if (length($in_file) ==  0) {
            add_a_file($def_file);
            prt("Set DEFAULT input to [$in_file]\n");
        }
    }
    if (length($in_file) ==  0) {
        give_help();
        pgm_exit(1,"\nERROR: No input file found in command!\n");
    }
    if (! -f $in_file) {
        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
    }
}

sub give_help {
    prt("\n");
    prt("$pgmname: version $VERS\n");
    prt("\n");
    prt("Usage: $pgmname [options] in-file/in-mask/in-dir\n");
    prt("\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>  (-o) = Write output to this file.\n");
    prt(" --recursive   (-r) = Given a directory, recurse into sub directories. (def=$g_recurse)\n");
    prt("\n");
    prt(" Will process input files as text, and count total lines, advise\n");
    prt(" lines containing tabs, and trailing spcaes. Inputs containing wild\n");
    prt(" cards '?' or '*', and directories are accepted.\n");
}

# eof - chktabs.pl
