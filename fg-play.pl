#!/usr/bin/perl -w
# NAME: fg-play.pl
# AIM: Read a FG playback generic protocol file
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use XML::Simple;
use Data::Dumper;
use Math::Trig;
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";

# log file stuff
our ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
$outfile = ($os =~ /win/i) ? path_u2d($outfile) : path_d2u($outfile);
open_log($outfile);

# user variables
my $VERS = "0.0.6 2016-04-18";
###my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = $temp_dir."/tempnew.csv";
my $def_proto_file = 'D:\FG\fg-64\install\FlightGear\fgdata\Protocol\playback.xml';
my $min_ias = 0;    # skip records below this

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'D:\FG\fg-64\tempp3.csv';
my $def_ias = 53;

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


my %inputs = (
    'var_separator' => ',',
    'line_separator' => 'newline',
    'chunk' => 1
    );


#my %chunk1 = (
# 'magnetos' => { 'type' => 'float', 'node' => '/controls/engines/engine[1]/magnetos' },
#);
# 'altitude-ft' => { 'type' => 'float', 'node' => '/position/altitude-ft' },
# 'latitude-deg' => { 'type' => 'double', 'node' => '/position/latitude-deg' },
# 'longitude-deg' => { 'type' => 'double', 'node' => '/position/longitude-deg' },

sub process_in_file($) {
    my ($inf) = @_;
    my $xref = XMLin($inf);
    # prt(Dumper($xref));
    # can MAYBE keep 'order' if an ARRAY used
    ##my $xref = XMLin($inf, ForceArray => 1);
    ##prt(Dumper($xref));
    $load_log = 1;
    my $root = 'PropertyList';
    my $b1 = 'generic';
    my $bin = 'input';
    my $bout = 'output';

    if (! defined ${$xref}{$b1}) {
        pgm_exit(1,"File $inf does not have '$b1'\n");
    }
    my $rn1 = ${$xref}{$b1};
    my (@iarr,@oarr,$icnt,$ocnt);
    my ($rin,$rout,$rinch,$rotch,$ch,$rh,$node,$len,$ccnt,$type);
    my $invsep = ',';
    my $inlsep = 'newline';
    my $otvsep = ',';
    my $otlsep = 'newline';
    prt("Found $b1");
    $icnt = 0;
    $ocnt = 0;
    ###pgm_exit(1,"TEMP EXIST\n");
    if (defined ${$rn1}{$bin}) {
        $rin = ${$rn1}{$bin};
        prt("/$bin");
        if (defined ${$rin}{var_separator}) {
            $invsep = ${$rin}{var_separator};
            prt(",ivs=$invsep");
        }
        if (defined ${$rin}{line_separator}) {
            $inlsep = ${$rin}{line_separator};
            prt(",ils=$inlsep");
        }
        if (defined ${$rin}{chunk}) {
            $rinch = ${$rin}{chunk};
            @iarr = keys %{$rinch};
            $icnt = scalar @iarr;
            prt(",chk=$icnt");
        } else {
            prt(",chk=NONE");
        }

    }

    if (defined ${$rn1}{$bout}) {
        $rout = ${$rn1}{$bout};
        prt("/$bout");
if (defined ${$rout}{var_separator}) {
            $otvsep = ${$rout}{var_separator};
            prt(",ovs=$otvsep");
        }
        if (defined ${$rout}{line_separator}) {
            $otlsep = ${$rout}{line_separator};
            prt(",ols=$otlsep");
        }
        if (defined ${$rout}{chunk}) {
            $rotch = ${$rout}{chunk};
            @oarr = keys %{$rotch};
            $ocnt = scalar @oarr;
            prt(",chk=$ocnt");
        } else {
            prt(",chk=NONE");
        }
    }
    prt("\n");
    my $min = 0;
    if ($icnt) {
        prt("List of $icnt OUPUT nodes...\n");
        $icnt = 0;
        foreach $ch (@iarr) {
            $len = length($ch);
            $min = $len if ($len > $min);
        }
        foreach $ch (@iarr) {
            $rh = ${$rinch}{$ch};
            if (defined ${$rh}{node}) {
                $node = ${$rh}{node};
                $icnt++;
                $ccnt = sprintf("%2d",$icnt);
                $ch .= ' ' while (length($ch) < $min);
                prt("$ccnt: $ch $node\n");
            }
        }
    }
    if ($ocnt) {
        prt("List of $ocnt INPUT nodes...\n");
        $ocnt = 0;
        foreach $ch (@oarr) {
            $len = length($ch);
            $min = $len if ($len > $min);
        }
        foreach $ch (@oarr) {
            $rh = ${$rotch}{$ch};
            if (defined ${$rh}{node}) {
                $node = ${$rh}{node};
                $ocnt++;
                $ccnt = sprintf("%2d",$ocnt);
                $ch .= ' ' while (length($ch) < $min);
                prt("$ccnt: $ch $node\n");
            }
        }
    }
}

