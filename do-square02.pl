#!/usr/bin/perl -w
# NAME: do-square02.pl
# AIM: Connect to fgfs through telnet, and fly a circuit...
# Circuit is extracted from an .xg file, with certain 'attributes' present to convey info...
# This could also be written/loaded as an xml file...
# More or less a re-write of fg_square.pl
# 05/07/2015 geoff mclane http://geoffair.net/mperl
#
# PREV.NAME: fg_square.pl
# AIM: Through a TELNET connection, fly the aircraft on a course
# 08/07/2015 - Flies a reasonable course, sometimes does a large turns, > 100 degs
# If information known, also align with the runway after turn final... 
# drop engine rpm, slow to flaps speed, lower flaps, commence decent... never completed
#
# 2021/01/13 - Add circuit names, Upwind, Crosswind, Downwind,..., Final to XG output
# 2021/01/08 - Adjust to Dell03 - DEF 5556
# 30/06/2015 - Much more refinement
# 03/04/2012 - More changes
# 16/07/2011 - Try to add flying a course around YGIL, using the autopilot
# 15/02/2011 (c) Geoff R. McLane http://geoffair.net/mperl - GNU GPL v2 (or +)
#
# A Circuit - consists of 5 'legs'
# Runway Takeoff -> Crosswind -> Downwind -> Base -> Upwind or Final to land runway
# Here they are notionally called - TR -> TL -> BL -> BR and Final-runway-Takeoff BR -> TR
# The original was based on a YGIL 33 takeoff, using a left-hand pattern at 100 ft agl
# 
# Need to prepare ALL cicuits, meaning left and right, and 2 for each runway
# When a runway is chosen, then should fly the left circuit of that runway
# 
# Heading: This is where my nose points
# Course: This is my INTENDED path calculated taking in winds, variation and declination.
# Track: This is my ACTUAL path traveled over ground 
# Bearing: This is the position of another object from my position... mag/true
# 
# TODO: If fgfs_ac_on_ground() choose CIRCUIT, from loaded circuits using current ac heading,
# else if 'flying' choose CIRCUIT according to the --wind=167@10 - direction and speed in Knots.
#
# $$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$
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
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
require "Bucket2.pm" or die "Unable to load Bucket2.pm ...\n";

# log file stuff
my $outfile = $temp_dir."/temp.$pgmname.txt";
$outfile = ($os =~ /win/i) ? path_u2d($outfile) : path_d2u($outfile);
open_log($outfile);

# user variables
my $VERS = "0.0.8 2021-01-13"; # some small enhancements... 
### my $VERS = "0.0.7 2015-07-20"; # start an 02 verison
### = "0.0.6 2015-07-16"; # begin tracker xg function
### "0.0.5 2015-07-06";
my $load_log = 0;

# default CIRCUIT files - generated with finadap03.pl...
my $circ_xg = $perl_dir .'circuits/';
### my $in_file = $circ_xg.'lecd.xg';
### my $in_file = $circ_xg.'vhsk.xg';
### my $in_file = $circ_xg.'ystw.xg';
my $in_file = $circ_xg.'ygil.xg';
### my $in_file = $circ_xg.'ygil-L.xg';

my $tmp_xg_out  = $temp_dir."/tempCIRCUIT";
my $tmp_xg_out2 = $temp_dir."/tempCIRCUITA.xg";
my $tmp_wp_out = $temp_dir."/tempwaypt.xg";
my $tmp_trk_out = $temp_dir."/temptrk.xg";	# keep movements of aircraft

my $verbosity = 0;
my $out_file = '';
# my $HOST = "localhost";
my ($fgfs_io,$HOST,$PORT,$CONMSG,$TIMEOUT,$DELAY);
my $connect_win7 = 0;
my $connect_dell01 = 0;
if (defined $ENV{'COMPUTERNAME'}) {
    my $cn = $ENV{'COMPUTERNAME'};
    if ($cn eq 'DELL03') {
        # connect to Win 10 in DELL03
        $HOST = "localhost"; # DELL03 machine
        $PORT = 5556;
        $CONMSG = "Assumed in DELL03, Windows 10 ";
    } elsif (!$connect_win7 && ($cn eq 'WIN7-PC')) {
        # connect to Ubuntu in DELL02
        $HOST = "192.168.1.34"; # DELL02 machine
        $PORT = 5556;
        $CONMSG = "Assumed in WIN7-PC connection to Ubuntu DELL02 ";
    } else {
        # assumed in DELL01 - connect to WIN7-PC
        $HOST = "192.168.1.33"; # WIN7-PC machine
        $PORT = 5556; # 5557;
        $CONMSG = "Assumed in DELL01 connection to WIN7-PC ";
    }
} else {
    # assumed in Ubuntu 
    if ($connect_dell01) {
        # 1: connect to DELL01
        $HOST = "192.168.1.11"; # DELL01
        $PORT = 5551;
        $CONMSG = "Assumed in Ubuntu DELL02 connection to DELL01 ";
    } else {
        # 2: connect to WIN7-PC
        $HOST = "192.168.1.33"; # WIN7-PC machine
        $PORT = 5557;
        $CONMSG = "Assumed in Ubuntu, connection to WIN7-PC ";
    }
}
$TIMEOUT = 2;
$DELAY = 5;
my $engine_count = 1;
my $min_eng_rpm = 0; #400;
my $wait_alt_hold = 1;

my $use_calc_wind_hdg = 1;

my $circuit_mode = 0;
my $circuit_flag = 0;
my $chk_turn_done = 0;

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'def_file';

### constants
my $SG_NM_TO_METER = 1852;
my $SG_METER_TO_NM = 0.0005399568034557235;
# /** Feet to Meters */
my $SG_FEET_TO_METER = 0.3048;
# /** Meters to Feet */
my $SG_METER_TO_FEET = 3.28083989501312335958;

### program variables
my @warnings = ();

# circuits read from input xg file
my %xg_circuits = ();

my $g_ac = ''; # ${$rs}{'aircraft'};
my $g_fdm = ''; # ${$rs}{'fdm'};
my $g_aero = ''; # ${$rs}{'aero'};

# forward

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
    fgfs_disconnect();
    ReadMode('restore'); # not sure this is required, or what it does exactly
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

sub prtt($) {
    my $txt = shift;
    if ($txt =~ /^\n/) {
        $txt =~ s/^\n//;
        prt("\n".lu_get_hhmmss_UTC(time()).": $txt");
    } else {
        prt(lu_get_hhmmss_UTC(time()).": $txt");
    }
}

##################################################
my $g_icao = 'YGIL';
my $g_circuit = '33';
my $g_rwy_left = 1;     # is left or right circuit
my $g_rcx = 0;

# rough Gil circuit - will be replaced by CALCULATED values
my $tl_lat = -31.684063;
my $tl_lon = 148.614120;
my $bl_lat = -31.723495;
my $bl_lon = 148.633003;
my $br_lat = -31.716778;
my $br_lon = 148.666992;
my $tr_lat = -31.672960;
my $tr_lon = 148.649139;

my $a_gil_lat = -31.697287500;
my $a_gil_lon = 148.636942500;
my $a_dub_lat = -32.2174865;
my $a_dub_lon = 148.57727;

my $PI = 3.141592653589793;
# my $D2R = math.pi / 180;               # degree to radian
my $D2R = $PI / 180;               # degree to radian
my $R2D = 180.0 / $PI;

###################################################################

sub get_type($) {
    my $color = shift;
    my $type = 'Unknown!';
    if ($color eq 'gray') {
        $type = 'bbox';
    } elsif ($color eq 'white') {
        $type = 'circuit';
    } elsif ($color eq 'green') {
        $type = 'rcircuit';
    } elsif ($color eq 'blue') {
        $type = 'center line';
    } elsif ($color = 'red') {
        $type = 'runways';
    }
    return $type;
}

my ($ref_circuit_hash);
###my ($mreh_circuithash);
my ($g_elat1,$g_elon1,$g_elat2,$g_elon2,$g_rwy_az1);
my @g_center_lines = ();
sub got_runway_coords() {
    if (defined $g_elat1 && defined $g_elon1 && defined $g_elat2 && defined $g_elon2) {
        return 1;
    }
    return 0;
}

sub get_runway_center($$) {
    my ($rlat,$rlon) = @_;
    my ($az1,$az2,$distm);
    my $ret = 0;
    # if (defined $g_elat1 && defined $g_elon1 && defined $g_elat2 && defined $g_elon2) {
    if (got_runway_coords()) {
        my ($clat,$clon);
        my $res = fg_geo_inverse_wgs_84 ($g_elat1,$g_elon1,$g_elat2,$g_elon2,\$az1,\$az2,\$distm);
        $res = fg_geo_direct_wgs_84($g_elat1,$g_elon1,$az1,$distm/2,\$clat,\$clon,\$az2);
        ${$rlat} = $clat;
        ${$rlon} = $clon;
        $ret = 1;
    }
    return $ret;
}

sub get_runway_heading($) {
    my ($rhdg) = @_;
    my ($az1,$az2,$distm);
    my $ret = 0;
    if (got_runway_coords()) {
        ## my ($clat,$clon);
        my $res = fg_geo_inverse_wgs_84 ($g_elat1,$g_elon1,$g_elat2,$g_elon2,\$az1,\$az2,\$distm);
        # $res = fg_geo_direct_wgs_84($g_elat1,$g_elon1,$az1,$distm/2,\$clat,\$clon,\$az2);
        ${$rhdg} = $az1;
        $ret = 1;
    }
    return $ret;
}

sub fgfs_get_sim_time() {
    my $tm = getprop("/sim/time/elapsed-sec");  # double
    return $tm;
}

# from : C:\GTools\perl\uas-demo.nas
# var f8Ep=getprop("/instrumentation/airspeed-indicator/true-speed-kt");
# var VZeb=func(course_deg,f8Ep,add_carrier_motion){
sub compute_course_org($$) {
    my ($course_deg, $taspdkt) = @_;
    my $f8Ep = $taspdkt;
    my %IijX = ();

    $IijX{'course_deg'} = $course_deg;
    $IijX{'true_speed_kt'} = $f8Ep;
    my $aJ4U = $course_deg;
    my $JKSr = 0;
    my $Kf9Y = $course_deg * $D2R;
    my $wfn = getprop("/environment/wind-from-heading-deg");
    my $ynQo = $wfn * $D2R;
    my $kbJn = getprop("/environment/wind-speed-kt");
    $IijX{'wind-from'} = $wfn;
    $IijX{'wind-speed'} = $kbJn;
    my $Pk2F = ($kbJn/$f8Ep)*sin($ynQo-$Kf9Y);
    if(abs($Pk2F)>1.0){
        # ...
    } else {
        $aJ4U = ($Kf9Y + asin($Pk2F)) * $R2D;
        if($aJ4U<0){
            $aJ4U+=360.0;
        }
        if($aJ4U>360){
            $aJ4U-=360.0;
        }
        $JKSr = $f8Ep * sqrt(1-$Pk2F*$Pk2F) - $kbJn * cos($ynQo-$Kf9Y);
        if($JKSr<0){
        }
    }
    $IijX{'heading'} = $aJ4U;
    $IijX{'groundspeed'} = $JKSr;
    return \%IijX;
}

sub compute_course($$) {
    my ($course_deg, $taspdkt) = @_;
    my $wfmd = getprop("/environment/wind-from-heading-deg");
    my $wspd = getprop("/environment/wind-speed-kt");
    return compute_wind_course($course_deg, $taspdkt, $wfmd, $wspd);
}


###############################################################
### keep a tracker xg file
my %tracker_hash = ();
my $min_trk_dist = 50;	# meters
sub get_circuit_xg();

sub get_tracker() {
	my $rt = \%tracker_hash;
	if ( ! defined ${$rt}{'time'} ) {
        my $ct = time();
		${$rt}{'time'} = ($ct - 2);
		${$rt}{'lat'} = 0;
		${$rt}{'lon'} = 0;
        my $msg = "# Start ".lu_get_hhmmss_UTC($ct)."\n";
        ###$msg .= get_circuit_xg();
        $msg .= get_circuit_xg2($g_rcx);
        $msg .= "color gray\n";
        rename_2_old_bak($tmp_trk_out);
        write2file($msg,$tmp_trk_out);
	}
	return $rt;
}

sub add2tracker($) {
	my $rp = shift;
	my $rt = get_tracker();
	return if ( ! defined ${$rt}{'time'} );
	my $ct = time();
	if ($ct != ${$rt}{'time'}) {
        ${$rt}{'time'} = $ct;
        my $nlat = ${$rp}{'lat'};
        my $nlon = ${$rp}{'lon'};
		my $lat = ${$rt}{'lat'};
		my $lon = ${$rt}{'lon'};
		my ($az1,$az2,$distm);
        fg_geo_inverse_wgs_84($lat,$lon,$nlat,$nlon,\$az1,\$az2,\$distm);
		if ( $distm > $min_trk_dist ) {
			# write to TRACKER file
            set_int_stg(\$distm);
            my $msg = "$nlon $nlat # $distm\n";
            append2file($msg,$tmp_trk_out);
            ${$rt}{'lat'} = $nlat;
            ${$rt}{'lon'} = $nlon;
		}
	}
}
	
sub termtracker() {
    append2file("NEXT\n",$tmp_trk_out);
}

########################################################
## XG generation
sub get_circuit_xg() {
    my $xg = "annon $a_gil_lon $a_gil_lat ICAO $g_icao, circuit $g_circuit\n";
    $xg .= "color white\n";
    $xg .= "anno $tr_lon $tr_lat TR\n";
    $xg .= "$tr_lon $tr_lat\n";
    $xg .= "anno $tl_lon $tl_lat TL\n";
    $xg .= "$tl_lon $tl_lat\n";
    $xg .= "anno $bl_lon $bl_lat BL\n";
    $xg .= "$bl_lon $bl_lat\n";
    $xg .= "anno $br_lon $br_lat BR\n";
    $xg .= "$br_lon $br_lat\n";
    $xg .= "$tr_lon $tr_lat\n";
    $xg .= "NEXT\n";
    if (got_runway_coords()) {
        my ($elat1,$elon1,$elat2,$elon2);
        $elat1 = $g_elat1;
        $elon1 = $g_elon1;
        $elat2 = $g_elat2;
        $elon2 = $g_elon2;
        $xg .= "color blue\n";
        $xg .= "$elon1 $elat1\n";
        $xg .= "$elon2 $elat2\n";
        $xg .= "NEXT\n";
    }
    return $xg;
}

