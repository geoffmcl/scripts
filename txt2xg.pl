#!/usr/bin/perl -w
# NAME: txt2xg.pl
# AIM: SPECIALISED! Just to load a sid/star/... txt file in a little like INI format,
# and out an xg(raph) of any esults found.
# 19/08/2015 geoff mclane http://geoffair.net/mperl
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
my $cwd = cwd();
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
unshift(@INC, $perl_dir);
my $PATH_SEP = '/';
my $CDATROOT="/media/Disk2/FG/fg22/fgdata"; # 20150716 - 3.5++
if ($os =~ /win/i) {
    $PATH_SEP = "\\";
    $CDATROOT="F:/fgdata"; # 20140127 - 3.1
}
###require 'logfile.pl' or die "Error: Unable to locate logfile.pl ...\n";
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
# log file stuff
our ($LF);
my $outfile = $temp_dir.$PATH_SEP."temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';

# ### DEBUG ###
my $debug_on = 1;
#my $def_file = 'C:\Users\user\Documents\FG\LFPO.procedures.txt';
my $def_file = $perl_dir.'circuits'.$PATH_SEP.'LFPO.procedures.txt';

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

######################################################################
my $apt_file = $CDATROOT.$PATH_SEP.'Airports'.$PATH_SEP.'apt.dat.gz';
my $awy_file = $CDATROOT.$PATH_SEP.'Navaids'.$PATH_SEP.'awy.dat.gz';
my $fix_file = $CDATROOT.$PATH_SEP.'Navaids'.$PATH_SEP.'fix.dat.gz';

my $apts_csv = $perl_dir.'circuits'.$PATH_SEP.'airports2.csv';
my $rwys_csv = $perl_dir.'circuits'.$PATH_SEP.'runways.csv';

sub load_gzip_file($) {
    my ($fil) = shift;
	prt("[v2] Loading [$fil] file... moment...\n") if (VERB2());
	mydie("ERROR: Can NOT locate [$fil]!\n") if ( !( -f $fil) );
	open NIF, "gzip -d -c $fil|" or mydie( "ERROR: CAN NOT OPEN $fil...$!...\n" );
	my @arr = <NIF>;
	close NIF;
    prt("[v9] Got ".scalar @arr." lines to scan...\n") if (VERB9());
    return \@arr;
}

my ($rfixarr);
my $done_fix_arr = 0;
sub load_fix_file {
    return $rfixarr if ($done_fix_arr);
    $rfixarr = load_gzip_file($fix_file);
    $done_fix_arr = 1;
    return $rfixarr;
}

sub get_fix_sample() {
    my $stg = <<EOF;
I
600 Version - data cycle 2009.12, build 20091080, metadata FixXP700.  Copyright (c) 2009, Robin A. Peel (robin\@xsquawkbox.net).
 52.013889 -000.052778 ASKEY
 50.052778  008.533611 ASKIK
 54.503333  031.086667 ASKIL
99
EOF
    return $stg;
}

my ($rfixhash);
my $done_fix_hash = 0;

sub load_fix_hash($) {
    my ($rfa) = @_;
    return $rfixhash if ($done_fix_hash);
    my $max = scalar @{$rfa};
    my ($line,$len,@arr,$cnt,$typ,$flat,$flon,$fname,$name,$key);
    my %h;
    foreach $line (@{$rfa}) {
        chomp $line;
        $line = trim_all($line);
        $len = length($line);
        next if ($len == 0);
        next if ($line =~ /^I/);
        @arr = split(/\s+/,$line);
        $cnt = scalar @arr;
        $typ = $arr[0];
        next if ($typ == 600);
        last if ($typ == 99);
        if ($cnt >= 3) {
            $flat = $arr[0];
            $flon = $arr[1];
            $name = trim_all($arr[2]);
            $h{$name} = [ $flat, $flon ];
        }
    }
    $rfixhash = \%h;
    $done_fix_hash = 1;
    @arr = keys %h;
    $len = scalar @arr;
    prt("Loaded $len fixes from $fix_file\n");
    return $rfixhash;
}


sub search_fix_file($) {
    my ($name) = @_;
    my ($flat,$flon,$rll,$key);
    my $rfa = load_fix_file();
    # my $raa = load_awy_file();
    my $tfh = load_fix_hash($rfa);
    my $cnt = scalar keys %{$tfh};
    prt("[v2] Searching $cnt fix records for [$name]\n") if (VERB2());
    $cnt = 0;
    foreach $key (keys %{$tfh}) {
        if ($key =~ /$name/) {
            $rll = ${$tfh}{$key};
            $flat = ${$rll}[0];
            $flon = ${$rll}[1];
            $flat  = sprintf("%.8f",$flat);
            $flon  = sprintf("%.8f",$flon);
            prt("FIX: $key $flat $flon\n") if (VERB9());
            $cnt++;
            last;
        }
    }
    return $cnt;
}


#######################################################################