sub process_in_file_TOO_DIFFICULT($) {
    my ($inf) = @_;
    #my $xref = XMLin($inf);
    # prt(Dumper($xref));
    # can MAYBE keep 'order' if an ARRAY used
    my $xref = XMLin($inf, ForceArray => 1);
    prt(Dumper($xref));
    $load_log = 1;
    my $root = 'PropertyList';
    my $b1 = 'generic';
    my $bin = 'input';
    my $bout = 'output';

    if (! defined ${$xref}{$b1}) {
        pgm_exit(1,"File $inf does not have '$b1'\n");
    }
    my $ra1 = ${$xref}{$b1};
    my $rn1 = ${$ra1}[0];
}

# this should be fixed offset
my $max_lat = 42;
my $min_lat = 40;

sub process_in_file_csv($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Process $lncnt lines form $inf...\n");
    my ($line,$lnn,@arr,$len,$val,$i,$i2,$lat,$lon,$alt);
    my ($rol,$pit,$hdg,$slip,$ias);
    $lnn = 0;
    my $icnt = 0;
    my @acvs = ();
    my $ioff = -1;
    my $skipped = 0;
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        $line = trim_all($line);
        $len = length($line);
        next if ($len == 0);
        @arr = split(",",$line);
        $len = scalar @arr;
        if ($len != $icnt) {
            $icnt = $len;
            prt("$lnn: $icnt elements...\n");
        }
        #if ($line =~ /\s*#\s*include\s+(.+)$/) {
        #    $inc = $1;
        #    prt("$lnn: $inc\n");
        #
        for ($i = 0; $i < $len; $i++) {
            $val = $arr[$i];
            $i2 = $i + 1;
            if (($val < $max_lat) && ($val > $min_lat) && (($i2 + 8) < $len)) {
                $lat = $val;
                $lon = $arr[$i2];
                $alt = $arr[$i2+1];
                $rol = $arr[$i2+2];
                $pit = $arr[$i2+3];
                $hdg = $arr[$i2+4];
                $slip = $arr[$i2+5];
                $ias = $arr[$i2+6];

                if ($ioff != $i) {
                    $ioff = $i;
                    prt("Lat,Lon,Alt offset is $ioff\n");
                }
                if ($alt > -9900) {
                    prt("$lnn: $lat,$lon,$alt\n") if (VERB5());
                    #           0    1    2    3    4    5    6     7
                    push(@acvs,[$lat,$lon,$alt,$rol,$pit,$hdg,$slip,$ias]);
                } else {
                    $skipped++; # skip these -9999 alt records
                    # fired **before** scenery loaded!!!
                }
                last;
            }
        }
    }
    $len = scalar @acvs;
    prt("Got $len CVS lines... skipped $skipped with altitude LT -9900\n");
    my $csv = "lon,lat,alt,hdg,ias,roll,pitch,slip\n";
    my ($ra);
    $len = 0;
    my $skipias = 0;
    foreach $ra (@acvs) {
        $lat = ${$ra}[0];
        $lon = ${$ra}[1];
        $alt = ${$ra}[2];
        $rol = ${$ra}[3];
        $pit = ${$ra}[4];
        $hdg = ${$ra}[5];
        $slip = ${$ra}[6];
        $ias = ${$ra}[7];

        if (($min_ias > 0) && ($ias < $min_ias)) {
            $skipias++;
            next;
        }

        # round out some values
        $alt = int($alt);
        $hdg = int($hdg);
        $ias = int($ias);

        $len++;
        $csv .= "$lon,$lat,$alt,$hdg,$ias,$rol,$pit,$slip\n";
    }
    write2file($csv,$out_file);
    prt("CVS lines $len, written to $out_file... ");
    if ($min_ias > 0) {
        prt("skipped $skipias below $min_ias...");
    }
    prt("\n");
}

#########################################
### MAIN ###
parse_args(@ARGV);
##### process_in_file($def_proto_file); # xml load, if needed
process_in_file_csv($in_file);
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
            } elsif ($sarg =~ /^s/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $min_ias = $sarg;
                prt("Set min, IAS Kts to [$min_ias].\n") if ($verb);
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
        if ($min_ias == 0) {
            $min_ias = $def_ias;
            prt("Set DEFAULT min. IAS $min_ias.\n");
        }
    }

    if (length($in_file) ==  0) {
        pgm_exit(1,"ERROR: No input files found in command!\n");
    }
    if (! -f $in_file) {
        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
    }

}

# eof

