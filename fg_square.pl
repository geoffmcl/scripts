#!/usr/bin/perl -w
# NAME: fg_square.pl
# AIM: Through a TELNET connection, fly the aircraft on a course
# 30/06/2015 - Much more refinement
# 03/04/2012 - More changes
# 16/07/2011 - Try to add flying a course around YGIL, using the autopilot
# 15/02/2011 geoff mclane http://geoffair.net/mperl
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use IO::Socket;
use Term::ReadKey;
use Time::HiRes qw( usleep gettimeofday tv_interval );
use Math::Trig;
my $cwd = cwd();
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
$perl_dir .= "/temp";
# unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl'! Check location and \@INC content.\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
require "Bucket2.pm" or die "Unable to load Bucket2.pm ...\n";
# log file stuff
my ($LF);
my $outfile = $perl_dir."/temp.$pgmname.txt";
open_log($outfile);

my $VERS = "0.0.3 2015-06-30";
# my $VERS = "0.0.2 2012-04-03";
# my $VERS = "0.0.1 2011-02-16";
# defaults
# my $HOST = "localhost";
my ($HOST,$PORT,$CONMSG);
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
        $PORT = 5556;
        $CONMSG = "Assumed in DELL01 connection to WIN7-PC ";
    }
} else {
    # assumed in Ubuntu - connect to DELL01
    $HOST = "192.168.1.11"; # DELL01
    $PORT = 5557;
    $CONMSG = "Assumed in Ubuntu DELL02 connection to DELL01 ";
}

### constants
my $SGD_PI = 3.1415926535;
my $SGD_DEGREES_TO_RADIANS = $SGD_PI / 180.0;
my $SGD_RADIANS_TO_DEGREES = 180.0 / $SGD_PI;
my $DEF_GS = 3;
my $ATAN3 = atan( $DEF_GS * $SGD_DEGREES_TO_RADIANS );
# /** Feet to Meters */
my $SG_FEET_TO_METER = 0.3048;
# /** Meters to Feet */
my $SG_METER_TO_FEET = 3.28083989501312335958;
my $SG_NM_TO_METER = 1852;
my $SG_METER_TO_NM = 0.0005399568034557235;

# user variables
my $load_log = 0;
my $in_file = '';
my $send_run_exit = 0;
my $wait_alt_hold = 0;
my $min_fly_speed = 30; # Knots
my $min_upd_position = 5 * 60;  # update if older than 5 minutes
my $bug_in_bug = 1;
my $min_apt_distance_m = 25 * $SG_NM_TO_METER;  # interested if within 25 nautical miles
my $degs_to_rwy = 35;
my $min_agl_height = 4500;  # was just 500
my $short_time_stg = 1; # shorten 00:00:59 to 59s
my $target_decent = 500; # feet per minute decent rate target
my $set_run_lights = 1; # auto turn on RUNNING lights
my $min_eng_rpm = 0; #400;
my $tmp_circuit = $perl_dir."\\tempcircuit.txt";
my $use_new_getcpt = 1; # try ON - oops need moer code to protect from next change

my $stand_glide_degs = 3; # degrees
my $stand_patt_alt = 1000; # feet
my $stand_cross_nm = 2.1; # nm, but this will depend on the aircraft

# from solve.pl
my $bad_latlon = 200;
my $in_lat = $bad_latlon;
my $in_lon = $bad_latlon;
my $graf_file = "tempgraf.gif";
my $graf_bat = $perl_dir."\\tempgraf.bat";
my $min_turn_diff = 6; # 5;    # was 1
my $min_turn_diff2 = 3; # another indicator added, using indicate heading
my $target_lat = 0; # like ${$rl}{$targ}[$OL_LAT];
my $target_lon = 0; # like ${$rl}{$targ}[$OL_LON];
my $in_takeoff = 0; 
my $exp_takeoff = 1;
my $g_in_takeoff = 0;   # doing a takeoff

# debug
my $keep_av_time = 1;
my $debug_on = 0;
my $def_file = 'def_file';
my $dbg_01 = 0;
my $dbg_02 = 0;
my $dbg_roll = 1;   # show 'roll' on each display

### program variables
my @warnings = ();

my $FGFS_IO; # Telnet IO handle

my $TIMEOUT = 2;  # second to wait for a connect.
my $DELAY = 5;    # delay between getting a/c position
my $MSDELAY = 200; # max wait before keyboard sampling
my $gps_next_time = 5 * 60; # gps update each ?? minutes

my $engine_count = 1;

my $a_gil_lat = -31.697287500;
my $a_gil_lon = 148.636942500;
my $a_dub_lat = -32.2174865;
my $a_dub_lon = 148.57727;

# rough Gil circuit - will be replaced by CALCULATED values
my $tl_lat = -31.684063;
my $tl_lon = 148.614120;
my $bl_lat = -31.723495;
my $bl_lon = 148.633003;
my $br_lat = -31.716778;
my $br_lon = 148.666992;
my $tr_lat = -31.672960;
my $tr_lon = 148.649139;
my $use_pattern = 1; # adjust the above values to the computed circuit
my $add_text_count = 1; # add text count
my $try_dash_line = 1;
my $switch_circuit = 0; # try the OTHER circuit 15 (def = 33)
my $active_key = 'YGIL';
my $active_runway = '33';
# Access to RUNWAY INFORMATION, like
#    ${$rrwys}[$off][$RW_LLAT] = $elat1;
#    ${$rrwys}[$off][$RW_LLON] = $elon1;
#    ${$rrwys}[$off][$RW_RLAT] = $elat2;
#    ${$rrwys}[$off][$RW_RLON] = $elon2;
my ($active_ref_rwys,$active_off_rwys);

my $circuit_mode = 0;
my $circuit_flag = 0;
my $ref_circuit_hash;

my $away_max = 3; # when more than 3 nm from GIL, turn back to GIL 'g'

my $target_char = '';
my $prev_nm = 0;
my $last_trend = '';

# last KAP140 lock values
my $kap_tm = '';
my $kap_ah = 'false';
my $kap_pa = 'false';
my $kap_ra = 'false';
my $kap_hh = 'false';

# RUNWAY ARRAY OFFSETS
my $RW_LEN = 0;
my $RW_HDG = 1;
my $RW_REV = 2;
my $RW_TT1 = 3;
my $RW_TT2 = 4;
my $RW_CLAT = 5;
my $RW_CLON = 6;
my $RW_LLAT = 7;
my $RW_LLON = 8;
my $RW_RLAT = 9;
my $RW_RLON = 10;
my $RW_DONE = 11;
#                 Len    Hdg   Rev  Title  RTit Ctr Lat    Ctr Lon
#                 0      1     2    3     4     5          6           7  8  9  10 11
my @gil_patt = ();
### my @gil_rwys = ( [4204,  162.0, 0, '15', '33', -31.696928, 148.636404, 0, 0, 0, 0, 0 ] );
my @gil_rwys = ( [3984,  162.22, 0, '15', '33', -31.69656323, 148.6363057, 0, 0, 0, 0, 0 ] );
#my @gil_navs = ( ["", 0 ] );
my @gil_navs = ();
#my @gil_rwys = ( [162.0, 4204], [93.0, 1902] );
my @dub_patt = ( [ ] );
my @dub_rwys = ( [5600, 53.61, 0, '05', '23', -32.218265, 148.576145, 0, 0, 0, 0, 0 ] );
my @dub_navs = ( ["VOR", 114.4], ["NDB", 251] );

my $OL_LAT = 0;
my $OL_LON = 1;
my $OL_NAV = 2;
my $OL_RWY = 3;
my $OL_PAT = 4;
my %apt_locations = (
    # ICAO       Center LAT, LON       NAVAIDS      RUNWAYS
    'YGIL' => [$a_gil_lat, $a_gil_lon, \@gil_navs, \@gil_rwys, \@gil_patt ],
    'YSDU' => [$a_dub_lat, $a_dub_lon, \@dub_navs, \@dub_rwys, \@dub_patt ]
    );

sub get_locations() { return \%apt_locations; }

my $VNE_c172n = 160;    # KIAS
my $VNO_c172n = 128;    # KIAS
my $VA_c172b  = 97;     # 2300 ponds
my $VFE_c172n = 85;     # KIAS

my $c172n_max_rpm_loss = 125;
my $c172n_max_rpm_diff = 50;

my $c172n_to_roll_min = 55;   # KIAS LIFT NOSE WHEEL - Up elevator
my $c172n_climb_speed = 75; # 70-80 KIAS
my $c172n_land_speed_nf = 65;  # 60-70 (flaps UP)
my $c172n_land_speed = 60;  # 55 - 65 (Flaps DOWN)

my $curr_target = '';

my $head_target = 0;
my $prev_target = 0;
my $requested_hb = 0;
my $begin_hb = 0;
my $bgn_turn_tm = 0;
my $chk_turn_done = 0;
my $last_turn_diff = 0;
my $chk_turn_count = 0;
my $done_turn_done = 0;
my $end_of_turn = 0;       # set flag to check first ETA to target
my $chk_course_time = 0;    # time to check and correct course
my $once_per_leg = 0;
my $chk_time_set = 0;

my $last_wind_info = '';    # metar info at last update

my $mag_deviation = 0; # = difference ($curr_hdg - $curr_mag) at ast update
my $mag_variation = 0; # from /environment/magnetic-variation-deg

# current hashes - at last update
my %m_curr_engine = ();
my %m_curr_klocks = ();
my %m_curr_posit = ();
my %m_curr_env = ();
my %m_curr_comms = ();
my %m_curr_consumables = ();
my %m_curr_gps = ();
my %m_curr_sim = ();
my %m_curr_orientation = ();
my %m_curr_flight = ();
my %m_curr_brakes = ();

# fetch the above global - which should not be referred to directly
sub get_curr_posit() { return \%m_curr_posit; }
sub get_curr_env() { return \%m_curr_env; }
sub get_curr_comms() { return \%m_curr_comms; }
sub get_curr_consumables() { return \%m_curr_consumables; }
sub get_curr_gps() { return \%m_curr_gps; }
sub get_curr_engine() { return \%m_curr_engine; }
sub get_curr_Klocks() { return \%m_curr_klocks; }
sub get_curr_sim() { return \%m_curr_sim; }
sub get_curr_orientation() { return \%m_curr_orientation; }
sub get_curr_flight() { return \%m_curr_flight; }
sub get_curr_brakes() { return \%m_curr_brakes; }

my %route_YGIL = (
    1 => [-31.64176667, 148.61393333], # turn right from 343D to 068D
    2 => [-31.62000000, 148.64025000], # turn right from 068D to 162D
    3 => [-31.74516667, 148.70450000], # turn right from 162D to 252D
    4 => [-31.76133333, 148.66890000]  # turn right from 252D to 343D
    );

my %route_YGIL2 = (
    1 => [-31.73727354, 148.6977026], # -31.7405905 148.7023707 240
    2 => [-31.75996394, 148.6677629], # -31.76322411 148.6653013 331
    3 => [-31.69726764, 148.6318662], # -31.68792475 148.6226809  58
    4 => [-31.67646645, 148.6607911]  # -31.66952521 148.6512852 150
    );

sub get_YGIL_route() { return \%route_YGIL }

#############################################################################
### Flight Controls
my $flt_aileron = "/controls/flight/aileron"; # set_flt_ailerons
my $flt_aileron_trim = "/controls/flight/aileron-trim";
my $flt_elevator = "/controls/flight/elevator";
my $flt_elevator_trim = "/controls/flight/elevator-trim";
my $flt_flaps = "/controls/flight/flaps";
my $flt_rudder = "/controls/flight/rudder";
my $flt_rudder_trim = "/controls/flight/rudder-trim";
#############################################################################
#############################################################################
### Gear Controls
my $gr_brake_left = "/controls/gear/brake-left";    # double
my $gr_brake_right = "/controls/gear/brake-right";
my $gr_brake_park = "/controls/gear/brake-parking";    # int 0=off 1=On

#############################################################################
#############################################################################
my $hdg_bug_stg = "/autopilot/settings/heading-bug-deg";

#############################################################################
my $hdg_off_stg = "/instrumentation/heading-indicator/offset-deg";
my $hdg_ind_stg = "/instrumentation/heading-indicator/indicated-heading-deg"; # this should control autopilot HDG 
my $alt_ind_stg = "/instrumentation/altimeter/indicated-altitude-ft";
my $alt_inhg_stg = "/instrumentation/altimeter/setting-inhg";


# fgfs - class FlightProperties - FlightProperties.cxx .hxx
my $get_V_north = "/velocities/speed-north-fps";
my $get_V_east = "/velocities/speed-east-fps";
my $get_V_down = "/velocities/speed-down-fps";
my $get_uBody = "/velocities/uBody-fps";
my $get_vBody = "velocities/vBody-fps";
my $get_wBody = "/velocities/wBody-fps";
my $get_A_X_pilot = "/accelerations/pilot/x-accel-fps_sec";
my $get_A_Y_pilot = "/accelerations/pilot/y-accel-fps_sec";
my $get_A_Z_pilot = "/accelerations/pilot/z-accel-fps_sec";
# getPosition SGGeod::fromDegFt(get_Longitude_deg(), get_Latitude_deg(), get_Altitude());
# get_Latitude = get_Latitude_deg() * SG_DEGREES_TO_RADIANS;
# get_Longitude = get_Longitude_deg() * SG_DEGREES_TO_RADIANS;
my $get_Altitude = "/position/altitude-ft";
my $get_Altitude_AGL = "/position/altitude-agl-ft";
my $get_Latitude_deg = "/position/latitude-deg";
my $get_Longitude_deg = "/position/longitude-deg";
my $get_Track = "/orientation/track-deg";
# set_Euler_Angles(double phi, double theta, double psi)
my $get_Phi_deg = "/orientation/roll-deg";
my $get_Theta_deg = "/orientation/pitch-deg";
my $get_Psi_deg = "/orientation/heading-deg";
# get_Phi_dot = get_Phi_dot_degps() * SG_DEGREES_TO_RADIANS;
# get_Theta_dot = get_Theta_dot_degps() * SG_DEGREES_TO_RADIANS;
# get_Psi_dot = get_Psi_dot_degps() * SG_DEGREES_TO_RADIANS;
my $get_Alpha = "/orientation/alpha-deg"; # * SG_DEGREES_TO_RADIANS;
my $get_Beta = "/orientation/beta-deg"; # * SG_DEGREES_TO_RADIANS;
my $get_Phi_dot_degps = "/orientation/roll-rate-degps";
my $get_Theta_dot_degps = "/orientation/pitch-rate-degps";
my $get_Psi_dot_degps = "/orientation/yaw-rate-degps";
# get_Total_temperature = 0.0;
# get_Total_pressure = 0.0;
# get_Dynamic_pressure = 0.0;
# ==================
###############################################################
### Velosities ###
my $set_V_calibrated_kts = "/velocities/airspeed-kt";
my $set_Climb_Rate = "/velocities/vertical-speed-fps";
#my $KNOTS_TO_FTS = ($SG_NM_TO_METER * $SG_METER_TO_FEET) / 3600.0;
my $get_V_ground_speed = "/velocities/groundspeed-kt"; # * $KNOTS_TO_FTS;
my $get_V_calibrated_kts = "/velocities/airspeed-kt";
my $get_V_equiv_kts = "/velocities/equivalent-kt";
my $get_Climb_Rate = "/velocities/vertical-speed-fps";
my $get_Runway_altitude_m = "/environment/ground-elevation-m";
# set_Accels_Pilot_Body(double x, double y, double z)
# _root->setDoubleValue("accelerations/pilot/x-accel-fps_sec", x);
# _root->setDoubleValue("accelerations/pilot/y-accel-fps_sec", y);
# _root->setDoubleValue("accelerations/pilot/z-accel-fps_sec", z);
# set_Velocities_Local(double x, double y, double z)
#  _root->setDoubleValue("velocities/speed-north-fps", x);
#  _root->setDoubleValue("velocities/speed-east-fps", y);
#  _root->setDoubleValue("velocities/speed-down-fps", z);
# set_Velocities_Wind_Body(double x, double y, double z)
#  _root->setDoubleValue("velocities/vBody-fps", x);
#  _root->setDoubleValue("velocities/uBody-fps", y);
#  _root->setDoubleValue("velocities/wBody-fps", z);
# set_Euler_Rates(double x, double y, double z)
#  _root->setDoubleValue("orientation/roll-rate-degps", x * SG_RADIANS_TO_DEGREES);
#  _root->setDoubleValue("orientation/pitch-rate-degps", y * SG_RADIANS_TO_DEGREES);
#  _root->setDoubleValue("orientation/yaw-rate-degps", z * SG_RADIANS_TO_DEGREES);
# set_Alpha(double a) _root->setDoubleValue("orientation/alpha-deg", a * SG_RADIANS_TO_DEGREES;
# set_Beta(double b) _root->setDoubleValue("orientation/side-slip-rad", b);
# set_Altitude_AGL(double ft) _root->setDoubleValue("position/altitude-agl-ft", ft);
###############################################################

my $get_P_body = "/orientation/p-body";
my $get_Q_body = "/orientation/q-body";
my $get_R_body = "/orientation/r-body";