sub process_in_file($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($line,$inc,$lnn,$len,$section,@arr,$cnt,$i);
    my ($ns,$ew,$lat,$lon,$dlat,$dlon,$name);
    my (@arr2,$wp);
    $lnn = 0;
    my %waypoints = ();
    #my $rfh = search_fix_file("MATIX");
    my $rfa = load_fix_file();
    my $rfh = load_fix_hash($rfa);

    $section = '';
    foreach $line (@lines) {
        chomp $line;
        $line = trim_all($line);
        $lnn++;
        $len = length($line);
        next if ($len == 0);
        if ($line =~ /^\s*\#/) {
            # skip comments
        } elsif ($line =~ /^\[(.+)\]/) {
            $section = $1; # section
            last if ($section eq 'EOF');
        } else {
            @arr = split("=",$line);
            $cnt = scalar @arr;
            for ($i = 0; $i < $cnt; $i++) {
                $inc = trim_all($arr[$i]);
                $arr[$i] = $inc;
            }
            if ($cnt != 2) {
                prtw("WARNING:$lnn: [$line] spit in $cnt! Expected 2\n");
                next;
            }
            $name = $arr[0];
            $inc  = $arr[1];
            if ($section =~ /^STAR/) {
            } elsif ($section =~ /^SID/) {
            } elsif ($section =~ /^APP/) {
            } elsif ($section eq 'WAYPOINTS') {
                # if ($inc =~ /^[NS]([0-8][0-9](\.[0-5]\d){2}|90(\.00){2})\040[EW]((0\d\d|1[0-7]\d)(\.[0-5]\d){2}|180(\.00){2})$/)
                # VEBEK = N49 16.1 E003 41.0 At FL110 MAX 280 KT
                # if ($inc =~ /^(N|S)(\d{2}\s+(\d|\.)+\s+(E|W)(\d{3}\s+(\d|\.)+\s+/) {
                if ($inc =~ /^(N|S)(\d{2})\s+(.+)\s+(E|W)(\d{3})\s+(\d|\.)+/) {
                    $ns = $1;
                    $lat = $2;
                    $dlat = $3;
                    $ew = $4;
                    $lon = $5;
                    $dlon = $6;
                    $lat += $dlat / 60;
                    $lon += $dlon / 60;
                    prt("$lnn: $name $lat,$lon\n") if (VERB9());
                    $waypoints{$name} = [$lat,$lon];
                } else {
                    prtw("WARNING:$lnn: [$inc] failed regex\n");
                }
            } else {
                pgm_exit(1,"Error: Section [$section] not coded! *** FIX ME ***\n");
            }
        }
    }
    @arr = keys %{$rfh};
    foreach $name (@arr) {
        $waypoints{$name} = ${$rfh}{$name}; # [$lat,$lon];
    }

    $lnn = 0;
    $section = '';
    my %dupes = ();
    foreach $line (@lines) {
        chomp $line;
        $line = trim_all($line);
        $lnn++;
        $len = length($line);
        next if ($len == 0);
        if ($line =~ /^\s*\#/) {
            # skip comments
        } elsif ($line =~ /^\[(.+)\]/) {
            $section = $1; # section
            last if ($section eq 'EOF');
            prt("$lnn: section $section\n");
        } else {
            @arr = split("=",$line);
            $cnt = scalar @arr;
            for ($i = 0; $i < $cnt; $i++) {
                $inc = trim_all($arr[$i]);
                $arr[$i] = $inc;
            }
            if ($cnt != 2) {
                prtw("WARNING:$lnn: [$line] spit in $cnt! Expected 2\n");
                next;
            }
            $name = $arr[0];
            $inc  = $arr[1];
            if ($section =~ /^STAR/) {
                @arr2 = split(/\s+/,$name);
                $name = $arr2[0];
                @arr2 = split("-",$inc);
                $cnt = scalar @arr2;
                for ($i = 0; $i < $cnt; $i++) {
                    $inc = trim_all($arr2[$i]);
                    $arr2[$i] = $inc;
                }
                prt("$lnn:star $name = ".join(" ",@arr2)."\n");
                for ($i = 0; $i < $cnt; $i++) {
                    $wp = $arr2[$i];
                    last if ($wp =~ /^\#/);
                    if (! defined $waypoints{$wp}) {
                        if (! defined $dupes{$wp}) {
                            $dupes{$wp} = 1;
                            prtw("WARNING: star waypoint [$wp] NOT in hash!\n");
                        }
                    }
                }

            } elsif ($section =~ /^SID/) {
                # to do
            } elsif ($section =~ /^APP/) {
                @arr2 = split("-",$inc);
                $cnt = scalar @arr2;
                for ($i = 0; $i < $cnt; $i++) {
                    $inc = trim_all($arr2[$i]);
                    $arr2[$i] = $inc;
                }
                prt("$lnn:app $name = ".join(" ",@arr2)."\n");
                for ($i = 0; $i < $cnt; $i++) {
                    $wp = $arr2[$i];
                    last if ($wp =~ /^\#/);
                    if (! defined $waypoints{$wp}) {
                        if (! defined $dupes{$wp}) {
                            $dupes{$wp} = 1;
                            prtw("WARNING: app waypoint [$wp] NOT in hash!\n");
                        }
                    }
                }
            } elsif ($section eq 'WAYPOINTS') {
                # done WAYPOINTS, if any
            } else {
                pgm_exit(1,"Error: Section [$section] not coded! *** FIX ME ***\n");
            }
        }
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

# eof - template.pl
