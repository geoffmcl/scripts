#!/usr/bin/perl -w
# NAME: nasreline.pl
# AIM: Given a nasal file, try to reline it...
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
my $VERS = "0.0.6 2015-07-11";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';
my $PATH_SEP = '/';
my $tmpout = $temp_dir."/tempreline.nas";
my $ind_char = '    ';  # 4 space indenting
my $show_quoted_items = 0;

# ### DEBUG ###
my $debug_on = 1;
my $def_file = 'C:\GTools\perl\uas-demo.nas';

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

sub process_in_file($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($line,$inc,$lnn,$i,$len,$ch,$indent,$inquot,$qc,$addnl,$i2,$quot);
    $lnn = 0;
    $indent = 0;
    my @brackets = ();
    my @braces = ();
    my $ncode = ''; # new code line, with indent addedd
    my @nlines = ();
    my @quotes = ();
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        $len = length($line);
        if ($line =~ /^\s*\#/) {
            # nasal comment line
            push(@nlines,$line);
            next;
        }
        $addnl = 0;
        for ($i = 0; $i < $len; $i++) {
            $ch = substr($line,$i,1);
            if ($inquot) {
                if ($ch eq $qc) {
                    $inquot = 0;
                    if ( !($quot =~ /^\s*$/) ) {
                        push(@quotes,$quot);
                    }
                } else {
                    $quot .= $ch;
                }
            } else {
                if ($ch eq '"') {
                    $inquot = 1;
                    $qc = $ch;
                    $quot = '';
                } elsif ($ch eq '(') {
                    push(@brackets,$lnn);
                } elsif ($ch eq ')') {
                    if (@brackets) {
                        pop @brackets;
                    }
                } elsif ($ch eq '{') {
                    push(@braces,$lnn);
                    $indent++;
                    $ncode .= $ch;
                    $i2 = $i + 1;
                    # preview the following content, looking for ';'
                    for (; $i2 < $len; $i2++) {
                        $ch = substr($line,$i2,1);
                        if ($ch =~ /\s/) {
                            # allow spaces
                        } elsif ($ch eq '}') {
                            # allow close
                        } else {
                            last;
                        }
                    }
                    if ($ch eq ';') {
                        $i2 = $i + 1;
                        for (; $i2 < $len; $i2++) {
                            $ch = substr($line,$i2,1);
                            if ($ch =~ /\s/) {
                                $ncode .= $ch;
                                $i = $i2;
                            } elsif ($ch eq '}') {
                                $ncode .= $ch;
                                $i = $i2;
                                if (@braces) {
                                    pop @braces;
                                }
                                $indent-- if ($indent);
                            } elsif ($ch eq ';') {
                                $ncode .= $ch;
                                $i = $i2;
                            } else {
                                last;
                            }
                        }
                    }
                    push(@nlines,$ncode);
                    $ncode = $ind_char x $indent;
                    $ch = '';   # dealt with char
                } elsif ($ch eq '}') {
                    if (@braces) {
                        pop @braces;
                    }
                    $indent-- if ($indent);
                    if ($ncode =~ /^\s*$/) {
                        # nothing to add
                    } else {
                        push(@nlines,$ncode); # add this line
                    }
                    $ncode = $ind_char x $indent; # create indent 1 less
                    $ncode .= $ch;
                    push(@nlines,$ncode);
                    $ncode = $ind_char x $indent;
                    $ch = '';   # dealt with character
                } elsif ($ch eq ';') {
                    # add this line, plus any comments
                    $ncode .= $ch;
                    if ($ncode =~ /^\s*for\s*\(/) {
                        next;   # have added char to nocode, but in a for, NO NEW LINES
                    }
                    $i++;
                    for (; $i < $len; $i++) {
                        $ch = substr($line,$i,1);
                        if ($ch =~ /\s/) {
                            $ncode .= $ch;
                        } elsif ($ch eq '#') {
                            # add the end of line command
                            $ncode .= $ch;
                            $i++;
                            for (; $i < $len; $i++) {
                                $ch = substr($line,$i,1);
                                $ncode .= $ch;  # add all the comment
                            }
                        } else {
                            $i--;   # back up to deal with this character
                            last; # might have added some spaces
                        }
                    }
                    push(@nlines,$ncode);
                    $ncode = $ind_char x $indent;
                    $ch = '';   # dealt with this character
                }
            }
            $ncode .= $ch;
        }
        $inquot = 0;    # would be BAD if still in QUOTES
    }
    $line = join("\n",@nlines)."\n";
    write2file($line,$tmpout);
    prt("Written relined nasal to $tmpout\n");
    $len = scalar @quotes;
    my %dupes = ();
    if ($len) {
        prt("List of $len quoted text items...\n");
        $len = 0;
        foreach $line (sort @quotes) {
            if (defined $dupes{$line}) {
                $dupes{$line}++;
            } else {
                $dupes{$line} = 1;
                prt("$line\n") if ($show_quoted_items);
                $len++;
            }
        }
        prt("Done list of $len unique quoted text items...\n");
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
}

# eof - nasreline.pl