# $rcx = $xg_circuits{$key} 
sub get_circuit_xg2($) {
    my $rcx = shift;
    my $xg = "annon $a_gil_lon $a_gil_lat ICAO $g_icao, circuit $g_circuit\n";

    my ($rca,$rends);
    my ($tllat,$tllon,$bllat,$bllon,$brlat,$brlon,$trlat,$trlon);
    my ($elat1,$elon1,$elat2,$elon2);
    my ($az1,$az2,$dist,$d2,$clat,$clon,$az3);
    my ($rwy);
    my $rwyLR = 'LR';
    if (${$rcx}{'rwy_left'}) {
        #                0         1         2         3          4        5         6         7
        # $h1{'left'} = [$l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon];
        $rca = ${$rcx}{'left'};
        $g_rwy_left = 1;
        $rwyLR = 'L';
    } else {
        $rca = ${$rcx}{'right'};
        $g_rwy_left = 0;
        $rwyLR = 'R';
    }
    # set the appropriate circuit
    $tllat = ${$rca}[0];
    $tllon = ${$rca}[1];
    $bllat = ${$rca}[2];
    $bllon = ${$rca}[3];
    $brlat = ${$rca}[4];
    $brlon = ${$rca}[5];
    $trlat = ${$rca}[6];
    $trlon = ${$rca}[7];

    $rends = ${$rcx}{'runway'}; #  = [$g_elat1,$g_elon1,$g_elat2,$g_elon2];
    $elat1 = ${$rends}[0];
    $elon1 = ${$rends}[1];
    $elat2 = ${$rends}[2];
    $elon2 = ${$rends}[3];

    # Upwind - from takeoff to TR
    fg_geo_inverse_wgs_84 ($elat2,$elon2,$trlat,$trlon,\$az1,\$az2,\$dist);
    $d2 = $dist / 2;    # mid
    fg_geo_direct_wgs_84($elat2,$elon2,$az1,$d2,\$clat,\$clon,\$az3);
    $xg .= "anno $clon $clat Upwind\n"; # to TR

    # $xg .= "anno $trlon $trlat TR\n";
    # $xg .= "$trlon $trlat\n";
    # Crosswind - from TR to TL
    fg_geo_inverse_wgs_84 ($trlat,$trlon,$tllat,$tllon,\$az1,\$az2,\$dist);
    $d2 = $dist / 2;    # mid
    fg_geo_direct_wgs_84($trlat,$trlon,$az1,$d2,\$clat,\$clon,\$az3);
    $xg .= "anno $clon $clat Crosswind\n"; # to TL

    # $xg .= "anno $tllon $tllat TL\n";
    # $xg .= "$tllon $tllat\n";

    # Downwind - from TL to BL
    fg_geo_inverse_wgs_84 ($tllat,$tllon,$bllat,$bllon,\$az1,\$az2,\$dist);
    $d2 = $dist / 2;    # mid
    fg_geo_direct_wgs_84($tllat,$tllon,$az1,$d2,\$clat,\$clon,\$az3);
    $xg .= "anno $clon $clat Downwind\n"; # to BL

    # $xg .= "anno $bllon $bllat BL\n";
    # $xg .= "$bllon $bllat\n";

    # Base - from BL to BR
    fg_geo_inverse_wgs_84 ($bllat,$bllon,$brlat,$brlon,\$az1,\$az2,\$dist);
    $d2 = $dist / 2;    # mid
    fg_geo_direct_wgs_84($bllat,$bllon,$az1,$d2,\$clat,\$clon,\$az3);
    $xg .= "anno $clon $clat Base\n";

    # $xg .= "anno $brlon $brlat BR\n";
    # Final - BR to runway
    fg_geo_inverse_wgs_84 ($brlat,$brlon,$elat1,$elon1,\$az1,\$az2,\$dist);
    $d2 = $dist / 2;    # mid
    fg_geo_direct_wgs_84($brlat,$brlon,$az1,$d2,\$clat,\$clon,\$az3);
    $xg .= "anno $clon $clat Final\n";


    $xg .= "color white\n";
    $xg .= "anno $trlon $trlat TR\n";
    $xg .= "$trlon $trlat\n";
    $xg .= "anno $tllon $tllat TL\n";
    $xg .= "$tllon $tllat\n";
    $xg .= "anno $bllon $bllat BL\n";
    $xg .= "$bllon $bllat\n";
    $xg .= "anno $brlon $brlat BR\n";
    $xg .= "$brlon $brlat\n";
    $xg .= "$trlon $trlat\n";
    $xg .= "NEXT\n";
    $xg .= "color blue\n";
    $xg .= "$elon1 $elat1\n";
    $xg .= "$elon2 $elat2\n";
    $xg .= "NEXT\n";

    # put ICAO - center runway
    fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$dist);
    $d2 = $dist / 2;    # mid
    fg_geo_direct_wgs_84($elat1,$elon1,$az1,$d2,\$clat,\$clon,\$az3);
    $xg .= "anno $clon $clat $g_icao $rwyLR\n"; # $rwy

    # put runway IDs
    # $h2{'rwy_id'}      = $rwy2;
    if (defined ${$rcx}{'rwy_id'}) {
        $rwy = ${$rcx}{'rwy_id'};
        $xg .= "anno $elon1 $elat1 $rwy\n";
    }

    # $h2{'rwy_id2'}     = $rwy;
    if (defined ${$rcx}{'rwy_id2'}) {
        $rwy = ${$rcx}{'rwy_id2'};
        $xg .= "anno $elon2 $elat2 $rwy\n";
    }

    return $xg;
}

# $rcx = $xg_circuits{$key} 
sub write_circuit_xg2($$) {
    my ($rcx,$file) = @_;
    my $xg = get_circuit_xg2($rcx);
    write2file($xg,$file);
    prt("Circuit xg written to '$file'\n");
}

#sub write_circuit_xg($) {
#    my $file = shift;
#    my $xg = get_circuit_xg();
#    write2file($xg,$file);
#    prt("Circuit XG written to '$file'\n");
#}

# Expect a somewhat special xg describing an airport, its runways,
# and the left and right circuits around those runways
# flags
my $had_blue  = 0x0001;
my $had_white = 0x0002;
sub process_in_file($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n") if (VERB2());
    my ($line,$inc,$lnn,$type,@arr,$cnt,$ra,$lat,$lon,$text,$rwy);
    my (@arr2);
    ###################################################################
    ### RIGHT and LEFT circuits
    my ($l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon);
    my ($r_tl_lat,$r_tl_lon,$r_bl_lat,$r_bl_lon,$r_br_lat,$r_br_lon,$r_tr_lat,$r_tr_lon);

    $lnn = 0;
    my $color = '';
    my @points = ();
    my %h = ();     # has to return
    my $circ_cnt = 0;
    my $cl_cnt = 0;
    my $flag = 0;
    my $bcnt = 0;
    my @block = ();
    my @blocks = ();
    my %colors = ();
    my %dupes = ();
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        if ($line =~ /^\s*color\s+(.+)$/) {
            $color = $1;
            if (defined $dupes{$color}) {
                # doing the next block...
                $bcnt++;
                if (@block) {
                    %dupes = ();
                    my @a = @block;
                    push(@blocks,\@a);
                    @block = ();
                }
            }
            $dupes{$color} = 1;
            $colors{$color} = 1;
        }
        push(@block,$line);
    }
    if (@block) {
        $bcnt++;
        %dupes = ();
        my @a = @block;
        push(@blocks,\@a);
        @block = ();
    }
    $bcnt = scalar @blocks;
    # prt("Split files lines into $bcnt blocks...\n");
    # pgm_exit(1,"TEMP EXIT\n");
    my $inrwy = 0;
    my $lr = '';
    my $got_left = 0;
    my $got_right = 0;
    my $got_center = 0;
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        if ($line =~ /^\s*\#/) {
            if ($line =~ /begin runway description/) {
                $inrwy = 1;
                undef $rwy;
                $got_left = 0;
                $got_right = 0;
                $got_center = 0;
            } elsif ($line =~ /end runway description/) {
                $inrwy = 0;
                if (defined $rwy) {
                    $g_circuit = $rwy;
                    if ($rwy =~ /^(\d+)(R|L|C)*$/) {
                        my $rwy2 = ($1 > 18) ? $1 - 18 : $1 + 18;
                        $rwy2 = '0'.$rwy2 if ($rwy2 < 10);
                        if (defined $2) {
                            $rwy2 .= 'L' if ($2 eq 'R');
                            $rwy2 .= 'R' if ($2 eq 'L');
                            $rwy2 .= 'C' if ($2 eq 'C');
                        }
                        if ($got_left && $got_right && $got_center) {
                            my %h1 = ();
                            my %h2 = ();
                            my ($az1,$az2,$dist);
                            $h1{'left'} = [$l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon];
                            $h1{'right'} = [$r_tl_lat,$r_tl_lon,$r_bl_lat,$r_bl_lon,$r_br_lat,$r_br_lon,$r_tr_lat,$r_tr_lon];
                            $h1{'runway'} = [$g_elat1,$g_elon1,$g_elat2,$g_elon2];
                            fg_geo_inverse_wgs_84($g_elat1,$g_elon1,$g_elat2,$g_elon2,\$az1,\$az2,\$dist);
                            $h1{'rwy_heading'} = $az1;
                            $h1{'rwy_id'}      = $rwy;
                            $h1{'rwy_id2'}     = $rwy2;
                            $h1{'rwy_left'}    = 1;
                            # store under each key - is this a good idea?
                            $xg_circuits{$rwy}  = \%h1;

                            $h2{'left'} = [$l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon];
                            $h2{'right'} = [$r_tl_lat,$r_tl_lon,$r_bl_lat,$r_bl_lon,$r_br_lat,$r_br_lon,$r_tr_lat,$r_tr_lon];
                            $h2{'runway'} = [$g_elat2,$g_elon2,$g_elat1,$g_elon1];
                            fg_geo_inverse_wgs_84($g_elat2,$g_elon2,$g_elat1,$g_elon1,\$az1,\$az2,\$dist);
                            $h2{'rwy_heading'} = $az1;
                            $h2{'rwy_id'}      = $rwy2;
                            $h2{'rwy_id2'}     = $rwy;
                            $h2{'rwy_left'}    = 0;

                            $xg_circuits{$rwy2} = \%h2;
                        }
                    }
                }

            }
            prt("$lnn: $line\n") if (VERB9());
        } elsif ($line =~ /^\s*color\s+(.+)$/) {
            $color = $1;
            $type = 'Unknown!';
            if ($color eq 'gray') {
                $type = 'bbox';
            } elsif ($color eq 'white') {
                $type = 'circuit';
                $circ_cnt = 0;
                $g_rwy_left = 1;
            } elsif ($color eq 'green') {
                $type = 'rcircuit';
                $circ_cnt = 0;
                $g_rwy_left = 0;
            } elsif ($color eq 'blue') {
                $type = 'center line';
                if ($flag & $had_blue) {
                    # This is a NEW set starting
                }
            } elsif ($color = 'red') {
                $type = 'runways';
            }
            prt("$lnn: color $color $type\n") if (VERB9());
        } elsif ($line =~ /^\s*NEXT/i) {
            $cnt = scalar @points;
            if ($cnt) {
                $h{$color} = [] if (! defined $h{$color});
                $ra = $h{$color};
                my @a = @points;
                push(@{$ra},\@a);
                prt("NEXT: Added $cnt pts to $color\n") if (VERB9());
            }
            @points = ();   # clear accumulated pointes
        } elsif ($line =~ /^\s*anno\s+/) {
            @arr = split(/\s+/,$line);
            $cnt = scalar @arr;
            # 0    1   2   3
            # anno lon lat text
            if ($cnt > 3) {
                $lon = $arr[1];
                $lat = $arr[2];
                $text = join(' ', splice(@arr,3));
                @arr2 = split(/\s+/,$text);
                if (scalar @arr2 == 4) {
                    $g_icao = $arr2[0];
                    $g_circuit = $arr2[3];
                    $a_gil_lat = $lat;
                    $a_gil_lon = $lon;
                    prt("CIRCUIT $a_gil_lat,$a_gil_lon ICAO $g_icao, circuit $g_circuit\n"); # if (VERB5());
                } elsif ($text =~ /final\s+(\w+)$/) {
                    $rwy = $1;
                } elsif ($text =~ /(\w+)-TR$/) {
                    $lr = $1;
                } elsif ($text =~ /(\w+)-TL$/) {
                    $lr = $1;
                } elsif ($text =~ /(\w+)-BL$/) {
                    $lr = $1;
                } elsif ($text =~ /(\w+)-BR$/) {
                    $lr = $1;
                } else {
                    prt("Annotation $lat,$lon '$text'\n") if (VERB9());
                }
            }
        } else {
            @arr = split(/\s+/,$line);
            $cnt = scalar @arr;
            if ($cnt >= 2) {
                $lon = $arr[0];
                $lat = $arr[1];
                push(@points,[$lat,$lon]);
            }
            if ( $type eq 'circuit') {
                # get the LEFT CIRCUIT described in the .xg
                if ($circ_cnt == 0) {
                    $l_tr_lat = $lat;
                    $l_tr_lon = $lon;
                    $tr_lat = $lat;
                    $tr_lon = $lon;
                } elsif ($circ_cnt == 1) {
                    $l_tl_lat = $lat;
                    $l_tl_lon = $lon;
                    $tl_lat = $lat;
                    $tl_lon = $lon;
                } elsif ($circ_cnt == 2) {
                    $l_bl_lat = $lat;
                    $l_bl_lon = $lon;
                    $bl_lat = $lat;
                    $bl_lon = $lon;
                } elsif ($circ_cnt == 3) {
                    $l_br_lat = $lat;
                    $l_br_lon = $lon;
                    $br_lat = $lat;
                    $br_lon = $lon;
                }
                $circ_cnt++;
                $got_left = 1 if ($circ_cnt == 4);
            } elsif ( $type eq 'rcircuit') {
                # get the CIRCUIT described in the .xg
                if ($circ_cnt == 0) {
                    $r_tr_lat = $lat;
                    $r_tr_lon = $lon;
                    $tr_lat = $lat;
                    $tr_lon = $lon;
                } elsif ($circ_cnt == 1) {
                    $r_tl_lat = $lat;
                    $r_tl_lon = $lon;
                    $tl_lat = $lat;
                    $tl_lon = $lon;
                } elsif ($circ_cnt == 2) {
                    $r_bl_lat = $lat;
                    $r_bl_lon = $lon;
                    $bl_lat = $lat;
                    $bl_lon = $lon;
                } elsif ($circ_cnt == 3) {
                    $r_br_lat = $lat;
                    $r_br_lon = $lon;
                    $br_lat = $lat;
                    $br_lon = $lon;
                }
                $circ_cnt++;
                $got_right = 1 if ($circ_cnt == 4);
            } elsif ($type eq 'center line') {
                if ($cl_cnt & 0x01) {
                    $g_elat2 = $lat;
                    $g_elon2 = $lon;
                } else {
                    $g_elat1 = $lat;
                    $g_elon1 = $lon;
                }
                $cl_cnt++;
                if (($cl_cnt % 2) == 0) {
                    $got_center = 1;
                    push(@g_center_lines,[$g_elat1,$g_elon1,$g_elat2,$g_elon2]);
                }

            }

        }
    }
    @arr2 = keys %xg_circuits;
    $bcnt = scalar @arr2;
    if (!$bcnt) {
        pgm_exit(1,"FAILED to get circuits from $inf\n");
    }
    my ($key,$rcx,$az1,$tmpxg,$msg);
    $msg ="Bagged $bcnt circuits ";
    foreach $key (@arr2) {
        $g_circuit = $key;
        $rcx = $xg_circuits{$key};
        $g_rcx = $rcx;
        $az1 = ${$rcx}{'rwy_heading'};
        #if (${$rcx}{'rwy_id'} eq $key) {
        #    # doing this runway - get heading
            $az1 += 180;
            $az1 -= 360 if ($az1 > 360);
        #}
        set_decimal1_stg(\$az1);
        $msg .= "$key ($az1) ";
        $tmpxg = $tmp_xg_out.$key.'.xg';
        write_circuit_xg2($rcx,$tmpxg);

    }
    prt("$msg\n");
    ### $mreh_circuithash = \%h;
    ### show_ref_circuit_hash();
    ### $tmpxg = $tmp_xg_out.'.xg';
    ### write_circuit_xg($tmpxg);
    $ref_circuit_hash = get_circuit_hash2($rcx);
    ### pgm_exit(1,"TEMP EXIT\n");
}