sub show_warnings($) {
    my ($val) = @_;
    if (@warnings) {
        prt( "\nGot ".scalar @warnings." WARNINGS...\n" );
        foreach my $itm (@warnings) {
           prt("$itm\n");
        }
        prt("\n");
    } else {
        #prt( "\nNo warnings issued.\n\n" );
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

sub prt2($) {
   my ($tx) = shift;
   prt_log($tx);
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

sub set_decimal1_stg_old($) {
    my $r = shift;
    ${$r} =  int((${$r} + 0.05) * 10) / 10;
}

# set_double1_stg($)
sub set_decimal1_stg($) {
    my $r = shift;
    ${$r} =  int((${$r} + 0.05) * 10) / 10;
    ${$r} = "0.0" if (${$r} == 0);
    ${$r} .= ".0" if !(${$r} =~ /\./);
}
sub set_decimal2_stg($) {
    my $r = shift;
    ${$r} =  int((${$r} + 0.005) * 100) / 100;
    ${$r} = "0.0" if (${$r} == 0);
    ${$r} .= ".0" if !(${$r} =~ /\./);
}
sub set_decimal3_stg($) {
    my $r = shift;
    ${$r} =  int((${$r} + 0.0005) * 1000) / 1000;
    ${$r} = "0.0" if (${$r} == 0);
    ${$r} .= ".0" if !(${$r} =~ /\./);
}

sub set_decimal6_form($) {
    my $r = shift;
    ${$r} = sprintf( "%.6f", ${$r} );
}


sub set_int_stg($) {
    my $r = shift;
    ${$r} =  int(${$r} + 0.5);
}

sub get_dist_stg_nm($) {
    my ($dist) = @_;
    my $nm = $dist * $SG_METER_TO_NM;
    set_decimal1_stg(\$nm);
    $nm .= "nm";
    return $nm;
}

sub normalised_hdg($) {
    my $hdg = shift;
    $hdg += 360 if ($hdg < 0);
    $hdg -= 360 if ($hdg >= 360);
    return $hdg;
}

sub show_distance_heading($$$$) {
    my ($lat1,$lon1,$lat2,$lon2) = @_;
    my ($az1,$az2,$dist);
    fg_geo_inverse_wgs_84 ($lat1,$lon1,$lat2,$lon2,\$az1,\$az2,\$dist);
    $dist = get_dist_stg_nm($dist);
    set_hdg_stg(\$az1);
    prt("Is $dist, on heading $az1\n");
}

sub show_rw_patt($$) {
    my ($key,$rpatts) = @_;
    my $cnt = scalar @{$rpatts};
    prt("Display of $cnt patterns/circuits for $key...\n");
    my ($i,$lat1,$lon1,$lat2,$lon2,$j);
    for ($i = 0; $i < $cnt; $i++) {
        for ($j = 0; $j < 8; $j += 2) {
            $lat1 = ${$rpatts}[$i][$j+0];
            $lon1 = ${$rpatts}[$i][$j+1];
            if ($j == 6) {
                $lat2 = ${$rpatts}[$i][0];
                $lon2 = ${$rpatts}[$i][1];
            } else {
                $lat2 = ${$rpatts}[$i][$j+2];
                $lon2 = ${$rpatts}[$i][$j+3];
            }
            prt("$i:$j: $lat1,$lon1  $lat2,$lon2\n");
            show_distance_heading($lat1,$lon1,$lat2,$lon2);
        }
    }
}

sub set_runway_ends_and_patt($$$$$) {
    my ($rrwys,$off,$key,$rpatts,$set) = @_;
    # set ENDS of runway
    my $rlen = ${$rrwys}[$off][$RW_LEN];
    my $rhdg = ${$rrwys}[$off][$RW_HDG];
    my $clat = ${$rrwys}[$off][$RW_CLAT];
    my $clon = ${$rrwys}[$off][$RW_CLON];
    my $rty1 = ${$rrwys}[$off][$RW_TT1];
    my $rty2 = ${$rrwys}[$off][$RW_TT2];
    my $rwlen2 = ($rlen * $SG_FEET_TO_METER) / 2;
    my ($elat1,$elon1,$eaz1,$elat2,$elon2,$eaz2);
    my $hdgr = $rhdg + 180;
    $hdgr -= 360 if ($hdgr >= 360);
    ${$rrwys}[$off][$RW_REV] = $hdgr;

    fg_geo_direct_wgs_84( $clat, $clon, $rhdg, $rwlen2, \$elat1, \$elon1, \$eaz1 );
    fg_geo_direct_wgs_84( $clat, $clon, $hdgr, $rwlen2, \$elat2, \$elon2, \$eaz2 );
    ${$rrwys}[$off][$RW_LLAT] = $elat1;
    ${$rrwys}[$off][$RW_LLON] = $elon1;
    ${$rrwys}[$off][$RW_RLAT] = $elat2;
    ${$rrwys}[$off][$RW_RLON] = $elon2;
    ${$rrwys}[$off][$RW_DONE] = $off + 1;

    my ($az1,$az2,$dist);
    fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$dist);
    $dist = $dist * $SG_METER_TO_FEET;
    set_int_stg(\$az1);
    set_int_stg(\$az2);
    set_int_stg(\$dist);
    # init: YSDU: 23: -32.2136987804606,148.583432501246 05: -32.2228307960945,148.568856770273 234 5600 54 vs 53.61 5600
    # init: YGIL: 33: -31.7024233216057,148.638492502638 15: -31.6914326394609,148.634315743548 342 4204 162 vs 162 4204
    #prt("init: $key: $rty2: $elat1,$elon1 $az1 $rty1: $elat2,$elon2 $az1 $dist $az2 vs $rhdg $rlen\n");
    prt("init:$set:$off: $key: $rty2:$az1: $elat1,$elon1\n");
    prt("init:$set:$off: $key: $rty1:$az2: $elat2,$elon2\n");

    # We have the RUNWAY ends - now extend out to first turn to crosswind leg, and turn to final
    # but by how MUCH - ok decide from runway end, out to where it is a 3 degree glide from 1000 feet
    $dist = ($stand_patt_alt * $SG_FEET_TO_METER) / tan($stand_glide_degs * $SGD_DEGREES_TO_RADIANS);
    my ($plat11,$plon11,$plat12,$plon12,$plat13,$plon13,$paz1);
    my ($plat21,$plon21,$plat22,$plon22,$plat23,$plon23,$paz2);
    my ($hdg1L,$hdg1R,$crossd);
    fg_geo_direct_wgs_84( $clat, $clon, $rhdg, $rwlen2+$dist, \$plat11, \$plon11, \$paz1 );
    fg_geo_direct_wgs_84( $clat, $clon, $hdgr, $rwlen2+$dist, \$plat21, \$plon21, \$paz2 );
    $hdg1L = normalised_hdg($rhdg - 90);
    $hdg1R = normalised_hdg($rhdg + 90);
    $crossd = $stand_cross_nm * $SG_NM_TO_METER;
    # ON $rhdg to $elat1, $elon1 to ... turn point, go LEFT and to get NEXT points, this end
    fg_geo_direct_wgs_84( $plat11, $plon11, $hdg1L, $crossd, \$plat12, \$plon12, \$paz1 );
    fg_geo_direct_wgs_84( $plat21, $plon21, $hdg1L, $crossd, \$plat13, \$plon13, \$paz1 );

    # from the turn point, go LEFT and RIGHT to get NEXT points, this other end
    fg_geo_direct_wgs_84( $plat21, $plon21, $hdg1R, $crossd, \$plat22, \$plon22, \$paz2 );
    fg_geo_direct_wgs_84( $plat11, $plon11, $hdg1R, $crossd, \$plat23, \$plon23, \$paz2 );

    if ($use_pattern && ($key eq $active_key)) { # 'YGIL'
    # if ($use_pattern && ($key eq 'YGIL')) {
        if ($switch_circuit) {
            # At YGIL, this is a 15 circuit (the prevailing wind! SSE...
            $tl_lat = $plat12;
            $tl_lon = $plon12;
            $bl_lat = $plat13;
            $bl_lon = $plon13;
            $br_lat = $plat21;
            $br_lon = $plon21;
            $tr_lat = $plat11;
            $tr_lon = $plon11;
            $active_runway = '15';
        } else {
            # At YGIL, this is a 33 circuit
            $tl_lat = $plat22; #-31.684063;
            $tl_lon = $plon22; #148.614120;
            $bl_lat = $plat23; #-31.723495;
            $bl_lon = $plon23; #148.633003;
            $br_lat = $plat11; #-31.716778;
            $br_lon = $plon11; #148.666992;
            $tr_lat = $plat21; #-31.672960;
            $tr_lon = $plon21; #148.649139;
            $active_runway = '33';
        }
        prt("Set pattern as the rectangle for $key $active_runway...\n");
        $active_ref_rwys = $rrwys;
        $active_off_rwys = $off;
    }

    if ($dbg_01) {
        # now we have 4 points, either side of the runway
        prt("On $rhdg, at $plat11,$plon11 turn $hdg1L to $plat12,$plon12\n");
        show_distance_heading($plat11,$plon11,$plat12,$plon12);
        # This is the LONG downwind side 12 to 13
        prt("On $hdg1L at $plat12,$plon12, turn $hdgr to $plat13,$plon13\n");
        show_distance_heading($plat12,$plon12,$plat13,$plon13);
        prt("On $hdgr at $plat13,$plon13 turn $hdg1R to $plat21,$plon21\n");
        show_distance_heading($plat13,$plon13,$plat21,$plon21);
        prt("On $hdg1R at $plat21,$plon21 turn $rhdg to $elat1,$elon1\n");
        show_distance_heading($plat21,$plon21,$elat1,$elon2);
        prt("\n");
        #E.G. for YGIL - TO 15
        #On 162, at -31.7523059488988,148.65746239832 turn 72 to -31.7414611993009,148.696497359091
        #Is 2.1nm, on heading  72
        #On 72 at -31.7414611993009,148.696497359091, turn 342 to -31.630701184372,148.654359238954
        #Is 7.0nm, on heading 342
        #On 342 at -31.630701184372,148.654359238954 turn 252 to -31.6415460967825,148.615370603846
        #Is 2.1nm, on heading 252
        #On 252 at -31.6415460967825,148.615370603846 turn 162 to -31.7024233216057,148.638492502638
        #Is 3.8nm, on heading 165

        prt("On $hdgr at $plat21,$plon21 turn $hdg1R to $plat22,$plon22\n");
        show_distance_heading($plat21,$plon21,$plat22,$plon22);
        # This is the LONG downwind side 22 to 23
        prt("On $hdg1R at $plat22,$plon22 turn $rhdg to $plat23,$plon23\n");
        show_distance_heading($plat22,$plon22,$plat23,$plon23);
        prt("On $rhdg at $plat23,$plon23 turn $hdg1L to $plat11,$plon11\n");
        show_distance_heading($plat23,$plon23,$plat11,$plon11);
        prt("On $hdg1L at $plat11,$plon11 turn $hdgr to $elat2,$elon2\n");
        show_distance_heading($plat11,$plon11,$elat2,$elon2);
        prt("\n");
        #E.G. for YGIL, TO 33
        #On 342 at -31.6415460967825,148.615370603846 turn 252 to -31.6523790808638,148.576372922039
        #Is 2.1nm, on heading 252
        #On 252 at -31.6523790808638,148.576372922039 turn 162 to -31.7631387187979,148.618418340898
        #Is 7.0nm, on heading 162
        #On 162 at -31.7631387187979,148.618418340898 turn 72 to -31.7523059488988,148.65746239832
        #Is 2.1nm, on heading  72
        #On 72 at -31.7523059488988,148.65746239832 turn 342 to -31.6914326394609,148.634315743548
        #Is 3.8nm, on heading 342
    }

    @{$rpatts} = ();
    # add notional RIGHT side circuit first
    push(@{$rpatts}, [$plat11,$plon11,$plat12,$plon12,$plat13,$plon13,$plat21,$plon21,$clat,$clon,$rlen,$rhdg]);
    # then notional LEFT size circuit
    push(@{$rpatts}, [$plat21,$plon21,$plat22,$plon22,$plat23,$plon23,$plat11,$plon11,$clat,$clon,$rlen,$hdgr]);

}

sub init_runway_array() {
    my $rl = get_locations();
    my ($key,$off,$cnt,$rrwys,$rpatts,$set);
    $set = 0;
    foreach $key (keys %{$rl}) {
        $set++;
        $rrwys = ${$rl}{$key}[$OL_RWY];
        $rpatts = ${$rl}{$key}[$OL_PAT];
        $cnt = scalar @{$rrwys};
        for ($off = 0; $off < $cnt; $off++) {
            prt("Doing set $set, offset $off of $cnt\n");
            set_runway_ends_and_patt($rrwys,$off,$key,$rpatts,$set);
        }
    }
    if ($dbg_02) {
        foreach $key (keys %{$rl}) {
            $rpatts = ${$rl}{$key}[$OL_PAT];
            show_rw_patt($key,$rpatts);
        }
    }
    # pgm_exit(1,"Temp exit");
}

# ### FG TELENET CREATION and IO ###
# ==================================

sub fgfs_connect($$$) {
	my ($host,$port,$timeout) = @_;
	my $socket;
	STDOUT->autoflush(1);
	prtt("Connect $host, $port, timeout $timeout secs ");
	while ($timeout--) {
		if ($socket = IO::Socket::INET->new(
				Proto => 'tcp',
				PeerAddr => $host,
				PeerPort => $port)) {
			prt(" DONE.\n");
			$socket->autoflush(1);
			sleep 1;
			return $socket;
		}	
		prt(".\n");
		sleep(1);
    	prtt("Again $host, $port, timeout $timeout secs ");
	}
	prt(" FAILED!\n");
	return 0;
}

sub get_exit($) {
    my ($val) = shift;
    pgm_exit($val,"fgfs get FAILED!\n");
}

sub fgfs_send($) {
	print $FGFS_IO shift, "\015\012";
}

sub fgfs_set($$) {
    my ($node,$val) = @_;
	fgfs_send("set $node $val");
    return 1;
}

# DEBUG ONLY STUFF
my @intervals = ();
sub fgfs_get_w_time($$) {
    my ($txt,$rval) = @_;
    my $tb = [gettimeofday];
	fgfs_send("get $txt");
	eof $FGFS_IO and return 0;
	${$rval} = <$FGFS_IO>;
    my $elapsed = tv_interval ( $tb, [gettimeofday]);
    push(@intervals,$elapsed);
	${$rval} =~ s/\015?\012$//;
	${$rval} =~ /^-ERR (.*)/ and (prtw("WARNING: $1\n") and return 0);
	return 1;
}

sub fgfs_get($$) {
    my ($txt,$rval) = @_;
    # return fgfs_get_w_time($txt,$rval) if ($keep_av_time);
	fgfs_send("get $txt");
	eof $FGFS_IO and return 0;
	${$rval} = <$FGFS_IO>;
	${$rval} =~ s/\015?\012$//;
	${$rval} =~ /^-ERR (.*)/ and (prtw("WARNING: $1\n") and return 0);
	return 1;
}

# get Euler angles
sub fgfs_get_roll($) {
    my $ref = shift;
    fgfs_get($get_Phi_deg,$ref) or get_exit(-2); # double = "/orientation/roll-deg";
    return 1;
}
sub fgfs_get_pitch($) {
    my $ref = shift;
    fgfs_get($get_Theta_deg,$ref) or get_exit(-2); # double = "/orientation/pitch-deg";
    return 1;
}
sub fgfs_get_heading($) {
    my $ref = shift;
    fgfs_get($get_Psi_deg,$ref) or get_exit(-2);    # double = "/orientation/heading-deg";
    return 1;
}

sub fgfs_get_orientation() {
    my ($roll,$pitch,$heading);
    fgfs_get_roll(\$roll);
    fgfs_get_pitch(\$pitch);
    fgfs_get_heading(\$heading);
    my $ro = get_curr_orientation();
    ${$ro}{'roll'} = $roll;
    ${$ro}{'pitch'} = $pitch;
    ${$ro}{'heading'} = $heading;
    ${$ro}{'time'} = time();
    return $ro;
}

sub get_curr_roll() {
    my $ro = fgfs_get_orientation();
    my $roll = ${$ro}{'roll'};
    set_decimal2_stg(\$roll);
    return $roll;
}


# convenient combinations of factors, using the above IO
# ======================================================
sub fgfs_get_gps();     # sim GPS values
sub fgfs_get_engines();  # C172p - needs to be tuned for each engine config
sub fgfs_get_K_locks(); # KAP140 Autopilot controls
sub fgfs_get_position();   # geod/graphic position
sub fgfs_get_environ(); # world environment
sub fgfs_get_comms();   # COMMS stack - varies per aircraft
sub fgfs_get_consumables(); # Fuel, etc...

# individual path into the property tree
sub fgfs_get_gps_alt($) {
    my $ref = shift;
    fgfs_get("/instrumentation/gps/indicated-altitude-ft", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_gps_gspd_kts($) {
    my $ref = shift;
    fgfs_get("/instrumentation/gps/indicated-ground-speed-kt", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_gps_lat($) {
    my $ref = shift;
    fgfs_get("/instrumentation/gps/indicated-latitude-deg", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_gps_lon($) {
    my $ref = shift;
    fgfs_get("/instrumentation/gps/indicated-longitude-deg", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_gps_track($) {
    my $ref = shift;
    fgfs_get("/instrumentation/gps/indicated-track-magnetic-deg", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_gps_track_true($) {
    my $ref = shift;
    fgfs_get("/instrumentation/gps/indicated-track-true-deg", $ref) or get_exit(-2); # double
    return 1;
}

sub fgfs_get_gps() {
    my ($lat,$lon,$alt,$gspd,$trkm,$trkt);
    fgfs_get_gps_alt(\$alt);
    fgfs_get_gps_gspd_kts(\$gspd);
    fgfs_get_gps_lat(\$lat);
    fgfs_get_gps_lon(\$lon);
    fgfs_get_gps_track(\$trkm);
    fgfs_get_gps_track_true(\$trkt);
    my $rc = get_curr_gps();
    ${$rc}{'time'} = time();
    ${$rc}{'lon'} = $lon;
    ${$rc}{'lat'} = $lat;
    ${$rc}{'alt'} = $alt;
    ${$rc}{'hdg'} = $trkt;
    ${$rc}{'mag'} = $trkm;
    #${$rc}{'bug'} = $curr_hb;
    #${$rc}{'agl'} = $curr_agl;
    ${$rc}{'spd'} = $gspd;  # KT
    return $rc;
}

sub fgfs_get_coord($$) {
	my ($rlon,$rlat) = @_;
	fgfs_get("/position/longitude-deg", $rlon) or get_exit(-2);
	fgfs_get("/position/latitude-deg", $rlat) or get_exit(-2);
	return 1;
}

sub fgfs_get_alt($) {
	my $ref_alt = shift;
	fgfs_get("/position/altitude-ft", $ref_alt) or get_exit(-2);
	return 1;
}

sub fgfs_get_hdg_true($) {
	my $ref_hdg = shift;
	fgfs_get("/orientation/heading-deg", $ref_hdg) or get_exit(-2);
	return 1;
}
sub fgfs_get_hdg_mag($) {
	my $ref_hdg = shift;
	fgfs_get("/orientation/heading-magnetic-deg", $ref_hdg) or get_exit(-2);
	return 1;
}


# aero=[SenecaII-jsbsim]
sub set_SenecaII() {
	if ($hdg_bug_stg ne "/instrumentation/kcs55/ki525/selected-heading-deg") {
        $hdg_bug_stg = "/instrumentation/kcs55/ki525/selected-heading-deg";
        prtt("Set hdg bug stg = [$hdg_bug_stg]\n");
    }
    $engine_count = 2;
}

# DEFAULT c172p $hdg_bug_stg = "/autopilot/settings/heading-bug-deg";
sub fgfs_get_hdg_bug($) {
	my $ref_hb = shift;
	fgfs_get($hdg_bug_stg, $ref_hb) or get_exit(-2);
	return 1;
}

sub fgfs_set_hdg_bug($) {
	my $val = shift;
	fgfs_set($hdg_bug_stg, $val) or get_exit(-2);
	return 1;
}

sub fgfs_get_alt_ind($) {
	my $ref_off = shift;
	fgfs_get($alt_ind_stg, $ref_off) or get_exit(-2); # double
	return 1;
}

sub fgfs_get_alt_inhg($) {
	my $ref_off = shift;
	fgfs_get($alt_inhg_stg, $ref_off) or get_exit(-2); # double
	return 1;
}

# "/instrumentation/heading-indicator/offset-deg"
sub fgfs_get_hdg_off($) {
	my $ref_off = shift;
	fgfs_get($hdg_off_stg, $ref_off) or get_exit(-2);
	return 1;
}


sub fgfs_set_hdg_off($) {
	my $val = shift;
	fgfs_set($hdg_off_stg, $val) or get_exit(-2);
	return 1;
}

sub fgfs_get_hdg_ind($) {
	my $ref_off = shift;
	fgfs_get($hdg_ind_stg, $ref_off) or get_exit(-2);
	return 1;
}

sub fgfs_get_agl($) {
	my $ref_alt = shift;
	fgfs_get("/position/altitude-agl-ft", $ref_alt) or get_exit(-2);
	return 1;
}

# "/velocities/airspeed-kt";
sub fgfs_get_aspd_kts($) {
    my $ref = shift;
	fgfs_get($get_V_calibrated_kts, $ref) or get_exit(-2);
	return 1;
}

# "/velocities/groundspeed-kt"; # * $KNOTS_TO_FTS;
sub fgfs_get_gspd_kts($) {
    my $ref = shift;
	fgfs_get($get_V_ground_speed, $ref) or get_exit(-2);
	return 1;
}

####################################################################
### Lights
my $ctl_nav_lights_prop = "/controls/lighting/nav-lights";  # bool
my $ctl_beacon_prop = "/controls/lighting/beacon";  # bool
my $ctl_strobe_prop = "/controls/lighting/strobe";  # bool
my %ctrl_lighting = ();
sub fgfs_get_ctrl_lighting() {
    return \%ctrl_lighting;
}
sub fgfs_get_nav_light($) {
    my $ref = shift;
    fgfs_get($ctl_nav_lights_prop, $ref) or get_exit(-2);  # double
    return 1;
}
sub fgfs_set_nav_light($) {
    my $val = shift;
    fgfs_set($ctl_nav_lights_prop, $val) or get_exit(-2);  # double
    return 1;
}

sub fgfs_get_beacon($) {
    my $ref = shift;
    fgfs_get($ctl_beacon_prop, $ref) or get_exit(-2);  # double
    return 1;
}
sub fgfs_set_beacon($) {
    my $val = shift;
    fgfs_set($ctl_beacon_prop, $val) or get_exit(-2);  # double
    return 1;
}
sub fgfs_get_strobe($) {
    my $ref = shift;
    fgfs_get($ctl_strobe_prop, $ref) or get_exit(-2);  # double
    return 1;
}
sub fgfs_set_strobe($) {
    my $val = shift;
    fgfs_set($ctl_strobe_prop, $val) or get_exit(-2);  # double
    return 1;
}

sub fgfs_get_lighting() {
    my ($nl,$bk,$sb);
    fgfs_get_nav_light(\$nl);
    fgfs_get_beacon(\$bk);
    fgfs_get_strobe(\$sb);
    my $rl = fgfs_get_ctrl_lighting();
    ${$rl}{'time'} = time();
    ${$rl}{'navlight'} = $nl;
    ${$rl}{'beacon'} = $bk;
    ${$rl}{'strobe'} = $sb;
    return $rl;
}

####################################################################
my $eng_running_prop = "/engines/engine/running";
my $eng_rpm_prop = "/engines/engine/rpm";
my $eng_mag_prop = "/engines/engine/magnetos";
my $eng_mix_prop = "/engines/engine/mixture";

my $ctl_eng_mag_prop = "/controls/engines/engine/magnetos";  # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
my $ctl_eng_mix_prop = "/controls/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich


# is the engine running?
sub fgfs_get_eng_running($) {
    my $ref = shift;
    fgfs_get($eng_running_prop, $ref) or get_exit(-2); # bool true/false
    #prt("$eng_running_prop = ${$ref}\n");
    return 1;
}
sub fgfs_get_eng_rpm($) {
    my $ref = shift;
    fgfs_get($eng_rpm_prop, $ref) or get_exit(-2);  # double
    #prt("$eng_rpm_prop = ${$ref}\n");
    return 1;
}

#  int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
sub fgfs_get_eng_mag($) {
    my $ref = shift;
    ###fgfs_get($eng_mag_prop, $ref) or get_exit(-2);  # double
    fgfs_get($ctl_eng_mag_prop, $ref) or get_exit(-2);  # double
    return 1;
}
sub fgfs_set_eng_mag($) {
    my $val = shift;
    fgfs_set($ctl_eng_mag_prop, $val) or get_exit(-2);  # double
    return 1;
}

# $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich
sub fgfs_get_eng_mix($) {
    my $ref = shift;
    ###fgfs_get($eng_mix_prop, $ref) or get_exit(-2);  # double
    fgfs_get($ctl_eng_mix_prop, $ref) or get_exit(-2);  # double
    return 1;
}
sub fgfs_set_eng_mix($) {
    my $val = shift;
    ###fgfs_get($eng_mix_prop, $ref) or get_exit(-2);  # double
    fgfs_set($ctl_eng_mix_prop, $val) or get_exit(-2);  # double
    return 1;
}

my $eng_throttle_prop = "/controls/engines/engine/throttle";

sub fgfs_get_eng_throttle($) {  # range 0 to 1 (double)
    my $ref = shift;
    fgfs_get($eng_throttle_prop, $ref) or get_exit(-2);
    #prt("$eng_throttle_prop = ${$ref}\n");
    return 1;
}
sub fgfs_set_eng_throttle($) {  # range 0 to 1 (double)
    my $val = shift;
    fgfs_set($eng_throttle_prop, $val) or get_exit(-2);
    return 1;
}

sub fgfs_get_eng_running2($) {
    my $ref = shift;
    fgfs_get("/engines/engine[1]/running", $ref) or get_exit(-2); # bool true/false
    return 1;
}
sub fgfs_get_eng_rpm2($) {
    my $ref = shift;
    fgfs_get("/engines/engine[1]/rpm", $ref) or get_exit(-2);  # double
    return 1;
}
sub fgfs_get_eng_throttle2($) {  # range 0 to 1
    my $ref = shift;
    fgfs_get("/controls/engines/engine[1]/throttle", $ref) or get_exit(-2);
    return 1;
}

my $ind_alt_ft = 0; # YGIL = 881.7 feet
my $set_in_hg = 0;  # 29.92 STP inches of mercury
my $ind_off_degs = 0;   # -52.8.. what is this?
my $altimeter_msg = '';
my $alt_msg_chg = 0;
my $ind_hdg_degs = 0;

# this is changing fast in a TURN
sub update_hdg_ind() {
    fgfs_get_hdg_ind(\$ind_hdg_degs);
}

# sub fgfs_get_altimeter()
sub get_altimeter_stg() {
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
    set_decimal1_stg(\$hg);

    my $msg = "QNH $hg, IndFt $ai, ";
    if ($altimeter_msg ne $msg) {
        $altimeter_msg = $msg;
        $alt_msg_chg++;
    }
}

sub fgfs_get_engines() {
    my $re = get_curr_engine();
    my ($running,$rpm,$throt,$tmp,$mag,$mix);
    fgfs_get_eng_running(\$running);
    fgfs_get_eng_rpm(\$rpm);
    fgfs_get_eng_throttle(\$throt);
    fgfs_get_eng_mag(\$mag);    # # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    # $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich
    fgfs_get_eng_mix(\$mix); # double 1 to 0

    if (($throt =~ /^\w+$/) && (($throt eq 'true')||($throt eq 'false'))) {
        $tmp = $running;
        $running = $throt;
        $throt = $tmp;
    }
    ${$re}{'running'} = $running;
    ${$re}{'rpm'} = $rpm;
    ${$re}{'throttle'} = $throt;
    ${$re}{'magn'} = $mag;   # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    ${$re}{'mix'} = $mix;

    #prt("Set 'running' to [$running]\n");
    #prt("Set 'rpm' to [$rpm]\n");
    #prt("Set 'throttle' to [$throt]\n");
    ${$re}{'time'} = time();
    if ($engine_count == 2) {
        fgfs_get_eng_running2(\$running);
        fgfs_get_eng_rpm2(\$rpm);
        fgfs_get_eng_throttle2(\$throt);
        ${$re}{'running2'} = $running;
        ${$re}{'rpm2'} = $rpm;
        ${$re}{'throttle2'} = $throt;
    }
    return $re;
}



#############################################################################
### Flight Controls
sub get_flt_ailerons($) {
    my $ref = shift;
    fgfs_get($flt_aileron, $ref) or get_exit(-2); # double
    return 1;
}
sub set_flt_ailerons($) {
    my $val = shift;
    fgfs_set($flt_aileron, $val) or get_exit(-2); # double
    return 1;
}
sub get_flt_ailerons_trim($) {
    my $ref = shift;
    fgfs_get($flt_aileron_trim, $ref) or get_exit(-2); # double
    return 1;
}
sub set_flt_ailerons_trim($) {
    my $val = shift;
    fgfs_set($flt_aileron_trim, $val) or get_exit(-2); # double
    return 1;
}
sub get_flt_elevator($) {
    my $ref = shift;
    fgfs_get($flt_elevator, $ref) or get_exit(-2); # double
    return 1;
}
sub set_flt_elevator($) {
    my $val = shift;
    fgfs_set($flt_elevator, $val) or get_exit(-2); # double
    return 1;
}
sub get_flt_elevator_trim($) {
    my $ref = shift;
    fgfs_get($flt_elevator_trim, $ref) or get_exit(-2); # double
    return 1;
}
sub set_flt_elevator_trim($) {
    my $val = shift;
    fgfs_set($flt_elevator_trim, $val) or get_exit(-2); # double
    return 1;
}
sub get_flt_flaps($) {
    my $ref = shift;
    fgfs_get($flt_flaps, $ref) or get_exit(-2); # double
    return 1;
}
sub set_flt_flaps($) {
    my $val = shift;
    fgfs_set($flt_flaps, $val) or get_exit(-2); # double
    return 1;
}
# "/controls/flight/rudder";
sub get_flt_rudder($) {
    my $ref = shift;
    fgfs_get($flt_rudder, $ref) or get_exit(-2); # double
    return 1;
}
sub set_flt_rudder($) {
    my $val = shift;
    fgfs_set($flt_rudder, $val) or get_exit(-2); # double
    return 1;
}
# "/controls/flight/rudder-trim";
sub get_flt_rudder_trim($) {
    my $ref = shift;
    fgfs_get($flt_rudder_trim, $ref) or get_exit(-2); # double
    return 1;
}
sub set_flt_rudder_trim($) {
    my $val = shift;
    fgfs_set($flt_rudder_trim, $val) or get_exit(-2); # double
    return 1;
}

sub fgfs_get_flight() {
    my ($ai,$ait,$el,$elt,$flp,$rud,$rudt);
    get_flt_ailerons(\$ai);
    get_flt_ailerons_trim(\$ait);
    get_flt_elevator(\$el);
    get_flt_elevator_trim(\$elt);
    get_flt_rudder(\$rud);
    get_flt_rudder_trim(\$rudt);
    get_flt_flaps(\$flp);
    
    my $rf = get_curr_flight();
    ${$rf}{'time'} = time();
    ${$rf}{'ai'}   = $ai;
    ${$rf}{'ait'}  = $ait;
    ${$rf}{'el'}   = $el;
    ${$rf}{'elt'}  = $elt;
    ${$rf}{'rud'}  = $rud;
    ${$rf}{'rudt'} = $rudt;
    ${$rf}{'flap'} = $flp;
    
    return $rf;
}

sub fgfs_set_flight_zero() {
    set_flt_ailerons(0.0);
    set_flt_ailerons_trim(0.0);
    set_flt_elevator(0.0);
    set_flt_elevator_trim(0.0);
    set_flt_rudder(0.0);
    set_flt_rudder_trim(0.0);
    set_flt_flaps(0.0);
}

#############################################################################
#############################################################################
### Gear (Break) Controls
# $gr_brake_left = "/controls/gear/brake-left";    # double
sub get_brake_left($) {
    my $ref = shift;
    fgfs_get($gr_brake_left, $ref) or get_exit(-2); # double
    return 1;
}
sub set_brake_left($) {
    my $val = shift;
    fgfs_get($gr_brake_left, $val) or get_exit(-2); # double
    return 1;
}
# $gr_brake_right = "/controls/gear/brake-right";
sub get_brake_right($) {
    my $ref = shift;
    fgfs_get($gr_brake_right, $ref) or get_exit(-2); # double
    return 1;
}
sub set_brake_right($) {
    my $val = shift;
    fgfs_get($gr_brake_right, $val) or get_exit(-2); # double
    return 1;
}

# $gr_brake_park = "/controls/gear/brake-parking";    # int 0=off 1=On
sub get_brake_park($) {
    my $ref = shift;
    fgfs_get($gr_brake_park, $ref) or get_exit(-2); # double
    return 1;
}
sub set_brake_park($) {
    my $val = shift;
    fgfs_set($gr_brake_park, $val) or get_exit(-2); # int 0=off, 1=on
    return 1;
}

sub fgfs_get_brakes() {
    my ($bl,$br,$bk);
    get_brake_left(\$bl);
    get_brake_right(\$br);
    get_brake_park(\$bk);   # # $gr_brake_park = "/controls/gear/brake-parking";    # int 0=off 1=On
    my $rf = get_curr_brakes();
    ${$rf}{'time'} = time();
    ${$rf}{'bl'}   = $bl;
    ${$rf}{'br'}   = $br;
    ${$rf}{'bk'}   = $bk;
    return $rf;
}

sub get_curr_brake_stg() {
    my $rf = fgfs_get_brakes();
    my ($bl,$br,$bk,$pk);
    $bl = ${$rf}{'bl'};
    $br = ${$rf}{'br'};
    $bk = ${$rf}{'bk'};

    $bk = 0 if (length($bk) == 0);
    $pk = 'off';
    $pk = 'on' if ($bk > 0);
    
    set_decimal1_stg(\$bl);
    set_decimal1_stg(\$br);
    return "L=$bl R=$br P=$pk";
}

#############################################################################


sub fgfs_get_K_ah($) {
    my $ref = shift;
    fgfs_get("/autopilot/KAP140/locks/alt-hold", $ref) or get_exit(-2); # = true/false
    return 1;
}
sub fgfs_get_K_pa($) {
    my $ref = shift;
    fgfs_get("/autopilot/KAP140/locks/pitch-axis", $ref) or get_exit(-2); # = true/false
    return 1;
}
sub fgfs_get_K_pm($) {
    my $ref = shift;
    fgfs_get("/autopilot/KAP140/locks/pitch-mode", $ref) or get_exit(-2); # = 1/0
    return 1;
}
sub fgfs_get_K_ra($) {
    my $ref = shift;
    fgfs_get("/autopilot/KAP140/locks/roll-axis", $ref) or get_exit(-2); # = true/false
    return 1;
}
sub fgfs_get_K_rm($) {
    my $ref = shift;
    fgfs_get("/autopilot/KAP140/locks/roll-mode", $ref) or get_exit(-2); # = 1/0
    return 1;
}
sub fgfs_get_K_hh($) {
    my $ref = shift;
    fgfs_get("/autopilot/KAP140/locks/hdg-hold", $ref) or get_exit(-2); # = true/false
    return 1;
}

sub fgfs_get_K_locks() {
    my ($ah,$pa,$pm,$ra,$rm,$hh);
    fgfs_get_K_ah(\$ah); # alt-hold   bool
    fgfs_get_K_pa(\$pa); # pitch-axis bool
    fgfs_get_K_pm(\$pm);
    fgfs_get_K_ra(\$ra); # roll-axis  bool
    fgfs_get_K_rm(\$rm);
    fgfs_get_K_hh(\$hh); # hdg-hold   bool
    my $rk = get_curr_Klocks();
    ${$rk}{'time'} = time();
    ${$rk}{'ah'} = $ah;
    ${$rk}{'pa'} = $pa;
    ${$rk}{'pm'} = $pm;
    ${$rk}{'ra'} = $ra;
    ${$rk}{'rm'} = $rm;
    ${$rk}{'hh'} = $hh;
    return $rk;
}

# get roll,pitch,heading
sub get_rph_stg2($$$) {
    my ($roll,$pitch,$heading) = @_;
    set_decimal2_stg(\$roll);
    set_decimal2_stg(\$pitch);
    set_decimal2_stg(\$heading);
    return "r${roll}/p${pitch}/h${heading}";
}


sub get_rph_stg() {
    my $ro = fgfs_get_orientation();    # get ORIENTATION
    return get_rph_stg2(${$ro}{'roll'},${$ro}{'pitch'},${$ro}{'heading'});
}

sub fgfs_get_position() {
    #my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag);
    my ($curr_lat,$curr_lon,$curr_alt,$curr_hdg,$curr_mag,$curr_hb,$curr_agl);
    my ($curr_aspd,$curr_gspd);
    my ($diff,$diff2);
    fgfs_get_coord(\$curr_lon,\$curr_lat);
    fgfs_get_alt(\$curr_alt);
    fgfs_get_hdg_true(\$curr_hdg);  # /orientation/heading-deg
    fgfs_get_hdg_mag(\$curr_mag);   # /orientation/heading-magnetic-deg
    fgfs_get_agl(\$curr_agl);
    fgfs_get_hdg_bug(\$curr_hb);
    fgfs_get_aspd_kts(\$curr_aspd);
    fgfs_get_gspd_kts(\$curr_gspd);
    my $rc = get_curr_posit();
    my $gps = get_curr_gps();
    my $tm = time();
    ${$rc}{'gps-update'} = 0;
    if (defined ${$rc}{'time'} && defined ${$gps}{'time'}) {
        my $ptm = ${$rc}{'time'};
        my $gtm = ${$gps}{'time'};
        if ($ptm > $gtm) {
            $diff = $ptm - $gtm; # get seconds different
            if ($diff > $gps_next_time) {
                prtt("Adding a GPS update... Next in ".int($gps_next_time / 60)." mins...\n");
                $gps = fgfs_get_gps(); # get the GPS position of things, check and compare...
                ${$rc}{'gps-update'} = 1; # maybe in display, show difference, if ANY...
            }
        }
    } elsif (defined ${$rc}{'time'}) {
        prtt("Initial GPS update... next in ".int($gps_next_time / 60)." mins\n");
        $gps = fgfs_get_gps(); # get the GPS position of things, check and compare...
        ${$rc}{'gps-update'} = 1; # maybe in display, show difference, if ANY...
    }

    ${$rc}{'time'} = $tm;
    ${$rc}{'lon'} = $curr_lon;
    ${$rc}{'lat'} = $curr_lat;
    ${$rc}{'alt'} = $curr_alt;
    ${$rc}{'hdg'} = $curr_hdg;
    ${$rc}{'mag'} = $curr_mag;  # /orientation/heading-magnetic-deg
    ${$rc}{'bug'} = $curr_hb;
    ${$rc}{'agl'} = $curr_agl;
    ${$rc}{'aspd'} = $curr_aspd; # Knots
    ${$rc}{'gspd'} = $curr_gspd; # Knots
    $mag_deviation = ($curr_hdg - $curr_mag);
    if ($chk_turn_done) {
        $chk_turn_count++;
        my $ro = fgfs_get_orientation();    # get ORIENTATION
        my ($roll,$pitch,$heading,$rph);
        my ($val1,$val2,$val3,$val4,$val5,$val6,$val7,$trend);

        $roll = ${$ro}{'roll'};
        $pitch = ${$ro}{'pitch'};
        $heading = ${$ro}{'heading'};
        $rph = get_rph_stg2(${$ro}{'roll'},${$ro}{'pitch'},${$ro}{'heading'});

        $diff = abs($requested_hb - $curr_mag); # is this correct?????
        #$diff = abs($requested_hb - $curr_hdg); # change
        $diff = 360 - $diff if ($diff > 180);
        my $trd = '=';
        if ($diff < $last_turn_diff) {
            $trd = '-';
        } elsif ($diff > $last_turn_diff) {
            $trd = '+';
        }
        $val1 = $diff;
        $val2 = $last_turn_diff;
        $val3 = $requested_hb;
        $val4 = $curr_mag;
        $val5 = $curr_hdg;
        $val6 = $ind_off_degs;
        update_hdg_ind(); # this is changing fast in a TURN
        # get difference between requested_hb, and as indicated
        $diff2 = abs($requested_hb - $ind_hdg_degs);
        $diff2 = 360 - $diff2 if ($diff2 > 180);

        $val7 = $ind_hdg_degs;

        set_decimal1_stg(\$val1) if (length($val1));
        set_decimal1_stg(\$val2) if (length($val2));
        set_decimal1_stg(\$val3) if (length($val3));
        set_decimal1_stg(\$val4) if (length($val4));
        #set_decimal1_stg(\$val5) if (length($val5));
        set_hdg_stg(\$val5) if (length($val5));
        set_decimal1_stg(\$val6) if (length($val6));
        ###set_decimal1_stg(\$val7) if (length($val7));
        set_hdg_stg(\$val7) if (length($val7));

        if (($diff <= $min_turn_diff)||($trd ne '-')||($diff2 <= $min_turn_diff2)) {
            my $ctm = $tm - $bgn_turn_tm;
            my $angle = int(abs($requested_hb - $begin_hb));
            my $mag = int($curr_mag + 0.5);
            my $dps = '';
            if ($ctm > 0) {
                $dps = (int((($angle / $ctm) + 0.05) * 10) / 10).'DPS';
            }
            my $tmp = int($requested_hb + 0.5);
            #############################################################################
            # why assume turn completed -
            # requested heading bug is within a few degrees of the curr indicated heading
            my $res = "res: ";
            $res .= "1<$min_turn_diff2 " if ($diff2 <= $min_turn_diff2);
            $res .= "2<$min_turn_diff " if ($diff <= $min_turn_diff);
            $res .= '3trd=$trd ' if ($trd ne '-');
            #############################################################################

            ###############################################
            $chk_turn_done = 0;
            $done_turn_done = 1;    # set done turn done message
            $end_of_turn = 1;       # set flag to check first ETA to target
            ###############################################
            my $ct = time();
            my $rch = $ref_circuit_hash;    # needed for in-circuit mode
            ${$rch}{'last_time'} = $ct;
            ${$rch}{'begin_time'} = $ct;
            # 20150703: remove roll, pitch, heading = $rph 
            # and remove another display of hdg/mag = c $val4/$val5 
            prtt("Completed TURN $res to $val3, $angle degs ${val7}i/${tmp}r ${mag}m/${val5}t in $ctm secs $dps d=$val1$trd\n\n");
        } else {
            prtt("Awaiting TC to $val3, $val7, c $val4/$val5 d=$val1$trd, p=$val2 $min_turn_diff $rph\n");
            $last_turn_diff = $diff;
        }
    }
    return $rc;
}


# =====================
sub fgfs_get_wind_speed($) {
    my ($ref) = @_;
    #fgfs_get("/environment/wind-speed-kt", $ref) or get_exit(-2); # double
    fgfs_get("/environment/metar/base-wind-speed-kt", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_wind_heading($) {
    my ($ref) = @_;
    #fgfs_get("/environment/wind-from-heading-deg", $ref) or get_exit(-2); # double
    #fgfs_get("/environment/metar/base-wind-range-from", $ref) or get_exit(-2); # double
    fgfs_get("/environment/metar/base-wind-dir-deg", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_wind_east($) {
    my ($ref) = @_;
    #fgfs_get("/environment/wind-from-east-fps", $ref) or get_exit(-2); # double
    fgfs_get("/environment/metar/base-wind-from-east-fps", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_wind_north($) {
    my ($ref) = @_;
    #fgfs_get("/environment/wind-from-north-fps", $ref) or get_exit(-2); # double
    fgfs_get("/environment/metar/base-wind-from-north-fps", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_metar($) {
    my ($ref) = @_;
    fgfs_get("/environment/metar/data", $ref) or get_exit(-2); # double
    return 1;
}

sub fgfs_get_mag_var($) {
    my $ref = shift;
    fgfs_get("/environment/magnetic-variation-deg", $ref) or get_exit(-2); # double
    return 1;
}

# my $YSDU_metar = "2011/07/22 14:00 YSDU 221400Z AUTO 15010KT 9999 // NCD 06/04 Q1020";
my ($g_wind_dir, $g_wind_speed,$g_qnh_bars,$g_qnh_inhg);
sub set_global_metar($) {
    my $met = shift;    # $metar string from FG
    my @arr = split(/\s+/,$met);
    my $cnt = scalar @arr;
    my ($itm,$dir,$spd,$bars,$chg,$inhg);
    $chg = 0;
    $inhg = 0;
    foreach $itm (@arr) {
        if ($itm =~ /^(\d{3})(\d{2})KT/) {
            $dir = $1;
            $spd = $2;
            if (!defined $g_wind_dir) {
                $g_wind_dir = $dir;
                $chg++;
            } elsif ($g_wind_dir != $dir) {
                $g_wind_dir = $dir;
                $chg++;
            }
            if (!defined $g_wind_speed) {
                $g_wind_speed = $spd;
                $chg++;
            } elsif ($g_wind_speed != $spd) {
                $g_wind_speed = $spd;
                $chg++;
            }
        } elsif ($itm =~ /^Q(\d{4})$/) {
            $bars = $1;
            $inhg = $bars * 0.000295299830714 * 100;
            if (!defined $g_qnh_bars) {
                $g_qnh_bars = $bars / 100;
                $g_qnh_inhg = $inhg;
                $chg++;
            } elsif ($g_qnh_bars != $bars) {
                $g_qnh_bars = $bars / 100;
                $g_qnh_inhg = $inhg;
                $chg++;
            }
        }
    }
    if ($chg == 3) {
        set_decimal2_stg(\$inhg);
        prtt("Global Weather $g_wind_dir/$g_wind_speed QNH $g_qnh_bars $inhg\n");
    }
}


sub fgfs_get_environ() {
    my ($wspd,$whdg,$weast,$wnor,$met,$mv);
    fgfs_get_wind_speed(\$wspd);
    fgfs_get_wind_heading(\$whdg);
    fgfs_get_wind_east(\$weast);
    fgfs_get_wind_north(\$wnor);
    fgfs_get_metar(\$met);  # "/environment/metar/data"
    fgfs_get_mag_var(\$mv);
    my $renv = get_curr_env();
    ${$renv}{'time'} = time();
    ${$renv}{'speed-kt'} = $wspd;
    ${$renv}{'heading-deg'} = $whdg;
    ${$renv}{'east-fps'} = $weast;
    ${$renv}{'north-fps'} = $wnor;
    ${$renv}{'metar'} = $met;   # store metar
    ${$renv}{'mag-variation'} = $mv;
    $mag_variation = $mv;
    set_global_metar($met);
    return $renv;
}

sub fgfs_get_comm1_active($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/comm/frequencies/selected-mhz", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_comm1_stdby($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/comm/frequencies/standby-mhz", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_comm1($$) {
    my ($rca,$rcs) = @_;
    fgfs_get_comm1_active($rca);
    fgfs_get_comm1_stdby($rcs);
}

sub fgfs_get_comm2_active($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/comm[1]/frequencies/selected-mhz", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_comm2_stdby($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/comm[1]/frequencies/standby-mhz", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_comm2($$) {
    my ($rca,$rcs) = @_;
    fgfs_get_comm2_active($rca);
    fgfs_get_comm2_stdby($rcs);
}

# NAV1 Display
sub fgfs_get_nav1_radial($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/nav/radials/selected-deg", $ref) or get_exit(-2); # double
    return 1;
}

sub fgfs_get_nav1_active($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/nav/frequencies/selected-mhz", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_nav1_stdby($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/nav/frequencies/standby-mhz", $ref) or get_exit(-2); # double
    return 1;
}

sub fgfs_get_nav1($$) {
    my ($rna,$rns) = @_;
    fgfs_get_nav1_active($rna);
    fgfs_get_nav1_stdby($rns);
}

sub fgfs_get_nav2_active($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/nav[1]/frequencies/selected-mhz", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_nav2_stdby($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/nav[1]/frequencies/standby-mhz", $ref) or get_exit(-2); # double
    return 1;
}

sub fgfs_get_nav2($$) {
    my ($rna,$rns) = @_;
    fgfs_get_nav2_active($rna);
    fgfs_get_nav2_stdby($rns);
}

sub fgfs_get_adf_active($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/adf/frequencies/selected-khz", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_adf_stdby($) {
    my ($ref) = @_;
    fgfs_get("/instrumentation/adf/frequencies/standby-khz", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_adf($$) {
    my ($radf,$radfs) = @_;
    fgfs_get_adf_active($radf);
    fgfs_get_adf_stdby($radfs);
}

sub fgfs_get_comms() {
    my ($c1a,$c1s);
    my ($n1a,$n1s);
    my ($c2a,$c2s);
    my ($n2a,$n2s);
    my ($adf,$adfs);
    fgfs_get_adf(\$adf,\$adfs);
    fgfs_get_comm1(\$c1a,\$c1s);
    fgfs_get_nav1(\$n1a,\$n1s);
    fgfs_get_comm2(\$c2a,\$c2s);
    fgfs_get_nav2(\$n2a,\$n2s);
    my $rc = get_curr_comms();
    ${$rc}{'time'} = time();
    ${$rc}{'adf-act'} = $adf;
    ${$rc}{'adf-sby'} = $adfs;
    ${$rc}{'comm1-act'} = $c1a;
    ${$rc}{'comm1-sby'} = $c1s;
    ${$rc}{'nav1-act'}  = $n1a;
    ${$rc}{'nav1-sby'}  = $n1s;
    ${$rc}{'comm2-act'} = $c2a;
    ${$rc}{'comm2-sby'} = $c2s;
    ${$rc}{'nav2-act'}  = $n2a;
    ${$rc}{'nav2-sby'}  = $n2s;
    return $rc;
}

sub fgfs_get_fuel1_imp($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank/level-gal_imp", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_fuel1_us($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank/level-gal_us", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_fuel2_imp($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[1]/level-gal_imp", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_fuel2_us($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[1]/level-gal_us", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_fuel_lbs($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/total-fuel-lbs", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_fuel_kgs($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/total-fuel-kg", $ref) or get_exit(-2); # double
    return 1;
}

sub fgfs_get_consumables() {
    my ($t1gi,$t1gus,$t2gi,$t2gus);
    my ($tlbs,$tkgs);
    fgfs_get_fuel1_imp(\$t1gi);
    fgfs_get_fuel1_us(\$t1gus);
    fgfs_get_fuel2_imp(\$t2gi);
    fgfs_get_fuel2_us(\$t2gus);
    fgfs_get_fuel_lbs(\$tlbs);
    fgfs_get_fuel_kgs(\$tkgs);
    my $rc = get_curr_consumables();
    ${$rc}{'time'} = time();
    ${$rc}{'tank1-imp'} = $t1gi;
    ${$rc}{'tank1-us'} = $t1gus;
    ${$rc}{'tank2-imp'} = $t2gi;
    ${$rc}{'tank2-us'} = $t2gus;
    ${$rc}{'total-imp'} = ($t1gi + $t2gi);
    ${$rc}{'total-us'} = ($t1gus + $t2gus);
    ${$rc}{'total-lbs'} = $tlbs;
    ${$rc}{'total-kgs'} = $tkgs;
    return $rc;
}

sub fgfs_get_aero($) {
    my $ref = shift;    # \$aero
    fgfs_get("/sim/aero", $ref) or get_exit(-2); # string
    return 1;
}
sub fgfs_get_fdm($) {
    my $ref = shift;    # \$aero
    fgfs_get("/sim/flight-model", $ref) or get_exit(-2); # string
    return 1;
}
sub fgfs_get_root($) {
    my $ref = shift;    # \$aero
    fgfs_get("/sim/fg-root", $ref) or get_exit(-2); # string
    return 1;
}
sub fgfs_get_desc($) {
    my $ref = shift;    # \$aero
    fgfs_get("/sim/decription", $ref) or get_exit(-2); # string
    return 1;
}

sub fgfs_get_sim_info() {
    my ($aero,$fdm,$root,$desc);
    fgfs_get_aero(\$aero);
    fgfs_get_fdm(\$fdm);
    fgfs_get_root(\$root);
    fgfs_get_desc(\$desc);
    my $rs = get_curr_sim();
    ${$rs}{'aero'} = $aero;
    ${$rs}{'fdm'} = $fdm;
    ${$rs}{'root'} = $root;
    ${$rs}{'desc'} = $desc;
    ${$rs}{'time'} = time();
    if ($aero eq 'SenecaII-jsbsim') {
        set_SenecaII();
    }
    return $rs;
}

# ####################################################
# ====================================================

END {
	if (defined $FGFS_IO) {
        prtw("WARNING: End with socket open... closing connection...\n");
		fgfs_send("run exit") if ($send_run_exit);
		close $FGFS_IO;
        undef $FGFS_IO;
	}
    #prt("END\n");
}

# ### ABOVE ARE FG TELENET FUNCTIONS ###
# ======================================

sub get_position_stg($$$) {
    my ($rlat,$rlon,$ragl) = @_;
    my ($lat,$lon,$agl);
    fgfs_get_coord(\$lon,\$lat);
    fgfs_get_agl(\$agl);
    ${$rlat} = $lat;
    ${$rlon} = $lon;
    ${$ragl} = $agl;
    set_lat_stg(\$lat);
    set_lon_stg(\$lon);
    set_int_stg(\$agl);
    return "$lat,$lon,$agl";
}


sub get_current_position() { # get_curr_posit(), but check for update needed
    my $rp = get_curr_posit();
    if (!defined ${$rp}{'time'}) {
        prtt("Moment, need to get current position...\n");
        fgfs_get_position();
    }
    my $ct = time;
    my $tm = ${$rp}{'time'};
    if (($ct - $tm) > $min_upd_position) {
        prtt("Moment, need to update current position...\n");
        fgfs_get_position();
    }
    return $rp;
}

sub got_flying_speed() {
    my $rc = get_current_position(); # get_curr_posit(), but check if update needed
    my $aspd = ${$rc}{'aspd'}; # Knots
    return 0 if ($aspd < $min_fly_speed);
    return 1;
}

sub got_keyboard($) {
    my ($rc) = shift;
    if (defined (my $char = ReadKey(-1)) ) {
		# input was waiting and it was $char
        ${$rc} = $char;
        return 1;
	}
    return 0;
}

sub sleep_ms($) {
    my $usecs = shift; # = $INTERVAL
    if ($usecs > 0) {
        my $secs = $usecs / 1000;
        select(undef,undef,undef,$secs);
	    #usleep($usecs);    # sampling interval
    }
}

sub set_dist_stg($) {
    my ($rd) = @_;
    my $dist = ${$rd};
    my ($sc);
    if ($dist < 1000) {
        $dist = int($dist);
        $sc = 'm';
    } else {
        $dist = (int(($dist / 1000) * 10) / 10);
        $sc = 'Km';
    }
    ${$rd} = "$dist$sc";
}

sub set_dist_m2kmnm_stg($) {
    my ($rd) = @_;
    my $distm = ${$rd};
    my $km = $distm;
    set_dist_stg(\$km);
    $km .= '/';
    $km .= get_dist_stg_nm($distm);
    ${$rd} = $km;
}

sub set_hdg_stg1($) {
    my ($rh) = @_;
    my $hdg = ${$rh};
    $hdg = (int(($hdg+0.05) * 10) / 10);
    ${$rh} = $hdg;
}

sub set_lat_stg($) {
    my ($rl) = @_;
    ${$rl} = sprintf("%2.7f",${$rl});
}

sub set_lon_stg($) {
    my ($rl) = @_;
    ${$rl} = sprintf("%3.7f",${$rl});
}

sub set_hdg_stg($) {
    my ($rh) = @_;
    my $hdg = ${$rh};
    $hdg = 360 if ($hdg == 0); # always replace 000 with 360 ;=))
    $hdg = sprintf("%03d",int($hdg+0.5));
    ${$rh} = $hdg;
}

sub headed_to_target() {
    if ($head_target) {
        if (length($curr_target)) {
            my $rl = get_locations();
            if (defined ${$rl}{$curr_target}) {
                return 1;
            }
        }
    } elsif ($circuit_mode) {
        return 1;
    }
    return 0;
}

sub show_YGIL_route() {
    my $rr = get_YGIL_route();
    my $rc = get_curr_posit();
    my $tm = ${$rc}{'time'};
    my $lon = ${$rc}{'lon'};
    my $lat = ${$rc}{'lat'};
    my $alt = ${$rc}{'alt'};
    my $hdg = ${$rc}{'hdg'};
    my $mag = ${$rc}{'mag'};    # /orientation/heading-magnetic-deg
    my $hb = ${$rc}{'bug'};
    my $agl = ${$rc}{'agl'};
    my $aspd = ${$rc}{'aspd'}; # Knots
    my $gspd = ${$rc}{'gspd'}; # Knots
    my ($az1,$az2,$dist,$ddist);
    my ($key,$val,$rlat,$rlon);
    my ($sc,$atr,$tky,$dky,$m1,$nmdist);
    my %hash = ();
    my $ldist = 1000000;
    my $ctrk = 360;
    my $ctm = lu_get_hhmmss_UTC(time());
    foreach $key (sort keys %{$rr}) {
        $val = ${$rr}{$key};
        $rlat = ${$val}[0];
        $rlon = ${$val}[1];
        fg_geo_inverse_wgs_84 ($lat,$lon,$rlat,$rlon,\$az1,\$az2,\$dist);
        $hash{$key} = [$az1,$dist];
        #push(@arr, [$az1,$dist]);
        $atr = abs($az1 - $hb);
        if ($atr < $ctrk) {
            $tky = $key;
            $ctrk = $atr;
        }  
        if ($dist < $ldist) {
            $ldist = $dist;
            $dky = $key;
        }
    }
    prt("$ctm: ");
    foreach $key (sort keys %hash) {
        $val = $hash{$key};
        $az1 = ${$val}[0];
        $dist = ${$val}[1];
        $az2 = get_mag_hdg_from_true($az1); # - $mag_deviation;
        $ddist = $dist;
        $m1 = '';
        # $m1 = ($key == $tky) ? "(T)" : "";
        if ($key == $tky) {
            $m1 = '(T)';
            #$track_headingT = $az1;
            #$track_headingM = $az2;
        }
        if ($dist < 1000) {
            $dist = int($dist);
            $sc = 'm';
        } else {
            $dist = (int(($dist / 1000) * 10) / 10);
            $sc = 'km';
        }
        if ( $key == $dky ) {
            $sc .= '(c)';
        }
        if (($key == $tky)||($key == $dky)) {
            get_hdg_stg(\$az1);
            get_hdg_stg(\$az2);
            #$az1 = int($az1 + 0.5);
            prt("$key: T$az1 M$az2 $m1 $dist $sc. ");
        }
    }
    # display stuff
    $hdg = (int(($hdg+0.05) * 10) / 10);
    $mag = (int(($mag+0.05) * 10) / 10);
    if (defined $hb && ($hb =~ /^-*(\d|\.)+$/)) {
        set_hdg_stg(\$hb);
    } elsif (defined $hb) {
        $hb = "?$hb?";
    } else {
        $hb = 'und!';
    }
    #prt(" hdg $hdg/$hb\n");
    prt(" hM $mag hT $hdg b $hb ");
    my $h2t = headed_to_target();
    my $nm = 0;
    $dist = 0;
    if ($h2t) {
        my $rl = get_locations();
        my ($tlat,$tlon);
        $tlat = ${$rl}{$curr_target}[$OL_LAT];
        $tlon = ${$rl}{$curr_target}[$OL_LON];
        fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
        $nmdist = get_dist_stg_nm($dist);
        set_hdg_stg(\$az1);
        prt("hm: $nmdist $az1 $curr_target");
    }
    prt("\n");
    if ($h2t) {
        #if (($target_char eq 'G')&&($nm > $away_max)) {
        #    head_for_target($curr_target,$target_char);
        #}
    }
}

sub secs_HHMMSS2($) {
    my ($secs) = @_;
    my ($mins,$hrs,$stg);
    $mins = int($secs / 60);
    $secs -= ($mins * 60);
    $hrs = int($mins / 60);
    $mins -= ($hrs * 60);
    $stg = sprintf("%02d:%02d:%02d", $hrs, $mins, $secs);
    if ($short_time_stg) {
        $stg =~ s/^00:// if ($stg =~ /^00:/);
        $stg =~ s/^00:// if ($stg =~ /^00:/);
        $stg .= 's' if (length($stg) == 2); # Add seconds if just seconds
    }
    return $stg;
}

sub get_longest_rw($) {
    my ($rrwys) = shift;
    my $cnt = scalar @{$rrwys};
    my ($i,$maxlen,$len,$ii);
    $maxlen = 0;
    $ii = 0;
    for ($i = 0; $i < $cnt; $i++) {
        $len = ${$rrwys}[$i][$RW_LEN];
        if ($len > $maxlen) {
            $maxlen = $len;
            $ii = $i;
        }
    }
    return $ii;
}

sub get_closest_rw_hdg($$) {
    my ($hdg,$rrwys) = @_;
    my $cnt = scalar @{$rrwys};
    my ($i,$diff,$mindiff,$rhdg,$rnam);
    $mindiff = 400;
    my %h = ();
    $i = get_longest_rw($rrwys); # maybe not always best choice, but for now...
    #for ($i = 0; $i < $cnt; $i++) {
        $rhdg = ${$rrwys}[$i][$RW_HDG];
        $rnam = ${$rrwys}[$i][$RW_TT1];
        $diff = abs($hdg - $rhdg);
        if ($diff < $mindiff) {
            $mindiff = $diff;
            $h{'offset'} = $i;
            $h{'name'} = $rnam;
            $h{'diff'} = $hdg - $rhdg;
        }
        $rhdg = ${$rrwys}[$i][$RW_REV];
        $rnam = ${$rrwys}[$i][$RW_TT2];
        $diff = abs($hdg - $rhdg);
        if ($diff < $mindiff) {
            $mindiff = $diff;
            $h{'offset'} = $i;
            $h{'name'} = $rnam;
            $h{'diff'} = $hdg - $rhdg;
        }
    #}
    return \%h;
}

sub track_to_within_degs($$$$) {
    my ($rp,$max_degs,$hdg,$rrwys) = @_;
    my $iret = 0;
    my $cnt = scalar @{$rrwys};
    my ($i,$diff,$rhdg,$rlen,$rnam);
    ${$rp}{'s_closest'} = get_closest_rw_hdg($hdg,$rrwys);
    #prtt("Check hdg $hdg ");
    for ($i = 0; $i < $cnt; $i++) {
        $rhdg = ${$rrwys}[$i][$RW_HDG];
        $rnam = ${$rrwys}[$i][$RW_TT1];
        #prt( "against $rhdg ");
        if (abs($hdg - $rhdg) <= $max_degs) {
            #prt(" ok1\n");
            $iret = 1;
            last;
        } else {
            $rhdg = ${$rrwys}[$i][$RW_REV];
            $rnam = ${$rrwys}[$i][$RW_TT2];
            #prt( "against $rhdg ");
            if (abs($hdg - $rhdg) <= $max_degs) {
                #prt(" ok2\n");
                $iret = 2;
                last;
            }
        }
    }
    if ($iret > 0) {
        $diff = $hdg - $rhdg;

        ${$rp}{'s_diff'} = $diff;
        ${$rp}{'s_offset'} = $i;
        ${$rp}{'s_rname'} = $rnam;
        ${$rp}{'s_type'} = $iret;

        set_int_stg(\$rhdg);
        set_int_stg(\$diff);
        ${$rp}{'s_hdg-diff'} = " $diff to $rhdg($rnam)";
    }
    #prt(" FAILED\n");
    return $iret;
}

sub get_feet_per_min($$$$) {
    my ($aspd_kt,$dist_km,$agl_ft,$dbg) = @_;
    my $mps  = $aspd_kt * $SG_NM_TO_METER / 3600; # convert speed to meters/second
    my $time = ($dist_km * 1000) / $mps;
    my $rate_mps = ( $agl_ft * $SG_FEET_TO_METER ) / $time;
    my $rate_fpm = ($rate_mps * $SG_METER_TO_FEET) * 60;
    if ($dbg) {
        my ($tmp1,$tmp2,$tmp3,$tmp4);
        $tmp1 = $mps;
        $tmp2 = $time;
        $tmp3 = $rate_fpm;
        $tmp4 = $dist_km;
        set_decimal1_stg(\$tmp1);
        set_decimal1_stg(\$tmp2);
        set_decimal1_stg(\$tmp3);
        set_decimal1_stg(\$tmp4);
        prt("An spd ${aspd_kt}Kt=${tmp1}mps, dist=${dist_km}KM. time=${tmp2}secs. rate ${tmp3}fpm\n");
    }
    return $rate_fpm;
}

# range 0-360 degrees
sub sub_two_azimuths($$) {
    my ($az1,$az2) = @_;
    my $res = 0;
    if ($az1 <= $az2) {
        $res = $az2 - $az1;
    } else {
        $res = ($az1 - $az2);
        $res *= -1;
    }
    return $res;
}


sub show_flight($) {
    my ($rf) = @_;
    return if (!defined ${$rf}{'time'});
    my $ctm = lu_get_hhmmss_UTC(${$rf}{'time'});
    my ($ai,$ait,$el,$elt,$flp,$rud,$rudt,$flap);
    #get_flt_ailerons(\$ai);
    #get_flt_ailerons_trim(\$ait);
    #get_flt_elevator(\$el);
    #get_flt_elevator_trim(\$elt);
    #get_flt_rudder(\$rud);
    #get_flt_rudder_trim(\$rudt);
    #my $rf = get_curr_flight();
    $ai  = ${$rf}{'ai'};    # 1 = right, -0.9 = left
    $ait = ${$rf}{'ait'};
    $el  = ${$rf}{'el'};    # 1 = down, to -1(-0.9) = up (climb)
    $elt = ${$rf}{'elt'};
    $rud = ${$rf}{'rud'};   # 1 = right, to -1(0.9) left
    $rudt= ${$rf}{'rudt'};
    $flp = ${$rf}{'flap'};  # 0 = none, 0.333 = 5 degs, 0.666 = 10, 1 = full extended

    $flap = "none";
    if ($flp >= 0.3) {
        if ($flp >= 0.6) {
            if ($flp >= 0.9) {
                $flap = 'full'
            } else {
                $flap = '10';
            }
        } else {
            $flap = '5';
        }
    }


    # mess for display...
    set_decimal1_stg(\$ai);
    set_decimal1_stg(\$ait);
    set_decimal1_stg(\$el);
    set_decimal1_stg(\$elt);
    set_decimal1_stg(\$rud);
    set_decimal1_stg(\$flp);
    set_decimal1_stg(\$rudt);

    prtt("FltCtrls a=$ai/$ait e=$el/$elt r=$rud/$rudt, f=$flp($flap)\n");

}

# atan of 3 degrees is 0.052312 (52.312107 K)
# From 2500 feet, at 3 degrees is dist 14.566418 Km
# From 2000 feet, at 3 degrees is dist 11.653134 Km
# From 1500 feet, at 3 degrees is dist 8.739851 Km
# From 1000 feet, at 3 degrees is dist 5.826567 Km
# From  500 feet, at 3 degrees is dist 2.913284 Km
# from : http://www.answers.com/topic/instrument-landing-system
# outer marker beacon, usually located about 5 mi (8 km) from the runway
my $sp_prev_msg = '';
my $sp_msg_skipped = 0;
my $sp_msg_show = 10;
my $sp_msg_cnt = 0;

sub show_position($) {
    my ($rp) = @_;
    return if (!defined ${$rp}{'time'});
    my $ctm = lu_get_hhmmss_UTC(${$rp}{'time'});
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$cpos,$tmp);
    my ($rch,$targ_lat,$targ_lon,$targ_hdg,$targ_dist,$targ_pset,$prev_pset);
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    $hdg  = ${$rp}{'hdg'};
    $agl  = ${$rp}{'agl'};
    $hb   = ${$rp}{'bug'};
    $mag  = ${$rp}{'mag'};  # is this really magnetic - # /orientation/heading-magnetic-deg
    $aspd = ${$rp}{'aspd'}; # Knots
    $gspd = ${$rp}{'gspd'}; # Knots

    $rch = $ref_circuit_hash;    # needed for in-circuit mode
    $targ_lat = ${$rch}{'target_lat'};
    $targ_lon = ${$rch}{'target_lon'};
    $targ_hdg = ${$rch}{'target_hgd'};
    $targ_dist = ${$rch}{'target_dist'};
    $targ_pset = ${$rch}{'targ_ptset'};   # current chosen point = TARGET point
    $prev_pset = ${$rch}{'prev_ptset'};   # previous to get TARGET TRACK

    my $msg = '';
    my $eta = '';
    my $have_target = 0;
    #show_YGIL_route();
    if (${$rp}{'gps-update'} == 1) { # maybe in display, show difference, if ANY...
        my $rg = get_curr_gps();
        if (defined ${$rg}{'time'}) {
            my $glon = ${$rg}{'lon'};
            my $glat = ${$rg}{'lat'};
            my $galt = ${$rg}{'alt'};
            my $ghdg = ${$rg}{'hdg'};
            # $agl = ${$rp}{'agl'};
            # $hb  = ${$rp}{'bug'};
            my $gmag = ${$rg}{'mag'};
            fgfs_get_mag_var(\$mag_variation);

            # display mess
            set_lat_stg(\$glat);
            set_lon_stg(\$glon);
            set_hdg_stg(\$ghdg);
            set_hdg_stg(\$gmag);
            $galt = int($galt + 0.5);
            prt("$ctm: GPS $glat,$glon,$galt ft, hdg=${ghdg}T/${gmag}M \n");
            show_environ(fgfs_get_environ());
        }
    }
    
    $msg = '';
    my $re = fgfs_get_engines();
    my $run = ${$re}{'running'};
    my $rpm = ${$re}{'rpm'};
    my $thr = ${$re}{'throttle'};
    my $magn = ${$re}{'magn'}; # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    my $mixt = ${$re}{'mix'}; # $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich

    $thr = (int($thr * 100) / 10);
    $rpm = int($rpm + 0.5);

    ##########################################
    # assumes FLYING and autopilot set on
    # #####################################
    if (headed_to_target()) {
        $have_target = 1;
        my $rl = get_locations();
        my ($tlat,$tlon,$az1,$az2,$dist,$rrwys);
        ### my $rch = $ref_circuit_hash;
        if ($circuit_mode) {
            if (!defined ${$rch}{'target_lat'} || !defined ${$rch}{'target_lon'}) {
                pgm_exit(1,"ERROR: target_lat, lon NOT defined?\n");
            }
            $tlat  = ${$rch}{'target_lat'};
            $tlon  = ${$rch}{'target_lon'};
        } else {
            $tlat  = ${$rl}{$curr_target}[$OL_LAT];
            $tlon  = ${$rl}{$curr_target}[$OL_LON];
        }
        $rrwys = ${$rl}{$curr_target}[$OL_RWY];
        ##################################################################
        fg_geo_inverse_wgs_84($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
        $az2   = get_mag_hdg_from_true($az1); # - $mag_deviation;
        #################################################################
        if ( got_flying_speed() ) {
            # with GRD SPEED (Knots), and Distance (meters), calculate an ETA (secs)
            my $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
            $eta = "ETA:".secs_HHMMSS2($secs); # display as hh:mm:ss
            # Hmmm, Dist, AGL, and GrdSpd would allow assessment of a standard 3 degree Glide SLope (GS)
            # my $min_dist = $agl / $ATAN3;
            if ($circuit_mode) {
                # what to add
                ### my $rch = $ref_circuit_hash;
                my $ptset = ${$rch}{'targ_ptset'};   # get TARGET point TR,BR,BL,TL
                ###my $nxt_ps = get_nxt_ps($ptset);
                ###my $taz1 = ${$rch}{$nxt_ps}[0];  # = [$az1,$az2,$dist]; etc...
                ###my $prev_ps = get_prev_pointset($ptset);
                # OR
                my $prev_ps = ${$rch}{'prev_ptset'}; # coming from HERE to target
                my $taz1 = ${$rch}{$prev_ps}[0];  # = [$az1,$az2,$dist]; etc...
                my $taz2 = get_mag_hdg_from_true($taz1);
                my $cmag = ${$rp}{'mag'};   # /orientation/heading-magnetic-deg
                my $chdg = ${$rp}{'hdg'};
                my $devm = sub_two_azimuths($taz2,$cmag);
                my $devt = sub_two_azimuths($taz1,$chdg);
                my $curr_tim = time();
                my $hsecs = $secs / 2;
                my $nsecs = ($secs > 20 ? 15 : $secs);
                $eta .= " $once_per_leg";
                if (!$once_per_leg && ($secs > 10)) {
                    $eta .= "c";
                    if ($end_of_turn && !$chk_time_set) {  # flag to check first ETA to target
                        $chk_course_time = $curr_tim + $nsecs; # time to check and correct course
                        $eta .= secs_HHMMSS2($hsecs);
                        $end_of_turn = 0;
                        $chk_time_set = 1;
                    } elsif ($chk_time_set) {
                        if ($curr_tim >= $chk_course_time) {
                            # check for a course correction
                            $az2 = get_mag_hdg_from_true($az1);
                            set_hdg_bug($az2);
                            set_hdg_stg(\$az2);
                            set_hdg_stg(\$az1);
                            $eta .= "to m${az2}t$az1";
                            if ($nsecs < $secs) {
                                $chk_course_time = $curr_tim + $nsecs; # time to check and correct course
                                $chk_time_set = 1;
                            } else {
                                $once_per_leg = 1;
                                $chk_time_set = 0;
                            }
                        } else {
                            $eta .= 'W'.secs_HHMMSS2($chk_course_time - $curr_tim);
                        }
                    }
                }
                set_hdg_stg(\$taz2);
                set_int_stg(\$devm);
                set_hdg_stg(\$taz1);
                set_int_stg(\$devt);
                $eta .= " $taz2:$devm" # :$taz1:$devt";
            # if (($dist > 0) && ($dist < ($min_dist * 2)))
            } elsif (($agl > 0) && ($dist > 0) && ($dist < $min_apt_distance_m)) {
                # we are WITHIN min apt distance - get glide from here
                $eta .= " *";
                $eta .= "@" if (abs($az1 - $hdg) < 15); # within 15 degrees of the heading to the runway
                if ( ($dist > 0) && ($agl > 0) ) {
                    if ( track_to_within_degs($rp,$degs_to_rwy,$az1,$rrwys) ) {
                        $eta .= "+";
                        my $fpm = get_feet_per_min($aspd,$dist/1000,$agl,0);
                        if ($fpm > 2000) {
                            $fpm = ">2Kfpm";
                        } elsif ($fpm > 1000) {
                            set_int_stg(\$fpm);
                            $fpm .= "fpm";
                        } else {
                            set_int_stg(\$fpm);
                            $fpm .= " fpm";
                        }
                        $eta .= " $fpm";
                        #my $gs = atan2($agl,$dist) * $SGD_RADIANS_TO_DEGREES;
                        #set_int_stg(\$gs);
                        #$eta .= " ${gs}gs";
                        $eta .= ${$rp}{'s_hdg-diff'};
                    } else {
                        my $rh = ${$rp}{'s_closest'}; # = get_closest_rw_hdg($hdg,$rrwys);
                        my $i = ${$rh}{'offset'};
                        my $rn = ${$rh}{'name'};
                        my $df = ${$rh}{'diff'};
                        set_int_stg(\$df);
                        $eta .= " $rn \@ $df";
                    }
                }
            }
        }
        # display messing
        #set_dist_stg(\$dist);
        my $nmdist = get_dist_stg_nm($dist);
        my $nm = $dist * $SG_METER_TO_NM;
        my $trend = '=';
        if ($nm > $prev_nm) {
            $trend = "+"
        } elsif ($nm < $prev_nm) {
            $trend = '-';
        }
        if ($trend ne $last_trend) {
            $nmdist .= $last_trend;
        }
        $nmdist .= $trend; # add the TREND now
        $prev_nm = $nm;
        $last_trend = $trend; # update LAST
        set_hdg_stg(\$az1);
        set_hdg_stg(\$az2);
        $msg = "hm:$curr_target $nmdist ${az1}T/${az2}M";
    } # end if (headed_to_target())
    # #####################################
    

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
        fgfs_set_hdg_bug($mag);
    }
    set_int_stg(\$alt);
    set_lat_stg(\$lat);
    set_lon_stg(\$lon);
    $cpos = "$lat,$lon,$alt";
    if ($aspd < $min_fly_speed) {
        # ON GROUND has different concerns that say position
        get_altimeter_stg();
        $agl = "OG ";
        if ($alt_msg_chg) {
            $alt_msg_chg = 0;
            $agl .= "$altimeter_msg ";
        } else {
            if ($sp_msg_cnt < 5) {
                $agl .= "$altimeter_msg ";
            } else {
                $agl .= "$cpos";
            }
        }
    } else {
        if ($agl > $min_agl_height) {
            $agl = '';
        } elsif ($have_target) {
            $agl = '';
        } else {
            $agl = int($agl + 0.5)."Ft";
        }
    }
    $aspd = int($aspd + 0.5);
    $gspd = int($gspd + 0.5);
    $msg .= " $aspd/${gspd}Kt";
    $msg .= " R=".get_curr_roll() if ($dbg_roll);
    if (!$have_target) {
        $msg .= " E($rpm/$thr\%)";
        $msg .= " B(".get_curr_brake_stg().")";
    }

    update_hdg_ind(); # this is changing fast in a TURN
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
            $sp_msg_cnt++;          # count of messages atually output
        }
    } else {
        $show_msg = 1;
        $sp_msg_cnt++;          # count of messages atually output
    }
    if ($show_msg) {
        $hdg  = ${$rp}{'hdg'};
        # $agl  = ${$rp}{'agl'};
        # $hb   = ${$rp}{'bug'};
        $mag  = ${$rp}{'mag'};  # is this really magnetic - # /orientation/heading-magnetic-deg
        set_hdg_stg(\$hdg);
        set_hdg_stg(\$mag);
        prt("$ctm: $agl hdg=".$hdg."t/".$mag."m/${tmp}i,b=$hb $msg $eta\n");
    }

    $sp_prev_msg = $msg;    # save last message
    
}

sub show_environ($) {
    my ($renv) = @_;
    my ($tm,$wspd,$whdg,$weast,$wnor);
    my ($tmp1,$tmp2);
    if (defined ${$renv}{'time'}) {
        $tm = ${$renv}{'time'};
        $wspd = ${$renv}{'speed-kt'};
        $whdg = ${$renv}{'heading-deg'};
        $weast = ${$renv}{'east-fps'};
        $wnor = ${$renv}{'north-fps'};
        my $ctm = lu_get_hhmmss_UTC($tm);
        my $chdg = sprintf("%03d", int($whdg + 0.5));
        my $cspd = sprintf("%02d", int($wspd + 0.5));
        $tmp1 = $mag_deviation;
        $tmp2 = $mag_variation;
        set_decimal1_stg(\$tmp1);
        set_decimal1_stg(\$tmp2);
        set_decimal1_stg(\$weast);
        set_decimal1_stg(\$wnor);
        $last_wind_info = "$chdg${cspd}KT";
        prt("$ctm: $last_wind_info - E=$weast, N=$wnor fps - MV=$tmp1($tmp2)\n");
        my $metar = ${$renv}{'metar'};
        if ((defined $metar) && length($metar)) {
            prt("$ctm: $metar\n");
        }
    }
}

sub show_comms($) {
    my ($rc) = @_;
    my ($c1a,$c1s);
    my ($n1a,$n1s);
    my ($adf,$adfs);
    my ($c2a,$c2s);
    my ($n2a,$n2s);
    if (defined ${$rc}{'time'}) {
        my $ctm = lu_get_hhmmss_UTC(${$rc}{'time'});
        $adf = ${$rc}{'adf-act'};
        $adfs = ${$rc}{'adf-sby'};
        $c1a = ${$rc}{'comm1-act'};
        $c1s = ${$rc}{'comm1-sby'};
        $n1a = ${$rc}{'nav1-act'};
        $n1s = ${$rc}{'nav1-sby'};
        $c2a = ${$rc}{'comm2-act'};
        $c2s = ${$rc}{'comm2-sby'};
        $n2a = ${$rc}{'nav2-act'};
        $n2s = ${$rc}{'nav2-sby'};
        prt("$ctm: ".sprintf("ADF   %03d (%03d)",$adf,$adfs)."\n");
        prt("$ctm: ".sprintf("COMM1 %03.3f (%03.3f) NAV1 %03.3f (%03.3f)",$c1a,$c1s,$n1a,$n1s)."\n");
        prt("$ctm: ".sprintf("COMM2 %03.3f (%03.3f) NAV2 %03.3f (%03.3f)",$c2a,$c2s,$n2a,$n2s)."\n");
    }
}

sub show_consumables($) {
    my $rc = shift;
    if (defined ${$rc}{'time'}) {
        my ($t1gi,$t1gus,$t2gi,$t2gus,$totgi,$totgus);
        my ($tlbs,$tkgs);
        my $ctm = lu_get_hhmmss_UTC(${$rc}{'time'});
        $t1gi = ${$rc}{'tank1-imp'};
        $t1gus = ${$rc}{'tank1-us'};
        $t2gi = ${$rc}{'tank2-imp'};
        $t2gus = ${$rc}{'tank2-us'};
        $totgi = ${$rc}{'total-imp'};
        $totgus = ${$rc}{'total-us'};
        $tlbs = ${$rc}{'total-lbs'};
        $tkgs = ${$rc}{'total-kgs'};

        # display fixes
        set_decimal1_stg(\$t1gi);
        set_decimal1_stg(\$t1gus);
        set_decimal1_stg(\$t2gi);
        set_decimal1_stg(\$t2gus);
        set_decimal1_stg(\$totgi);
        set_decimal1_stg(\$totgus);
        set_decimal1_stg(\$tlbs);
        set_decimal1_stg(\$tkgs);
        prt("$ctm: Total $totgi gal.imp ($totgus us), $tlbs lbs ($tkgs kgs). T1 $t1gi($t1gus), T2 $t2gi($t2gus)\n");
    }
}

sub show_K_locks() {
    my $rk = fgfs_get_K_locks();
    my ($pm,$rm);
    $kap_tm = ${$rk}{'time'};
    $kap_ah = ${$rk}{'ah'};
    $kap_pa = ${$rk}{'pa'};
    $pm = ${$rk}{'pm'};
    $kap_ra = ${$rk}{'ra'};
    $rm = ${$rk}{'rm'};
    $kap_hh = ${$rk}{'hh'};
    my $msg = '';
    if ((defined $kap_ah && ($kap_ah eq 'true'))&&
        (defined $kap_pa && ($kap_pa eq 'true'))&&
        (defined $kap_ra && ($kap_ra eq 'true'))&&
        (defined $kap_hh && ($kap_hh eq 'true'))) {
        $msg = "Full ON";
    }
    prt("KAP140 locks: alt-hold=$kap_ah, pitch-axis=$kap_pa, roll-axis=$kap_ra, hdg-hold=$kap_hh $msg\n");
}

sub check_keyboard() {
    my ($char,$val,$pmsg);
    if (got_keyboard(\$char)) {
        $val = ord($char);
        $pmsg = sprintf( "%02X", $val );
        if ($val == 27) {
            prt("ESC key... Eixting...\n");
            return 1;
        } elsif ($char eq '+') {
            $DELAY++;
            prt("Increase delay to $DELAY seconds...\n");
        } elsif ($char eq '-') {
            $DELAY-- if ($DELAY);
            prt("Decrease delay to $DELAY seconds...\n");
        } else {
            prt("Got keyboard input hex[$pmsg]...\n");
        }
    }
    return 0;
}

# Show 1 (or 2) motors values
sub show_engines() {
    my ($running,$rpm,$magn,$mixt,$cmag);
    my ($run2,$rpm2);
    my ($throt,$thpc,$throt2,$thpc2);
    my $re = fgfs_get_engines();
    $running = ${$re}{'running'};
    $rpm     = ${$re}{'rpm'};
    $throt   = ${$re}{'throttle'};
    $magn    = ${$re}{'magn'};
    $mixt    = ${$re}{'mix'};   # 0 = 100% - Full rich (for TO/LD)
    $cmag = 'BOTH';
    if ($magn == 0) {
        $cmag = 'NONE';
    } elsif ($magn == 1) {
        $cmag = 'LEFT';
    } elsif ($magn == 2) {
        $cmag = 'RIGHT';
    }
    # prt("run = [$running] rpm = [$rpm]\n");
    if ($engine_count == 2) {
        # TWO engines
        $run2   = ${$re}{'running2'};
        $rpm2   = ${$re}{'rpm2'};
        $throt2 = ${$re}{'throttle2'};
        $thpc = (int($throt * 100) / 10);
        $rpm = int($rpm + 0.5);
        $thpc2 = (int($throt2 * 100) / 10);
        $rpm2 = int($rpm2 + 0.5);
        ### prtt("Run1=$running, rpm=$rpm, throt=$thpc\% ...\n");
        prtt("Run1=$running, rpm=$rpm, throt=$thpc\%, mags $cmag, mix $mixt...\n");
        prtt("Run2=$run2, rpm=$rpm2, throt=$thpc2\% ...\n");
    } else {
        # ONE engine
        $thpc = (int($throt * 100) / 10);
        $rpm = int($rpm + 0.5);
        prtt("Run=$running, rpm=$rpm, throt=$thpc\%, mags $cmag, mix $mixt...\n");
    }
}

sub show_engines_and_fuel() {
    show_engines();
    show_consumables(fgfs_get_consumables());
}

#######################################################################
########### WAIT for engine start ####### need motor for flight #######
#######################################################################
sub wait_for_engine() {
    my ($ok,$btm,$ntm,$dtm,$ctm);
    my ($running,$rpm);
    my ($run2,$rpm2);
    my ($throt,$thpc,$throt2,$thpc2);
    my ($magn,$cmag,$mixt);
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
                $thpc = (int($throt * 100) / 10);
                $rpm = int($rpm + 0.5);
                $thpc2 = (int($throt2 * 100) / 10);
                $rpm2 = int($rpm2 + 0.5);
                prtt("Run1=$running, rpm=$rpm, throt=$thpc\%, mags $cmag, mix $mixt ...\n");
                prtt("Run2=$run2, rpm=$rpm2, throt=$thpc2\% ...\n");
                $ok = 1;
                last;
            }
        } else {
            # ONE engine
            if (($running eq 'true') && ($rpm > $min_eng_rpm)) {
                $thpc = (int($throt * 100) / 10);
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
        if ($dtm > $DELAY) {
            $ctm += $dtm;
            # show_flight(get_curr_flight());
            show_flight(fgfs_get_flight());
            if ($engine_count == 2) {
                prtt("Waiting for $engine_count engines to start... $ctm secs (run1=$running rpm1=$rpm, run2=$run2 rpm2=$rpm2)\n");
            } else {
                prtt("Waiting for $engine_count engine to start... $ctm secs (run=$running rpm=$rpm)\n");
            }
            $btm = $ntm;
        }
    }
    my $rp = fgfs_get_position();
    prtt("Position on got engine...\n");
    show_position($rp);
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
            prtt("Position on acquiring altitude hold...\n");
            show_position($rp);
            $ok = 1;
        } else {
            if (check_keyboard()) {
                return 1;
            }
        }
        $ntm = time();
        $dtm = $ntm - $btm;
        if ($dtm > $DELAY) {
            $ctm += $dtm;
            prtt("Cycle waiting for altitude hold... $ctm secs\n") if (!$ok);
            $btm = $ntm;
        }
    }
    return 0;
}

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
    $hdg -= $mag_deviation;
    get_hdg_in_range(\$hdg);
    return $hdg;
}

sub set_circuit_hash() {
    my $rch = $ref_circuit_hash;
    ${$rch}{'begin_hb'} = $begin_hb;
    ${$rch}{'requested_hb'} = $requested_hb;
    ${$rch}{'begin_turn'} = time();
    ${$rch}{'in_turn'} = 1;
}


sub set_hdg_bug($) {
    my ($hdg) = shift;
    my $rc = get_curr_posit();  # acutally get LAST position HASH
    my $diff = abs($hdg - $requested_hb);
    $diff = 360 - $diff if ($diff > 180);
    if ($diff < 5) {
        return;
    }

    fgfs_set_hdg_bug($hdg);     # set the BUG (for autopilot)
    $begin_hb = ${$rc}{'bug'};  # get bug BEFORE change
    $requested_hb = $hdg;
    $bgn_turn_tm = time();
    $chk_turn_count = 0;
    $last_turn_diff = 180; # set maximum DIFFERENCE!
    ###############################################
    $chk_turn_done = 1;
    $done_turn_done = 0;
    $end_of_turn = 0;       # set flag to check first ETA to target
    ###############################################
    $diff = abs($begin_hb - $requested_hb);
    my $bhb = $begin_hb;
    my $rhb = $requested_hb;
    $diff = 360 - $diff if ($diff > 180);
    set_circuit_hash();
    set_decimal1_stg(\$diff);
    set_decimal1_stg(\$bhb);
    set_decimal1_stg(\$rhb);
    prtt("set_hdg_bug: from $bhb to $rhb = $diff - ctd=1 dtd=0\n");
}

sub set_hdg_bug_force($) {
    my ($hdg) = shift;
    my $rc = get_curr_posit();  # acutally get LAST position HASH
    fgfs_set_hdg_bug($hdg);     # set the BUG (for autopilot)
    $begin_hb = ${$rc}{'bug'};  # get bug BEFORE change
    $requested_hb = $hdg;
    $bgn_turn_tm = time();
    $chk_turn_count = 0;
    $last_turn_diff = 180; # set maximum DIFFERENCE!
    ###############################################
    $chk_turn_done = 1;
    $done_turn_done = 0;
    $end_of_turn = 0;       # set flag to check first ETA to target
    ###############################################
    my $diff = abs($begin_hb - $requested_hb);
    my $bhb = $begin_hb;
    my $rhb = $requested_hb;
    $diff = 360 - $diff if ($diff > 180);
    set_circuit_hash();

    set_decimal1_stg(\$diff);
    set_decimal1_stg(\$bhb);
    set_decimal1_stg(\$rhb);
    prtt("set_hdg_bug: from $bhb to $rhb = $diff - ctd=1 dtd=0\n");
}


sub head_for_target($$) {
    my ($targ,$char) = @_;
    my $rc = get_curr_posit();
    my $lon = ${$rc}{'lon'};
    my $lat = ${$rc}{'lat'};
    my $rl = get_locations();
    if (length($targ) && (defined ${$rl}{$targ})) {
        # appear to have such a target
        $target_char = $char;
        my ($az1,$az2,$dist);
        $target_lat = ${$rl}{$targ}[$OL_LAT];
        $target_lon = ${$rl}{$targ}[$OL_LON];
        fg_geo_inverse_wgs_84 ($lat,$lon,$target_lat,$target_lon,\$az1,\$az2,\$dist);
        $az2 = get_mag_hdg_from_true($az1);
        set_hdg_bug_force($az2);
        $curr_target = $targ;
        $head_target = 1;

        # display stuff
        set_hdg_stg(\$az1);
        set_hdg_stg(\$az2);
        set_dist_stg(\$dist);
        prtt("Head for [$curr_target] on ${az1}T/${az2}M $dist\n");

        # check the WINDS, weather
        my $renv = fgfs_get_environ();
        show_environ($renv);

        # get the RADIO stack
        my $rcomms = fgfs_get_comms();
        show_comms($rcomms);   # show current comms

        # NAVAIDS, in minimal database - maybe use findap.pl to get FACTS???
        my $msg = '';
        my ($rnavs,$nav,$frq,$cnt,$i);
        $rnavs = ${$rl}{$targ}[$OL_NAV];
        $cnt = scalar @{$rnavs};
        for ($i = 0; $i < $cnt; $i++) {
            $nav = ${$rnavs}[$i][0];
            if ($nav && length($nav)) {
                $frq = ${$rnavs}[$i][1];
                $msg .= "[$nav,$frq] ";
            }
        }
        # could include a warning if a navaid is NOT already set in the COMMS array
        prtt("NAVAIDS: $msg\n") if (length($msg));

        # headed for new target - SHOW consumables, and maybe warnings, if any
        my $rcs = fgfs_get_consumables();
        show_consumables($rcs);
        # other things on choosing a target???

    } else {
        prtw("WARNING: No such target [$targ]!\n");
    }
}

my $in_orbit = 0;
my $secs_to_turn = 30;
my ($begin_mag,$orbit_tm,$orbit_bgn_lat,$orbit_bgn_lon,$orbit_type,$orbit_bgn_tm);

sub process_orbit() {
    return 0 if ($in_orbit == 0);
    return 0 if ((time() - $orbit_tm) < $secs_to_turn);
    my $msg = '';
    my $nmag = 0;
    my $norb = 0;
    if ($in_orbit == 1) {
        $nmag = $begin_mag + 180;
        $msg = "2nd turn $orbit_type...";
    } elsif ($in_orbit == 2) {
        $nmag = $begin_mag + 270;
        $msg = "3rd turn $orbit_type...";
    } elsif ($in_orbit == 3) {
        $nmag = $begin_mag;
        $msg = "Last turn $orbit_type...";
    } elsif ($in_orbit == 4) {
        if ($orbit_type eq 'O') {
            $nmag = $begin_mag + 90;    # first right turn
            $msg = "Re-do $orbit_type...";
            $in_orbit = 0; # note post increment below
            $norb = 1;
        } else {
            $msg = "End $orbit_type...";
            $in_orbit = 0;
        }
    } else {
        $msg = "Orbit value error... $in_orbit! Cancelling orbit\n";
        $in_orbit = 0;
    }
    if ($in_orbit || $norb) {
        $nmag -= 360 if ($nmag > 360);
        set_int_stg(\$nmag);
        $msg .= " b=$nmag";
        set_hdg_bug_force($nmag);
        $orbit_tm = time(); # update TIME
        $in_orbit++;
    }
    my ($lat,$lon,$agl);
    my $pstg = get_position_stg(\$lat,\$lon,\$agl);
    my $drift = '';
    if ($in_orbit < 2) {
        # either 0 ended, or 1 begin again
        my ($az1,$az2,$dist);
        fg_geo_inverse_wgs_84 ($orbit_bgn_lat,$orbit_bgn_lon,$lat,$lon,\$az1,\$az2,\$dist);
        my $tottm = time() - $orbit_bgn_tm;
        my $spd = (($dist * $SG_METER_TO_NM) / $tottm) * 60 * 60;
        # massage of display
        set_int_stg(\$spd);
        $spd = "0$spd" if ($spd < 10);
        $spd .= "KT";
        $dist = get_dist_stg_nm($dist);
        set_hdg_stg(\$az2);
        $drift = "drift $dist in ".secs_HHMMSS2($tottm)." $az2$spd (m:$last_wind_info)";
    }
    prtt("$msg $in_orbit $pstg $drift\n");
    return $in_orbit;
}

sub commence_orbit($) {
    my $typ = shift;
    if ($in_orbit) {
        prtt("Cancel current orbit... $in_orbit\n");
        $in_orbit = 0;
        return 0;
    }
    my ($nmag);
    my $msg = '';
    my ($lat,$lon,$agl);
    $orbit_type = $typ;
    fgfs_get_hdg_mag(\$begin_mag);
    $nmag = $begin_mag + 90;    # first right turn
    $msg = "Commence orbit ($typ)...";
    $nmag -= 360 if ($nmag > 360);
    set_int_stg(\$nmag);
    $msg .= " setting bug to $nmag";
    set_hdg_bug_force($nmag);
    $orbit_tm = time();
    $orbit_bgn_tm = $orbit_tm;
    $in_orbit++;
    my $pstg = get_position_stg(\$lat,\$lon,\$agl);
    $orbit_bgn_lat = $lat;
    $orbit_bgn_lon = $lon;
    prtt("$msg $in_orbit $pstg\n");
    return $in_orbit;
}

sub show_sim_info($) {
    my $rs = shift;
    my ($ctm,$aero,$fdm,$root,$desc);
    $aero = ${$rs}{'aero'};
    $fdm = ${$rs}{'fdm'};
    $root = ${$rs}{'root'};
    $desc = ${$rs}{'desc'};
    $ctm = lu_get_hhmmss_UTC(${$rs}{'time'});
    prt("$ctm: FDM=[$fdm] aero=[$aero] fg-root=[$root]\n");
    prt("$ctm: Desc=$desc\n") if ((defined $desc) && length($desc));
}

# $curr_target = 'YGIL';
# $head_target = 1;
sub lineup_to_target() {
    if (!got_flying_speed()) {
        prtt("Lineup: Appear on ground. NO lineup possible!\n");
        return 0;
    }
    my $rl = get_locations();
    my $rp = get_current_position(); # get_curr_posit(), but check for update needed
    my $targ = $curr_target;
    if ($head_target && length($targ) && (defined ${$rl}{$targ})) {
        my ($lat,$lon,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd);
        my ($tlat,$tlon);
        my ($dist,$az1,$az2,$tmp);
        $agl  = ${$rp}{'agl'};
        if ($agl < 200) {
            prtt("Lineup: Too LOW AGL=$agl feet. NO lineup possible!\n");
            return 0;
        }
        $lon  = ${$rp}{'lon'};
        $lat  = ${$rp}{'lat'};
        $alt  = ${$rp}{'alt'};
        $hdg  = ${$rp}{'hdg'};
        $hb   = ${$rp}{'bug'};
        $mag  = ${$rp}{'mag'};  # /orientation/heading-magnetic-deg
        $aspd = ${$rp}{'aspd'}; # Knots
        $gspd = ${$rp}{'gspd'}; # Knots

        $tlat = ${$rl}{$targ}[$OL_LAT];
        $tlon = ${$rl}{$targ}[$OL_LON];
        fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
        if ($dist > $min_apt_distance_m) {
            $dist = get_dist_stg_nm($dist);
            $tmp = $min_apt_distance_m * $SG_METER_TO_NM;
            set_decimal1_stg(\$tmp);
            prtt("Lineup: At distance $dist GT $tmp. Can only head for target $targ!\n");
            head_for_target($targ,$target_char);
            $in_orbit = 0;
            return 0;
        }
        # ok, got distance LESS THAN say 25nm, so try to LINE UP for nearest RUNWAY
        # but predicted decent rate will determine initial direction to head
        my $rrwys = ${$rl}{$targ}[$OL_RWY];
        my $rcnt = scalar @{$rrwys};
        my $re = fgfs_get_environ();    # get current winds
        my $fpm = get_feet_per_min($aspd,$dist/1000,$agl,0);
        if ($fpm < $target_decent) {
            # ok, can try head towards target
        } else {
            # must first head AWAY from target
        }
        # But really, after reading lots more on approaches to airport, it seems
        # what should happen is that here we target to enter the 'downwind' leg of
        # a standard circuit, unless we are in a possition for a straight in approach!!!
        #
        # So although I was going to consider wind direction and speed later, it seems
        # the first effor is to choose an appropriate runway to land on, then establish
        # left hand circuit/pattern for that runway, thus first getting the target GPS
        # location to head for...
        #
    } else {
        prtt("Lineup: NO target set!\n");
        return 0;
    }
    return 1;
}


sub keyboard_help() {
    prt("Keyboard Help\n");
    prt(" ?      This HELP output\n");
    prt(" ESC    Exit program.\n");
    prt(" a      Get autopilot (KAP140) locks\n");
    prt(" B/b    Increase/Decrease heading bug 1 degreee\n");
    prt(" c/C    Circuit mode. C cancel.\n");
    prt(" +/-    Increase/Decrease position delay check. Current $DELAY secs\n");
    prt(" 9/(    Increase/Decrease heading bug 90 degrees\n");
    #prt(" 1      Set heading target to Gil (YGIL)\n");
    #prt(" 2      Set heading target to Dubbo (YSDU)\n");
    prt(" e      Show Engine(s)\n");
    prt(" g/1    Head for target YGIL\n");
    prt(" d/2    Head for target YSDU\n");
    prt(" o/O    Commence a 360 degree orbit. O will repeat. If in orbit, cancel orbitting.\n");
    prt(" Any keyboard input exits the keyboard loop, and continues the main loop, except ESC!\n");
}

# ===============================================
# from solve.pl

sub Point_Inside_Triange($$$$$$$$) {
    my ($px,$py,$x1,$y1,$x2,$y2,$x3,$y3) = @_;
    my $a1 = Triangle_Area($px,$py,$x1,$y1,$x2,$y2);
    my $a2 = Triangle_Area($px,$py,$x2,$y2,$x3,$y3);
    my $a3 = Triangle_Area($px,$py,$x3,$y3,$x1,$y1);
    my $at = Triangle_Area($x1,$y1,$x2,$y2,$x3,$y3);
    my $sum = $a1 + $a2 + $a3;
    my $diff = abs($at - $sum);
    return 1 if ($diff < 1.0E-010); # take this SMALL value as EQUAL !!! 
    return 0;
}

sub Triangle_Area($$$$$$) {
    my ($x1,$y1,$x2,$y2,$x3,$y3) = @_;
    return abs($x1*$y2 + $x2*$y3 + $x3*$y1 - $x1*$y3 - $x3*$y2 - $x2*$y1) / 2;
}

sub add_arrow_to_center($$$$$) {
    my ($rh,$plat12,$plon12,$plat13,$plon13) = @_;
    my ($clat,$clon,$az1,$az2,$dist);
    fg_geo_inverse_wgs_84($plat12,$plon12,$plat13,$plon13,\$az1,\$az2,\$dist);
    fg_geo_direct_wgs_84($plat12,$plon12,$az1,$dist/2,\$clat,\$clon,\$az2);
    add_img_circle($rh,$clat,$clon);
    add_img_arrow($rh,$clat,$clon,$az1);
}

sub add_img_arrow($$$$) {
    my ($rh,$clat,$clon,$az) = @_;
    my ($w_ind1,$h_ind1);
    my ($maxlat,$minlat,$maxlon,$minlon);
    my ($w_dpp,$h_dpp);
    my ($sqwid,$sqhgt,$rmsg);
    my $adj = 0;
    $rmsg   = ${$rh}{'rmsg'};
    $maxlat = ${$rh}{'max_lat'};
    $minlat = ${$rh}{'min_lat'};
    $maxlon = ${$rh}{'max_lon'};
    $minlon = ${$rh}{'min_lon'};
    $w_dpp  = ${$rh}{'w_dpp'};
    $h_dpp  = ${$rh}{'h_dpp'};
    $sqwid  = ${$rh}{'sq_wid_adj'};
    $sqhgt  = ${$rh}{'sq_hgt_adj'};
    $w_ind1 = int((($clon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind1 = int((($clat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind1 = $sqhgt - $h_ind1;
    $h_ind1 += 1 if ($h_ind1 == 0);
    $w_ind1 += 1 if ($w_ind1 == 0);
    $h_ind1 -= 1 if ($h_ind1 == $sqhgt);
    $w_ind1 -= 1 if ($w_ind1 == $sqwid);
    my $rot = normalised_hdg(int($az+0.5) - (90+$adj));
    my $arrow_head = "path 'M 0,0 l -15,-5 +5,+5 -5,+5 +15,-5 z'";
    my $msg = "-draw \"push graphic-context stroke blue fill skyblue translate $w_ind1,$h_ind1 rotate $rot ";
    $msg .= "$arrow_head pop graphic-context\" ";
    ${$rmsg} .= $msg;
}

sub add_img_circle($$$) {
    my ($rh,$clat,$clon) = @_;
    my $rmsg = ${$rh}{'rmsg'};
    my ($w_ind1,$h_ind1);
    my ($maxlat,$minlat,$maxlon,$minlon);
    my ($w_dpp,$h_dpp);
    my ($sqwid,$sqhgt);
    $maxlat = ${$rh}{'max_lat'};
    $minlat = ${$rh}{'min_lat'};
    $maxlon = ${$rh}{'max_lon'};
    $minlon = ${$rh}{'min_lon'};
    $w_dpp = ${$rh}{'w_dpp'};
    $h_dpp = ${$rh}{'h_dpp'};
    $sqwid = ${$rh}{'sq_wid_adj'};
    $sqhgt = ${$rh}{'sq_hgt_adj'};
    $w_ind1 = int((($clon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind1 = int((($clat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind1 = $sqhgt - $h_ind1;
    $h_ind1 += 1 if ($h_ind1 == 0);
    $w_ind1 += 1 if ($w_ind1 == 0);
    $h_ind1 -= 1 if ($h_ind1 == $sqhgt);
    $w_ind1 -= 1 if ($w_ind1 == $sqwid);
    ${$rmsg} .= "-draw \"circle ".($w_ind1-1).",$h_ind1 ".($w_ind1+1).",$h_ind1\" ";
}

sub add_img_line($$$$$$) {
    my ($rh,$lat1,$lon1,$lat2,$lon2,$type) = @_;
    my ($w_ind1,$h_ind1,$w_ind2,$h_ind2);
    my ($maxlat,$minlat,$maxlon,$minlon);
    my ($w_dpp,$h_dpp);
    my ($sqwid,$sqhgt,$draw);
    my $rmsg = ${$rh}{'rmsg'};
    $maxlat = ${$rh}{'max_lat'};
    $minlat = ${$rh}{'min_lat'};
    $maxlon = ${$rh}{'max_lon'};
    $minlon = ${$rh}{'min_lon'};
    $w_dpp = ${$rh}{'w_dpp'};
    $h_dpp = ${$rh}{'h_dpp'};
    $sqwid = ${$rh}{'sq_wid_adj'};
    $sqhgt = ${$rh}{'sq_hgt_adj'};
    $w_ind1 = int((($lon1 - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind1 = int((($lat1 - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind1 = $sqhgt - $h_ind1;
    $h_ind1 += 1 if ($h_ind1 == 0);
    $w_ind1 += 1 if ($w_ind1 == 0);
    $h_ind1 -= 1 if ($h_ind1 == $sqhgt);
    $w_ind1 -= 1 if ($w_ind1 == $sqwid);
    $w_ind2 = int((($lon2 - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind2 = int((($lat2 - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind2 = $sqhgt - $h_ind2;
    $h_ind2 += 1 if ($h_ind2 == 0);
    $w_ind2 += 1 if ($w_ind2 == 0);
    $h_ind2 -= 1 if ($h_ind2 == $sqhgt);
    $w_ind2 -= 1 if ($w_ind2 == $sqwid);
    if ($type == 1) {
        $draw = "-draw \"stroke-dasharray 5 3 path 'M $w_ind1,$h_ind1 L $w_ind2,$h_ind2'\" ";
    } else {
        $draw = "-draw \"line $w_ind1,$h_ind1 $w_ind2,$h_ind2\" ";
    }
    ${$rmsg} .= $draw;
}

sub dist_less_or_equal5($$) {
    my ($dist,$min_dist) = @_;
    return 1 if ($dist <= $min_dist);
    my $d5 = $dist * 0.95;
    return 2 if ($d5 < $min_dist);
    return 0;
}

sub draw_text_at_latlon($$$$$) {
    my ($rh,$lat,$lon,$text,$flag) = @_;
    my ($w_ind1,$h_ind1);
    my ($maxlat,$minlat,$maxlon,$minlon);
    my ($w_dpp,$h_dpp);
    my ($sqwid,$sqhgt,$draw);
    my ($x_txt,$y_txt);
    my $len = length($text);
    return if ($len == 0);
    my $w_adj = $len * 3;
    my $h_adj = 5;
    $maxlat = ${$rh}{'max_lat'};
    $minlat = ${$rh}{'min_lat'};
    $maxlon = ${$rh}{'max_lon'};
    $minlon = ${$rh}{'min_lon'};
    $w_dpp = ${$rh}{'w_dpp'};
    $h_dpp = ${$rh}{'h_dpp'};
    $sqwid = ${$rh}{'sq_wid_adj'};
    $sqhgt = ${$rh}{'sq_hgt_adj'};
    $w_ind1 = int((($lon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind1 = int((($lat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind1 = $sqhgt - $h_ind1;
    $x_txt = $w_ind1 + 3;
    $y_txt = $h_ind1 + 4;
    $x_txt += 3 if (($x_txt - 3) <= 0);
    $x_txt -= 3 if (($x_txt + 3) >= $sqwid);
    $y_txt -= 5 if (($y_txt + 5) >= $sqhgt);
    $y_txt += 5 if (($y_txt - 5) <= 0);
    draw_text_at_pos($rh,$x_txt,$y_txt,$text,$flag);
}

sub draw_text_at_pos($$$$$) {
    my ($rh,$x_txt,$y_txt,$text,$flag) = @_;
    my $rmsg = ${$rh}{'rmsg'};
    my $msg = "-draw \"text $x_txt,$y_txt '$text'\" ";
    ${$rh}{'x_txt'} = $x_txt;
    ${$rh}{'y_txt'} = $y_txt;
    ${$rmsg} .= $msg;
}

sub get_circuit_hash() {
    my %h = ();
    $h{'tl_lat'} = $tl_lat;
    $h{'tl_lon'} = $tl_lon;
    $h{'bl_lat'} = $bl_lat;
    $h{'bl_lon'} = $bl_lon;
    $h{'br_lat'} = $br_lat;
    $h{'br_lon'} = $br_lon;
    $h{'tr_lat'} = $tr_lat;
    $h{'tr_lon'} = $tr_lon;
    set_circuit_values(\%h,1);
    return \%h;
}

sub get_mid_bl2br($$) {
    my ($rlat,$rlon) = @_;
    my ($az1,$az2,$dist);
    fg_geo_inverse_wgs_84 ($bl_lat,$bl_lon,$br_lat,$br_lon,\$az1,\$az2,\$dist);
    my $dist2 = $dist / 2;
    fg_geo_direct_wgs_84( $bl_lat, $bl_lon, $az1, $dist2, $rlat, $rlon, \$az2 );
}

sub get_mid_bl2br2($$) {
    my ($rlat,$rlon) = @_;
    my ($az1,$az2,$dist);
    fg_geo_inverse_wgs_84 ($bl_lat,$bl_lon,$br_lat,$br_lon,\$az1,\$az2,\$dist);
    my $dist2 = $dist / 2;
    my ($clat,$clon);
    fg_geo_direct_wgs_84( $bl_lat, $bl_lon, $az1, $dist2, \$clat, \$clon, \$az2 );
    $az2 = normalised_hdg($az1 + 90); # turn 90 degrees, and get a point
    fg_geo_direct_wgs_84( $clat, $clon, $az2, $dist2, $rlat, $rlon, \$az1 );
}

sub get_mid_tl2bl($$) {
    my ($rlat,$rlon) = @_;
    my ($az1,$az2,$dist);
    fg_geo_inverse_wgs_84 ($tl_lat,$tl_lon,$bl_lat,$bl_lon,\$az1,\$az2,\$dist);
    my $dist2 = $dist / 2;  # get the center of this line
    my ($clat,$clon);
    fg_geo_direct_wgs_84( $tl_lat, $tl_lon, $az1, $dist2, \$clat, \$clon, \$az2 );
    $az2 = normalised_hdg($az1 + 90); # turn 90 degrees, and get a point
    fg_geo_direct_wgs_84( $clat, $clon, $az2, $dist2, $rlat, $rlon, \$az1 );
}

sub get_runways_and_pattern($$) {
    my ($rh,$key) = @_;
    my $rl = get_locations();
    my ($rrwys,$rpatts);
    if (defined ${$rl}{$key}) {
        $rrwys = ${$rl}{$key}[$OL_RWY];
        $rpatts = ${$rl}{$key}[$OL_PAT];
        ${$rh}{'runways'} = $rrwys;
        ${$rh}{'pattern'} = $rpatts;
        ${$rh}{'airport'} = $key;
    } else {
        pgm_exit(1,"ERROR: Key [$key] NOT in locations!\n");
    }
}

sub in_world_range($$) {
    my ($lat,$lon) = @_;
    if (($lat < -90) ||
        ($lat >  90) ||
        ($lon < -180) ||
        ($lon > 180) ) {
        return 0;
    }
    return 1;
}

sub is_in_circuit($$$$$) {
    my ($rh,$lat,$lon,$msg,$i) = @_;
    if (Point_Inside_Triange($lat,$lon,$tl_lat,$tl_lon, $bl_lat,$bl_lon, $br_lat,$br_lon)) {
        prt("Point $i inside first triangle\n");
    } elsif (Point_Inside_Triange($lat,$lon,$tl_lat,$tl_lon, $tr_lat,$tr_lon, $br_lat,$br_lon)) {
        prt("Point $i inside second triangle\n");
    } else {
        prt("Point $i NOT in circuit\n");
    }
}

sub norm_vector_length($) {
    my ($rv) = @_;
    return sqrt(scalar_dot_product($rv, $rv));
}

sub norm_vector_length2($$) {
    my ($vx,$vy) = @_;
    return sqrt(scalar_dot_product2($vx, $vy, $vx, $vy));
}

sub paint_user_points($$) {
    my ($rh,$show) = @_;
    my ($tllat,$tllon,$bllat,$bllon,$brlat,$brlon,$trlat,$trlon);
    $tllat = ${$rh}{'tl_lat'};
    $tllon = ${$rh}{'tl_lon'};
    $bllat = ${$rh}{'bl_lat'};
    $bllon = ${$rh}{'bl_lon'};
    $brlat = ${$rh}{'br_lat'};
    $brlon = ${$rh}{'br_lon'};
    $trlat = ${$rh}{'tr_lat'};
    $trlon = ${$rh}{'tr_lon'};
    my ($minlat,$maxlat,$minlon,$maxlon);
    my ($latdegs,$londegs,$sqwid,$sqhgt);
    $minlat = $bad_latlon;
    $maxlat = -$bad_latlon;
    $minlon = $bad_latlon;
    $maxlon = -$bad_latlon;
    my ($u_lat,$u_lon,$t_lat,$t_lon,$i,$cnt,$ru,$clat,$clon);
    $maxlat = $tllat if ($tllat > $maxlat);
    $maxlat = $bllat if ($bllat > $maxlat);
    $maxlat = $brlat if ($brlat > $maxlat);
    $maxlat = $trlat if ($trlat > $maxlat);
    $minlat = $tllat if ($tllat < $minlat);
    $minlat = $bllat if ($bllat < $minlat);
    $minlat = $brlat if ($brlat < $minlat);
    $minlat = $trlat if ($trlat < $minlat);
    $maxlon = $tllon if ($tllon > $maxlon);
    $maxlon = $bllon if ($bllon > $maxlon);
    $maxlon = $brlon if ($brlon > $maxlon);
    $maxlon = $trlon if ($trlon > $maxlon);
    $minlon = $tllon if ($tllon < $minlon);
    $minlon = $bllon if ($bllon < $minlon);
    $minlon = $brlon if ($brlon < $minlon);
    $minlon = $trlon if ($trlon < $minlon);
    if (defined ${$rh}{'user_points'}) {
        $ru = ${$rh}{'user_points'};
        $cnt = scalar @{$ru};
        for ($i = 0; $i < $cnt; $i++) {
            $u_lat = ${$ru}[$i][0];
            $u_lon = ${$ru}[$i][1];
            $t_lat = ${$ru}[$i][2];
            $t_lon = ${$ru}[$i][3];
            $maxlat = $u_lat if ($u_lat > $maxlat);
            $minlat = $u_lat if ($u_lat < $minlat);
            $maxlon = $u_lon if ($u_lon > $maxlon);
            $minlon = $u_lon if ($u_lon < $minlon);
        }
    }
    my $key = '';
    my $rcnt = 0;
    my $pcnt = 0;
    my ($rrwys,$rpatts);
    my ($elat1,$elon1,$elat2,$elon2);
    my ($plat11,$plon11,$plat12,$plon12,$plat13,$plon13,$plat21,$plon21);
    if ((defined ${$rh}{'runways'})&&(defined ${$rh}{'pattern'})&&(defined ${$rh}{'airport'})) {
        $rrwys = ${$rh}{'runways'};
        $rpatts = ${$rh}{'pattern'};
        $key = ${$rh}{'airport'};
        $rcnt = scalar @{$rrwys};
        $pcnt = scalar @{$rpatts};
        prt("Adding $rcnt runways, and $pcnt patterns...\n");
        for ($i = 0; $i < $rcnt; $i++) {
            $elat1 = ${$rrwys}[$i][$RW_LLAT];
            $elon1 = ${$rrwys}[$i][$RW_LLON];
            $elat2 = ${$rrwys}[$i][$RW_RLAT];
            $elon2 = ${$rrwys}[$i][$RW_RLON];
            set_min_max(\$maxlat,\$minlat,\$maxlon,\$minlon,$elat1,$elon1);
            set_min_max(\$maxlat,\$minlat,\$maxlon,\$minlon,$elat2,$elon2);
        }
        for ($i = 0; $i < $pcnt; $i++) {
            $plat11 = ${$rpatts}[$i][0];
            $plon11 = ${$rpatts}[$i][1];
            $plat12 = ${$rpatts}[$i][2];
            $plon12 = ${$rpatts}[$i][3];
            $plat13 = ${$rpatts}[$i][4];
            $plon13 = ${$rpatts}[$i][5];
            $plat21 = ${$rpatts}[$i][6];
            $plon21 = ${$rpatts}[$i][7];
            set_min_max(\$maxlat,\$minlat,\$maxlon,\$minlon,$plat11,$plon11);
            set_min_max(\$maxlat,\$minlat,\$maxlon,\$minlon,$plat12,$plon12);
            set_min_max(\$maxlat,\$minlat,\$maxlon,\$minlon,$plat13,$plon13);
            set_min_max(\$maxlat,\$minlat,\$maxlon,\$minlon,$plat21,$plon21);
        }
    }
    ${$rh}{'max_lat'} = $maxlat;
    ${$rh}{'min_lat'} = $minlat;
    ${$rh}{'max_lon'} = $maxlon;
    ${$rh}{'min_lon'} = $minlon;
    my $lon_factor = 2;
    $latdegs = $maxlat - $minlat;
    $londegs = ($maxlon - $minlon) * $lon_factor;
    ${$rh}{'lon_degs'} = $londegs;
    ${$rh}{'lat_degs'} = $latdegs;
    $sqhgt = int(($latdegs * 10000) + 0.5);
    $sqwid = int(($londegs * 10000) + 0.5);
    ${$rh}{'sq_wid'} = $sqwid;
    ${$rh}{'sq_hgt'} = $sqhgt;
    my $targ_wid = 600;
    my $ratio = $sqwid / $sqhgt;
        if ($ratio > 1) {   # width > height
            $sqwid = $targ_wid; # set target width
            $sqhgt = int($targ_wid / $ratio); # and calculate NEW height
	    } else {
			$sqwid = int($targ_wid * $ratio); # calculate width
			$sqhgt = $targ_wid; # and set target width
        }
    ${$rh}{'sq_wid_adj'} = $sqwid;
    ${$rh}{'sq_hgt_adj'} = $sqhgt;
    my ($w_dpp,$h_dpp,$w_ind1,$h_ind1,$w_ind2,$h_ind2,$w_ind3,$h_ind3,$w_ind4,$h_ind4,$msg);
    my ($h_indu,$w_indu,$h_indt,$w_indt);
    my ($x_txt,$y_txt,$txt);
    $w_dpp = ($sqwid / $londegs) * $lon_factor;
    $h_dpp = $sqhgt / $latdegs;
    ${$rh}{'w_dpp'} = $w_dpp;
    ${$rh}{'h_dpp'} = $h_dpp;
    ${$rh}{'rmsg'} = \$msg;
    $msg = "convert -size ${sqwid}x${sqhgt} xc:wheat -fill white ";
    $msg .= "-pointsize 12 -strokewidth 0.5 ";
    if (length($key) && $rcnt) {
        if ($pcnt) {
            ${$rh}{'-stroke'} = "SlateGray";
            $msg .= "-stroke SlateGray ";
            for ($i = 0; $i < $pcnt; $i++) {
                $plat11 = ${$rpatts}[$i][0];
                $plon11 = ${$rpatts}[$i][1];
                $plat12 = ${$rpatts}[$i][2];
                $plon12 = ${$rpatts}[$i][3];
                $plat13 = ${$rpatts}[$i][4];
                $plon13 = ${$rpatts}[$i][5];
                $plat21 = ${$rpatts}[$i][6];
                $plon21 = ${$rpatts}[$i][7];
                $clat   = ${$rpatts}[$i][8];
                $clon   = ${$rpatts}[$i][9];
                add_img_line($rh,$plat11,$plon11,$plat12,$plon12,1);
                add_img_line($rh,$plat12,$plon12,$plat13,$plon13,1);
                add_img_line($rh,$plat13,$plon13,$plat21,$plon21,1);
                add_img_line($rh,$plat21,$plon21,$plat11,$plon11,1);
                if ($switch_circuit && ($i == 0)) {
                    add_arrow_to_center($rh,$plat11,$plon11,$plat12,$plon12);
                    add_arrow_to_center($rh,$plat12,$plon12,$plat13,$plon13);
                    add_arrow_to_center($rh,$plat13,$plon13,$plat21,$plon21);
                    add_arrow_to_center($rh,$clat,$clon,$plat11,$plon11);
                    add_arrow_to_center($rh,$plat21,$plon21,$clat,$clon);
                } elsif (!$switch_circuit && ($i == 1)) {
                    add_arrow_to_center($rh,$plat11,$plon11,$plat12,$plon12);
                    add_arrow_to_center($rh,$plat12,$plon12,$plat13,$plon13);
                    add_arrow_to_center($rh,$plat13,$plon13,$plat21,$plon21);
                    add_arrow_to_center($rh,$plat21,$plon21,$clat,$clon);
                    add_arrow_to_center($rh,$clat,$clon,$plat11,$plon11);
                }
            }
        }
        $msg .= "-stroke blue ";
        for ($i = 0; $i < $rcnt; $i++) {
            $elat1 = ${$rrwys}[$i][$RW_LLAT];
            $elon1 = ${$rrwys}[$i][$RW_LLON];
            $elat2 = ${$rrwys}[$i][$RW_RLAT];
            $elon2 = ${$rrwys}[$i][$RW_RLON];
            $w_ind1 = int((($elon1 - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
            $h_ind1 = int((($elat1 - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
            $h_ind1 = $sqhgt - $h_ind1;
            $h_ind1 += 1 if ($h_ind1 == 0);
            $w_ind1 += 1 if ($w_ind1 == 0);
            $h_ind1 -= 1 if ($h_ind1 == $sqhgt);
            $w_ind1 -= 1 if ($w_ind1 == $sqwid);
            $msg .= "-draw \"circle ".($w_ind1-1).",$h_ind1 ".($w_ind1+1).",$h_ind1\" ";
            $w_ind2 = int((($elon2 - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
            $h_ind2 = int((($elat2 - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
            $h_ind2 = $sqhgt - $h_ind2;
            $h_ind2 += 1 if ($h_ind2 == 0);
            $w_ind2 += 1 if ($w_ind2 == 0);
            $h_ind2 -= 1 if ($h_ind2 == $sqhgt);
            $w_ind2 -= 1 if ($w_ind2 == $sqwid);
            $msg .= "-draw \"circle ".($w_ind2-1).",$h_ind2 ".($w_ind2+1).",$h_ind2\" ";
            $msg .= "-draw \"line $w_ind1,$h_ind1 $w_ind2,$h_ind2\" ";
            my $clat = ${$rrwys}[$i][$RW_CLAT];
            my $clon = ${$rrwys}[$i][$RW_CLON];
            draw_text_at_latlon($rh,$clat,$clon,"YGIL",0);
        }
    }
    $msg .= "-stroke black ";
    $x_txt = $sqwid - 100;
    $y_txt = 20;
    draw_text_at_pos($rh,$x_txt,$y_txt,"Wind: SSE 8Kt",0);
    $w_ind1 = int((($tllon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind1 = int((($tllat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind1 = $sqhgt - $h_ind1;
    $h_ind1 += 1 if ($h_ind1 == 0);
    $w_ind1 += 1 if ($w_ind1 == 0);
    $h_ind1 -= 1 if ($h_ind1 == $sqhgt);
    $w_ind1 -= 1 if ($w_ind1 == $sqwid);
    $msg .= "-draw \"circle ".($w_ind1-1).",$h_ind1 ".($w_ind1+1).",$h_ind1\" ";
    $w_ind2 = int((($bllon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind2 = int((($bllat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind2 = $sqhgt - $h_ind2;
    $h_ind2 += 1 if ($h_ind2 == 0);
    $w_ind2 += 1 if ($w_ind2 == 0);
    $h_ind2 -= 1 if ($h_ind2 == $sqhgt);
    $w_ind2 -= 1 if ($w_ind2 == $sqwid);
    $msg .= "-draw \"circle ".($w_ind2-1).",$h_ind2 ".($w_ind2+1).",$h_ind2\" ";
    $w_ind3 = int((($brlon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind3 = int((($brlat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind3 = $sqhgt - $h_ind3;
    $h_ind3 += 1 if ($h_ind3 == 0);
    $w_ind3 += 1 if ($w_ind3 == 0);
    $h_ind3 -= 1 if ($h_ind3 == $sqhgt);
    $w_ind3 -= 1 if ($w_ind3 == $sqwid);
    $msg .= "-draw \"circle ".($w_ind3-1).",$h_ind3 ".($w_ind3+1).",$h_ind3\" ";
    $w_ind4 = int((($trlon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
    $h_ind4 = int((($trlat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
    $h_ind4 = $sqhgt - $h_ind4;
    $h_ind4 += 1 if ($h_ind4 == 0);
    $w_ind4 += 1 if ($w_ind4 == 0);
    $h_ind4 -= 1 if ($h_ind4 == $sqhgt);
    $w_ind4 -= 1 if ($w_ind4 == $sqwid);
    $msg .= "-draw \"circle ".($w_ind4-1).",$h_ind4 ".($w_ind4+1).",$h_ind4\" ";
    if (!$use_pattern) {
        $msg .= "-draw \"line $w_ind1,$h_ind1 $w_ind2,$h_ind2\" ";
        $msg .= "-draw \"line $w_ind2,$h_ind2 $w_ind3,$h_ind3\" ";
        $msg .= "-draw \"line $w_ind3,$h_ind3 $w_ind4,$h_ind4\" ";
        $msg .= "-draw \"line $w_ind4,$h_ind4 $w_ind1,$h_ind1\" ";
    }
    if (defined ${$rh}{'user_points'}) {
        $ru = ${$rh}{'user_points'};
        $cnt = scalar @{$ru};
        for ($i = 0; $i < $cnt; $i++) {
            $u_lat = ${$ru}[$i][0];
            $u_lon = ${$ru}[$i][1];
            $t_lat = ${$ru}[$i][2];
            $t_lon = ${$ru}[$i][3];
            $w_indu = int((($u_lon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
            $h_indu = int((($u_lat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
            $h_indu = $sqhgt - $h_indu;
            $h_indu += 1 if ($h_indu == 0);
            $w_indu += 1 if ($w_indu == 0);
            $h_indu -= 1 if ($h_indu == $sqhgt);
            $w_indu -= 1 if ($w_indu == $sqwid);
            $msg .= "-stroke blue ";
            $msg .= "-draw \"circle ".($w_indu-1).",$h_indu ".($w_indu+1).",$h_indu\" ";
            if ($add_text_count) {
                $txt = $i + 1;
                $x_txt = $w_indu + 3;
                $y_txt = $h_indu + 4;
                $x_txt += 3 if (($x_txt - 3) <= 0);
                $x_txt -= 3 if (($x_txt + 3) >= $sqwid);
                $y_txt -= 5 if (($y_txt + 5) >= $sqhgt);
                $y_txt += 5 if (($y_txt - 5) <= 0);
                $msg .= "-draw \"text $x_txt,$y_txt '$txt'\" ";
            }
            $w_indt = int((($t_lon - $minlon) * $w_dpp) + 0.5); # get degrees/pixels from left edge
            $h_indt = int((($t_lat - $minlat) * $h_dpp) + 0.5); # get degrees/pixels from bottom edge
            $h_indt = $sqhgt - $h_indt;
            $h_indt += 1 if ($h_indt == 0);
            $w_indt += 1 if ($w_indt == 0);
            $h_indt -= 1 if ($h_indt == $sqhgt);
            $w_indt -= 1 if ($w_indt == $sqwid);
            $msg .= "-draw \"circle ".($w_indu-1).",$h_indu ".($w_indu+1).",$h_indu\" ";
            $msg .= "-stroke red ";
            add_img_line($rh,$u_lat,$u_lon,$t_lat,$t_lon,0);
        }
    }
    $msg .= "$graf_file\n";
    $msg .= "imdisplay $graf_file\n";
    write2file($msg,$graf_bat);
    prt("Written $graf_bat\n");
    if ($show) {
        set_lat_stg(\$maxlat);
        set_lat_stg(\$minlat);
        set_lon_stg(\$maxlon);
        set_lon_stg(\$minlon);
        prt("Square wid=$londegs hgt=$latdegs ${sqwid}X${sqhgt}\n");
        prt("TL $maxlat,$minlon\n");
        prt("BL $minlat,$minlon\n");
        prt("BR $minlat,$maxlon\n");
        prt("TR $maxlat,$maxlon\n");
    }
}

sub point_in_circuit($$$$) {
    my ($rh,$lat,$lon,$rres) = @_;
    my ($tl_lat,$tl_lon,$bl_lat,$bl_lon,$br_lat,$br_lon,$tr_lat,$tr_lon);
    my $ret = 0;
    $tl_lat = ${$rh}{'tl_lat'};
    $tl_lon = ${$rh}{'tl_lon'};
    $bl_lat = ${$rh}{'bl_lat'};
    $bl_lon = ${$rh}{'bl_lon'};
    $br_lat = ${$rh}{'br_lat'};
    $br_lon = ${$rh}{'br_lon'};
    $tr_lat = ${$rh}{'tr_lat'};
    $tr_lon = ${$rh}{'tr_lon'};
    my $res = '';
    if (Point_Inside_Triange($lat,$lon,$tl_lat,$tl_lon, $bl_lat,$bl_lon, $br_lat,$br_lon)) {
        $res = "in circuit (1st tri)";
        $ret = 1;
    } elsif (Point_Inside_Triange($lat,$lon,$tl_lat,$tl_lon, $tr_lat,$tr_lon, $br_lat,$br_lon)) {
        $res = "in curcuit (2nd tri)";
        $ret = 1;
    } else {
        $res = "NOT in circuit.";
    }
    ${$rres} = $res;
    return $ret;
}

#######################################################################################
# A good attempt at choosing a circuit target
#######################################################################################
sub get_closest_ptset($$$$$$) {
    my ($rch,$slat,$slon,$rpt,$rlat,$rlon) = @_;
    set_distances_bearings($rch,$slat,$slon,"Initial position");
    my $pt = "TL";
    my $dist = ${$rch}{'tl_dist'};  # distance to top-left
    my $tlat = ${$rch}{'tl_lat'};
    my $tlon = ${$rch}{'tl_lon'};
    if (${$rch}{'bl_dist'} < $dist) {  # distance to bottom left
        # BOTTOM LEFT
        $dist = ${$rch}{'bl_dist'};
        $pt = "BL";
        $tlat = ${$rch}{'bl_lat'};
        $tlon = ${$rch}{'bl_lon'};
    }
    if (${$rch}{'br_dist'} < $dist) {  # distance to bottom right
        # BOTTOM RIGHT
        $dist = ${$rch}{'br_dist'};
        $pt = "BR";
        $tlat = ${$rch}{'br_lat'};
        $tlon = ${$rch}{'br_lon'};
    }
    if (${$rch}{'tr_dist'} < $dist) {  # distance to top right
        # TOP RIGHT
        $dist = ${$rch}{'tr_dist'};
        $pt = "TR";
        $tlat = ${$rch}{'tr_lat'};
        $tlon = ${$rch}{'tr_lon'};
    }
    ${$rpt} = $pt;
    ${$rlat} = $tlat;
    ${$rlon} = $tlon;
}

# This will return the next target when joining a circuit from in or out of current circuit
sub get_next_in_circuit_targ($$) {
    my ($slat,$slon) = @_;
    my $rch = $ref_circuit_hash;

    # get_closest_ptset($$$$$$)
    my ($pt,$tlat,$tlon);
    get_closest_ptset($rch,$slat,$slon,\$pt,\$tlat,\$tlon);

    my ($nlat,$nlon,$nxps);
    ## get next ptset
    $nxps = get_next_pointset($rch,$pt,\$nlat,\$nlon,0);
    ${$rch}{'target_lat'} = $nlat;   # $targ_lat;
    ${$rch}{'target_lon'} = $nlon;   # $targ_lon;

    ### This seems the BEST ;=))
    my ($clat,$clon);
    $clat = ($tlat + $nlat) / 2;
    $clon = ($tlon + $nlon) / 2;
    ### $next_targ_lat = $clat;
    ### $next_targ_lon = $clon;
    ## prt("Set target lat, lon $clat,$clon\n");
    my ($distm,$az1,$az2);
    
    fg_geo_inverse_wgs_84 ($slat,$slon,$clat,$clon,\$az1,\$az2,\$distm);

    ${$rch}{'user_lat'} = $slat;
    ${$rch}{'user_lon'} = $slon;
    # ${$rch}{'target_lat'} = $clat;   # $targ_lat;
    # ${$rch}{'target_lon'} = $clon;   # $targ_lon;
    ${$rch}{'target_hgd'} = $az1;
    ${$rch}{'target_dist'} = $distm;
    ${$rch}{'targ_ptset'} = $nxps;   # current chosen point = TARGET point
    ${$rch}{'prev_ptset'} = $pt;   # previous to get TARGET TRACK

    my $distnm = get_dist_stg_nm($distm);
    set_hdg_stg(\$az1);
    #    Suggest HEAD for
    # prt("Suggest head for $clat,$clon, on $az1, $distnm, prev $pt, next $nxps\n");
    prt("Suggest head for $nlat,$nlon, on $az1, $distnm, prev $pt, next $nxps\n");

}

#######################################################################################

# start of a circuit
# given current postion, choose the BEST postion to head for
# Decide if inside the circuit, or outside
sub process_lat_lon($$$$) {
    my ($rh,$lat,$lon,$msg) = @_;
    my $res = '';
    my $ptinc = point_in_circuit($rh,$lat,$lon,\$res);
    prt("\nSolving lat=$lat, lon=$lon $msg, $res \n");
    my ($tlat,$tlon,$az1,$az2,$dist);
    set_distances_bearings($rh,$lat,$lon,$msg);
    my $min_dist = 12000 * 1700;
    my $hdto = 'unsolved';
    my $targ_lon = $bad_latlon;
    my $targ_lat = $bad_latlon;
    my $targ_dist = 1000000000;

    # Aim is to set these values
    #${$rh}{'user_lat'} = $lat;
    #${$rh}{'user_lon'} = $lon;
    #${$rh}{'target_lat'} = $targ_lat;
    #${$rh}{'target_lon'} = $targ_lon;
    #${$rh}{'target_hgd'} = $hdg;
    #${$rh}{'target_dist'} = $dist;
    #${$rh}{'targ_ptset'} = $ptset;   # current chosen point = TARGET point
    #${$rh}{'prev_ptset'} = get_prev_pointset($ptset);   # previous to get TARGET TRACK

    my ($hdg,$ptset);
    $tlat = ${$rh}{'tl_lat'}; # = -31.684063;
    $tlon = ${$rh}{'tl_lon'}; # = 148.614120;
    $az1  = ${$rh}{'tl_az1'};
    $az2  = ${$rh}{'tl_az2'};
    $dist = ${$rh}{'tl_dist'};
    $res = 0;
    $ptset = "TL";
        $min_dist = $dist;
        $hdto = "to top left ($res)";
        $hdg = $az1;
        $targ_lat = $tlat;
        $targ_lon = $tlon;
        $targ_dist = $dist;
    $tlat = ${$rh}{'bl_lat'}; # = -31.684063;
    $tlon = ${$rh}{'bl_lon'}; # = 148.614120;
    $az1  = ${$rh}{'bl_az1'};
    $az2  = ${$rh}{'bl_az2'};
    $dist = ${$rh}{'bl_dist'};
    $res = dist_less_or_equal5($dist,$min_dist);
    if ($res) {
        $min_dist = $dist;
        $hdto = "to bottom left ($res)";
        $hdg = $az1;
        $targ_lat = $tlat;
        $targ_lon = $tlon;
        $targ_dist = $dist;
        $ptset = "BL";
    }
    $tlat = ${$rh}{'br_lat'}; # = -31.684063;
    $tlon = ${$rh}{'br_lon'}; # = 148.614120;
    $az1  = ${$rh}{'br_az1'};
    $az2  = ${$rh}{'br_az2'};
    $dist = ${$rh}{'br_dist'};
    $res = dist_less_or_equal5($dist,$min_dist);
    if ($res) {
        $min_dist = $dist;
        $hdto = "to bottom right ($res)";
        $hdg = $az1;
        $targ_lat = $tlat;
        $targ_lon = $tlon;
        $targ_dist = $dist;
        $ptset = "BR";
    }
    $tlat = ${$rh}{'tr_lat'}; # = -31.684063;
    $tlon = ${$rh}{'tr_lon'}; # = 148.614120;
    $az1  = ${$rh}{'tr_az1'};
    $az2  = ${$rh}{'tr_az2'};
    $dist = ${$rh}{'tr_dist'};
    $res = dist_less_or_equal5($dist,$min_dist);
    if ($res) {
        $min_dist = $dist;
        $hdto = "to top right ($res)";
        $hdg = $az1;
        $targ_lat = $tlat;
        $targ_lon = $tlon;
        $targ_dist = $dist;
        $ptset = "TR";
    }
    $tlat = ${$rh}{'tl_lat'}; # = -31.684063;
    $tlon = ${$rh}{'tl_lon'}; # = 148.614120;
    $az1  = ${$rh}{'tl_az1'};
    $az2  = ${$rh}{'tl_az2'};
    $dist = ${$rh}{'tl_dist'};
    $res = dist_less_or_equal5($dist,$min_dist);
    if ($res) {
        $min_dist = $dist;
        $hdto = "to top left ($res)";
        $hdg = $az1;
        $targ_lat = $tlat;
        $targ_lon = $tlon;
        $targ_dist = $dist;
        $ptset = "TL";
    }
    if ($ptinc) {
        $tlat = ${$rh}{'bl_lat'}; # = -31.684063;
        $tlon = ${$rh}{'bl_lon'}; # = 148.614120;
        $az1  = ${$rh}{'bl_az1'};
        $az2  = ${$rh}{'bl_az2'};
        $dist = ${$rh}{'bl_dist'};
        $hdto = "in circuit ($ptinc)";
        $hdg = $az1;
        $targ_lat = $tlat;
        $targ_lon = $tlon;
        $targ_dist = $dist;
        $ptset = "BL";
    }

    if ($use_new_getcpt) {
        get_next_in_circuit_targ($lat,$lon);
        # $lat = ${$rh}{'user_lat'};
        # $lon = ${$rh}{'user_lon'};
        $targ_lat = ${$rh}{'target_lat'};
        $targ_lon = ${$rh}{'target_lon'};
        $hdg      = ${$rh}{'target_hgd'};
        $dist     = ${$rh}{'target_dist'};
        $ptset    = ${$rh}{'targ_ptset'};   # current chosen point = TARGET point
        my $ppt   = ${$rh}{'prev_ptset'};   # previous to get TARGET TRACK
        $targ_dist = $dist;
    } else {
        prt("Set target_lat, lon $targ_lat,$targ_lon\n");
        ${$rh}{'user_lat'} = $lat;
        ${$rh}{'user_lon'} = $lon;
        ${$rh}{'target_lat'} = $targ_lat;
        ${$rh}{'target_lon'} = $targ_lon;
        ${$rh}{'target_hgd'} = $hdg;
        ${$rh}{'target_dist'} = $dist;
        ${$rh}{'targ_ptset'} = $ptset;   # current chosen point = TARGET point
        ${$rh}{'prev_ptset'} = get_prev_pointset($ptset);   # previous to get TARGET TRACK
    }
    set_most_values_plus($rh,1,$lat,$lon,$targ_lat,$targ_lon);

    set_hdg_stg3(\$hdg);
    set_int_dist_stg5(\$targ_dist);
    #set_lat_stg(\$targ_lat);
    #set_lon_stg(\$targ_lon);
    prt("Heading: $hdto, hdg=$hdg, to $targ_lat,$targ_lon, at $targ_dist m.\n");
}

sub scalar_dot_product($$) {
    my ($rv1,$rv2) = @_;
    return ${$rv1}[0] * ${$rv2}[0] + ${$rv1}[1] * ${$rv2}[1] + ${$rv1}[2] * ${$rv2}[2];
}

sub scalar_dot_product2($$$$) {
    my ($v1x,$v1y,$v2x,$v2y) = @_;
    return ($v1x * $v2x) + ($v1y * $v2y);
}

sub set_circuit_values($$) {
    my ($rch,$show) = @_;
    my ($az1,$az2,$dist);
    my ($dwd,$dwa,$bsd,$bsa,$rwd,$rwa,$crd,$cra);
    my ($tllat,$tllon,$bllat,$bllon,$brlat,$brlon,$trlat,$trlon);
    my ($elat1,$elon1);  # nearest end

    fg_geo_inverse_wgs_84 (${$rch}{'tl_lat'},${$rch}{'tl_lon'},${$rch}{'bl_lat'},${$rch}{'bl_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'l1_az1'} = $az1;
    ${$rch}{'l1_az2'} = $az2;
    ${$rch}{'l1_dist'} = $dist;
    ${$rch}{'TL'} = [$az1,$az2,$dist];

    fg_geo_inverse_wgs_84 (${$rch}{'bl_lat'},${$rch}{'bl_lon'},${$rch}{'br_lat'},${$rch}{'br_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'l2_az1'} = $az1;
    ${$rch}{'l2_az2'} = $az2;
    ${$rch}{'l2_dist'} = $dist;
    ${$rch}{'BL'} = [$az1,$az2,$dist];

    fg_geo_inverse_wgs_84 (${$rch}{'br_lat'},${$rch}{'br_lon'},${$rch}{'tr_lat'},${$rch}{'tr_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'l3_az1'} = $az1;
    ${$rch}{'l3_az2'} = $az2;
    ${$rch}{'l3_dist'} = $dist;
    ${$rch}{'BR'} = [$az1,$az2,$dist];

    fg_geo_inverse_wgs_84 (${$rch}{'tr_lat'},${$rch}{'tr_lon'},${$rch}{'tl_lat'},${$rch}{'tl_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'l4_az1'} = $az1;
    ${$rch}{'l4_az2'} = $az2;
    ${$rch}{'l4_dist'} = $dist;
    ${$rch}{'TR'} = [$az1,$az2,$dist];

    ${$rch}{'rwy_ref'} = $active_ref_rwys;
    ${$rch}{'rwy_off'} = $active_off_rwys;

    # ================================================
    $tllat = ${$rch}{'tl_lat'};
    $tllon = ${$rch}{'tl_lon'};
    $bllat = ${$rch}{'bl_lat'};
    $bllon = ${$rch}{'bl_lon'};
    $brlat = ${$rch}{'br_lat'};
    $brlon = ${$rch}{'br_lon'};
    $trlat = ${$rch}{'tr_lat'};
    $trlon = ${$rch}{'tr_lon'};
    my $msg = "# YGIL circuit\n";
    $msg .= "[YGIL]\n";
    $msg .= "P1=$tllat,$tllon\n";
    $msg .= "P2=$bllat,$bllon\n";
    $msg .= "P3=$brlat,$brlon\n";
    $msg .= "P4=$trlat,$trlon\n";
    $msg .= "direction=anticlockwise\n";
    write2file($msg,$tmp_circuit);
    prt("Circuit written to $tmp_circuit file\n");
    # ================================================

    if ($show) {
        ### my ($elat2,$elon2);
        ### my ($az11,$az21,$dist1);

        $tllat = ${$rch}{'tl_lat'};
        $tllon = ${$rch}{'tl_lon'};
        $bllat = ${$rch}{'bl_lat'};
        $bllon = ${$rch}{'bl_lon'};
        $brlat = ${$rch}{'br_lat'};
        $brlon = ${$rch}{'br_lon'};
        $trlat = ${$rch}{'tr_lat'};
        $trlon = ${$rch}{'tr_lon'};

        # extract values
        $dwa = ${$rch}{'l1_az1'};
        $dwd = ${$rch}{'l1_dist'};
        $bsd = ${$rch}{'l2_dist'};
        $bsa = ${$rch}{'l2_az1'};
        $rwd = ${$rch}{'l3_dist'};
        $rwa = ${$rch}{'l3_az1'};
        $crd = ${$rch}{'l4_dist'};
        $cra = ${$rch}{'l4_az1'};

        # get NEAREST runway END
        $elat1 = ${$active_ref_rwys}[$active_off_rwys][$RW_LLAT];
        $elon1 = ${$active_ref_rwys}[$active_off_rwys][$RW_LLON];

        fg_geo_inverse_wgs_84 (${$rch}{'br_lat'},${$rch}{'br_lon'},$elat1,$elon1,\$az1,\$az2,\$dist);

        # get OTHER runway END
        # $elat2 = ${$active_ref_rwys}[$active_off_rwys][$RW_RLAT];
        # $elon2 = ${$active_ref_rwys}[$active_off_rwys][$RW_RLON];
        ### fg_geo_inverse_wgs_84 (${$rch}{'br_lat'},${$rch}{'br_lon'},$elat2,$elon2,\$az11,\$az21,\$dist1);

        # set for display - values DESTROYED for calculations
        # ===================================================

        set_dist_stg(\$dist);
        set_int_stg(\$az1);
        ### set_dist_stg(\$dist1);

        set_lat_stg(\$tllat);
        set_lat_stg(\$bllat);
        set_lat_stg(\$brlat);
        set_lat_stg(\$trlat);
        set_lon_stg(\$tllon);
        set_lon_stg(\$bllon);
        set_lon_stg(\$brlon);
        set_lon_stg(\$trlon);

        prt("Set, show circuit...\nTL $tllat,$tllon\nBL ".
            "$bllat,$bllon\nBR ".
            "$brlat,$brlon\nTR ".
            "$trlat,$trlon\n");

        set_int_dist_stg5(\$dwd);
        set_hdg_stg3(\$dwa);
        set_int_dist_stg5(\$bsd);
        set_hdg_stg3(\$bsa);
        set_int_dist_stg5(\$rwd);
        set_hdg_stg3(\$rwa);
        set_int_dist_stg5(\$crd);
        set_hdg_stg3(\$cra);

        prt("l1 $dwd m, on $dwa (tl2bl) - downwind, turn $bsa to base\n");
        prt("l2 $bsd m, on $bsa (bl2br) - base,     turn $rwa to final $active_key $active_runway $dist on $az1\n");
        prt("l3 $rwd m, on $rwa (br2tr) - runway,   turn $cra to cross\n");
        prt("l4 $crd m, on $cra (tr2tl) - cross,    turn $dwa to downwind\n");

    }
}

# set current distances
# circuit decribed as
# top left tl    top right tr
#      ---------------
#      |             |
#           ...
#      |             |
#      ---------------
# bottom left bl bottom right br
sub set_distances_bearings($$$$) {
    my ($rh,$lat,$lon,$msg) = @_;
    ${$rh}{'usr_lat'} = $lat;
    ${$rh}{'usr_lon'} = $lon;
    ${$rh}{'usr_msg'} = $msg;
    my ($tlat,$tlon);
    my ($az1,$az2,$dist);
    $msg = '';  # start a DEBUG message
    $tlat = ${$rh}{'tl_lat'}; # = -31.684063;
    $tlon = ${$rh}{'tl_lon'}; # = 148.614120;
    fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
    ${$rh}{'tl_az1'} = $az1;
    ${$rh}{'tl_az2'} = $az2;
    ${$rh}{'tl_dist'} = $dist;  # distance to top-left
    set_int_dist_stg5(\$dist);
    $msg .= "TL $dist ";
    $tlat = ${$rh}{'bl_lat'}; # = -31.723495;
    $tlon = ${$rh}{'bl_lon'}; # = 148.633003;
    fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
    ${$rh}{'bl_az1'} = $az1;
    ${$rh}{'bl_az2'} = $az2;
    ${$rh}{'bl_dist'} = $dist;  # distance to bottom left
    set_int_dist_stg5(\$dist);
    $msg .= "BL $dist ";
    $tlat = ${$rh}{'br_lat'}; # = -31.716778;
    $tlon = ${$rh}{'br_lon'}; # = 148.666992;
    fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
    ${$rh}{'br_az1'} = $az1;    # from 'test' to BR point
    ${$rh}{'br_az2'} = $az2;
    ${$rh}{'br_dist'} = $dist;  # distance to bottom right
    set_int_dist_stg5(\$dist);
    $msg .= "BR $dist ";
    $tlat = ${$rh}{'tr_lat'}; # = -31.672960;
    $tlon = ${$rh}{'tr_lon'}; # = 148.649139;
    fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
    ${$rh}{'tr_az1'} = $az1;
    ${$rh}{'tr_az2'} = $az2;
    ${$rh}{'tr_dist'} = $dist;  # distance to top right
    set_int_dist_stg5(\$dist);
    $msg .= "TR $dist ";
    prt("Distances: $msg\n");
}

sub set_hdg_stg3($) {
    my $r = shift;
    set_int_stg($r);
    my $r3 = sprintf("%3d",${$r});
    ${$r} = $r3;
}

sub set_int_dist_stg5($) {
    my $r = shift;
    set_int_stg($r);
    my $r5 = sprintf("%5d",${$r});
    ${$r} = $r5;
}

sub set_min_max($$$$$$) {
    my ($rmaxlat,$rminlat,$rmaxlon,$rminlon,$lat,$lon) = @_;
    ${$rmaxlat} = $lat if ($lat > ${$rmaxlat});
    ${$rminlat} = $lat if ($lat < ${$rminlat});
    ${$rmaxlon} = $lon if ($lon > ${$rmaxlon});
    ${$rminlon} = $lon if ($lon < ${$rminlon});
}

sub set_most_values_plus($$$$$$) {
    my ($rh,$show,$u_lat,$u_lon,$t_lat,$t_lon) = @_;
    if (!defined ${$rh}{'user_points'}) {
        ${$rh}{'user_points'} = [];
    }
    my $ru = ${$rh}{'user_points'};
    push(@{$ru}, [$u_lat,$u_lon,$t_lat,$t_lon]);
}


# ===============================================
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
    my ($rh,$ptset,$rlat,$rlon,$show) = @_;
    my $nxps = 'none';
    my ($nlat,$nlon);
    if ($ptset eq 'TL') {
        $nxps = 'BL';
        $nlat = ${$rh}{'bl_lat'};
        $nlon = ${$rh}{'bl_lon'};
    } elsif ($ptset eq 'BL') {
        $nxps = 'BR';
        $nlat = ${$rh}{'br_lat'};
        $nlon = ${$rh}{'br_lon'};
    } elsif ($ptset eq 'BR') {
        $nxps = 'TR';
        $nlat = ${$rh}{'tr_lat'};
        $nlon = ${$rh}{'tr_lon'};
    } elsif ($ptset eq 'TR') {
        $nxps = 'TL';
        $nlat = ${$rh}{'tl_lat'};
        $nlon = ${$rh}{'tl_lon'};
    } else {
        prtw("WARNING: point [$ptset] set NOT one of 'TL', 'BR', 'TR', or 'TL'!");
    }
    ${$rlat} = $nlat;
    ${$rlon} = $nlon;
    prtt("get_next_pointset: from $ptset to $nxps\n") if ($show);
    return $nxps;
}

sub get_prev_pointset($) {
    my ($ptset) = @_;
    my $prevps = 'none';
    if ($ptset eq 'TL') {
        $prevps = 'TR';
    } elsif ($ptset eq 'BL') {
        $prevps = 'TL';
    } elsif ($ptset eq 'BR') {
        $prevps = 'BL';
    } elsif ($ptset eq 'TR') {
        $prevps = 'BR';
    } else {
        prtw("WARNING: point [$ptset] set NOT one of 'TL', 'BR', 'TR', or 'TL'!");
    }
    return $prevps;
}


# $circuit_mode is ON
# $mag_deviation = ($curr_hdg - $curr_mag);
# ref position hash
sub process_circuit($) {
    my ($rp) = @_;
    my $rch = $ref_circuit_hash;
    return if (!defined ${$rp}{'time'});
    my $ctm = lu_get_hhmmss_UTC(${$rp}{'time'});
    my $bgn_turn = 500; # meters BEFORE target, commence turn - should be a function of degrees to turn to next
    my $secs = 0;
    my $eta = '';
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$cpos,$msg);
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
    #my ($user_lat,$user_lon,$targ_lat,$targ_lon,$targ_hdg,$targ_dist);
    my ($targ_lat,$targ_lon);
    my ($az1,$az2,$dist);
    my $ct = time();
    if ($circuit_flag == 0) {
        # must choose target
        # ------------------
        $in_orbit = 0; # clear any running in ORBIT
        process_lat_lon($rch,$lat,$lon,"Begin location");
        # head for the targ
        $az1 = ${$rch}{'target_hgd'};
        $targ_lat = ${$rch}{'target_lat'}; 
        $targ_lon = ${$rch}{'target_lon'};
        $target_lat = $targ_lat;
        $target_lon = $targ_lon;
        # already done in process_lat_lon()
        # fg_geo_inverse_wgs_84 ($lat,$lon,$targ_lat,$targ_lon,\$az1,\$az2,\$dist);
        #####################################################
        $az2 = get_mag_hdg_from_true($az1);
        set_hdg_bug_force($az2);
        ${$rch}{'target_heading_t'} = $az1;
        ${$rch}{'target_heading_m'} = $az2;
        #####################################################
        $dist = ${$rch}{'target_dist'};
        ${$rch}{'last_dist'} = $dist;    # initially how far to go
        $curr_target = 'YGIL';
        $head_target = 1;
        $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
        ${$rch}{'change_oount'} = 0;    # no change direction yet
        # display stuff
        # $ptset = ${$rch}{'targ_ptset'}; # get active point set
        $eta = " ETA:".secs_HHMMSS2($secs); # display as hh:mm:ss
        set_hdg_stg(\$az1);
        set_hdg_stg(\$az2);
        set_dist_stg(\$dist);
        set_lat_stg(\$targ_lat);
        set_lon_stg(\$targ_lon);
        prtt("\nHEAD FOR [$targ_lat,$targ_lon] on ${az1}T/${az2}M $dist $ptset $eta\n");
        ${$rch}{'target_start'} = $ct;
        ${$rch}{'begin_time'} = $ct;
        ${$rch}{'last_time'} = $ct;
        $circuit_flag |= 1;
        ${$rch}{'change_oount'} = 0;    # no change direction yet
        return; # making a TURN - WAIT...
    }
    #$user_lat = ${$rch}{'user_lat'};
    #$user_lon = ${$rch}{'user_lon'};
    $targ_lat = ${$rch}{'target_lat'}; 
    $targ_lon = ${$rch}{'target_lon'};
    #$targ_hdg = ${$rch}{'target_hgd'};
    #$targ_dist = ${$rch}{'target_dist'};
    # $ptset = ${$rch}{'targ_ptset'}; # get active point set
    if ($circuit_flag == 1) {
        # wait for completion of a TURN
        if ($done_turn_done) {
            $circuit_flag |= 2;
            # get from current lat.lon to target lat.lon
            fg_geo_inverse_wgs_84 ($lat,$lon,$targ_lat,$targ_lon,\$az1,\$az2,\$dist);
            ${$rch}{'last_dist'} = $dist;
            $az2 = get_mag_hdg_from_true($az1);
            $done_turn_done = 0;
            if (abs($requested_hb - $az2) > 5) { # was just 1!!!
                # only if greater than 5 degrees needed...
                set_hdg_bug($az2);
            }
            # turn completed - I think
            ${$rch}{'last_time'} = $ct;
            ${$rch}{'begin_time'} = $ct;
            set_dist_m2kmnm_stg(\$dist);
            $msg = "roll=".get_curr_roll(); # get the current roll factor, to 2 desimal places
            prtt("Done turn cf=$circuit_flag, dist $dist $ptset $msg\n");
            return;
        }
    }
    if ($chk_turn_done) {
        # prtt("wait until any final turn completed circuit_flag=$circuit_flag\n");
        return;
    }
    my $last_dist = ${$rch}{'last_dist'};
    # get CURRENT distance to target
    fg_geo_inverse_wgs_84 ($lat,$lon,$targ_lat,$targ_lon,\$az1,\$az2,\$dist);
    # with GRD SPEED (Knots), and Distance (meters), calculate an ETA (secs)
    $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
    my $lt = ${$rch}{'last_time'};
    my $td = $ct - $lt;

    if ( ($td < 10) && ($dist > $bgn_turn) ) {
        # no need to check further
        return;
    }
    ${$rch}{'last_time'} = $ct;
    ${$rch}{'change_oount'}++;    # add a change direction

    my ($ntlat,$ntlon);
    my ($val1,$val2,$val3);
    my $nxt_ps = get_next_pointset($rch,$ptset,\$ntlat,\$ntlon,0);
    my $prev_ps = get_prev_pointset($ptset);
    $msg = "";
    my ($raad);
    if (defined ${$rch}{$prev_ps}) {
        $raad = ${$rch}{$prev_ps};
        $val1 = ${$raad}[0];    # get $az1 track to target
        $val2 = ${$raad}[1];    # get the reverse
        $val3 = ${$raad}[2];    # distance
        set_hdg_stg(\$val1);
        set_hdg_stg(\$val2);
        set_dist_stg(\$val3);
        # $msg = "$val3\@$val1";
        $msg .= "/" if (length($msg));
        #$msg .= "P$val1/$val2";
        $msg .= "P$val1\@$val3";
    }
    $msg .= " R=".get_curr_roll();

    # ##############################################
    # compare with LAST distance to target
    # ##############################################
    # if ( ($dist < $last_dist) && ($dist > $bgn_turn) ) {
    # if ( ($secs > 10) && ($dist < $last_dist) && ($dist > $bgn_turn) ) {
    if ( ($secs > 20) && ($dist < $last_dist) && ($dist > $bgn_turn) ) {
        # we are moving towards the target lat,lon
        ${$rch}{'last_dist'} = $dist;
        # set up DEBUG display
        $eta = "ETA:".secs_HHMMSS2($secs); # display as hh:mm:ss
        #set_dist_stg(\$last_dist);
        #set_dist_stg(\$dist);
        $val1 = $requested_hb;
        $val2 = $mag;
        $val3 = $hdg;
        #set_decimal1_stg(\$val1);
        #set_decimal1_stg(\$val2);
        #set_decimal1_stg(\$val3);
        set_hdg_stg(\$val1);
        set_hdg_stg(\$val2);
        set_hdg_stg(\$val3);
        #set_dist_m2kmnm_stg(\$last_dist);
        #set_dist_m2kmnm_stg(\$dist);
        set_dist_stg(\$last_dist);
        set_dist_stg(\$dist);
        # my ($g_wind_dir, $g_wind_speed,$g_qnh_bars);
        if ((defined $g_wind_dir)&&(defined $g_wind_speed) && (defined $g_qnh_bars)) {
            my $inhg = $g_qnh_inhg;
            set_decimal2_stg(\$inhg);
            $msg .= " $g_wind_dir/$g_wind_speed $g_qnh_bars $inhg";
        }
        prtt("Dist. to $ptset $dist, (p=$last_dist) r=$val2 h=M$val2/T$val3 $eta $msg\n");
        return; # goal reached
    }

    # ==============================================
    # moving onto the NEXT part of the circuit
    # ----------------------------------------
    if ($nxt_ps eq 'none') {
        prtt("\nERROR: Cancelling circuit. Failed to get next point from [$ptset]!\n\n");
        $circuit_mode = 0;
        return;
    }
    $target_lat = $ntlat;   # set NEW target
    $target_lon = $ntlon;
    fg_geo_inverse_wgs_84 ($lat,$lon,$ntlat,$ntlon,\$az1,\$az2,\$dist);
    ${$rch}{'last_dist'} = $dist;   # next distance pt-to-pset
    $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
    ################################################
    my $newhdg = get_mag_hdg_from_true($az1);
    ###set_hdg_bug($newhdg);
    set_hdg_bug_force($newhdg);
    $az2 = $newhdg;
    ################################################
    ${$rch}{'target_lat'} = $ntlat; 
    ${$rch}{'target_lon'} = $ntlon;
    ${$rch}{'targ_ptset'} = $nxt_ps; # set TARGET point set
    ${$rch}{'prev_ptset'} = $ptset;
    ${$rch}{'estim_secs'} = $secs; # estimated seconds to arrival at target
    # get TARGET TRACK from current to next
    my $taz1 = "NA";
    my $taz2 = "NA";
    if (defined ${$rch}{$ptset}) {
        $taz1 = ${$rch}{$ptset}[0];
        $taz2 = get_mag_hdg_from_true($taz1);
        set_hdg_stg(\$taz1);
        set_hdg_stg(\$taz2);
    }

    set_hdg_stg(\$az1);
    set_hdg_stg(\$az2);
    set_dist_stg(\$dist);
    $eta = "ETA:".secs_HHMMSS2($secs); # display as hh:mm:ss
    set_lat_stg(\$ntlat);
    set_lon_stg(\$ntlon);
    prtt("\nNEW HEAD [$ntlat,$ntlon] on ${az1}T/${az2}M $dist ($ptset-${taz2}-$nxt_ps) $eta $msg\n");
    $circuit_flag = 1; # wait for turn to complete
    $chk_time_set = 0;  # set on turn complete
    $once_per_leg = 0;  # done leg correction
}

sub wait_some_secs($) {
    my $secs = shift;
    my $tm = time();
    my $wait = 1;
    while ($wait) {
        my $now = time();
        if ($now > ($tm + $secs)) {
            $wait = 0;
        }
        if (check_keyboard()) {
            return 1;
        }
    }
    return 0;
}

sub do_takeoff2() {
    my $bk = 0;
    prtt("Going for takeof... assumed runway lined up...\n");
    set_brake_park($bk);
    prtt("Released parking break...\n");
    my $thr = 1;
    fgfs_set_eng_throttle($thr);
    prtt("Set throttle full...\n");
    $g_in_takeoff = 1;
    my ($rp,$lon,$lat,$alt,$agl,$hb,$hdg,$mag,$aspd,$gspd);
    my ($ilon,$ilat,$ialt,$iagl,$ihb,$ihdg,$imag,$iaspd,$igspd);
    my ($trend1,$trend2);
    my ($tm,$ptm,$targ_mag);
    $rp = fgfs_get_position();
    $ilon = ${$rp}{'lon'};
    $ilat = ${$rp}{'lat'};
    $ialt = ${$rp}{'alt'};
    $ihdg = ${$rp}{'hdg'};
    $iagl = ${$rp}{'agl'};
    $ihb  = ${$rp}{'bug'};
    # this should be the runway heading - NEEDS TO BE CHECKED
    $imag = ${$rp}{'mag'};  # /orientation/heading-magnetic-deg
    $targ_mag = $imag;
    $iaspd = ${$rp}{'aspd'}; # Knots
    $igspd = ${$rp}{'gspd'}; # Knots
    my ($rf,$ai,$ait,$el,$elt,$flp,$rud,$rudt,$flap);
    my ($iai,$iait,$iel,$ielt,$iflp,$irud,$irudt,$iflap);
    my ($msg,$cai,$cel,$crud);
    my ($diff1,$diff2,$diff3,$tmp);

    my $in_lift_off = 0;
    my $elev_agl = 0;
    my $flt_elev_set = 0;
    my $in_climb = 0;
    my $got_drift = 0;
    my $reached_500 = 0;
    my $show_msg = 0;

    prtt("Zeroing flight controles...\n");
    fgfs_set_flight_zero();
    # set_flt_ailerons(0.0);
    # set_flt_ailerons_trim(0.0);
    # set_flt_elevator(0.0);
    # set_flt_elevator_trim(0.0);
    # set_flt_rudder(0.0);
    # set_flt_rudder_trim(0.0);
    # set_flt_flaps(0.0);

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
    $flap = "none";
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

    $ptm = time();
    while ($g_in_takeoff) {
        if (check_keyboard()) {
            return 1;
        }
        $rf = fgfs_get_flight();
        $ai  = ${$rf}{'ai'};    # 1 = right, -0.9 = left
        $ait = ${$rf}{'ait'};
        $el  = ${$rf}{'el'};    # 1 = down, to -1(-0.9) = up (climb)
        $elt = ${$rf}{'elt'};
        $rud = ${$rf}{'rud'};   # 1 = right, to -1(0.9) left
        $rudt= ${$rf}{'rudt'};
        $flp = ${$rf}{'flap'};  # 0 = none, 0.333 = 5 degs, 0.666 = 10, 1 = full extended

        $rp = fgfs_get_position();
        $lon = ${$rp}{'lon'};
        $lat = ${$rp}{'lat'};
        $alt = ${$rp}{'alt'};
        $hdg = ${$rp}{'hdg'};
        $agl = ${$rp}{'agl'};
        $hb  = ${$rp}{'bug'};
        $mag = ${$rp}{'mag'};   # /orientation/heading-magnetic-deg
        $aspd = ${$rp}{'aspd'}; # Knots
        $gspd = ${$rp}{'gspd'}; # Knots
        $tm = time();
        $msg = 'to ';
        $msg = "To " if ($in_lift_off);
        #######################################
        $diff1 = $agl - $elev_agl;
        if ($flt_elev_set) {
            if ($diff1 > 30) {
                # GAINED 30 feet - we are IN THE AIR
                # ==================================
                set_flt_elevator(-0.15); # -0.05);
                get_flt_elevator(\$el);
                set_int_stg(\$diff1);
                $msg .= "dif=$diff1 ";
                $flt_elev_set = 0;
                $in_climb = 1;
                $show_msg = 1;
            }
        } 
        if ($in_climb) {
            if ($agl > 500) {
                if (!$reached_500) {
                    $diff1 = $agl;
                    set_int_stg(\$diff1);
                    $msg .= "REACHED $diff1";
                    $show_msg = 1;
                    $reached_500 = 1;
                }
            }
        }

        if ($aspd > $c172n_to_roll_min) {
            if ($in_lift_off) {
                $msg = "TO ";
            } else {
                # FIRST TIME HERE
                $msg = "\nTO ";
                $in_lift_off = 1;
                # el up -0.25   # maybe TOO MUCH???
                $elev_agl = $agl;

                # would be nice if these could mount over time, instead of absolute SET!!!
                # ========================================================================
                set_flt_elevator(-0.2); # -0.25;
                get_flt_elevator(\$el);
                # rd rt 0.030915
                # ail right 0.272568
                set_flt_ailerons(0.24);
                get_flt_ailerons(\$ai);

                #  rd rt 0.030915 - no did not help really onl on grass perhaps
                # set_flt_rudder(0.1);
                # get_flt_rudder(\$rud);

                $flt_elev_set = 1;
            }
        }

        #######################################
        # check for drift from runway heading
        $diff2 = $targ_mag - $mag;
        $diff1 = abs($diff2);
        if ($diff1 > 0.5) { # was 1 # need to act quickly on this - was 2
            #set_int_stg(\$diff1);
            set_decimal1_stg(\$diff1); # set_double1_stg(\$diff1);
            set_decimal1_stg(\$diff2); # set_double1_stg(\$diff1);
            $tmp = $targ_mag;
            set_hdg_stg(\$tmp);
            if ($in_lift_off) {
                $msg .= "Drift $diff2 $tmp ";
            } else {
                $msg .= "drift $diff2 $tmp ";
            }
            $got_drift = 1;
            $show_msg = 1;
        }


        $diff1 = abs($ai - $iai);
        $diff2 = abs($el - $iel);
        $diff3 = abs($rud - $irud);

        $cai = $ai;
        set_decimal6_form(\$cai);
        $cel = $el;
        set_decimal6_form(\$cel);
        $crud = $rud;
        set_decimal6_form(\$crud);

        if ($show_msg || ($tm != $ptm)) {
            ############################################################
            ### DISPLAY ###
            # prtt("lat/lon $lat,$lon,$alt $mag,$hdg,$agl\n");
            $trend1 = '=';
            if ($aspd > $iaspd) {
                $trend1 = "+";
            } elsif ($aspd < $iaspd) {
                $trend1 = "-";
            }
            $trend2 = '=';
            if ($agl > $iagl) {
                $trend2 = "+";
            } elsif ($agl < $iagl) {
                $trend2 = "-";
            }
            set_int_stg(\$alt);
            set_hdg_stg(\$hdg);
            set_hdg_stg(\$mag);
            set_int_stg(\$agl);
            set_int_stg(\$aspd);
            # add STD QNH altitude = $alt

            $msg .= "$aspd$trend1 $agl$trend2 $mag,$hdg";
            # $diff1 = abs($ai - $iai);
            # $diff2 = abs($el - $iel);
            # $diff3 = abs($rud - $irud);
            if ($diff1 > 0.1) {
                if ($ai > $iai) {
                    $msg .= " ail right $cai"
                } elsif ($ai < $iai) {
                    $msg .= " ail left $cai"
                }
            }
            if ($diff2 > 0.05) {
                if ($el > $iel) {
                    $msg .= " el down $cel"
                } elsif ($el < $iel) {
                    $msg .= " el up $cel"
                }
            }
            # $rud = ${$rf}{'rud'};   # 1 = right, to -1(0.9) left
            if ($diff3 > 0.01) { # sesitive to DRIFT - fix - was 0.05
                if ($rud > $irud) {
                    $msg .= " rd rt $crud"
                } elsif ($rud < $irud) {
                    $msg .= " rd lf $crud"
                }
            }

            prtt("$msg\n");
            $ptm = $tm;
            $got_drift = 0;
            $show_msg = 0;
        }
    } # while ($g_in_takeoff)
}

my $do_magneto_test = 0;

sub do_takeoff() {
    # 1 - is engine running?
    my $re = fgfs_get_engines();
    my $run = ${$re}{'running'};
    my $rpm = ${$re}{'rpm'};
    my $thr = ${$re}{'throttle'};
    my $mag = ${$re}{'magn'}; # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    my $mix = ${$re}{'mix'}; # $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich
    my $idle = $thr;
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

    $rpm = int($rpm + 0.5);
    $thr = int($thr * 100);
    prtt("TAKEOFF: run=$run, rpm=$rpm, throttle=$thr, mags $mag, mix $mix, lights $navL/$beak/$strb\n");

    if (!$run) {
        prtt("Engine NOT running - NO TAKEOFF!\n");
        return 1;
    }
    if ($mag < 3) {
        my $tmp = "OFF";
        $tmp = 'LEFT' if ($mag == 2);
        $tmp = 'RIGHT' if ($mag == 1);
        prtt("Magnetos NOT BOTH got $tmp ** FIX ME ** - NO TAKEOFF!\n");
        return 1;
    }
    if ($mix < 1) {
        prtt("Mixture NOT FULL got $mix ** FIX ME ** - NO TAKEOFF!\n");
        return 1;
    }

    if (($navL eq 'false')||($beak eq 'false')||($strb eq 'false')) {
        if ($set_run_lights) {
            prtt("# TODO: Set running lights\n");
        } else {
            prtt("Some running lights nav $navL, bcn $beak, strobe $strb NOT ON! *** FIX ME *** - NO TAKEOFF\n");
            return 1;
        }
    }
    my $rf = fgfs_get_brakes();
    my ($bl,$br,$pbk,$pk);
    $bl = ${$rf}{'bl'};
    $br = ${$rf}{'br'};
    $pbk = ${$rf}{'bk'}; # $gr_brake_park = "/controls/gear/brake-parking";    # int 0=off 1=On
    $pbk = 0 if (length($pbk) == 0);
    if ($pbk == 0) {
        $pbk = 1;
        set_brake_park($pbk);
        prtt("Set parking break $pbk... for magnetos test...\n");
    }

    my $max_test = 1;
    my $state = 1;
    my $nrpm = 0;
    my $pass = 0;
    my $dnsw1 = 0;
    my $dnsw2 = 0;
    my $minrpmdrp = 60;
    my ($diff);

    if ($do_magneto_test) {
        $thr = 0.56;    # what is the percentage???
        fgfs_set_eng_throttle($thr);
        prtt("Waiting for throttle to settle... 3 secs\n");
        if (wait_some_secs(3)) {
            return 1;
        }
        fgfs_get_eng_rpm(\$rpm);
        $rpm = int($rpm + 0.5);
    } else { # if (!$do_magneto_test)
        prtt("Skipping magneto test...\n");
        $pass = 1;
        $max_test = 0;
    }
    while ($max_test) {
        $re = fgfs_get_engines();
        if ($state == 1) {
            if ($dnsw1 == 0) {
                fgfs_set_eng_mag(2);
                prtt("Set magneto RIGHT... \n");
                if (wait_some_secs(1)) {
                    return 1;
                }
            }
            $dnsw1 = 1;
            fgfs_get_eng_rpm(\$nrpm);
            $nrpm = int($nrpm + 0.5);
            $diff = ($rpm - $nrpm);
            prtt("With RIGHT diff $diff, $rpm $nrpm\n");
            if ($diff > $minrpmdrp) {
                fgfs_set_eng_mag(3);
                prtt("PASSED $diff - Set magneto BOTH...\n");
                $state = 2;
            }
            if (wait_some_secs(1)) {
                return 1;
            }
        } elsif ($state == 2) {
            if ($dnsw2 == 0) {
                fgfs_set_eng_mag(1);
                prtt("Set magneto LEFT... \n");
                if (wait_some_secs(1)) {
                    return 1;
                }
            }
            $dnsw2 = 1;
            fgfs_get_eng_rpm(\$nrpm);
            $nrpm = int($nrpm + 0.5);
            $diff = ($rpm - $nrpm);
            prtt("With LEFT diff $diff, $rpm $nrpm\n");
            if ($diff > $minrpmdrp) {
                fgfs_set_eng_mag(3);
                prtt("PASSED $diff - Set magneto BOTH...\n");
                $pass = 1;
                $max_test = 0;
            }
            if (wait_some_secs(1)) {
                return 1;
            }
        }
    }
    if ($idle > 0.1) {
        $idle = 0;
    }

    prtt("Set throttle to idle $idle...\n");
    fgfs_set_eng_throttle($idle);

    if (!$pass) {
        prtt("Failed magnetos test - NO TAKEOFF\n");
        return 1;
    }

    if (wait_some_secs(3)) {
        return 1;
    }

    do_takeoff2();

    return 0;
}

sub main_loop() {
    my ($char,$val,$pmsg);
    my ($nlat,$nlon);
    my ($rp,$re);
    my ($msecs,$ms,$ok,$kloop);
    #my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$nbug);
    #my ($run,$rpm);
    my ($hb,$nbug);
    my ($btm,$ntm,$ctm,$dtm);
    prt("$CONMSG at IP $HOST, port $PORT\n");
    # get the TELENET connection
    $FGFS_IO = fgfs_connect($HOST, $PORT, $TIMEOUT) ||
        pgm_exit(1,"ERROR: can't open socket!\n".
        "Is FG running on IP $HOST, with TELNET enabled on port $PORT?\n");

    ReadMode('cbreak'); # not sure this is required, or what it does exactly

	fgfs_send("data");  # switch exchange to data mode

    prtt("Get 'sim' information...\n");
    show_sim_info(fgfs_get_sim_info());
    prtt("Get Fuel - comsumables...\n");
    show_consumables(fgfs_get_consumables());
    prtt("Getting current environment...\n");
    show_environ(fgfs_get_environ());
    prtt("Getting current COMMS...\n");
    show_comms(fgfs_get_comms());

    # ### FOREVER - NOTHING happens without an ENGINE ###
    if ( wait_for_engine() ) {
       goto Exit;
    }

    # we have ENGINES!!!

    # will return immediately, if NOT $wait_alt_hold
    if ( wait_for_alt_hold() ) {
        goto Exit;
    }

    if ($keep_av_time && @intervals) {
        $ok = scalar @intervals;
        $btm = 0;
        foreach $ntm (@intervals) {
            $btm += $ntm;
        }
        $dtm = $btm / $ok;
        prtt("$ok accesses took $btm secs, avarage $dtm per access...\n");
        # 39 accesses took 15.568619 secs, avarage 0.399195358974359 per access...

    }
    $ok = 1;
    prtt("Entering MAIN loop...\n");
    # FOREVER, until ESC = exit
    my $bsecs = time();
    my $frames = 0;
    my ($tnow);
    my @frame = ();
    my $fcnt = 0;
    my $maxfcts = 10;
    my $gotfps = 0;
    while ($ok) {
        # get a FRAME counter
        $frames++;
        $tnow = time();
        if ($tnow != $bsecs) {
            $frame[$fcnt] = $frames;
            $fcnt++;
            if ($fcnt >= $maxfcts) {
                $fcnt = 0;
                $gotfps = 1;
            }
            $frames = 0;    # restart counter
            $bsecs = $tnow; # update time
        }
        $rp = fgfs_get_position();
        #$lon = ${$rp}{'lon'};
        #$lat = ${$rp}{'lat'};
        #$alt = ${$rp}{'alt'};
        #$hdg = ${$rp}{'hdg'};
        #$agl = ${$rp}{'agl'};
        $hb  = ${$rp}{'bug'};
        #$mag = ${$rp}{'mag'};  # /orientation/heading-magnetic-deg
        show_position($rp);
        process_circuit($rp) if ($circuit_mode);
        process_orbit() if ($in_orbit);
        $msecs = $DELAY * 1000;
        $kloop = 1;
        while ($msecs && $kloop) {
            if ($msecs > $MSDELAY) {
                $ms = $MSDELAY;
            } else {
                $ms = $msecs;
            }
            if ( got_keyboard(\$char) ) {
                $prev_target = $head_target;
                $head_target = 0;
                $val = ord($char);
                $pmsg = sprintf( "%02X", $val );
                if ($val == 27) {
                    prtt("ESC key... Exiting...\n");
                    $ok = 0;
                } elsif ($char eq '?') {
                    keyboard_help();
                    if ($gotfps && $maxfcts) {
                        my $totfms = 0;
                        my ($f);
                        for ($f = 0; $f < $maxfcts; $f++) {
                            $totfms += $frame[$f];
                        }
                        $totfms /= $maxfcts;
                        prt("Average FPS $totfms\n");
                    }
                } elsif ($char eq '+') {
                    $DELAY++;
                    prtt("Increase delay to $DELAY seconds...\n");
                } elsif ($char eq '-') {
                    $DELAY-- if ($DELAY);
                    prtt("Decrease delay to $DELAY seconds...\n");
                } elsif ($char eq '9') {
                    $circuit_mode = 0;
                    $circuit_flag = 0;
                    $chk_turn_done = 0;
                    $nbug = $hb + 90;
                    $nbug -= 360 if ($nbug >= 360);
                    $nbug = (int(($nbug + 0.05) * 10) / 10);
                    prtt("Set heading bug to $nbug\n");
                    set_hdg_bug_force($nbug);
                    $in_orbit = 0;
                } elsif ($char eq '(') {
                    $circuit_mode = 0;
                    $circuit_flag = 0;
                    $chk_turn_done = 0;
                    $nbug = $hb - 90;
                    $nbug += 360 if ($nbug < 0);
                    $nbug = (int(($nbug + 0.05) * 10) / 10);
                    prtt("Set heading bug to $nbug\n");
                    set_hdg_bug_force($nbug);
                    $in_orbit = 0;
                } elsif ($char eq 'a') {
                    show_K_locks();
                } elsif ($char eq 'B') {
                    $nbug = $hb + 1;
                    $nbug -= 360 if ($nbug >= 360);
                    $nbug = (int(($nbug + 0.05) * 10) / 10);
                    prtt("Set heading bug to $nbug\n");
                    set_hdg_bug_force($nbug);
                    $in_orbit = 0;
                } elsif ($char eq 'b') {
                    $nbug = $hb - 1;
                    $nbug += 360 if ($nbug < 0);
                    $nbug = (int(($nbug + 0.05) * 10) / 10);
                    prtt("Set heading bug to $nbug\n");
                    set_hdg_bug_force($nbug);
                } elsif ($char eq 'c') {
                    prtt("Set CIRCUIT mode\n");
                    $circuit_mode = 1;
                    $circuit_flag = 0;
                    $chk_turn_done = 0;
                    process_circuit($rp);
                } elsif ($char eq 'C') {
                    prtt("Clear CIRCUIT mode\n");
                    $circuit_mode = 0;
                    $circuit_flag = 0;
                    $chk_turn_done = 0;
                } elsif (($char eq 'd')||($char eq '2')) {
                    $circuit_mode = 0;
                    $circuit_flag = 0;
                    $chk_turn_done = 0;
                    $in_orbit = 0;
                    head_for_target('YSDU',$char);
                } elsif ($char eq 'e') {
                    show_engines_and_fuel();
                    $head_target = $prev_target;
                } elsif (($char eq 'g')||($char eq '1')) {
                    $in_orbit = 0;
                    $circuit_mode = 0;
                    $circuit_flag = 0;
                    $chk_turn_done = 0;
                    head_for_target('YGIL',$char);
                    prtt("Head for target [$curr_target]\n");
                } elsif (($char eq 'o')||($char eq 'O')) {
                    commence_orbit($char);
                #} elsif ($char eq 't') {
                #    #  160 (T) 13.4 km. 4: 175.2  14.4 km.  hM 153.3 hT 164.3 b 152
                #    $rp = fgfs_get_position();
                #    prt("Set to new track...\n");
                #} elsif ($char eq 'u') {
                #    prt("Do position update...\n");
                #    $kloop = 0;
                #    $ms = 0;
                } elsif (($char eq 'T')) {
                    do_takeoff();
                } else {
                    prtt("Got unused keyboard input hex[$pmsg]...\n");
                }
                last; # exit keyboard loop
            }
            sleep_ms($ms);
            $msecs -= $ms;
        }   # keyboard LOOP
    } # main LOOP
    
Exit:
    if ($send_run_exit) {
    	fgfs_send("run exit"); # YAHOO! THAT WORKED!!! PHEW!!!
        sleep(5);
    }
    prt("Closing telnet IO ...\n");
	close $FGFS_IO;
	undef $FGFS_IO;
    ReadMode('normal'); # not sure this is required, or what it does exactly

}

#########################################
### MAIN ###
parse_args(@ARGV);
init_runway_array();
$ref_circuit_hash = get_circuit_hash();
# ${$rch}{'TL'} = [$az1,$az2,$dist]; etc...
get_runways_and_pattern($ref_circuit_hash,'YGIL');
main_loop();

pgm_exit(0,"Normal exit(0)");
########################################

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have following argument!\n") if (!@av);
}

sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg);
    while (@av) {
        $arg = $av[0];
        if ($arg =~ /^-/) {
            $sarg = substr($arg,1);
            $sarg = substr($sarg,1) while ($sarg =~ /^-/);
            if (($sarg =~ /^help$/i)||($sarg eq '?')) {
                give_help();
                pgm_exit(0,"Help exit(0)");
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
            prt("Set input to [$in_file]\n");
        }
        shift @av;
    }
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-file\n");
    prt("Options:\n");
    prt(" --help         (-?) = This help, and exit 0.\n");
    prt(" --host <name>  (-h) = Set host name, or IP address. (def=$HOST)\n");
    prt(" --port <num>   (-p) = Set port. (def=$PORT)\n");
    prt(" --delay <secs> (-d) = Set delay in seconds between sampling. ($DELAY)\n");
    prt("Purpose: Establish a TELENET (tcp) connection to running FGFS, show current position, and\n");
    prt(" aid in setting the heading 'bug'.\n");
}

# eof - fg_square.pl
