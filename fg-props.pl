#!/usr/bin/perl -w
# NAME: fg-props.pl
# AIM: Test getting some FG TELENT properties
use strict;
use warnings;
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use IO::Socket;
use Term::ReadKey;
use Time::HiRes qw( usleep gettimeofday tv_interval );
#use Math::Trig;
use Math::Trig qw(great_circle_distance great_circle_direction deg2rad rad2deg);
my $cwd = cwd();
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "/temp";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl'! Check location and \@INC content.\n";
require 'lib_fgio.pl' or die "Unable to load 'lib_fgio.pl'! Check location and \@INC content.\n";
# log file stuff
our ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'def_file';


### program variables
my @warnings = ();

# my $HOST = "localhost";
my ($fgfs_io,$HOST,$PORT,$CONMSG,$TIMEOUT,$DELAY);
my $connect_win7 = 0;
if (defined $ENV{'COMPUTERNAME'}) {
    if (!$connect_win7 && $ENV{'COMPUTERNAME'} eq 'WIN7-PC') {
        # connect to Ubuntu in DELL02
        $HOST = "192.168.1.34"; # DELL02 machine
        $PORT = 5556;
        $CONMSG = "Assumed in WIN7-PC connection to Ubuntu DELL02 ";
    } else {
        # assumed in DELL01 - connect to WIN7-PC
        $HOST = "192.168.1.33"; # WIN7-PC machine
        $PORT = 5557;
        $CONMSG = "Assumed in DELL01 connection to WIN7-PC ";
    }
} else {
    # assumed in Ubuntu - connect to DELL01
    $HOST = "192.168.1.11"; # DELL01
    $PORT = 5551;
    $CONMSG = "Assumed in Ubuntu DELL02 connection to DELL01 ";
}
$TIMEOUT = 2;
$DELAY = 5;

sub VERB1() { return $verbosity >= 1; }
sub VERB2() { return $verbosity >= 2; }
sub VERB5() { return $verbosity >= 5; }
sub VERB9() { return $verbosity >= 9; }

sub prtt($) {
    my $txt = shift;
    if ($txt =~ /^\n/) {
        $txt =~ s/^\n//;
        prt("\n".lu_get_hhmmss_UTC(time()).": $txt");
    } else {
        prt(lu_get_hhmmss_UTC(time()).": $txt");
    }
}


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

sub wait_fgio_avail() {
    # sub fgfs_connect($$$) 
    prt("$CONMSG at IP $HOST, port $PORT\n");
    # get the TELENET connection
    $fgfs_io = fgfs_connect($HOST, $PORT, $TIMEOUT) ||
        pgm_exit(1,"ERROR: can't open socket!\n".
        "Is FG running on IP $HOST, with TELNET enabled on port $PORT?\n");

    ReadMode('cbreak'); # not sure this is required, or what it does exactly

	fgfs_send("data");  # switch exchange to data mode

}

my $last_decent_stats = 0;
sub show_decent_stats($$) {
    my ($rch,$rp) = @_;
    my $ctm = time();
    my $dtm = $ctm - $last_decent_stats;
    my $show_msg = 1;
    my ($ah,$gotah,$msg);
    $msg = '';
    if ($show_msg || ($dtm > $DELAY)) {
        $last_decent_stats = $ctm;
        # extract current POSIIION values
        my $lon  = ${$rp}{'lon'};
        my $lat  = ${$rp}{'lat'};
        my $alt  = ${$rp}{'alt'};
        my $agl  = ${$rp}{'agl'};
        my $hb   = ${$rp}{'bug'};
        my $gspd = ${$rp}{'gspd'}; # Knots
        $gotah = 0;
        fgfs_get_K_ah(\$ah);
        if ($ah eq 'true') {
            $gotah = 1;
        }
       if ($gotah) {
           # FLYING AT A CONSTANT HEIGHT
            $msg = "ah=on";
       } else {
            # are we DECENDING...
            $msg = "ah=off";
       }
        my $rf = fgfs_get_flight();
        my $iflp = ${$rf}{'flap'};  # 0 = none, 0.333 = 5 degs, 0.666 = 10, 1 = full extended
        my $flap = "none";
        if ($iflp >= 0.3) {
            if ($iflp >= 0.6) {
                if ($iflp >= 0.9) {
                    $flap = 'full'
                } else {
                    $flap = '10';
                }
            } else {
                $flap = '5';
            }
        }
        my $vspd = get_ind_vspd_ftm();
        set_int_stg(\$vspd);
        set_int_stg(\$agl);
        $msg .= " $agl ft, '$vspd' fpm, flaps $flap";
    }
    prtt("$msg\n") if (length($msg));
}

sub show_position($) {
    my ($rp) = @_;
    return if (!defined ${$rp}{'time'});
    my $ctm = lu_get_hhmmss_UTC(${$rp}{'time'});
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$cpos,$tmp);
    my ($rch,$targ_lat,$targ_lon,$targ_hdg,$targ_dist,$targ_pset,$prev_pset);
    my $msg = '';
    my $eta = '';
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    $hdg  = ${$rp}{'hdg'};
    $agl  = ${$rp}{'agl'};
    $hb   = ${$rp}{'bug'};
    $mag  = ${$rp}{'mag'};  # is this really magnetic - # /orientation/heading-magnetic-deg

    $aspd = ${$rp}{'aspd'}; # Knots
    $gspd = ${$rp}{'gspd'}; # Knots

    my $re = fgfs_get_engines();
    my $run = ${$re}{'running'};
    my $rpm = ${$re}{'rpm'};
    my $thr = ${$re}{'throttle'};
    my $magn = ${$re}{'magn'}; # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    my $mixt = ${$re}{'mix'}; # $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich

    # display stuff
    $thr = int($thr * 100);
    $rpm = int($rpm + 0.5);
    prt("$ctm $rpm/$thr\n");
}

sub connect_to_fgfs() {
    wait_fgio_avail();
    my ($rch);
    prt("Got FG telnet io... get position...\n");
    my $rp = fgfs_get_position();
    prt("Show position...\n");
    show_position($rp);
    show_decent_stats($rch,$rp);
    fgfs_disconnect();
}


#########################################
### MAIN ###
##parse_args(@ARGV);
##process_in_file($in_file);
connect_to_fgfs();
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