##############################################################
###########
sub check_keyboard() {
    my ($char,$val,$pmsg);
    if (got_keyboard(\$char)) {
        $val = ord($char);
        $pmsg = sprintf( "%02X", $val );
        if (($val == 27) || (lc($char) eq 'q')) {
            prtt("ESC key... Exiting loop...\n");
            return 1;
        } elsif ($char eq '+') {
            $DELAY++;
            prtt("Increase delay to $DELAY seconds...\n");
        } elsif ($char eq '-') {
            $DELAY-- if ($DELAY);
            prtt("Decrease delay to $DELAY seconds...\n");
        } else {
            prt("Got keyboard input hex[$pmsg]...\n");
        }
    }
    return 0;
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


######################################################################
my $sp_prev_msg = '';
my $sp_msg_skipped = 0;
my $sp_msg_show = 10;
my $sp_msg_cnt = 0;

my $have_target = 0;
my $min_fly_speed = 35; # was 30; # Knots
my $min_agl_height = 500;   # 4500;  # was just 500
my $alt_msg_chg = 0;
my $ind_alt_ft = 0; # YGIL = 881.7 feet
my $set_in_hg = 0;  # 29.92 STP inches of mercury
my $ind_off_degs = 0;   # -52.8.. what is this?
my $altimeter_msg = '';
my $ind_hdg_degs = 0;
my $dbg_roll = 0;
my $m_stable_cnt = 0;   # less than 2 degrees between previous ind hdg
my $got_alt_hold = 0;

sub get_hdg_in_range($) {
    my $r = shift;
    if (${$r} < 0) {
        ${$r} += 360;
    } elsif (${$r} > 360) {
        ${$r} -= 360;
    }
}

sub get_mag_hdg_from_true($) {
    my $hdg = shift;
    $hdg -= get_mag_deviation();
    get_hdg_in_range(\$hdg);
    return $hdg;
}

# this is changing fast in a TURN
sub update_hdg_ind() {
    fgfs_get_hdg_ind(\$ind_hdg_degs);
}

# sub fgfs_get_altimeter()
sub set_altimeter_stg() {
    my ($ai,$hg,$off,$ind);
    fgfs_get_alt_ind(\$ai);
    fgfs_get_alt_inhg(\$hg);
    # "/instrumentation/heading-indicator/offset-deg"
    fgfs_get_hdg_off(\$off);
    fgfs_get_hdg_ind(\$ind);
    $ind_alt_ft = $ai;
    $set_in_hg  = $hg;
    $ind_off_degs = $off;
    $ind_hdg_degs = $ind;

    set_decimal1_stg(\$ai);
    set_decimal2_stg(\$hg);

    my $msg = "QNH $hg, alt $ai";
    if ($altimeter_msg ne $msg) {
        $altimeter_msg = $msg;
        $alt_msg_chg++;
    }
}

my %show_postion_hash = ();

sub get_curr_pos_stg($$$) {
    my ($lat,$lon,$alt) = @_;
    set_int_stg(\$alt);
    set_lat_stg(\$lat);
    set_lon_stg(\$lon);
    return "$lat,$lon,$alt";
}


sub show_position($) {
    my ($rp) = @_;
    return if (!defined ${$rp}{'time'});
    my $ctm = lu_get_hhmmss_UTC(${$rp}{'time'});
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$cpos,$tmp,$tmp2);
    my ($rch,$targ_lat,$targ_lon,$targ_hdg,$targ_dist,$targ_pset,$prev_pset);
    my $msg = '';
    my $eta = '';
    add2tracker($rp);
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

    $thr = (int($thr * 100) / 10);
    $rpm = int($rpm + 0.5);
    # =================================================================
    # display stuff - note destroys values - local now only for display
    # =================================================================
    set_hdg_stg(\$hdg);
    set_hdg_stg(\$mag);
    # had some trouble with this BUG - seems not initialized!!! until you move it...
    if ($hb && ($hb =~ /^-*(\d|\.)+$/)) {
        set_hdg_stg(\$hb);
    } elsif ((defined $hb) && length($hb)) {
        $hb = "?$hb?!";
    } else {
        #### fgfs_set_hdg_bug($mag);
    }

    $cpos = get_curr_pos_stg($lat,$lon,$alt);
    ###############################################################
    ### criteria for ON GROUND
    ### TRIED if (fgfs_ac_on_ground()) but func error?
    my $dagl = '';
    if ( $aspd < $min_fly_speed ) {
        #############################################################
        # ON GROUND has different concerns that say position
        set_altimeter_stg();
        $dagl = "OG ";
        if ($alt_msg_chg) {
            $alt_msg_chg = 0;
            $dagl .= $altimeter_msg;
        } else {
            if ($sp_msg_cnt < 5) {
                $dagl .= $altimeter_msg;
            } else {
                $dagl .= $cpos;
            }
        }
        # $tmp = $agl;
        # set_int_stg(\$tmp);
        # $dagl .= ", agl $tmp";
        #############################################################
    } elsif (!$got_alt_hold) {
        if ($agl > $min_agl_height) {
            $dagl = '';
        } elsif ($have_target) {
            $dagl = '';
        } else {
            $dagl = int($agl + 0.5)."Ft";
        }
    } else {
        $dagl = '';
    }
    $aspd = int($aspd + 0.5);
    $gspd = int($gspd + 0.5);
    #$msg .= " $aspd/${gspd}Kt";
    #$msg .= " R=".get_curr_roll() if ($dbg_roll);
    if (!$have_target) {
        if ($got_alt_hold) {
            # what to add here
        } else {
            $msg .= " E($rpm/$thr\%)";
            $msg .= " B(".get_curr_brake_stg().")";
        }
    }

    #########################################################
    my $prev_hdg = $ind_hdg_degs;
    update_hdg_ind(); # this is changing fast in a TURN
    my $diff = get_hdg_diff($prev_hdg,$ind_hdg_degs);
    #########################################################
    my $turn = 's';
    $show_postion_hash{'last_turn'} = 's' if (!defined $show_postion_hash{'last_turn'});
    if (($diff < -1.0)||($diff > 1.0)) {
        $turn = 'InTurn';
        $m_stable_cnt = 0;
    } else {
        $m_stable_cnt++;
        $turn .= "$m_stable_cnt";
    }
    $msg .= " d=$turn";
    #########################################################

    $tmp = $ind_hdg_degs;
    ### set_decimal1_stg(\$tmp);
    set_hdg_stg(\$tmp);

    my $show_msg = 0;
    if ($msg eq $sp_prev_msg) {
        # decide to show or not
        $sp_msg_skipped++;
        if ($sp_msg_skipped > $sp_msg_show) {
            $sp_msg_skipped = 0;
            $show_msg = 1;
            $sp_msg_cnt++;          # count of messages actually output
        }
    } else {
        $show_msg = 1;
        $sp_msg_cnt++;          # count of messages atually output
    }
    if ($show_msg) {
        my $rch = $ref_circuit_hash;
        # Only if in a CIRCUIT
        if ($circuit_mode && $circuit_flag && defined ${$rch}{'target_hdg'}) {
            #if ($turn eq 's') {
            if ($m_stable_cnt > 1) {
                # in stable level flight - check for course change
                $eta = ${$rch}{'target_eta'};
                $lon  = ${$rp}{'lon'};
                $lat  = ${$rp}{'lat'};
                $aspd = ${$rp}{'aspd'}; # Knots
                my $tlat = ${$rch}{'target_lat'};   # $targ_lat;
                my $tlon = ${$rch}{'target_lon'};   # $targ_lon;
                my $chdg = ${$rch}{'target_hdg'};   # bug set to this
                my ($az1,$az2,$distm);
                # from current position to target position
                fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$distm);
                my $rwh = compute_course($az1,$aspd);
                my $whdg = ${$rwh}{'heading'};  # get computed hdg, corrected for wind
                my $wdiff = get_hdg_diff($az1,$whdg);    # get the difference
                my $thdg = $az1;    # calculate true heading
                if ($use_calc_wind_hdg) {
                    $thdg = $whdg;  # use a computed heading due to wind
                }
                my $tdiff = get_hdg_diff($chdg,$thdg);
                # give BOTH headings
                ${$rch}{'suggest_hdg'} = $az1;
                ${$rch}{'suggest_whdg'} = $whdg;
                if (${$rch}{'wp_mode'}) {
                    $eta = "wp mode";
                } elsif (abs($tdiff) > 1.2) { # was 1
                    #################################################
                    ### Suggest a new heading
                    my $distnm = get_dist_stg_nm($distm);
                    my $distkm = get_dist_stg_km($distm);
                    $tmp2 = $thdg;
                    set_decimal1_stg(\$tmp2);
                    # $eta .= " h=$tmp2, d $distnm $distkm ";
                    set_decimal1_stg(\$tdiff);
                    $eta .= " h=$tmp2, d=$tdiff, s $distkm ";
                    if (!$use_calc_wind_hdg) {
                        $tmp2 = $whdg;
                        set_decimal1_stg(\$tmp2);
                        $eta .= "w=$tmp2 ";
                    }
                    ## if (abs($az1 - $az2) > 1)
                    ## if (abs(get_hdg_diff($az1,$az2)) > 1)
                        if (${$rch}{'suggest_chg'}) {
                            ${$rch}{'suggest_chg'}++;
                            $eta .= " Waiting ".${$rch}{'suggest_chg'};
                        } else {
                            ${$rch}{'suggest_chg'} = 1;
                            $eta .= " Suggest change...";
                        }
                    ## }
                }
            }
        }
        $hdg  = ${$rp}{'hdg'};
        # $agl  = ${$rp}{'agl'};
        # $hb   = ${$rp}{'bug'};
        $mag  = ${$rp}{'mag'};  # is this really magnetic - # /orientation/heading-magnetic-deg
        set_hdg_stg(\$hdg);
        set_hdg_stg(\$mag);
        prt("$ctm: $dagl hdg=".$hdg."t/".$mag."m/${tmp}i/${hb}b $msg $eta\n");
    }

    $sp_prev_msg = $msg;    # save last message
    
}

###########################################################
## Had a BUG - some variable not numeric - set_hdg_stg
###############
my $last_tomsg = '';
my $last_tomsg_time = 0;
my $tomsg_delay = 15;

sub show_takeoff($) {
    my ($rp) = @_;
    my ($ilon,$ilat,$ialt,$ihdg,$iagl,$ihb,$imag,$iaspd,$igspd,$iind);
    $ilon = ${$rp}{'lon'};
    $ilat = ${$rp}{'lat'};
    $ialt = ${$rp}{'alt'};
    $ihdg = ${$rp}{'hdg'};
    $iagl = ${$rp}{'agl'};
    $ihb  = ${$rp}{'bug'};
    # this should be the runway heading - NEEDS TO BE CHECKED
    $imag = ${$rp}{'mag'};  # /orientation/heading-magnetic-deg
    $iaspd = ${$rp}{'aspd'}; # Knots
    $igspd = ${$rp}{'gspd'}; # Knots
    my $prev_hdg = $ind_hdg_degs;
    update_hdg_ind(); # this is changing fast in a TURN
    $iind = $ind_hdg_degs;
    my $diff = get_hdg_diff($prev_hdg,$iind);
    my $turn = 's';
    if (($diff < -1.0)||($diff > 1.0)) {
        $turn = 'InTurn';
    } else {
        $turn = 's';
    }

    # 1 - is engine running?
    my $re = fgfs_get_engines();
    my $run = ${$re}{'running'};
    my $rpm = ${$re}{'rpm'};
    my $thr = ${$re}{'throttle'};
    my $mag = ${$re}{'magn'}; # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    my $mix = ${$re}{'mix'}; # $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich
    my $idle = $thr;

    # 2 what lights are on/off
    my $rl = fgfs_get_lighting();
    my ($navL,$beak,$strb);
    # fgfs_get_nav_light(\$nl);
    # fgfs_get_beacon(\$bk);
    # fgfs_get_strobe(\$sb);
    # my $rl = fgfs_get_ctrl_lighting();
    # ${$rl}{'time'} = time();
    $navL = ${$rl}{'navlight'};
    $beak = ${$rl}{'beacon'};
    $strb = ${$rl}{'strobe'};

    my ($rf,$iai,$iait,$iel,$ielt,$irud,$irudt,$iflp,$flap);
    $rf = fgfs_get_flight();
    # get_flt_ailerons(\$ai);
    # get_flt_ailerons_trim(\$ait);
    # get_flt_elevator(\$el);
    # get_flt_elevator_trim(\$elt);
    # get_flt_rudder(\$rud);
    # get_flt_rudder_trim(\$rudt);
    # get_flt_flaps(\$flp);
    # ${$rf}{'time'} = time();
    $iai  = ${$rf}{'ai'};    # 1 = right, -0.9 = left
    $iait = ${$rf}{'ait'};
    $iel  = ${$rf}{'el'};    # 1 = down, to -1(-0.9) = up (climb)
    $ielt = ${$rf}{'elt'};
    $irud = ${$rf}{'rud'};   # 1 = right, to -1(0.9) left
    $irudt= ${$rf}{'rudt'};
    $iflp = ${$rf}{'flap'};  # 0 = none, 0.333 = 5 degs, 0.666 = 10, 1 = full extended
    $flap = "0";
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
    # mess for display...
    $iai   = int($iai * 10) / 10;
    $iait  = int($iait * 10) / 10;
    $iel   = int($iel * 10) / 10;
    $ielt  = int($ielt * 10) / 10;
    $irud  = int($irud * 10) / 10;
    $irudt = int($irudt * 10) / 10;
    set_decimal1_stg(\$iai);
    set_decimal1_stg(\$iait);
    set_decimal1_stg(\$iel);
    set_decimal1_stg(\$ielt);
    set_decimal1_stg(\$irud);
    set_decimal1_stg(\$iflp);
    set_decimal1_stg(\$irudt);

    set_int_stg(\$rpm);
    #set_decimal1_stg(\$thr);
    $thr = int($thr * 100);
    set_int_stg(\$ialt);    # = ${$rp}{'alt'};
    set_int_stg(\$iagl);    # = ${$rp}{'agl'};

    #set_hdg_stg(\$ihdg);    # = ${$rp}{'hdg'};
    #set_hdg_stg(\$ihb);     # = ${$rp}{'bug'};
    #set_hdg_stg(\$imag);    # = ${$rp}{'mag'};  # /orientation/heading-magnetic-deg
    #set_hdg_stg(\$iind);

    #### $iaspd = ${$rp}{'aspd'}; # Knots
    set_int_stg(\$igspd);   # = ${$rp}{'gspd'}; # Knots
    set_int_stg(\$ialt);
    set_int_stg(\$iagl);

    my $ct = time();
    my $msg = "$iagl/$ialt flt a=$iai/$iait e=$iel/$ielt r=$irud/$irudt, f=$iflp($flap) ".
        "- $rpm/$thr\%/$igspd";
    if ($msg ne $last_tomsg) {
        $last_tomsg = $msg;
        prtt("$msg\n");
        $last_tomsg_time = $ct;
    } else {
        if ($ct > ($last_tomsg_time + $tomsg_delay)) {
            $last_tomsg = $msg;
            prtt("$msg\n");
            $last_tomsg_time = $ct;
        }
    }
}


