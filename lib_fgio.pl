#!/usr/bin/perl -w
# NAME: lib_fgio.pl
# AIM: Functions for a TELNET connection to fgfs
# 24/09/2011 geoff mclane http://geoffair.net/mperl
# List: # fgfs_connect, fgfs_disconnect, fgfs_get, fgfs_get_K_ah, fgfs_get_K_hh, fgfs_get_K_locks,
# fgfs_get_K_pa
# fgfs_get_K_pm, fgfs_get_K_ra, fgfs_get_K_rm, fgfs_get_adf, fgfs_get_adf_active
# fgfs_get_adf_stdby, fgfs_get_aero, fgfs_get_agl, fgfs_get_alt, fgfs_get_aspd_kts
# fgfs_get_comm1, fgfs_get_comm1_active, fgfs_get_comm1_stdby, fgfs_get_comm2, fgfs_get_comm2_active
# fgfs_get_comm2_stdby, fgfs_get_comms, fgfs_get_consumables, fgfs_get_coord, fgfs_get_desc
# fgfs_get_eng_rpm, fgfs_get_eng_rpm2, fgfs_get_eng_running, fgfs_get_eng_running2
# fgfs_get_eng_throttle, fgfs_get_eng_throttle2, fgfs_get_engines, fgfs_get_environ
# fgfs_get_fdm, fgfs_get_fuel1_imp, fgfs_get_fuel1_us, fgfs_get_fuel2_imp, fgfs_get_fuel2_us
# fgfs_get_fuel_kgs, fgfs_get_fuel_lbs, fgfs_get_gps, fgfs_get_gps_alt, fgfs_get_gps_gspd_kts
# fgfs_get_gps_lat, fgfs_get_gps_lon, fgfs_get_gps_track, fgfs_get_gps_track_true
# fgfs_get_gspd_kts, fgfs_get_hdg_bug, fgfs_get_hdg_mag, fgfs_get_hdg_true, fgfs_get_mag_var
# fgfs_get_metar, fgfs_get_nav1, fgfs_get_nav1_active, fgfs_get_nav1_radial, fgfs_get_nav1_stdby
# fgfs_get_nav2, fgfs_get_nav2_active, fgfs_get_nav2_stdby, fgfs_get_position, fgfs_get_root
# fgfs_get_sim_info, fgfs_get_w_time, fgfs_get_wind_east, fgfs_get_wind_heading
# fgfs_get_wind_north, fgfs_get_wind_speed, fgfs_send, fgfs_set, fgfs_set_hdg_bug
# get_curr_Klocks, get_curr_comms, get_curr_consumables, get_curr_engine, get_curr_env
# get_curr_gps, get_curr_posit, get_curr_sim, get_current_position, get_exit, get_position_stg
# got_flying_speed, got_keyboard, in_world_range, secs_HHMMSS2, set_SenecaII, set_dist_m2kmnm_stg
# set_dist_stg, set_hdg_stg, set_hdg_stg1, set_hdg_stg3, set_int_dist_stg5, set_lat_stg
# set_lon_stg, show_K_locks, show_comms, show_consumables, show_engines, show_engines_and_fuel
# show_environ, show_sim_info, sleep_ms
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use IO::Socket;
use Term::ReadKey;
use Time::HiRes qw( usleep gettimeofday tv_interval );
use Math::Trig;

my $FGFS_IO; # Telnet IO handle
my $DELAY = 5;    # delay between getting a/c position
my $MSDELAY = 200; # max wait before keyboard sampling
my $gps_next_time = 5 * 60; # gps update each ?? minutes
my $SG_NM_TO_METER = 1852;
my $SG_METER_TO_NM = 0.0005399568034557235;

my $engine_count = 1;
my $is_jet_engine = 0;
my $keep_av_time = 0;
my $done_turn_done = 0;
my $last_wind_info = '';    # metar info at last update
my $chk_turn_done = 0;
my $send_run_exit = 0;
my $min_fly_speed = 30; # Knots
my $min_upd_position = 5 * 60;  # update if older than 5 minutes
my $short_time_stg = 1; # shorten 00:00:59 to 59s

my $mag_deviation = 0; # = difference ($curr_hdg - $curr_mag) at ast update
my $mag_variation = 0; # from /environment/magnetic-variation-deg

sub get_mag_deviation() {
    return $mag_deviation;
}

my $curr_target = '';

my $head_target = 0;
my $prev_target = 0;
my $requested_hb = 0;
my $begin_hb = 0;
my $bgn_turn_tm = 0;

# last KAP140 lock values
my $kap_tm = '';
my $kap_ah = 'false';
my $kap_pa = 'false';
my $kap_ra = 'false';
my $kap_hh = 'false';

my @intervals = ();

my $air_f14b = "f-14b-yasim";
my $got_aero_f14b = 0;

my $lib_fgio_verbosity = 1;
sub set_lib_fgio_verb($) { $lib_fgio_verbosity = shift; }

# current hashes - at last update
my %m_curr_engine = ();
my %m_curr_posit = ();
my %m_curr_environ = ();
my %m_curr_comms = ();
my %m_curr_consumables = ();
my %m_curr_gps = ();
my %m_curr_sim = ();
my %m_curr_aps = ();        # autopilot settings
my %m_curr_aplocks = ();    # ap locks
my %m_curr_klocks = ();     # KAP140 locks
my %m_curr_gear_wow = ();   # gear on ground