#################################################################
### Given a heading, select a RUNWAY, from %xg_circuits
sub get_runway_for_heading($) {
    my $hdg = shift;
    my @arr2 = keys %xg_circuits;
    my $bcnt = scalar @arr2;
    my ($key,$rcx,$az1,$diff,$msg,$tmp);
    $tmp = $hdg;
    set_hdg_stg(\$tmp);
    $msg = "Searching $bcnt circuits for $tmp hdg: ";
    my $mdiff = 180;
    my $ckey = '';
    my $set = '';
    foreach $key (@arr2) {
        $rcx = $xg_circuits{$key};
        $az1 = ${$rcx}{'rwy_heading'};
        ### if (${$rcx}{'rwy_id'} eq $key) {
        ### } else {
            # doing opposite - get heading
            $az1 += 180;
            $az1 -= 360 if ($az1 > 360);
        ### }
        $diff = abs(get_hdg_diff($hdg,$az1));
        $set = '';
        if ($diff < $mdiff) {
            $mdiff = $diff;
            $ckey = $key;
            $set = '*';
        }
        set_decimal1_stg(\$az1);
        set_int_stg(\$diff);
        $msg .= "$key $az1 ($diff) $set ";
    }
    prt("$msg\n");
    $key = '';
    $tmp = $hdg;
    set_hdg_stg(\$tmp);
    $msg = "For heading $tmp NO runway chosen! ";
    if (length($ckey) && defined $xg_circuits{$ckey}) {
        $rcx = $xg_circuits{$ckey};
        $key = ${$rcx}{'rwy_id'};
        $az1 = ${$rcx}{'rwy_heading'};
        # if (${$rcx}{'rwy_id'} eq $ckey) {
        # } else {
            # doing opposite - get heading
            $az1 += 180;
            $az1 -= 360 if ($az1 > 360);
        # }
        set_hdg_stg(\$az1);
        $msg = "For heading $tmp, chosen $ckey, takeoff on $az1 ";
    }
    prtt("$msg\n");
    return $ckey;
}

my $swap_wind_hdg = 1;

sub position_on_got_engine($) {
    my $rp = shift;
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$msg,$tmp,$tmp2,$rwy,$key,$rhdg);
    # my ($rch,$targ_lat,$targ_lon,$targ_hdg,$targ_dist,$targ_pset,$prev_pset);
    # my $msg = '';
    # my $eta = '';
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    $hdg  = ${$rp}{'hdg'};
    $agl  = ${$rp}{'agl'};
    $hb   = ${$rp}{'bug'};
    $mag  = ${$rp}{'mag'};  # is this really magnetic - # /orientation/heading-magnetic-deg
    $aspd = ${$rp}{'aspd'}; # Knots
    $gspd = ${$rp}{'gspd'}; # Knots
    my $from = "ac";
    my $rew = get_env_wind();
    my $whdg = ${$rew}{'wind-from'};
    my $wspd = ${$rew}{'wind-spd'};

    $msg = "Failed get runway heading...";
    fgfs_get_atc_runway(\$rwy);
    if ( defined $rwy && length($rwy) ) {
        if ( defined $xg_circuits{$rwy} ) {
            $key = $rwy;
            $from = 'atc';
        }
    }
    if ( ! defined $key) {
        # oops, seems ATC has not set an ACTIVE runway
        # Other methods of chossing a circuit
        if ($aspd < $min_fly_speed) {
            # use current ac heading - assume in takoff mode
        } else {
            $hdg = $whdg;   # select RUNWAY, and CIRCUIT on WIND HEADING
            if ($swap_wind_hdg) {
                $hdg += 180;
                $hdg -= 360 if ($hdg > 360);
            }
            set_hdg_stg(\$whdg);
            set_int_stg(\$wspd);
            $from = "wind $whdg".'@'.$wspd;
        }

        $key = get_runway_for_heading($hdg);
    }
    if (length($key) && defined $xg_circuits{$key}) {
        set_global_per_key($key);
        $msg = 'Set new from ';
    }

    # we have a suggested runway 
    if ( get_runway_heading(\$rhdg) ) {
        my $rch = $ref_circuit_hash;
        my $diff = abs(get_hdg_diff($rhdg,$hdg));
        $msg .= "$from hdg ";
        set_hdg_stg(\$hdg);
        set_hdg_stg(\$rhdg);
        set_int_stg(\$diff);
        $msg .= "$hdg, rwy $rhdg, (d=$diff)";
    }

    prtt("Position on got engine... $msg $key ".get_env_wind_stg()."\n");
    show_position($rp);
}

#######################################################################
########### WAIT for engine start ####### need motor for flight #######
#######################################################################
sub wait_for_engine() {
    my ($ok,$btm,$ntm,$dtm,$ctm);
    my ($running,$rpm);
    my ($run2,$rpm2);
    my ($throt,$thpc,$throt2,$thpc2);
    my ($magn,$cmag,$mixt,$msg);
    my $showstart = 1;
    my $last_msg = '';
    my $show_msg = 0;
    if ($g_ac eq 'ufo') {
        prtt("Aircraft is $g_ac - Always engine running...\n");
        my $rp = fgfs_get_position();
        position_on_got_engine($rp);
        return 0;
    }
    prtt("Checking $engine_count engine(s) running...\n");
    $btm = time();
    $ctm = 0;
    $ok = 0;
    show_flight(fgfs_get_flight());
    while (!$ok) {
        my $re = fgfs_get_engines();
        $running = ${$re}{'running'};
        $rpm     = ${$re}{'rpm'};
        $throt   = ${$re}{'throttle'};
        $magn    = ${$re}{'magn'};
        $mixt    = ${$re}{'mix'};
        $cmag = 'BOTH';
        if ($magn == 0) {
            $cmag = 'NONE';
        } elsif ($magn == 1) {
            $cmag = 'LEFT';
        } elsif ($magn == 2) {
            $cmag = 'RIGHT';
        }
        $mixt = int($mixt * 100);
        # prt("run = [$running] rpm = [$rpm]\n");
        if ($engine_count == 2) {
            # TWO engines
            $run2   = ${$re}{'running2'};
            $rpm2   = ${$re}{'rpm2'};
            $throt2 = ${$re}{'throttle2'};
            if (($running eq 'true') && ($run2 eq 'true') &&
                ($rpm > $min_eng_rpm) && ($rpm2 > $min_eng_rpm)) {
                $thpc = int($throt * 100);
                $rpm = int($rpm + 0.5);
                $thpc2 = int($throt2 * 100);
                $rpm2 = int($rpm2 + 0.5);
                prtt("Run1=$running, rpm=$rpm, throt=$thpc\%, mags $cmag, mix $mixt ...\n");
                prtt("Run2=$run2, rpm=$rpm2, throt=$thpc2\% ...\n");
                $ok = 1;
                last;
            }
        } else {
            # ONE engine
            if (($running eq 'true') && ($rpm > $min_eng_rpm)) {
                $thpc = int($throt * 100);
                $rpm = int($rpm + 0.5);
                prtt("Run=$running, rpm=$rpm, throt=$thpc\%, mags $cmag, mix $mixt ...\n");
                $ok = 1;
                last;
            }
        }
        if (check_keyboard()) {
            return 1;
        }
        $ntm = time();
        $dtm = $ntm - $btm;
        $msg = get_flight_stg(fgfs_get_flight());
        $show_msg = 0;
        if ($msg ne $last_msg) {
            $last_msg = $msg;
            prtt("$msg\n");
            $show_msg = 1;
        }
        if ($show_msg || ($dtm > $DELAY)) {
            $ctm += $dtm;
            # show_flight(get_curr_flight());
            # show_flight(fgfs_get_flight());
            set_int_stg(\$rpm);
            if ($engine_count == 2) {
                prtt("Waiting for $engine_count engines to start... $ctm secs (run1=$running rpm1=$rpm, run2=$run2 rpm2=$rpm2)\n");
            } else {
                prtt("Waiting for $engine_count engine to start... $ctm secs (run=$running rpm=$rpm)\n");
            }
            $btm = $ntm;
            if ($showstart) {
                prt("\n");
                prt("Start Engine Checklist\n");
                prt("\n");
                $msg = start_engine_checklist();
                prt("$msg\n");
                prt("\n");
                $showstart = 0;
            }
        }
    } # while (!$ok) - awaiting ENGINE

    my $rp = fgfs_get_position();
    position_on_got_engine($rp);
    return 0;
}


# stay HERE until AUTOPILOT kicks in...
sub wait_for_alt_hold() {
    my ($ok,$btm,$ntm,$dtm,$ctm);
    my ($ah,$rp);
    if ($wait_alt_hold) {
        prtt("Checking for altitude hold...\n");
    } else {
        fgfs_get_K_ah(\$ah);
        if ($ah eq 'true') {
            prtt("Got altitude hold ($ah)...\n");
        }
        return 0;
    }
    $btm = time();
    $ctm = 0;
    $ok = 0;
    while ( !$ok && $wait_alt_hold ) {
        fgfs_get_K_ah(\$ah);
        if ($ah eq 'true') {
            prtt("Got altitude hold ($ah)...\n");
            $rp = fgfs_get_position();
            my $msg =  get_ind_spdkt_stg();
            my $re = fgfs_get_engines();
            my $rpm = ${$re}{'rpm'};
            my $thr = ${$re}{'throttle'};
            my $mixt = ${$re}{'mix'}; # $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich
            set_int_stg(\$rpm);
            $thr = int($thr * 100);
            if ($mixt > 0.9) {
                $mixt = 'full';
            } else {
                set_decimal1_stg(\$mixt);
            }
            $msg .= " Eng rpm $rpm ($thr%/$mixt)";
            prtt("On altitude hold... speeds $msg\n");
            show_position($rp);
            $ok = 1;
            $got_alt_hold = 1;
        } else {
            if (check_keyboard()) {
                return 1;
            }
        }
        $ntm = time();
        $dtm = $ntm - $btm;
        if ($dtm > $DELAY) {
            $ctm += $dtm;
            $rp = fgfs_get_position();
            show_position($rp);
            ##prtt("Cycle waiting for altitude hold... $ctm secs\n") if (!$ok);
            show_takeoff($rp);
            $btm = $ntm;
        }
    }
    return 0;
}

sub reset_circuit_legs($) {
    my $rch = shift;
    # switch off which part of the circuit we are in
    ${$rch}{'target_takeoff'}  = 0;
    ${$rch}{'target_cross'}    = 0;
    ${$rch}{'target_downwind'} = 0;
    ${$rch}{'target_base'}     = 0;
    ${$rch}{'target_final'}    = 0;
    ${$rch}{'target_runway'}   = 0;
}

######################################################################
### Do some calculations on the current (global) circuit
######################################################################
my ($active_rcx);

sub set_circuit_values($$) {
    my ($rch,$show) = @_;
    my ($az1,$az2,$dist);
    my ($dwd,$dwa,$bsd,$bsa,$rwd,$rwa,$crd,$cra);
    my ($tllat,$tllon,$bllat,$bllon,$brlat,$brlon,$trlat,$trlon);
    my ($elat1,$elon1,$elat2,$elon2,$rwy_hdg,$circ);  # runway ends
    
    $elat1 = ${$rch}{'rwy_elat1'};  #  = $g_elat1;
    $elon1 = ${$rch}{'rwy_elon1'};  #  = $g_elon1;
    $elat2 = ${$rch}{'rwy_elat2'};  #  = $g_elat2;
    $elon2 = ${$rch}{'rwy_elon2'};  #  = $g_elon2;

    ### prt("Get runway heading... $elat1,$elon1 $elat2,$elon2...\n");
    fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$dist);
    if (defined ${$rch}{'rwy_left'} && (${$rch}{'rwy_left'} == 1)) {
        $rwy_hdg = $az1;
        $circ = 'left';
    } else {
        $rwy_hdg = $az2;
        $circ = 'right';
    }

    reset_circuit_legs($rch);

    # TR -> TL - cross
    fg_geo_inverse_wgs_84 (${$rch}{'tr_lat'},${$rch}{'tr_lon'},${$rch}{'tl_lat'},${$rch}{'tl_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'tr_az1'} = $az1;
    ${$rch}{'tr_az2'} = $az2;
    ${$rch}{'tr_dist'} = $dist;
    ${$rch}{'TR'} = [$az1,$az2,$dist];

    # TL -> BL - downwind
    fg_geo_inverse_wgs_84 (${$rch}{'tl_lat'},${$rch}{'tl_lon'},${$rch}{'bl_lat'},${$rch}{'bl_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'tl_az1'} = $az1;
    ${$rch}{'tl_az2'} = $az2;
    ${$rch}{'tl_dist'} = $dist;
    ${$rch}{'TL'} = [$az1,$az2,$dist];

    # BL -> BR - base
    fg_geo_inverse_wgs_84 (${$rch}{'bl_lat'},${$rch}{'bl_lon'},${$rch}{'br_lat'},${$rch}{'br_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'bl_az1'} = $az1;
    ${$rch}{'bl_az2'} = $az2;
    ${$rch}{'bl_dist'} = $dist;
    ${$rch}{'BL'} = [$az1,$az2,$dist];

    # BR -> TR - final - runway - takeoff - upwind leg
    fg_geo_inverse_wgs_84 (${$rch}{'br_lat'},${$rch}{'br_lon'},${$rch}{'tr_lat'},${$rch}{'tr_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'br_az1'} = $az1;
    ${$rch}{'br_az2'} = $az2;
    ${$rch}{'br_dist'} = $dist;
    ${$rch}{'BR'} = [$az1,$az2,$dist];

#    # get runways id, for a runway with this heading
#    # $h2{'left'} = [$l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon];
#    # $h2{'right'} = [$r_tl_lat,$r_tl_lon,$r_bl_lat,$r_bl_lon,$r_br_lat,$r_br_lon,$r_tr_lat,$r_tr_lon];
#    # $h2{'runway'} = [$g_elat1,$g_elon1,$g_elat2,$g_elon2];
#    # fg_geo_inverse_wgs_84($g_elat1,$g_elon1,$g_elat2,$g_elon2,\$az1,\$az2,\$dist);
#    # $h2{'rwy_heading'} = $az1;
#    # $h2{'rwy_id'} = $rwy;
#    # $h2{'rwy_id2'} = $rwy2;
#    # $xg_circuits{$rwy} = \%h2;
#    # $xg_circuits{$rwy2} = \%h2;
#    my ($key,$rcx,$diff,$fnd,$maxdiff,$circuit); # each key is a runway id
#    my @karr = keys %xg_circuits;
#    my $cnt = scalar @karr;
#    $fnd = $rwy_hdg;
#    set_hdg_stg(\$fnd);
#    prt("Searching $cnt circuits matching heading $fnd... $circ\n");
#    $fnd = 0;
#    $maxdiff = 5;
#    foreach $key (keys %xg_circuits) {
#        $rcx = $xg_circuits{$key};  # get ref circuit hash loaded from xg file load
#        if (defined ${$rcx}{'rwy_heading'} ) {
#            $diff = abs(get_hdg_diff( ${$rcx}{'rwy_heading'}, $rwy_hdg ));
#            if ($diff < $maxdiff) {
#                $maxdiff = $diff;
#                $circuit = ${$rcx}{'rwy_id'};
#                ${$rch}{'rwy_id'} = $circuit;
#                set_decimal3_stg(\$diff);
#                prt("Selected circuit $circuit, diff $diff\n");
#                $fnd = 1;
#                $active_rcx = $rcx;
#            }
#        } else {
#            pgm_exit(1,"rwy_heading NOT defined in xg curcuit hash!\n");
#        }
#    }
#    if ($cnt) {
#        if ($fnd) {
#            # found
#        } else {
#            pgm_exit(1,"Failed to select a circuits! WHY???\n");
#        }
#    }

    # ================================================
    $tllat = ${$rch}{'tl_lat'};
    $tllon = ${$rch}{'tl_lon'};
    $bllat = ${$rch}{'bl_lat'};
    $bllon = ${$rch}{'bl_lon'};
    $brlat = ${$rch}{'br_lat'};
    $brlon = ${$rch}{'br_lon'};
    $trlat = ${$rch}{'tr_lat'};
    $trlon = ${$rch}{'tr_lon'};
    # ================================================

    if ($show) {
        ### my ($elat2,$elon2);
        ### my ($az11,$az21,$dist1);

        # extract values
        # downwind TL to BL
        $dwa = ${$rch}{'tl_az1'};
        $dwd = ${$rch}{'tl_dist'};
        # base BL to BR
        $bsd = ${$rch}{'bl_dist'};
        $bsa = ${$rch}{'bl_az1'};
        # turn final BR to TR
        $rwd = ${$rch}{'br_dist'};
        $rwa = ${$rch}{'br_az1'};
        # cross TR to TL
        $crd = ${$rch}{'tr_dist'};
        $cra = ${$rch}{'tr_az1'};

        fg_geo_inverse_wgs_84 ($brlat,$brlon,$elat1,$elon1,\$az1,\$az2,\$dist);


        # set for display - values DESTROYED for calculations
        # ===================================================
        my $distkm = get_dist_stg_km($dist);
        # set_int_stg(\$az1);     # heading to runway
        set_decimal1_stg(\$az1);     # heading to runway
        ### set_dist_stg(\$dist1);

        set_lat_stg(\$tllat);
        set_lat_stg(\$bllat);
        set_lat_stg(\$brlat);
        set_lat_stg(\$trlat);
        set_lon_stg(\$tllon);
        set_lon_stg(\$bllon);
        set_lon_stg(\$brlon);
        set_lon_stg(\$trlon);

        prt("Set, show circuit $g_circuit... \n".
            "TL $tllat,$tllon\n".
            "BL $bllat,$bllon\n".
            "BR $brlat,$brlon\n".
            "TR $trlat,$trlon\n");

        set_int_dist_stg5(\$dwd);
        set_hdg_stg3(\$dwa);
        set_int_dist_stg5(\$bsd);
        set_hdg_stg3(\$bsa);
        set_int_dist_stg5(\$rwd);
        set_hdg_stg3(\$rwa);
        set_int_dist_stg5(\$crd);
        set_hdg_stg3(\$cra);

        prt("l1 $dwd m, on $dwa (tl2bl) - downwind, turn $bsa to base\n");
        prt("l2 $bsd m, on $bsa (bl2br) - base,     turn $rwa to final $g_icao $g_circuit $distkm on $az1\n");
        prt("l3 $rwd m, on $rwa (br2tr) - runway,   turn $cra to cross\n");
        prt("l4 $crd m, on $cra (tr2tl) - cross,    turn $dwa to downwind\n");

    }
}

#########################################################
## Initialise/reinitialise the circuit hash
## setup DEFAULT values from globals set on file read
#########################################################
#sub get_circuit_hash() {
#    my %h = ();
#    $h{'tl_lat'} = $tl_lat;
#    $h{'tl_lon'} = $tl_lon;
#    $h{'bl_lat'} = $bl_lat;
#    $h{'bl_lon'} = $bl_lon;
#    $h{'br_lat'} = $br_lat;
#    $h{'br_lon'} = $br_lon;
#    $h{'tr_lat'} = $tr_lat;
#    $h{'tr_lon'} = $tr_lon;
#
#    # $h2{'runway'} = [$g_elat1,$g_elon1,$g_elat2,$g_elon2];
#    $h{'rwy_elat1'} = $g_elat1;
#    $h{'rwy_elon1'} = $g_elon1;
#    $h{'rwy_elat2'} = $g_elat2;
#    $h{'rwy_elon2'} = $g_elon2;
#    $h{'rwy_id'}    = $g_circuit;
#    $h{'rwy_left'}  = $g_rwy_left;
#
#    my ($az1,$az2,$dist);
#    fg_geo_inverse_wgs_84($g_elat1,$g_elon1,$g_elat2,$g_elon2,\$az1,\$az2,\$dist);
#    $h{'rwy_heading'} = $az1;
#
#    set_circuit_values(\%h,1);
#
#    $h{'suggest_hdg'} = 0;
#    $h{'suggest_chg'} = 0;
#    $h{'target_secs'} = 0;
#    $h{'target_eta'} = 'none';
#    $h{'target_start'} = 0;
#    $h{'begin_time'} = time();
#    $h{'last_time'} = 0;
#
#    $h{'eta_update'} = 0;
#    $h{'eta_trend'} = '=';
#    $h{'targ_first'}  = 0;
#    # wp mode to get to a runway say...
#    $h{'wp_mode'} = 0;
#    $h{'wp_cnt'} = 0;
#    $h{'wp_off'} = 0;
#    $h{'wp_flag'} = 0;
#    $h{'wpts'} = [];    # array of waypoints
#    return \%h;
#}

######################################################################
### Build a HASH as the current 'circuit' hash

sub get_circuit_hash2($) {
    my $rcx = shift;
    my %h = ();
    my ($rca,$rends);
    my ($tllat,$tllon,$bllat,$bllon,$brlat,$brlon,$trlat,$trlon);
    my ($elat1,$elon1,$elat2,$elon2);
    my ($rwy);
    $rwy = ${$rcx}{'rwy_id'};
    if (${$rcx}{'rwy_left'}) {
        #                0         1         2         3          4        5         6         7
        # $h1{'left'} = [$l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon];
        $rca = ${$rcx}{'left'};
        $g_rwy_left = 1;
    } else {
        $rca = ${$rcx}{'right'};
        $g_rwy_left = 0;
    }
    # set the appropriate circuit
    $tllat = ${$rca}[0];
    $tllon = ${$rca}[1];
    $bllat = ${$rca}[2];
    $bllon = ${$rca}[3];
    $brlat = ${$rca}[4];
    $brlon = ${$rca}[5];
    $trlat = ${$rca}[6];
    $trlon = ${$rca}[7];

    $rends = ${$rcx}{'runway'}; #  = [$g_elat1,$g_elon1,$g_elat2,$g_elon2];
    $elat1 = ${$rends}[0];
    $elon1 = ${$rends}[1];
    $elat2 = ${$rends}[2];
    $elon2 = ${$rends}[3];

    $h{'rcx'} = $rcx;       # set the circuit hash in use
    $h{'tl_lat'} = $tllat;
    $h{'tl_lon'} = $tllon;
    $h{'bl_lat'} = $bllat;
    $h{'bl_lon'} = $bllon;
    $h{'br_lat'} = $brlat;
    $h{'br_lon'} = $brlon;
    $h{'tr_lat'} = $trlat;
    $h{'tr_lon'} = $trlon;

    # $h2{'runway'} = [$g_elat1,$g_elon1,$g_elat2,$g_elon2];
    $h{'rwy_elat1'} = $elat1;
    $h{'rwy_elon1'} = $elon1;
    $h{'rwy_elat2'} = $elat2;
    $h{'rwy_elon2'} = $elon2;
    $h{'rwy_id'}    = $rwy;
    $h{'rwy_left'}  = ${$rcx}{'rwy_left'};

    #my ($az1,$az2,$dist);
    #fg_geo_inverse_wgs_84($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$dist);
    #$h{'rwy_heading'} = $az1;
    $h{'rwy_heading'} = ${$rcx}{'rwy_heading'};

    set_circuit_values(\%h,1);

    $h{'suggest_hdg'} = 0;
    $h{'suggest_chg'} = 0;
    $h{'target_secs'} = 0;
    $h{'target_eta'} = 'none';
    $h{'target_start'} = 0;
    $h{'begin_time'} = time();
    $h{'last_time'} = 0;

    $h{'eta_update'} = 0;
    $h{'eta_trend'} = '=';
    $h{'targ_first'}  = 0;
    # wp mode to get to a runway say...
    $h{'wp_mode'} = 0;
    $h{'wp_cnt'} = 0;
    $h{'wp_off'} = 0;
    $h{'wp_flag'} = 0;
    $h{'wpts'} = [];    # array of waypoints
    return \%h;
}


##############################################################
## Extract from circuit hash, and place values in GLOBAL
##############################################################
sub set_global_per_key($) {
    my $key = shift;
    if (length($key) && defined $xg_circuits{$key}) {
        $g_circuit = $key;  # SET ACTIVE CIRCUIT
        my $rcx = $xg_circuits{$key};
        $g_rcx = $rcx;
        my ($rca,$rends);
        if (${$rcx}{'rwy_left'}) {
            #                0         1         2         3          4        5         6         7
            # $h1{'left'} = [$l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon];
            $rca = ${$rcx}{'left'};
            $g_rwy_left = 1;
        } else {
            $rca = ${$rcx}{'right'};
            $g_rwy_left = 0;
        }
        # set the appropriate circuit
        $tl_lat = ${$rca}[0];
        $tl_lon = ${$rca}[1];
        $bl_lat = ${$rca}[2];
        $bl_lon = ${$rca}[3];
        $br_lat = ${$rca}[4];
        $br_lon = ${$rca}[5];
        $tr_lat = ${$rca}[6];
        $tr_lon = ${$rca}[7];

        # TODO: this needs to be CHECKED - maybe in wrong order
        $rends = ${$rcx}{'runway'}; #  = [$g_elat1,$g_elon1,$g_elat2,$g_elon2];
        $g_elat1 = ${$rends}[0];
        $g_elon1 = ${$rends}[1];
        $g_elat2 = ${$rends}[2];
        $g_elon2 = ${$rends}[3];

        $ref_circuit_hash = get_circuit_hash2($rcx);
        write_circuit_xg2($rcx,$tmp_xg_out2);
    }
}

sub get_nxt_ps($) {
    my $ps = shift;
    my $nxps = 'none';
    if ($ps eq 'TL') {
        $nxps = 'BL';
    } elsif ($ps eq 'BL') {
        $nxps = 'BR';
    } elsif ($ps eq 'BR') {
        $nxps = 'TR';
    } elsif ($ps eq 'TR') {
        $nxps = 'TL';
    } else {
        prtw("WARNING: point [$ps] set NOT one of 'TL', 'BR', 'TR', or 'TL'!");
    }
    return $nxps;
}

sub get_next_pointset($$$$$) {
    my ($rch,$ptset,$rlat,$rlon,$show) = @_;
    my $nxps = 'none';
    my ($nlat,$nlon);
    if ($ptset eq 'TL') {
        $nxps = 'BL';
        $nlat = ${$rch}{'bl_lat'};
        $nlon = ${$rch}{'bl_lon'};
    } elsif ($ptset eq 'BL') {
        $nxps = 'BR';
        $nlat = ${$rch}{'br_lat'};
        $nlon = ${$rch}{'br_lon'};
    } elsif ($ptset eq 'BR') {
        $nxps = 'TR';
        $nlat = ${$rch}{'tr_lat'};
        $nlon = ${$rch}{'tr_lon'};
    } elsif ($ptset eq 'TR') {
        $nxps = 'TL';
        $nlat = ${$rch}{'tl_lat'};
        $nlon = ${$rch}{'tl_lon'};
    } else {
        pgm_exit(1,"ERROR: get_next_point [$ptset] set NOT one of 'TL', 'BR', 'TR', or 'TL'!");
    }
    ${$rlat} = $nlat;
    ${$rlon} = $nlon;
    prtt("get_next_pointset: from $ptset to $nxps\n") if ($show);
    return $nxps;
}

sub get_prev_pointset($$$$$) {
    my ($rch,$ptset,$rlat,$rlon,$show) = @_;
    my $prevps = 'none';
    my ($nlat,$nlon);
    if ($ptset eq 'TL') {
        $prevps = 'TR';
        $nlat = ${$rch}{'tr_lat'};
        $nlon = ${$rch}{'tr_lon'};
    } elsif ($ptset eq 'BL') {
        $prevps = 'TL';
        $nlat = ${$rch}{'tl_lat'};
        $nlon = ${$rch}{'tl_lon'};
    } elsif ($ptset eq 'BR') {
        $prevps = 'BL';
        $nlat = ${$rch}{'bl_lat'};
        $nlon = ${$rch}{'bl_lon'};
    } elsif ($ptset eq 'TR') {
        $prevps = 'BR';
        $nlat = ${$rch}{'br_lat'};
        $nlon = ${$rch}{'br_lon'};
    } else {
        pgm_exit(1,"ERROR: get_prev_point [$ptset] set NOT one of 'TL', 'BR', 'TR', or 'TL'!");
    }
    ${$rlat} = $nlat;
    ${$rlon} = $nlon;
    prtt("get_prev_pointset: from $ptset to $prevps\n") if ($show);
    return $prevps;
}


#######################################################################################
# A good attempt at choosing a circuit target
# just get closest point on the circuit
#######################################################################################
sub get_closest_ptset($$$$$$) {
    my ($rch,$slat,$slon,$rpt,$rlat,$rlon) = @_;
    ### set_distances_bearings($rch,$slat,$slon,"Initial position");
    my ($dist,$az1,$az2);
    my ($dist2,$az12,$az22);
    my $pt = "TL";
    my $tlat = ${$rch}{'tl_lat'};
    my $tlon = ${$rch}{'tl_lon'};
    my $nlat = $tlat;
    my $nlon = $tlon;
    # set first DISTANCE
    fg_geo_inverse_wgs_84 ($slat,$slon,$tlat,$tlon,\$az1,\$az2,\$dist);

    # get next point
    $tlat = ${$rch}{'bl_lat'};
    $tlon = ${$rch}{'bl_lon'};
    fg_geo_inverse_wgs_84 ($slat,$slon,$tlat,$tlon,\$az12,\$az22,\$dist2);
    if ($dist2 < $dist) {
        $pt = "BL";
        $dist = $dist2;
        $nlat = $tlat;
        $nlon = $tlon;
    }
    $tlat = ${$rch}{'br_lat'};
    $tlon = ${$rch}{'br_lon'};
    fg_geo_inverse_wgs_84 ($slat,$slon,$tlat,$tlon,\$az12,\$az22,\$dist2);
    if ($dist2 < $dist) {
        $pt = "BR";
        $dist = $dist2;
        $nlat = $tlat;
        $nlon = $tlon;
    }
    $tlat = ${$rch}{'tr_lat'};
    $tlon = ${$rch}{'tr_lon'};
    fg_geo_inverse_wgs_84 ($slat,$slon,$tlat,$tlon,\$az12,\$az22,\$dist2);
    if ($dist2 < $dist) {
        $pt = "TR";
        $dist = $dist2;
        $nlat = $tlat;
        $nlon = $tlon;
    }
    ${$rpt} = $pt;  # set CLOSEST ptset
    ${$rlat} = $nlat;   # return target lat,lon
    ${$rlon} = $nlon;
}

#####################################################
##### SET A TARGET TO ONE OF APEX OF THE CIRCUIT ####
#####################################################
# This will return the next target when joining a circuit from in or out of current circuit
# Sequence assumed TL -> BL -> BR -> TR -> TL
# ###########################################
sub set_next_in_circuit_targ($$$$$) {
    my ($rch,$rp,$slat,$slon,$pt) = @_;
    my ($nlat,$nlon,$nxps,$msg,$whdg,$wspd);
    ## get next ptset
    $nxps = get_next_pointset($rch,$pt,\$nlat,\$nlon,0);
    ${$rch}{'target_lat'} = $nlat;   # $targ_lat;
    ${$rch}{'target_lon'} = $nlon;   # $targ_lon;
    ### This seems the BEST ;=))
    ### my ($clat,$clon);
    ### $clat = ($tlat + $nlat) / 2;
    ### $clon = ($tlon + $nlon) / 2;
    ### $next_targ_lat = $clat;
    ### $next_targ_lon = $clon;
    ## prt("Set target lat, lon $clat,$clon\n");
    my ($distm,$az1,$az2);
    # get info, from HERE to TARGET
    fg_geo_inverse_wgs_84 ($slat,$slon,$nlat,$nlon,\$az1,\$az2,\$distm);
    ${$rch}{'user_lat'} = $slat;
    ${$rch}{'user_lon'} = $slon;
    # set a heading taking account of the WIND conditions
    my $aspd = ${$rp}{'aspd'}; # Knots
    my $gspd = ${$rp}{'gspd'}; # Knots
    my $rwh = compute_course($az1,$aspd);
    $whdg = ${$rwh}{'heading'};
    $wspd = ${$rwh}{'groundspeed'};
    my $wdiff = get_hdg_diff($az1,$whdg);

    # maybe should use this heading???
    if ($use_calc_wind_hdg) {
        ${$rch}{'target_hdg'} = $whdg;
    } else {
        ${$rch}{'target_hdg'} = $az1;
    }
    ${$rch}{'target_dist'} = $distm;
    ${$rch}{'targ_ptset'} = $nxps;   # current chosen point = TARGET point
    ${$rch}{'prev_ptset'} = $pt;   # previous to get TARGET TRACK

    update_hdg_ind();
    my $diff = get_hdg_diff($ind_hdg_degs,$az1);

    #    Suggest HEAD for
    # prt("Suggest head for $clat,$clon, on $az1, $distnm, prev $pt, next $nxps\n");
    my $distnm = get_dist_stg_nm($distm);
    my $distkm = get_dist_stg_km($distm);

    ##set_hdg_stg(\$az1);
    set_decimal1_stg(\$az1);
    my $targ = 'NEXT';
    my $prev = "$pt-$nxps $az1";

    if (defined ${$rch}{'targ_first'}) {
        if (${$rch}{'targ_first'} <= 1) {
            $targ = 'First';
            ${$rch}{'targ_first'} = 1;
            $prev = "prev usr pt";
            $pt = '';
        } else {
            $targ = 'Next';
        }
        ${$rch}{'targ_first'}++;
    } else {
        $targ = "????";
    }

    ### add ETA...
    ### my $gspd = ${$rp}{'gspd'}; # Knots
    my $secs = int(( $distm / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
    my $eta = " ETA:".secs_HHMMSS2($secs); # display as hh:mm:ss
    ${$rch}{'target_secs1'} = $secs;

    $msg = '';
    set_hdg_stg(\$diff);

    reset_circuit_legs($rch);
    ####################################################################
    # BR -> TR = final - runway - 
    if ( ($pt eq 'BR') && ($nxps eq 'TR') ) {
        # BR -> TR - headed to runway, decending for landing, speed, flaps...
        $msg .= "to RUNWAY";
        if (got_runway_coords() && defined $g_rwy_az1) {
            my $diff = get_hdg_diff(${$rch}{'target_hdg'},$g_rwy_az1);
            if (($diff < -15) || ($diff > 15)) {
                $msg .= " ok";
            } else {
                set_decimal1_stg(\$diff);
                $msg .= " $diff";
            }
        }

        ${$rch}{'target_runway'} = 1;   # enter wp mode - just follow some way points...

    ####################################################################
    # TL -> BL = downwind
    } elsif ( ($pt eq 'TL') && ($nxps eq 'BL') ) {
        # TL -> BL - long downwind leg, do landing checks, 
        ${$rch}{'target_downwind'} = 1;
        $msg .= "to downwind";
    ####################################################################
    # BL -> BR = base
    } elsif ( ($pt eq 'BL') && ($nxps eq 'BR') ) {
        ${$rch}{'target_base'} = 1;
        $msg .= "to base";
    # TR -> TL = cross
    } elsif ( ($pt eq 'TR') && ($nxps eq 'TL') ) {
        ${$rch}{'target_cross'} = 1;
        $msg .= "to cross";
    }
    # Add wind direction and speed '020@5' kts
    #set_hdg_stg(\$hdg);
    set_decimal1_stg(\$whdg);
    set_decimal1_stg(\$wdiff);
    set_int_stg(\$aspd);
    set_int_stg(\$gspd);
    set_int_stg(\$wspd);
    $msg .= " ".get_env_wind_stg()." $whdg $wdiff $aspd/$gspd/$wspd";

    ##################
    ##### TARGET #####
    prtt("\n$targ target $nxps, on $az1 ($diff), $distnm $distkm, $prev $msg $eta\n");
    #set_lat_stg(\$nlat);
    #set_lon_stg(\$nlon);
    ###prtt("\n$targ target $nlat,$nlon, on $az1, $distnm $distkm, prev $pt, next $nxps\n");
    ###################
}

##############################################################
### This is ONE simple idea, but NOT very good
# 
### Assumes a patern layout
#      cross
#   TL       TR
#    ---------
# d  |       | takeoff
# o  |       |
# w  ...
# n  |       |
# w  |       | final
#    ---------
#   BL        BR
#      base
#
# From far outside the circuit
# If approaching from the upwind side, choose TR if distant, TL if close in... actual RL
# is to cross pattern (at 3-4000ft), headed for half way between TL and BL, and turn left to join circuit
# If approaching from the crosswind leg, choose TL if distant, of BL if close
# If approaching from downwind, choose BL, joining circuit smoothly if poss.
# If approaching from base, choose BR if min turn to final, else BL
#

sub get_next_in_circuit_targ($$$$) {
    my ($rch,$rp,$slat,$slon) = @_;
    ### my $rch = $ref_circuit_hash;
    my ($pt,$tlat,$tlon,$msg);
    get_closest_ptset($rch,$slat,$slon,\$pt,\$tlat,\$tlon);
    ######################################################################
    # maybe keep this, if it is dist > 1 Km, and on my heading +/-10 degrees...
    my ($az1,$az2,$dist);
    fg_geo_inverse_wgs_84($slat,$slon,$tlat,$tlon,\$az1,\$az2,\$dist);
    my $hdg = ${$rp}{'hdg'};
    my $diff = abs(get_hdg_diff($az1,$hdg));
    ###if (($diff < 25) && ($dist > 1000))
    if (($diff < 30) && ($dist > 1000)) {
        my $ppt = get_prev_pointset($rch,$pt,\$tlat,\$tlon,0);
        set_int_stg(\$diff);
        $dist = get_dist_stg_km($dist);
        set_hdg_stg(\$az1);
        prtt("Choosing CLOSEST ptset $pt on $az1 ($diff) at $dist...\n");
        $pt = $ppt; # set next bumps the pointet...
    } else {
        set_int_stg(\$diff);
        $dist = get_dist_stg_km($dist);
        set_hdg_stg(\$az1);
        $msg = "Closest $pt on $az1 ($diff) at $dist.";

        my $npt = get_next_pointset($rch,$pt,\$tlat,\$tlon,0);
        fg_geo_inverse_wgs_84($slat,$slon,$tlat,$tlon,\$az1,\$az2,\$dist);
        $dist = get_dist_stg_km($dist);
        set_hdg_stg(\$az1);
        prtt("Choosing NEXT ptset $npt on $az1 at $dist. $msg...\n");
    }
    ######################################################################
    set_next_in_circuit_targ($rch,$rp,$slat,$slon,$pt);
}

sub choose_best_target($$) {
    my ($rch,$rp) = @_;
    my ($lat,$lon,$alt);
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    ${$rch}{'targ_first'} = 1;
    get_next_in_circuit_targ($rch,$rp,$lat,$lon);
}

sub set_suggested_hdg($$) {
    my ($rch,$rp) = @_;
    my $chdg = ${$rch}{'target_hdg'};
    my $shdg = ${$rch}{'suggest_hdg'};
    my $whdg = ${$rch}{'suggest_whdg'};
    my $ct = time();
    if ($use_calc_wind_hdg) {
        $shdg = $whdg;
    }
    ${$rch}{'target_hdg'} = $shdg;
    fgfs_set_hdg_bug(${$rch}{'target_hdg'});
    ${$rch}{'suggest_chg'} = 0;
    $m_stable_cnt = 0;

    $circuit_flag |= 2;
    ### set_hdg_bug_force($az2);
    ${$rch}{'target_heading_t'} = $shdg;
    ${$rch}{'target_heading_m'} = get_mag_hdg_from_true($shdg);
    ${$rch}{'target_start'} = $ct;
    ${$rch}{'begin_time'} = $ct;
    ${$rch}{'last_time'} = $ct;
    my $dist = ${$rch}{'target_dist'};
    ${$rch}{'last_dist'} = $dist;    # initially how far to go

    my $lon  = ${$rp}{'lon'};
    my $lat  = ${$rp}{'lat'};
    my $tlat = ${$rch}{'target_lat'};
    my $tlon = ${$rch}{'target_lon'};
    my ($az1,$az2);
    fg_geo_inverse_wgs_84($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
    # display a turn commencing
    my $gspd = ${$rp}{'gspd'}; # Knots
    my $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
    ${$rch}{'change_oount'} = 0;    # no change direction yet
    # display stuff
    # $ptset = ${$rch}{'targ_ptset'}; # get active point set
    my $eta = " ETA:".secs_HHMMSS2($secs); # display as hh:mm:ss
    my $diff = get_hdg_diff($chdg,$shdg);
    set_decimal1_stg(\$diff);
    set_hdg_stg(\$chdg);
    set_hdg_stg(\$shdg);
    prtt("TURN from $chdg to $shdg ($diff) degs, to targ... $eta\n");
}


####################################################################
### Add WIND indication
### size of wind line should be based on $wspd, not on 
### $dist = ($stand_patt_alt * $SG_FEET_TO_METER) / tan($stand_glide_degs * $SGD_DEGREES_TO_RADIANS);
### fg_geo_inverse_wgs_84 ($brlat,$brlon,$elat1,$elon1,\$az11,\$az21,\$dist1);
### my $dist4 = $dist1 / 4;
### speed is in Knots
### my $KNOTS_TO_FTS = ($SG_NM_TO_METER * $SG_METER_TO_FEET) / 3600.0;
### my $KNOTS_TO_MPS = $SG_NM_TO_METER / 3600.0;
sub Add_WIND_indication($$$) {
    my ($mid_lat,$mid_lon,$dist4) = @_;
    my $xg = '';
    my $rew = get_env_wind();
    my $whdg1 = ${$rew}{'wind-from'};
    my $wspd  = ${$rew}{'wind-spd'};
    my ($wlat1,$wlon1,$wlat2,$wlon2,$waz1);
    my $whdg2 = $whdg1 + 180;
    $whdg2 -= 360 if ($whdg2 >= 360);
    ####my $wsize = $wspd * 10;
    my $wsize = $dist4 / 4;
    fg_geo_direct_wgs_84($mid_lat,$mid_lon, $whdg1, $dist4 / 2, \$wlat1, \$wlon1, \$waz1 );
    fg_geo_direct_wgs_84($mid_lat,$mid_lon, $whdg2, $dist4 / 2, \$wlat2, \$wlon2, \$waz1 );
    $xg .= "color green\n";
    $xg .= "$wlon1 $wlat1\n";
    $xg .= "$wlon2 $wlat2\n";
    $xg .= "NEXT\n";
    $xg .= "# wsize $wsize\n";
    if ($wsize > 3) {
        my ($wlatv1,$wlonv1,$whdg,$wlatv2,$wlonv2);

        $whdg = $whdg1 + 30;
        $whdg -= 360 if ($whdg > 360);
        fg_geo_direct_wgs_84($wlat1,$wlon1, $whdg, $wsize, \$wlatv1, \$wlonv1, \$waz1 );
        $xg .= "$wlon1 $wlat1\n";
        $xg .= "$wlonv1 $wlatv1\n";
        $xg .= "NEXT\n";

        fg_geo_direct_wgs_84($wlat2,$wlon2, $whdg, $wsize, \$wlatv2, \$wlonv2, \$waz1 );
        $xg .= "$wlon2 $wlat2\n";
        $xg .= "$wlonv2 $wlatv2\n";
        $xg .= "NEXT\n";

        $xg .= "$wlonv1 $wlatv1\n";
        $xg .= "$wlonv2 $wlatv2\n";
        $xg .= "NEXT\n";

        $whdg = $whdg1 - 30;
        $whdg += 360 if ($whdg < 0);
        fg_geo_direct_wgs_84($wlat1,$wlon1, $whdg, $wsize, \$wlatv1, \$wlonv1, \$waz1 );
        $xg .= "$wlon1 $wlat1\n";
        $xg .= "$wlonv1 $wlatv1\n";
        $xg .= "NEXT\n";

        fg_geo_direct_wgs_84($wlat2,$wlon2, $whdg, $wsize, \$wlatv2, \$wlonv2, \$waz1 );
        $xg .= "$wlon2 $wlat2\n";
        $xg .= "$wlonv2 $wlatv2\n";
        $xg .= "NEXT\n";

        $xg .= "$wlonv1 $wlatv1\n";
        $xg .= "$wlonv2 $wlatv2\n";
        $xg .= "NEXT\n";
    }

    set_hdg_stg(\$whdg1);
    set_int_stg(\$wspd);
    $xg .= "anno $mid_lon $mid_lat $whdg1".'@'."$wspd\n";
    return $xg;
}

sub set_wpts_to_rwy($$) {
    my ($rch,$rp) = @_;
    if (!got_runway_coords()) {
        return;
    }

    my ($lat,$lon);
    my ($elat1,$elon1,$elat2,$elon2);
    my ($az1,$az2,$distm);
    my ($tllat,$tllon,$bllat,$bllon,$brlat,$brlon,$trlat,$trlon,$tmp);
    my $thdg = ${$rch}{'target_hdg'};
    my ($diff,$diff2,$fnd);
    my ($mid_lat,$mid_lon);
    # ================================================
    $tllat = ${$rch}{'tl_lat'};
    $tllon = ${$rch}{'tl_lon'};
    $bllat = ${$rch}{'bl_lat'};
    $bllon = ${$rch}{'bl_lon'};
    $brlat = ${$rch}{'br_lat'};
    $brlon = ${$rch}{'br_lon'};
    $trlat = ${$rch}{'tr_lat'};
    $trlon = ${$rch}{'tr_lon'};
    # ================================================
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};

    # are we picking up the right RUNWAY
    $elat1 = ${$rch}{'rwy_elat1'};
    $elon1 = ${$rch}{'rwy_elon1'};
    $elat2 = ${$rch}{'rwy_elat2'};
    $elon2 = ${$rch}{'rwy_elon2'};
    #$rwy = ${$rch}{'rwy_id'};
    #$isleft = ${$rch}{'rwy_left'};
    my ($az11,$az21,$dist1,$az12,$az22,$dist2,$char,$tnow,$tnxt);
    fg_geo_inverse_wgs_84 ($brlat,$brlon,$elat1,$elon1,\$az11,\$az21,\$dist1);
    fg_geo_inverse_wgs_84 ($brlat,$brlon,$elat2,$elon2,\$az12,\$az22,\$dist2);
    if ($dist2 < $dist1) {
        # TODO: THIS SHOULD NOT HAPPEN, AND SHULD BE FIXED ELSEWHERE
        $tmp = $dist1;
        $dist1 = $dist2;
        $dist2 = $tmp;

        $tmp = $az11;
        $az11 = $az12;
        $az12 = $tmp;

        $tmp = $az21;
        $az21 = $az22;
        $az22 = $tmp;

        $tmp = $elat1;
        $elat1 = $elat2;
        $elat2 = $tmp;

        $tmp = $elon1;
        $elon1 = $elon2;
        $elon2 = $tmp;
        prt("\nNOTE: switched to other end... TODO: *** FIX ME ***\n\n");
        ${$rch}{'rwy_elat1'} = $elat1; 
        ${$rch}{'rwy_elon1'} = $elon1;
        ${$rch}{'rwy_elat2'} = $elat2;
        ${$rch}{'rwy_elon2'} = $elon2;
    }

    fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$distm);
    # this is the leg BR to TR for 33 circuit
    # $brlat = ${$rch}{'br_lat'};
    # $brlon = ${$rch}{'br_lon'};
    $diff = abs(get_hdg_diff($az1,$thdg));
    if ($diff > 30) {
        set_hdg_stg(\$az1);
        set_hdg_stg(\$thdg);
        set_decimal1_stg(\$diff);
        prt("\nTarget hdg $thdg gt 30 ($diff) away from runway $az1... no solution...\n\n");
        $tnxt = 0;
        my $loopcnt = 0;
        while ( !got_keyboard(\$char) ) {
            $tnow = time();
            if ($tnow != $tnxt) {
                $tnxt = $tnow;
                prt("Any key to continue!\n");
                $loopcnt++;
                if ($loopcnt > 30) {
                    prt("Continuing with circuit...\n");
                    last;
                }
            }
        }
        return; # do not set waypoint mode...
    }

    ##################################################
    ### Divide the segment BR to $elat1,$elon1 into 4
    ##################################################
    fg_geo_inverse_wgs_84 ($brlat,$brlon,$elat1,$elon1,\$az11,\$az21,\$dist1);
    ${$rch}{'wp_bgn_lat'} = $lat;
    ${$rch}{'wp_bgn_lon'} = $lon;
    # This should be the TOUCHDOWN point
    ${$rch}{'wp_end_lat'} = $elat1;
    ${$rch}{'wp_end_lon'} = $elon1;
    ${$rch}{'wp_heading'} = $az11;
    ${$rch}{'wp_distance'} = $dist1;

    my $dist4 = $dist1 / 4;
    my ($wp_lat,$wp_lon,$wp_az1,$cnt);
    fg_geo_direct_wgs_84($brlat,$brlon, $az11, $dist4, \$wp_lat, \$wp_lon, \$wp_az1 );
    my @wpts = ();
    push(@wpts, [ $wp_lat, $wp_lon ]);  # set first wp
    fg_geo_direct_wgs_84($brlat,$brlon, $az11, ($dist4 * 2), \$wp_lat, \$wp_lon, \$wp_az1 );
    push(@wpts, [ $wp_lat, $wp_lon ]);  # 2nd
    $mid_lat = $wp_lat;
    $mid_lon = $wp_lon;
    fg_geo_direct_wgs_84($brlat,$brlon, $az11, ($dist4 * 3), \$wp_lat, \$wp_lon, \$wp_az1 );
    push(@wpts, [ $wp_lat, $wp_lon ]);  # 3rd, and
    push(@wpts, [ $elat1, $elon1 ]);    # add DESTINATION as last

    my $ra = ${$rch}{'wpts'};    # array of waypoints
    @{$ra} = @wpts;
    $cnt = scalar @wpts;
    ${$rch}{'wp_cnt'} = $cnt;
    ${$rch}{'wp_off'} = 0;
    ${$rch}{'wp_flag'} = 0;

    ###my $xg = get_circuit_xg();   # no, do NOT want WHOLE circuit
    ### Just 'final', 'runway', and waypoints
    my $xg = "# wp mode points\n";
    $xg .= "color white\n";
    $xg .= "anno $brlon $brlat BR\n";
    $xg .= "$brlon $brlat\n";
    $xg .= "$elon1 $elat1\n";
    $xg .= "NEXT\n";
    # add runway in blue
    $xg .= "color blue\n";
    $xg .= "$elon1 $elat1\n";
    $xg .= "$elon2 $elat2\n";
    $xg .= "NEXT\n";

    $xg .= Add_WIND_indication($mid_lat,$mid_lon,$dist4);

    #####################################################################
    ## Add DOTS for each waypoint
    my ($i,$ra2);
    # start at BR
    $xg .= "color red\n";
    $xg .= "$brlon $brlat\n";
    $xg .= "NEXT\n";
    $xg .= "color red\n";
    for ($i = 0; $i < $cnt; $i++) {
        $ra2 = ${$ra}[$i]; 
        $wp_lat = ${$ra2}[0];
        $wp_lon = ${$ra2}[1];
        $xg .= "$wp_lon $wp_lat\n";
        $xg .= "NEXT\n";
    }

    ##$xg .= "$elon1 $elat1\n";
    ##$xg .= "NEXT\n";
    $xg .= "color white\n";
    $xg .= "$lon $lat # current position\n";
    $xg .= "NEXT\n";

    # setup for adding 'track' to 'runway'
    $xg .= "color gray\n";
    rename_2_old_bak($tmp_wp_out);
    write2file($xg,$tmp_wp_out);
    prtt("Generated $cnt wps to target... started $tmp_wp_out\n");
    prtt("\nEnter WAYPOINT mode - follow $cnt wps...\n");
    ${$rch}{'wp_mode'} = 1;
    ${$rch}{'wp_start'} = time();
    ${$rch}{'wp_last'} = ${$rch}{'wp_start'};
    ${$rch}{'wp_next_sec'} = 0;
}


sub get_speeds_stg($$$) {
    my ($aspd,$gspd,$wspd) = @_;
    set_int_stg(\$aspd);
    set_int_stg(\$gspd);
    set_int_stg(\$wspd);
    return "$aspd/$gspd,$wspd";
}

#######################################################################
### Generate a set of WAYPOINT to target RUNWAY
###############################################
sub do_wpts_to_rwy($$) {
    my ($rch,$rp) = @_;
    my $flg = ${$rch}{'wp_flag'};
    my $off = ${$rch}{'wp_off'};
    my $cnt = ${$rch}{'wp_cnt'};
    my ($ra2,$wp_lat,$wp_lon,$diff,$ah,$gotah,$msg);
    if ($cnt == 0) {
        ${$rch}{'wp_mode'} = 0;
        return;
    }

    # extract current POSIIION values
    my $lon  = ${$rp}{'lon'};
    my $lat  = ${$rp}{'lat'};
    my $alt  = ${$rp}{'alt'};
    my $agl  = ${$rp}{'agl'};
    my $hb   = ${$rp}{'bug'};
    my $gspd = ${$rp}{'gspd'}; # Knots
    my $aspd = ${$rp}{'aspd'}; # Knots
    $gotah = 0;
    fgfs_get_K_ah(\$ah);
    if ($ah eq 'true') {
        $gotah = 1;
    }

    my $ra = ${$rch}{'wpts'};    # array of waypoints
    my $gonxt = 0;
    if ($off < $cnt) {
        $ra2 = ${$ra}[$off];
    } else {
        $ra2 = ${$ra}[$off-1];  # get LAST
    }
    # get way point lat,lon
    $wp_lat = ${$ra2}[0];
    $wp_lon = ${$ra2}[1];

    my $ct = time();
    my ($az1,$az2,$dist,$tlat,$tlon,$secs,$eta);
    my ($taz1,$taz2,$tdist,$tsecs,$teta);
    my ($rwh,$whdg,$wdiff,$wspd,$spds);
    my ($elat1,$elon1,$eaz1,$eaz2,$edist,$esecs);
    my $sethb = 0;
    $msg = '';
    # get END target, and update
    $elat1 = ${$rch}{'wp_end_lat'};
    $elon1 = ${$rch}{'wp_end_lon'};
    fg_geo_inverse_wgs_84($lat,$lon,$elat1,$elon1,\$eaz1,\$eaz2,\$edist);
    $esecs = int(( $edist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
    ${$rch}{'end_targ_hdg'}  = $eaz1;
    ${$rch}{'end_targ_dist'} = $edist;
    ${$rch}{'end_targ_secs'} = $esecs;
    $teta = "".secs_HHMMSS2($esecs);
    $tsecs = $esecs;
    ##############################################################################
    if ($flg == 0) {
        # first entry, start up first target
        fg_geo_inverse_wgs_84($lat,$lon,$wp_lat,$wp_lon,\$az1,\$az2,\$dist);
        $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
        $diff = get_hdg_diff($hb,$az1);
        $rwh = compute_course($az1,$aspd);
        $whdg = ${$rwh}{'heading'};
        $wspd = ${$rwh}{'groundspeed'};
        $wdiff = get_hdg_diff($az1,$whdg);
        $spds = get_speeds_stg($aspd,$gspd,$wspd);

        if ($secs > 15) {
            fgfs_set_hdg_bug($az1);
            $sethb = 1;
        } elsif (abs($diff) < 5) {
            fgfs_set_hdg_bug($az1);
            $sethb = 1;
        }
        $m_stable_cnt = 0;
        ${$rch}{'suggest_chg'} = 0;

        # keep the next TARGET wp
        ${$rch}{'wp_targ_lat'}  = $wp_lat;
        ${$rch}{'wp_targ_lon'}  = $wp_lon;
        ${$rch}{'wp_targ_hdg'}  = $az1;
        ${$rch}{'wp_targ_whdg'} = $whdg;
        ${$rch}{'wp_targ_dist'} = $dist;
        ${$rch}{'wp_targ_secs'} = $secs;
        ${$rch}{'wp_set_hb'}    = $sethb;
        ${$rch}{'wp_init_agl'}  = $agl;
        ${$rch}{'wp_flag'} = 1;
        ${$rch}{'wp_off'} = 1;  # move to first wp

        # display mess up
        $dist = get_dist_stg_km($dist);
        set_hdg_stg(\$az1);
        $eta = "eta:".secs_HHMMSS2($secs);
        $az1 .= '*' if ($sethb);
        prtt("WP: Set first of $cnt wps, h=$az1, d=$dist, $eta $teta $spds\n");
        return; # all done setting FIRST target

    ##############################################################################
    } else {
    ##############################################################################
        # get TARGET WP
        $tlat = ${$rch}{'wp_targ_lat'};
        $tlon = ${$rch}{'wp_targ_lon'};
        # check course correction
        fg_geo_inverse_wgs_84($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
        $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
        $eta = "eta:".secs_HHMMSS2($secs);
        $rwh = compute_course($az1,$aspd);
        $whdg = ${$rwh}{'heading'};
        $wspd = ${$rwh}{'groundspeed'};
        $spds = get_speeds_stg($aspd,$gspd,$wspd);
        if ($secs < 20) { # was 15
            $gonxt = 1;
        }

        if ( !$gonxt && ($dist < ${$rch}{'wp_targ_dist'})) {
            # stay on this track
            ${$rch}{'wp_targ_dist'} = $dist;
            $diff = get_hdg_diff(${$rch}{'wp_targ_hdg'},$az1);
            if (abs($diff) > 1) {

                fgfs_set_hdg_bug($az1);
                $m_stable_cnt = 0;
                ${$rch}{'suggest_chg'} = 0;

                $sethb = 1;
                ${$rch}{'wp_targ_hdg'} = $az1;
                set_hdg_stg(\$az1);
                ${$rch}{'wp_last'} = $ct;
                $dist = get_dist_stg_km($dist);
                set_decimal1_stg(\$diff);
                $msg = "WP: Adj* $off of $cnt, at $dist, hdg $az1 ($diff) $eta $spds";
            } elsif ($ct != ${$rch}{'wp_last'}) {
                ${$rch}{'wp_last'} = $ct;
                $dist = get_dist_stg_km($dist);
                $msg = "WP: Cont $off of $cnt, at $dist $eta $teta $spds";
            }
            if (!$gotah) {
                # are we DECENDING...
                $msg .= get_decent_msg($rp);
            }
            prtt("$msg\n") if (length($msg));
            return;
        }

        ############################################################################
        $off++;
        fg_geo_inverse_wgs_84($lat,$lon,$wp_lat,$wp_lon,\$az1,\$az2,\$dist);
        $rwh = compute_course($az1,$aspd);
        $whdg = ${$rwh}{'heading'};
        $wspd = ${$rwh}{'groundspeed'};
        $wdiff = get_hdg_diff($az1,$whdg);
        $spds = get_speeds_stg($aspd,$gspd,$wspd);

        fgfs_set_hdg_bug($az1);
        $m_stable_cnt = 0;
        ${$rch}{'suggest_chg'} = 0;

        $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
        $eta = "eta:".secs_HHMMSS2($secs);
        ${$rch}{'wp_targ_lat'} = $wp_lat;
        ${$rch}{'wp_targ_lon'} = $wp_lon;
        ${$rch}{'wp_targ_hdg'} = $az1;
        ${$rch}{'wp_targ_dist'} = $dist;
        ${$rch}{'wp_targ_secs'} = $secs;
        ${$rch}{'wp_flag'} |= 2;
        ${$rch}{'wp_off'} = $off;
        $dist = get_dist_stg_km($dist);
        if ($off <= $cnt) {
            if ($ct != ${$rch}{'wp_last'}) {
                ${$rch}{'wp_last'} = $ct;
                $off--;
                prtt("WP: Next wp $off of $cnt, at $dist $eta $teta $spds\n");
            }
            return;
        }
        $off--;
        ############################################################################
        prtt("WP: Last $off of $cnt, at $dist $eta $spds\n\n");
    }
    ##############################################################################

    # end of WAYPOINT tracker
    set_int_stg(\$alt);
    set_int_stg(\$az1);
    set_int_stg(\$secs);
    my $xg = "$lon $lat # $alt - $secs on $az1\n";
    $xg .= "NEXT\n";
    $xg .= "color yellow\n";
    $xg .= "$lon $lat # $alt - $secs on $az1\n";
    $elat1 = ${$rch}{'wp_end_lat'};
    $elon1 = ${$rch}{'wp_end_lon'};
    $xg .= "$elon1 $elat1 # touch down\n"; # there should aready be a RED dot
    $xg .= "NEXT\n";
    append2file($xg,$tmp_wp_out);
    prtt("Written track to '$tmp_wp_out'\n");

    ${$rch}{'wp_mode'} = 0;
}

sub show_decent_checks() {
    my $txt = decent_checks();
    my $msg = "\nDecent Checklist\n";
    $msg .= $txt;
    $msg .= "\n";
    prt("$msg\n");
}

sub get_decent_msg($) {
    my $rp = shift;
    my $rf = fgfs_get_flight();
    my $msg = '';
    my $agl  = ${$rp}{'agl'};
    my $hb   = ${$rp}{'bug'};
    my $gspd = ${$rp}{'gspd'}; # Knots
    my $aspd = ${$rp}{'aspd'}; # Knots
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
    set_int_stg(\$aspd);
    set_int_stg(\$gspd);
    $msg .= " ias=$aspd/$gspd, $agl ft, $vspd fpm, flaps $flap";
    return $msg;
}

my $last_decent_stats = 0;
sub show_decent_stats($$) {
    my ($rch,$rp) = @_;
    my $ctm = time();
    my $dtm = $ctm - $last_decent_stats;
    my $show_msg = 0;
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
        my $aspd = ${$rp}{'aspd'}; # Knots
        $gotah = 0;
        fgfs_get_K_ah(\$ah);
        if ($ah eq 'true') {
            $gotah = 1;
        }
       if ($gotah) {
           # FLYING AT A CONSTANT HEIGHT

       } else {
            # are we DECENDING/CLIMBING...
            $msg = "ah=off ";
            $msg .= get_decent_msg($rp);
       }
    }
    prtt("$msg\n") if (length($msg));
}

# $circuit_mode is ON
# $mag_deviation = ($curr_hdg - $curr_mag);
# ref position hash
sub process_circuit($) {
    my ($rp) = @_;
    my $rch = $ref_circuit_hash;
    return if (!defined ${$rp}{'time'});
    my $ctm = lu_get_hhmmss_UTC(${$rp}{'time'});
    my $ct = time();
    my $bgn_turn = 500; # meters BEFORE target, commence turn - should be a function of degrees to turn to next
    my $secs = -1;
    my $eta = '';
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$cpos,$msg,$tmp);
    my ($az1,$az2,$dist,$tlat,$tlon);
    my $ptset = ${$rch}{'targ_ptset'};   # current chosen point TR,BR,BL,TL
    if (!defined $ptset) {
        $ptset = 'none';
    }
    # extract current POSIIION values
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    $hdg  = ${$rp}{'hdg'};
    $agl  = ${$rp}{'agl'};
    $hb   = ${$rp}{'bug'};
    $mag  = ${$rp}{'mag'};  # /orientation/heading-magnetic-deg
    $aspd = ${$rp}{'aspd'}; # Knots
    $gspd = ${$rp}{'gspd'}; # Knots

    ###########################################################################
    if (${$rch}{'wp_mode'} && ${$rch}{'wp_flag'}) {
        # if in WP MODE, keep another track record... each second
        if ($ct != ${$rch}{'wp_next_sec'}) {
            ${$rch}{'wp_next_sec'} = $ct;
            $tlat  = ${$rch}{'wp_end_lat'};
            $tlon  = ${$rch}{'wp_end_lon'};
            fg_geo_inverse_wgs_84($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
            $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
            $tmp = $alt;
            set_int_stg(\$tmp);
            set_int_stg(\$secs);
            set_int_stg(\$az1);
            append2file("$lon $lat # $tmp - $secs on $az1\n",$tmp_wp_out);
        }
    }
    ###########################################################################

    if ($circuit_mode && $circuit_flag) {
        if (!defined ${$rch}{'target_lat'} || !defined ${$rch}{'target_lon'}) {
            pgm_exit(1,"ERROR: target_lat, lon NOT defined?\n");
        }
        $tlat  = ${$rch}{'target_lat'};
        $tlon  = ${$rch}{'target_lon'};
        fg_geo_inverse_wgs_84($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
        $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
        my $psecs = ${$rch}{'target_secs'};
        ###${$rch}{'target_secs'} = $secs;
        my $ct = time();
        my $trend = ${$rch}{'eta_trend'};
        if (${$rch}{'eta_update'} == $ct) {
            # less than a second - no update
        } else {
            ${$rch}{'target_secs'} = $secs;
            ${$rch}{'eta_update'} = $ct;
            $trend = '=';
            if ($secs < $psecs) {
                $trend = '-';
            } elsif ($psecs > $secs) {
                $trend = "++";
            }
            ${$rch}{'eta_trend'} = $trend;
            ${$rch}{'target_eta'} = "ETA:".secs_HHMMSS2($secs).$trend; # display as hh:mm:ss
        }
        ###${$rch}{'target_eta'} = "ETA:".secs_HHMMSS2($secs).$trend; # display as hh:mm:ss
    }

    # FIRST TIME HERE
    if ($circuit_flag == 0) {
        choose_best_target($rch,$rp);
        $circuit_flag = 1;
        # set intital course to target
        fgfs_set_hdg_bug(${$rch}{'target_hdg'});
        $m_stable_cnt = 0;
        ${$rch}{'suggest_chg'} = 0;
        return;
    }

    if ($circuit_flag) {
        if ($m_stable_cnt > 1) {  # less than 2 degrees between previous ind hdg
            if (${$rch}{'wp_mode'}) {
                 do_wpts_to_rwy($rch,$rp);
            } elsif (${$rch}{'target_secs'} < 25 ) { # was 22, 20
                # only XX secs to target - choose next target
                my ($ntlat,$ntlon);
                my $ptset = ${$rch}{'targ_ptset'};  # passing this target, head for next
                ##my $nxt_ps = get_next_pointset($rch,$ptset,\$ntlat,\$ntlon,0);
                set_next_in_circuit_targ($rch,$rp,$lat,$lon,$ptset);

                fgfs_set_hdg_bug(${$rch}{'target_hdg'});
                $m_stable_cnt = 0;
                ${$rch}{'suggest_chg'} = 0;

                if (${$rch}{'target_runway'}) {
                    if (${$rch}{'target_runway'} == 1) {
                        ${$rch}{'target_runway'} = 2;
                        set_wpts_to_rwy($rch,$rp);
                    } else {

                    }
                } elsif (${$rch}{'target_base'}) {
                    if (${$rch}{'target_base'} == 1) {
                        # init for this leg
                        show_decent_checks();
                        ${$rch}{'target_base'} = 2;
                    }
                    show_decent_stats($rch,$rp);
                } elsif (${$rch}{'target_downwind'}) {
                    show_decent_stats($rch,$rp);
                } elsif (${$rch}{'target_cross'}) {
                    show_decent_stats($rch,$rp);
                }
            } elsif (${$rch}{'suggest_chg'}) {
                set_suggested_hdg($rch,$rp);
            } else {
                # NOT wp mode, NOT choose new target, NOT suggested change, so...
                show_decent_stats($rch,$rp);
            }
        }
    }
}

sub show_winds_radio_fuel() {

    # check the WINDS, weather
    my $renv = fgfs_get_environ();
    show_environ($renv);

    # get the RADIO stack
    my $rcomms = fgfs_get_comms();
    show_comms($rcomms);   # show current comms

    # headed for new target - SHOW consumables, and maybe warnings, if any
    my $rcs = fgfs_get_consumables();
    show_consumables($rcs);
    # other things on choosing a target???

}

my $do_init_pset = 0;

my $help = "ESC/q=exit, c/C=circuit/off, h=home, ?=this";

sub keyboard_help() {
    prt("Keyboard Help\n");
    prt(" ?      This HELP output\n");
    prt(" ESC(q) Exit program.\n");
    prt(" h      Head home - centre of active runway\n");
#    prt(" a      Get autopilot (KAP140) locks\n");
#    prt(" B/b    Increase/Decrease heading bug 1 degreee\n");
    prt(" c/C    Circuit mode. C cancel.\n");
#    prt(" +/-    Increase/Decrease position delay check. Current $DELAY secs\n");
#    prt(" 9/(    Increase/Decrease heading bug 90 degrees\n");
    #prt(" 1      Set heading target to Gil (YGIL)\n");
    #prt(" 2      Set heading target to Dubbo (YSDU)\n");
    prt(" e      Show Engine(s)\n"); # add 20210115
#    prt(" g/1    Head for target YGIL\n");
#    prt(" d/2    Head for target YSDU\n");
#    prt(" o/O    Commence a 360 degree orbit. O will repeat. If in orbit, cancel orbitting.\n");
#    prt(" Any keyboard input exits the keyboard loop, and continues the main loop, except ESC!\n");
    prt(" W      Show weather, radio, fuel info\n");
}

sub clear_circuit_mode($) {
    my $rch = shift;
    #### prtt("Clear CIRCUIT mode\n");
    $circuit_mode = 0;
    $circuit_flag = 0;
    $chk_turn_done = 0;
    ${$rch}{'wp_mode'} = 0;
    ${$rch}{'suggest_chg'} = 0;
}

# $rp = fgfs_get_position();
# $rch = $ref_circuit_hash;
sub head_for_home($$) {
    my ($rch,$rp) = @_;
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$tlat,$tlon);
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    $hdg  = ${$rp}{'hdg'};
    $agl  = ${$rp}{'agl'};
    $hb   = ${$rp}{'bug'};
    $mag  = ${$rp}{'mag'};  # is this really magnetic - # /orientation/heading-magnetic-deg
    $aspd = ${$rp}{'aspd'}; # Knots
    $gspd = ${$rp}{'gspd'}; # Knots

    if (!get_runway_center(\$tlat,\$tlon)) {
        prtt("No target chosen!\n");
    }
    my ($az1,$az2,$distm);
    # from present position to target - center of active runway
    my $res = fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$distm);
    my $rwh = compute_course($az1,$aspd);   # factor in the different
    my $whdg = ${$rwh}{'heading'};  # = $whdg;
    my $wdiff = get_hdg_diff($az1,$whdg);
    my $secs = int(( $distm / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
    my $eta = "eta:".secs_HHMMSS2($secs); # display as hh:mm:ss

    ${$rch}{'target_hdg'} = $whdg;

    fgfs_set_hdg_bug(${$rch}{'target_hdg'});
    $m_stable_cnt = 0;
    ${$rch}{'suggest_chg'} = 0;

    # display stuff
    set_hdg_stg(\$whdg);
    #set_dist_stg(\$distm);
    my $distkm = get_dist_stg_km($distm);
    prtt("Turning to heading $whdg, target $distkm, $eta\n");

    show_winds_radio_fuel();

}

sub main_loop() {

    prtt("Get 'sim' information...\n");
    my $rs = show_sim_info(fgfs_get_sim_info());
    $g_ac = ${$rs}{'aircraft'};
    $g_fdm = ${$rs}{'fdm'};
    $g_aero = ${$rs}{'aero'};
    prtt(fgfs_get_versions());
    prtt("Get Fuel - comsumables...\n");
    show_consumables(fgfs_get_consumables());
    prtt("Getting current environment...\n");
    show_environ(fgfs_get_environ());
    prtt("Getting current COMMS...\n");
    show_comms(fgfs_get_comms());

    # ### FOREVER - NOTHING happens without an ENGINE ###
    if ( wait_for_engine() ) {
       return 1;
    }

    # we have ENGINES!!!
    if ( wait_for_alt_hold() ) {
        return 1;
    }
    my $ok = 1;
    my ($char,$val,$rp);
    my $rch = $ref_circuit_hash;
    if ($do_init_pset) {
        $rp = fgfs_get_position();
        get_next_in_circuit_targ($rch,$rp,${$rp}{'lat'},${$rp}{'lon'});
    }

    while ($ok) {
        $rp = fgfs_get_position();
        $rch = $ref_circuit_hash;
        show_position($rp);
        if ( got_keyboard(\$char) ) {
            $val = ord($char);
            if (($val == 27)||(lc($char) eq 'q')) {
                prtt("Quit key... Exiting...\n");
                $ok = 0;
                return 0;
            } elsif ($char eq 'c') {
                if ($circuit_mode) {
                    prtt("Already in CIRCUIT mode!\n");
                } else {
                    clear_circuit_mode($rch);
                    prtt("Set CIRCUIT mode\n");
                    $circuit_mode = 1;
                    process_circuit($rp);
                }
            } elsif ($char eq 'C') {
                prtt("Clear CIRCUIT mode\n");
                clear_circuit_mode($rch);
            } elsif ($char eq 'h') {
                prtt("Head for home...\n");
                clear_circuit_mode($rch);
                head_for_home($rch,$rp);
            } elsif ($char eq 'e') {
                prtt("Show engine(s)...\n");
                # show_engines(); # add 20210115, but better...
                show_engines_and_fuel(); # show fuel plus...
            } elsif ($char eq 'W') {
                prtt("Show Weather, radios, fuel...\n");
                show_winds_radio_fuel();
            } elsif ($char eq '?') {
                keyboard_help();
                # prtt("$help\n");
            } else {
                prtt("Unhandled key val=$val, '$char'! $help\n");
            }
        }
        process_circuit($rp) if ($circuit_mode);
    }
}

#########################################
### MAIN ###
parse_args(@ARGV);
process_in_file($in_file);
wait_fgio_avail();
main_loop();
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
            if (($sarg =~ /^help/i)||($sarg eq '?')) {
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
            } elsif (($sarg =~ /^port$/i)||($sarg eq 'p')) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $PORT = $sarg;
                prt("Set PORT to [$PORT]\n");
                if ( !($sarg =~ /^\d+$/) ) {
                    prtw("WARNING: Port is NOT all numeric!\n");
                }
            } elsif (($sarg =~ /^host$/i)||($sarg eq 'h')) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $HOST = $sarg;
                prt("Set HOST to [$HOST]\n");
            } elsif (($sarg =~ /^delay$/i)||($sarg eq 'd')) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if ($sarg =~ /^\d+$/) {
                    $DELAY = $sarg;
                    prt("Set DELAY to [$DELAY]\n");
                } else {
                    pgm_exit(1,"ERROR: Invalid argument [$arg $sarg]! Dealy can ONLY be an integer!\n");
                }
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
    ###pgm_exit(1,"TEMP EXIT\n");
}

sub give_help {
    my $msg = '';
    prt("\n");
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-file\n");
    prt("Options:\n");
    prt(" --help         (-?) = This help, and exit 0.\n");
    prt(" --verb[n]      (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load         (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>   (-o) = Write output to this file.\n");
    prt(" --host <name>  (-h) = Set host name, or IP address. (def=$HOST)\n");
    prt(" --port <num>   (-p) = Set port. (def=$PORT)\n");
    prt(" --delay <secs> (-d) = Set delay in seconds between sampling. ($DELAY)\n");
    prt("\n");
    $msg = (( -f $in_file) ? "ok" : "NOT FOUND");
    prt(" The input xg file establishes a circuit to fly, (def $in_file $msg)\n");
    prt(" Establish a TELNET connection to an instance of fgfs running on a host:port\n");
    prt(" Will wait for engine running, and after that altitude hold.\n");
    prt(" Accepts keyboard input to run scenarios, ESC key to exit\n");
    prt("\n");
}

sub landing_checks() {
    my $txt = <<EOF;
Speed Normal... 60-70 KIAS (Short/Soft 55) 
GUMPS check... Complete
Fuel Selector... Both
Landing Light... On
Seat Belts... On
Flaps... As Required
Mixture... Rich (Below 3000 ft MSL)
Autopilot... Off
Carburetor Heat... As Required
EOF
    return $txt;
}

sub decent_checks() {
    my $txt = <<EOF;
Seats & Belts... Secure
Fuel Selector... Both
Mixture... Enrich
Engine Instruments... Check
Avionics... Set
NAV/GPS Switch... Set
Aircraft Lights... As Required
Pitot Heat... As Required 
EOF
    return $txt;
}

sub start_engine_checklist() {
    my $txt = <<EOF;
Throttle... Open 1/4 Inch
Mixture... Idle Cutoff
Propeller Area... CLEAR
Master Switch... On
Flashing Beacon... On
 If Engine is Cold:
  Auxiliary Fuel Pump Switch... On
  Mixture... Set to Full Rich then Idle Cutoff
  Auxiliary Fuel Pump Switch... Off
Ignition Switch... Start
Mixture... Advance to Rich when engine starts
Throttle... 1,000 RPM Max
Oil Pressure... Check
Mixture... Lean For Taxi 
EOF
    return $txt;
}

# eof - do-square02.pl