my $show_set_dec_error = 0;

my $wait_ms_get = 50;

sub set_wait_ms_get($) {
    my $ms = shift;
    my $ret = $wait_ms_get;
    $wait_ms_get = $ms;
    return $ret;
}

# some utility functions
sub is_all_numeric($) {
    my ($txt) = shift;
    $txt = substr($txt,1) if ($txt =~ /^-/);
    return 1 if ($txt =~ /^(\d|\.)+$/);
    return 0;
}

sub set_decimal1_stg($) {
    my $r = shift;
    if (is_all_numeric(${$r})) {
        ${$r} =  int((${$r} + 0.05) * 10) / 10;
        ${$r} = "0.0" if (${$r} == 0);
        ${$r} .= ".0" if !(${$r} =~ /\./);
    } else {
        prtw("WARNING: set_decimal1_stg() passed non-numeric value [".${$r}."]") if ($show_set_dec_error);
    }
}

sub set_decimal2_stg($) {
    my $r = shift;
    ${$r} =  int((${$r} + 0.005) * 100) / 100;
    ${$r} = "0.00" if (${$r} == 0);
    ${$r} .= ".00" if !(${$r} =~ /\./);
}
sub set_decimal3_stg($) {
    my $r = shift;
    ${$r} =  int((${$r} + 0.0005) * 1000) / 1000;
    ${$r} = "0.000" if (${$r} == 0);
    ${$r} .= ".000" if !(${$r} =~ /\./);
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

sub get_dist_stg_km($) {
    my ($dist) = @_;
    my $km = $dist / 1000;
    set_decimal1_stg(\$km);
    $km .= "Km";
    return $km;
}

# fetch the above global - which should not be referred to directly
sub get_curr_posit() { return \%m_curr_posit; }
sub get_curr_env() { return \%m_curr_environ; }
sub get_curr_comms() { return \%m_curr_comms; }
sub get_curr_consumables() { return \%m_curr_consumables; }
sub get_curr_gps() { return \%m_curr_gps; }
sub get_curr_engine() { return \%m_curr_engine; }
sub get_curr_Klocks() { return \%m_curr_klocks; }
sub get_curr_aplocks() { return \%m_curr_aplocks; }
sub get_curr_sim() { return \%m_curr_sim; }
sub get_curr_aps() { return \%m_curr_aps; } # autopilot settings
sub get_curr_gear_wow() { return \%m_curr_gear_wow; }


my $gear0_wow = "/gear/gear[0]/wow";
my $gear1_wow = "/gear/gear[1]/wow";
my $gear2_wow = "/gear/gear[2]/wow";

my $ctrls_gear_pbrake = "/controls/gear/brake-parking"; # int
my $ctrls_gear_lbrake = "/controls/gear/brake-left";    # int
my $ctrls_gear_rbrake = "/controls/gear/brake-right";   # int
my $ctrls_gear_down = "/controls/gear/gear-down"; # bool true/false
# special, for carrier operations
my $ctrls_gear_cap_cms = "/controls/gear/catapult-launch-cmd"; # bool
my $ctrls_gear_lnchbar = "/controls/gear/launchbar"; # bool
my $ctrls_gear_tailhook = "/controls/gear/tailhook"; # bool

sub fgfs_get_gear0_wow($) {
    my $ref = shift;
    fgfs_get($gear0_wow, $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_gear1_wow($) {
    my $ref = shift;
    fgfs_get($gear1_wow, $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_gear2_wow($) {
    my $ref = shift;
    fgfs_get($gear2_wow, $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_park_brake($) {
    my $ref = shift;
    fgfs_get($ctrls_gear_pbrake, $ref) or get_exit(-2); # int
    return 1;
}
sub fgfs_get_left_brake($) {
    my $ref = shift;
    fgfs_get($ctrls_gear_lbrake, $ref) or get_exit(-2); # int
    return 1;
}
sub fgfs_get_right_brake($) {
    my $ref = shift;
    fgfs_get($ctrls_gear_rbrake, $ref) or get_exit(-2); # int
    return 1;
}
sub fgfs_get_gear_down($) {
    my $ref = shift;
    fgfs_get($ctrls_gear_down, $ref) or get_exit(-2); # bool
    return 1;
}

sub fgfs_get_gear_wow() {
    my $rh = get_curr_gear_wow();
    my ($wow0,$wow1,$wow2,$gdown,$pbrake);
    fgfs_get_gear0_wow(\$wow0);
    ${$rh}{'gear_wow0'} = $wow0;
    fgfs_get_gear1_wow(\$wow1);
    ${$rh}{'gear_wow1'} = $wow1;
    fgfs_get_gear2_wow(\$wow2);
    ${$rh}{'gear_wow2'} = $wow2;
    fgfs_get_park_brake(\$pbrake);
    ${$rh}{'park_brake'} = $pbrake;
    fgfs_get_gear_down(\$gdown);
    ${$rh}{'gear_down'} = $gdown;
    my $onground = 'false';
    if (($wow0 eq 'true')||($wow1 eq 'true')||($wow2 eq 'true')) {
        $onground = 'true';
    }
    ${$rh}{'on_ground'} = $onground;
    ${$rh}{'time'} = time();
    return $rh;
}

sub fgfs_show_gear_wow() {
    my $rh = fgfs_get_gear_wow();
    my ($ctm,$wow0,$wow1,$wow2,$onground,$pbrake,$gdown);
    $wow0 = ${$rh}{'gear_wow0'};
    $wow1 = ${$rh}{'gear_wow1'};
    $wow2 = ${$rh}{'gear_wow2'};
    $onground = ${$rh}{'on_ground'};
    $pbrake = ${$rh}{'park_brake'};
    $gdown = ${$rh}{'gear_down'};
    $ctm = lu_get_hhmmss_UTC(${$rh}{'time'});
    prt("$ctm: Gear WOW: g1=$wow0, g2=$wow1, g3=$wow2, on_ground=$onground, park=$pbrake, down=$gdown\n");
    return $rh;
}


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
my $get_P_body = "/orientation/p-body";
my $get_Q_body = "/orientation/q-body";
my $get_R_body = "/orientation/r-body";

# ### FG TELENET CREATION and IO ###
# ==================================

sub fgfs_connect($$$) {
	my ($host,$port,$timeout) = @_;
	my $socket;
	STDOUT->autoflush(1);
    $timeout = 1 if ($timeout <= 0);
    my $to = $timeout;
	prtt("Connect $host, $port, timeout $timeout secs ") if ($lib_fgio_verbosity);
	while ($timeout--) {
		if ($socket = IO::Socket::INET->new(
				Proto => 'tcp',
				PeerAddr => $host,
				PeerPort => $port,
				Timeout => $to ) ) {
			prt(" done.\n") if ($lib_fgio_verbosity);
			$socket->autoflush(1);
			sleep 1;
            $FGFS_IO = $socket;
			return $socket;
		}	
		prt(".") if ($lib_fgio_verbosity);
        last if ($timeout == 0);
		sleep(1);
	}
	prtt(" FAILED!\n") if ($lib_fgio_verbosity);
	return 0;
}

sub fgfs_disconnect() {
	if (defined $FGFS_IO) {
        prtt("closing connection...\n") if ($lib_fgio_verbosity);
		fgfs_send("run exit") if ($send_run_exit);
		close $FGFS_IO;
        undef $FGFS_IO;
	}
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

sub setprop($$) {
    my ($node,$val) = @_;
    return fgfs_set($node,$val);
}

# DEBUG ONLY STUFF
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

sub sleep_ms($) {
    my $usecs = shift; # = $INTERVAL
    if ($usecs > 0) {
        my $secs = $usecs / 1000;
        select(undef,undef,undef,$secs);
	    #usleep($usecs);    # sampling interval
    }
}

sub fgfs_get($$) {
    my ($txt,$rval) = @_;
    return 0 if (!defined $FGFS_IO);
    ### return fgfs_get_w_time($txt,$rval) if ($keep_av_time);
	fgfs_send("get $txt");
    sleep_ms($wait_ms_get) if ($wait_ms_get > 0);
	eof $FGFS_IO and return 0;
	${$rval} = <$FGFS_IO>;
	${$rval} =~ s/\015?\012$//;
	${$rval} =~ /^-ERR (.*)/ and (prtw("WARNING: $1\n") and return 0);
	return 1;
}

sub getprop($) {
    my $path = shift;
    my ($val);
    fgfs_get($path,\$val);
    return $val;
}

# convenient combinations of factors, using the above IO
# ======================================================
sub fgfs_get_gps();     # sim GPS values
sub fgfs_get_engines();  # C172p - needs to be tuned for each engine config
sub fgfs_get_K_locks(); # KAP140 Autopilot controls
sub fgfs_get_position();   # geod/graphic position
sub fgfs_get_environ(); # world environment
sub fgfs_get_comms();   # COMS stack - varies per aircraft
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


# Contents of /position
# ----------------------
my $pos_alt_ft = "/position/altitude-ft";
my $pos_alt_agl = "/position/altitude-agl-ft";
my $pos_lat_degs = "/position/latitude-deg";
my $pos_lon_degs = "/position/longitude-deg";
my $pos_grd_elev = "/position/ground-elev-ft";

sub fgfs_get_coord($$) {
	my ($rlon,$rlat) = @_;
	fgfs_get("/position/longitude-deg", $rlon) or get_exit(-2);
	fgfs_get("/position/latitude-deg", $rlat) or get_exit(-2);
	return 1;
}
sub fgfs_get_coord2($$) {
	my ($rlon,$rlat) = @_;
	${$rlon} = getprop($pos_lon_degs);
	${$rlat} = getprop($pos_lat_degs);
	return 1;
}

sub fgfs_get_alt($) {
	my $ref_alt = shift;
	fgfs_get("/position/altitude-ft", $ref_alt) or get_exit(-2);
	return 1;
}
sub fgfs_get_alt2($) {
	my $ref_alt = shift;
	${$ref_alt} = getprop($pos_alt_ft);
	return 1;
}
sub fgfs_get_agl2($) {
    my $rval = shift;
    ${$rval} = getprop($pos_alt_agl);
    return 1;
}
sub fgfs_get_ground_elev($) {
    my $rval = shift;
    ${$rval} = getprop($pos_grd_elev);
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
sub set_f_14b() {
    if ($hdg_bug_stg ne "/autopilot/settings/heading-bug-deg") {
        $hdg_bug_stg = "/autopilot/settings/heading-bug-deg";
        prtt("Set hdg bug stg = [$hdg_bug_stg]\n");
    }
    $min_fly_speed = 150; # Knots
    $got_aero_f14b = 1;
    $engine_count = 2;
    $is_jet_engine = 1;
}

# autopilot settings (F11)
my $aps_head_bug_deg = "/autopilot/setting/heading-bug-deg";
my $aps_targ_alt_ft = "/autopilot/settings/target-altitude-ft";
my $aps_targ_bank_deg = "/autopilot/settings/target-bank-deg";
my $aps_targ_pitch_deg = "/autopilot/settings/target-pitch-deg";
my $aps_targ_rate = "/autopilot/settings/target-rate-of-climb";
my $aps_targ_roll_deg = "/autopilot/settings/target-roll-deg";
my $aps_targ_speed_kt = "/autopilot/settings/target-speed-kt";
my $aps_targ_yaw_deg = "/autopilot/settings/target-yaw-deg";
my $aps_true_heading = "/autopilot/settings/true-heading-deg";

sub fgfs_get_aps_head_bug_degs($) {
	my $ref = shift;
	fgfs_get($aps_head_bug_deg, $ref) or get_exit(-2);
	return 1;
}
sub fgfs_get_aps_targ_alt($) {
	my $ref = shift;
	fgfs_get($aps_targ_alt_ft, $ref) or get_exit(-2);
	return 1;
}
sub fgfs_get_aps_targ_bank($) {
	my $ref = shift;
	fgfs_get($aps_targ_bank_deg, $ref) or get_exit(-2);
	return 1;
}
sub fgfs_get_aps_targ_pitch($) {
	my $ref = shift;
	fgfs_get($aps_targ_pitch_deg, $ref) or get_exit(-2);
	return 1;
}
sub fgfs_get_aps_targ_rate($) {
	my $ref = shift;
	fgfs_get($aps_targ_rate, $ref) or get_exit(-2);
	return 1;
}
sub fgfs_get_aps_targ_roll($) {
	my $ref = shift;
	fgfs_get($aps_targ_roll_deg, $ref) or get_exit(-2);
	return 1;
}
sub fgfs_get_aps_targ_speed($) {
	my $ref = shift;
	fgfs_get($aps_targ_speed_kt, $ref) or get_exit(-2);
	return 1;
}
sub fgfs_get_aps_targ_yaw($) {
	my $ref = shift;
	fgfs_get($aps_targ_yaw_deg, $ref) or get_exit(-2);
	return 1;
}
sub fgfs_get_aps_true_heading($) {
	my $ref = shift;
	fgfs_get($aps_true_heading, $ref) or get_exit(-2);
	return 1;
}

# get aoutpilot settings
sub fgfs_get_aps() {
    my ($alt,$bank,$rate,$speed,$yaw,$head);
    my $rc = get_curr_aps();
    fgfs_get_aps_targ_alt(\$alt);
    ${$rc}{'alt'} = $alt;
    fgfs_get_aps_targ_bank(\$bank);
    ${$rc}{'bank'} = $bank;
    fgfs_get_aps_targ_rate(\$rate);
    ${$rc}{'rate'} = $rate;
    fgfs_get_aps_targ_speed(\$speed);
    ${$rc}{'speed'} = $speed;
    fgfs_get_aps_targ_yaw(\$yaw);
    ${$rc}{'yaw'} = $yaw;
    fgfs_get_aps_true_heading(\$head);
    ${$rc}{'head'} = $head;
    ${$rc}{'time'} = time();
    return $rc;
}

sub show_autopilot_settings($) {
    my ($rc) = shift;
    my ($tm,$alt,$bank,$rate,$speed,$yaw,$head);
    $tm = lu_get_hhmmss_UTC(${$rc}{'time'});
    $alt = ${$rc}{'alt'};
    $bank = ${$rc}{'bank'};
    $rate = ${$rc}{'rate'};
    $speed = ${$rc}{'speed'};
    $yaw = ${$rc}{'yaw'};
    $head = ${$rc}{'head'};
    prt("$tm: alt=$alt, bank=$bank, rate=$rate, speed=$speed, yaw=$yaw, head=$head\n");
}

#/autopilot/internal/true-heading-error-deg
#/autopilot/internal/yaw-error-deg
#/autopilot/route-manager/active
#/autopilot/route-manager/current-wp
#/autopilot/route-manager/route
#/autopilot/route-manager/route/num
#/autopilot/route-manager/wp/dist

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

#################################################################
##############

####################################################################
my $eng_running_prop = "/engines/engine/running";
my $eng_rpm_prop = "/engines/engine/rpm";
my $eng_mag_prop = "/engines/engine/magnetos";
my $eng_mix_prop = "/engines/engine/mixture";

my $eng_throttle_prop = "/controls/engines/engine/throttle";
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
sub fgfs_get_eng_jet($) {
    my $ref = shift;
    fgfs_get("/engines/engine/n1", $ref) or get_exit(-2);  # double
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

# /controls/engines/engine/throttle
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
    if ($is_jet_engine) {
        fgfs_get("/engines/engine[1]/n1", $ref) or get_exit(-2);  # double
    } else {
        fgfs_get("/engines/engine[1]/rpm", $ref) or get_exit(-2);  # double
    }
    return 1;
}
sub fgfs_get_eng_throttle2($) {  # range 0 to 1
    my $ref = shift;
    fgfs_get("/controls/engines/engine[1]/throttle", $ref) or get_exit(-2);
    return 1;
}


sub fgfs_get_engines() {
    my $re = get_curr_engine();
    my ($running);
    fgfs_get_eng_running(\$running);
    ${$re}{'running'} = $running;
    my ($rpm);
    fgfs_get_eng_rpm(\$rpm);
    ${$re}{'rpm'} = $rpm;
    my ($throt);
    fgfs_get_eng_throttle(\$throt);
    ${$re}{'throttle'} = $throt;
    my ($magn,$mix);
    fgfs_get_eng_mag(\$magn);    # # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    # $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich
    fgfs_get_eng_mix(\$mix); # double 1 to 0
    ${$re}{'magn'} = $magn;   # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    ${$re}{'mix'}  = $mix;

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

###############################################################################

#############################################################################
#############################################################################
### Gear (Break) Controls
my %m_curr_brakes = ();
sub get_curr_brakes() { return \%m_curr_brakes; }

my $gr_brake_left  = "/controls/gear/brake-left";    # double
my $gr_brake_right = "/controls/gear/brake-right";
my $gr_brake_park  = "/controls/gear/brake-parking";    # int 0=off 1=On

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


###############################################################################
# KAP140 Autopilot
# ----------------
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

## alt-hold (false)
# apr-hold (false)
# gs-hold (false)
## hdg-hold (false)
# nav-hold (false)
# pitch-arm (0)
## pitch-axis (false)
## pitch-mode (0)
# rev-hold (false)
# roll-arm (0)
## roll-axis (false)
## roll-mode (0)

sub fgfs_get_K_locks() {
    my ($ah,$pa,$pm,$ra,$rm,$hh);
    fgfs_get_K_ah(\$ah); # alt-hold   bool
    fgfs_get_K_pa(\$pa); # pitch-axis bool
    fgfs_get_K_pm(\$pm); # ptich-mode val
    fgfs_get_K_ra(\$ra); # roll-axis  bool
    fgfs_get_K_rm(\$rm); # roll-mode  val
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

# Generic autopilot
my $fgfs_apl_alt = "/autopilot/locks/altitude";
my $fgfs_apl_head = "/autopilot/locks/heading";
my $fgfs_apl_speed = "/autopilot/locks/speed";
my $fgfs_apl_yaw = "/autopilot/locks/yaw";

sub fgfs_get_apl_alt($) {
    my $ref = shift;
    fgfs_get($fgfs_apl_alt, $ref) or get_exit(-2); # = true/false
    return 1;
}
sub fgfs_get_apl_head($) {
    my $ref = shift;
    fgfs_get($fgfs_apl_head, $ref) or get_exit(-2); # = true/false
    return 1;
}
sub fgfs_get_apl_speed($) {
    my $ref = shift;
    fgfs_get($fgfs_apl_speed, $ref) or get_exit(-2); # = true/false
    return 1;
}
sub fgfs_get_apl_yaw($) {
    my $ref = shift;
    fgfs_get($fgfs_apl_yaw, $ref) or get_exit(-2); # = true/false
    return 1;
}

sub fgfs_get_ap_locks() {
    my ($alt,$head,$speed,$yaw);
    my $rh = get_curr_aplocks();
    fgfs_get_apl_alt(\$alt);
    ${$rh}{'apl_alt'} = $alt;
    fgfs_get_apl_head(\$head);
    ${$rh}{'apl_head'} = $head;
    fgfs_get_apl_speed(\$speed);
    ${$rh}{'apl_speed'} = $speed;
    fgfs_get_apl_yaw(\$yaw);
    ${$rh}{'apl_yaw'} = $yaw;
    ${$rh}{'time'} = time();
    return $rh;
}

# show_ap_locks(fgfs_get_ap_locks())
sub show_ap_locks($) {
    my ($rh) = @_;
    my ($tm,$alt,$head,$speed,$yaw);
    $alt = ${$rh}{'apl_alt'};
    $head = ${$rh}{'apl_head'};
    $speed = ${$rh}{'apl_speed'};
    $yaw = ${$rh}{'apl_yaw'};
    $tm = lu_get_hhmmss_UTC(${$rh}{'time'});
    if (defined $alt) {
        if (length($alt) == 0) {
            $alt = 'off';
        }
    } else {
        $alt = 'offd';
    }
    if (defined $head) {
        if (length($head) == 0) {
            $head = 'off';
        }
    } else {
        $head = 'offd';
    }
    if (defined $speed) {
        if (length($speed) == 0) {
            $speed = 'off';
        }
    } else {
        $speed = 'offd';
    }
    if (defined $yaw) {
        if (length($yaw) == 0) {
            $yaw = 'off';
        }
    } else {
        $yaw = 'offd';
    }
    prt("$tm: A/P Locks alt=$alt, head=$head, speed=$speed, yaw=$yaw\n");
}


sub fgfs_get_position() {
    #my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag);
    my ($curr_lat,$curr_lon,$curr_alt,$curr_hdg,$curr_mag,$curr_hb,$curr_agl);
    my ($curr_aspd,$curr_gspd);
    fgfs_get_coord(\$curr_lon,\$curr_lat);
    fgfs_get_alt(\$curr_alt);
    fgfs_get_hdg_true(\$curr_hdg);
    fgfs_get_hdg_mag(\$curr_mag);
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
            my $diff = $ptm - $gtm; # get seconds different
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
    ${$rc}{'mag'} = $curr_mag;
    ${$rc}{'bug'} = $curr_hb;
    ${$rc}{'agl'} = $curr_agl;
    ${$rc}{'aspd'} = $curr_aspd; # Knots
    ${$rc}{'gspd'} = $curr_gspd; # Knots
    $mag_deviation = ($curr_hdg - $curr_mag);
    if ($chk_turn_done) {
        if (abs($requested_hb - $curr_mag) <= 1) {
            my $ctm = $tm - $bgn_turn_tm;
            my $angle = int(abs($requested_hb - $begin_hb));
            my $mag = int($curr_mag + 0.5);
            my $dps = '';
            if ($ctm > 0) {
                $dps = (int((($angle / $ctm) + 0.05) * 10) / 10).'DPS';
            }
            my $tmp = int($requested_hb + 0.5);
            prtt("Completed TURN $angle degrees to $tmp/$mag in $ctm seconds... $dps\n");
            $chk_turn_done = 0;
            $done_turn_done = 1;    # set done turn done message
        }
    }
    ${$rc}{'gettimeofday'} = [gettimeofday];
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

sub fgfs_get_environ() {
    my ($wspd,$whdg,$weast,$wnor,$metar,$mv);
    my $renv = get_curr_env();
    fgfs_get_wind_speed(\$wspd);
    ${$renv}{'speed-kt'} = $wspd;
    fgfs_get_wind_heading(\$whdg);
    ${$renv}{'heading-deg'} = $whdg;
    fgfs_get_wind_east(\$weast);
    ${$renv}{'east-fps'} = $weast;
    fgfs_get_wind_north(\$wnor);
    ${$renv}{'north-fps'} = $wnor;
    fgfs_get_mag_var(\$mv);
    ${$renv}{'mag-variation'} = $mv;
    $mag_variation = $mv;
    # THIS CAN CAUSE A PROBLEM
    #fgfs_get_metar(\$metar);
    #${$renv}{'metar'} = $metar;
    ${$renv}{'time'} = time();
    return $renv;
}

# ======================================================================================
# GET current com1 com2 nav1 nav2 adf - active and standby
# ===================================
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

# ======================================================================
# SET coms, navs, and adf frequenciies
# ====================================
sub fgfs_set_com1($) {
    my $com1 = shift;
    fgfs_set("/instrumentation/comm/frequencies/selected-mhz", $com1) or get_exit(-2); # double
    my ($c1a,$c1s);
    fgfs_get_comm1(\$c1a,\$c1s);
    prt("Have set COM1 to $c1a, standby $c1s\n");
}

sub fgfs_set_com2($) {
    my $com2 = shift;
    fgfs_set("/instrumentation/comm[1]/frequencies/selected-mhz", $com2) or get_exit(-2); # double
    my ($c2a,$c2s);
    fgfs_get_comm2(\$c2a,\$c2s);
    prt("Have set COM2 to $c2a, standby $c2s\n");
}

sub fgfs_set_nav1($) {
    my $nav1 = shift;
    fgfs_set("/instrumentation/nav/frequencies/selected-mhz", $nav1) or get_exit(-2); # double
    my ($n1a,$n1s);
    fgfs_get_nav1(\$n1a,\$n1s);
    prt("Have set NAV1 to $n1a, standby $n1s\n");
}
sub fgfs_set_nav2($) {
    my $nav2 = shift;
    fgfs_set("/instrumentation/nav[1]/frequencies/selected-mhz", $nav2) or get_exit(-2); # double
    my ($n2a,$n2s);
    fgfs_get_nav2(\$n2a,\$n2s);
    prt("Have set NAV2 to $n2a, standby $n2s\n");
}
sub fgfs_set_adf($) {
    my $adf = shift;
    fgfs_set("/instrumentation/adf/frequencies/selected-khz",$adf) or get_exit(-2); # double
    my ($adfa,$adfs);
    fgfs_get_adf(\$adfa,\$adfs);
    prt("Have set ADF  to $adfa, standby $adfs\n");
}
# ======================================================================


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

# how to get FUEL for the f-14b
# looks like /consumables/fuel/tank[0] to tank[9]?
# the fule instrument get /sim/model/f-14b/controls/fuel/bingo = 11500 - what is this?
# And /sim/model/f-14b/instrumentation/fuel-gauges/left-wing-display = '859.2...'
# and /sim/model/f-14b/instrumentation/fuel-gauges/right-wing-display = '874.8...'
sub fgfs_get_f14b_fuel_left($) {
    my $ref = shift;
    fgfs_get("/sim/model/f-14b/instrumentation/fuel-gauges/left-wing-display", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_f14b_fuel_right($) {
    my $ref = shift;
    fgfs_get("/sim/model/f-14b/instrumentation/fuel-gauges/right-wing-display", $ref) or get_exit(-2); # double
    return 1;
}

# center tank?
sub fgfs_get_f14b_C_gus($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[1]/level-gal_us", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_f14b_C_lbs($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[1]/level-lbs", $ref) or get_exit(-2); # double
    return 1;
}

# Beam Boxes
sub fgfs_get_f14b_LBB_gus($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[2]/level-gal_us", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_f14b_LBB_lbs($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[2]/level-lbs", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_f14b_RBB_gus($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[4]/level-gal_us", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_f14b_RBB_lbs($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[4]/level-lbs", $ref) or get_exit(-2); # double
    return 1;
}

# Sumps??? SHOULD THESE BE ADDED TO THE TOTAL - decided YES
sub fgfs_get_f14b_LS_gus($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[3]/level-gal_us", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_f14b_LS_lbs($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[3]/level-lbs", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_f14b_RS_gus($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[5]/level-gal_us", $ref) or get_exit(-2); # double
    return 1;
}
sub fgfs_get_f14b_RS_lbs($) {
    my $ref = shift;
    fgfs_get("/consumables/fuel/tank[5]/level-lbs", $ref) or get_exit(-2); # double
    return 1;
}

sub fgfs_get_consumables() {
    my ($t1gi,$t1gus,$t2gi,$t2gus);
    my ($tlbs,$tkgs);
    if ($got_aero_f14b) {
        my ($llbs,$rlbs,$ls,$rs,$lsb,$rsb,$cgal,$clbs);
        #my $one_gal = 8.345; # pounds
        #my $us_gal = 3.785411784;   # litres
        #my $uk_gal = 4.54609;       # litres
        my $uk2us = 1.2;    # uk to us gallon

        # QUANTITY / LEVEL
        #fgfs_get_f14b_fuel_left(\$t1gus);
        #fgfs_get_f14b_fuel_right(\$t2gus);
        fgfs_get_f14b_C_gus(\$cgal);
        fgfs_get_f14b_LBB_gus(\$t1gus);
        fgfs_get_f14b_RBB_gus(\$t2gus);
        fgfs_get_f14b_LS_gus(\$ls);
        fgfs_get_f14b_RS_gus(\$rs);
        $t1gus += $ls + ($cgal / 2);
        $t2gus += $rs + ($cgal / 2);

        # prt("Gals us left $t1gus, right $t2gus\n");
        $t1gi = $t1gus / $uk2us;
        $t2gi = $t2gus / $uk2us;

        # WEIGHT (pounds)
        fgfs_get_f14b_C_lbs(\$clbs);
        fgfs_get_f14b_LBB_lbs(\$llbs);
        fgfs_get_f14b_RBB_lbs(\$rlbs);
        fgfs_get_f14b_LS_lbs(\$lsb);
        fgfs_get_f14b_RS_lbs(\$rsb);
        $tlbs = $clbs + $llbs + $rlbs + $lsb + $rsb;
        $tkgs = $tlbs * 2.2;
    } else {
        fgfs_get_fuel1_imp(\$t1gi);
        fgfs_get_fuel1_us(\$t1gus);
        fgfs_get_fuel2_imp(\$t2gi);
        fgfs_get_fuel2_us(\$t2gus);
        fgfs_get_fuel_lbs(\$tlbs);
        fgfs_get_fuel_kgs(\$tkgs);
    }
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
    } elsif (($aero eq $air_f14b)||($aero =~ /^f-14b/)) {
        set_f_14b();
    }
    return $rs;
}

#############################################################################
### Flight Controls
my %m_curr_flight = ();

sub get_curr_flight() { return \%m_curr_flight; }

my $flt_aileron =       "/controls/flight/aileron"; # set_flt_ailerons
my $flt_aileron_trim =  "/controls/flight/aileron-trim";
my $flt_elevator =      "/controls/flight/elevator";
my $flt_elevator_trim = "/controls/flight/elevator-trim";
my $flt_flaps =         "/controls/flight/flaps";
my $flt_rudder =        "/controls/flight/rudder";
my $flt_rudder_trim =   "/controls/flight/rudder-trim";

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

#############################################################################


# ####################################################
# ====================================================

END {
	if (defined $FGFS_IO) {
        prtw("WARNING: End with socket open... closing connection...\n");
		fgfs_send("run exit") if ($send_run_exit);
		close $FGFS_IO;
        undef $FGFS_IO;
	}
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
        if (length($adf) && length($adfs) && is_all_numeric($adf) && is_all_numeric($adfs)) {
            prt("$ctm: ".sprintf("ADF   %03d (%03d)",$adf,$adfs)."\n");
        }
        prt("$ctm: ".sprintf("COM1 %03.3f (%03.3f) NAV1 %03.3f (%03.3f)",$c1a,$c1s,$n1a,$n1s)."\n");
        prt("$ctm: ".sprintf("COM2 %03.3f (%03.3f) NAV2 %03.3f (%03.3f)",$c2a,$c2s,$n2a,$n2s)."\n");
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

sub show_engines() {
    my ($running,$rpm,$crpm);
    my ($run2,$rpm2,$crpm2);
    my ($throt,$thpc,$throt2,$thpc2);
    my $re = fgfs_get_engines();
    $running = ${$re}{'running'};
    $rpm     = ${$re}{'rpm'};
    $throt   = ${$re}{'throttle'};
    # ONE engine
    $thpc = (int($throt * 100) / 10);
    $crpm = "rpm=";
    $crpm = "n1=" if ($is_jet_engine);
    if (defined $rpm && length($rpm)) {
        if ($is_jet_engine) {
            $crpm .= (int($rpm * 100) / 100);
        } else {
            $crpm .= int($rpm + 0.5);
        }
    } else {
        $crpm .= "N/A";
    }
    # prt("run = [$running] rpm = [$rpm]\n");
    if ($engine_count == 2) {
        # TWO engines
        $run2   = ${$re}{'running2'};
        $rpm2   = ${$re}{'rpm2'};
        $throt2 = ${$re}{'throttle2'};
        $thpc = (int($throt * 100) / 10);
        $crpm2 = "rpm=";
        $crpm2 = "n1=" if ($is_jet_engine);
        if (defined $rpm && length($rpm)) {
            if ($is_jet_engine) {
                $crpm2 .= (int($rpm2 * 100) / 100);
            } else {
                $crpm2 .= int($rpm2 + 0.5);
            }
        } else {
            $crpm2 .= "N/A";
        }
        $thpc2 = (int($throt2 * 100) / 10);
        prtt("Eng1=$running, $crpm, throt=$thpc\% ...\n");
        prtt("Eng2=$run2, $crpm2, throt=$thpc2\% ...\n");
    } else {
        prtt("Eng=$running, $crpm, throt=$thpc\% ...\n");
    }
}

sub show_engines_and_fuel() {
    show_engines();
    show_consumables(fgfs_get_consumables());
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

# from file [/home/geoff/downloads/curt/f-14b/Nasal/uas-demo.nas].
my @uas_demo_list = qw(
/ai/models/carrier/controls/ai-control
/ai/models/carrier/controls/tgt-speed-kts
/ai/models/carrier/orientation/true-heading-deg
/ai/models/carrier/position/latitude-deg
/ai/models/carrier/position/longitude-deg
/ai/models/tanker
/ai/models/tanker/position/altitude-ft
/ai/models/tanker/position/latitude-deg
/ai/models/tanker/position/longitude-deg
/ai/models/tanker/radar/bearing-deg
/ai/models/tanker/radar/range-nm
/autopilot/internal/true-heading-error-deg
/autopilot/internal/yaw-error-deg
/autopilot/route-manager/active
/autopilot/route-manager/current-wp
/autopilot/route-manager/route
/autopilot/route-manager/route/num
/autopilot/route-manager/wp/dist
/canopy/position-norm
/controls/flight/elevator
/controls/flight/elevator-trim
/controls/flight/flaps
/controls/flight/flapscommand
/controls/flight/ground-spoilers-armed
/controls/flight/rudder
/controls/flight/speedbrake
/controls/flight/wing-fold
/environment/wind-from-heading-deg
/environment/wind-speed-kt
/instrumentation/airspeed-indicator/indicated-speed-kt
/instrumentation/airspeed-indicator/true-speed-kt
/orientation/heading-deg
/orientation/side-slip-deg
/position/altitude-agl-ft
/position/altitude-ft
/sim/current-view/field-of-view
/sim/current-view/goal-heading-offset-deg
/sim/current-view/goal-pitch-offset-deg
/sim/current-view/view-number
/sim/freeze/fuel
/sim/gui/dialogs/f-14b-drone/config/dialog
/sim/hud/enable3d[1]
/sim/hud/visibility[1]
/sim/input/click/altitude-ft
/sim/input/click/elevation-ft
/sim/input/click/latitude-deg
/sim/input/click/longitude-deg
/sim/signals/fdm-initialized
/sim/time/elapsed-sec
/sim/tower/altitude-ft
/sim/tower/auto-position
/sim/tower/latitude-deg
/sim/tower/longitude-deg
/uas/airport-id
/uas/approach/closing-speed-kt
/uas/approach/diameter
/uas/approach/dist-to-touchdown
/uas/approach/forty-five-dist
/uas/approach/gs-lock
/uas/approach/ideal-alt-ft
/uas/approach/ideal-vertical-rate
/uas/approach/real-glideslope
/uas/approach/runway-heading-error
/uas/approach/target-vert-speed
/uas/approach/turn-dist
/uas/approach/vert-error
/uas/camera-target
/uas/camera-zoom
/uas/flight-altitude-ft
/uas/master-switch
/uas/runway-id
/uas/rwy-dist
/uas/state
/uas/view-mode
/uas/xtrack
/velocities/airspeed-kt
/velocities/groundspeed-kt
);


1;
# eof - lib_fgio.pl
