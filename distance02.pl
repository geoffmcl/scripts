#!/usr/bin/perl -w
# NAME: distance02.pl
# AIM: Use perl trig function for distance London to Tokyo...
# from : http://perldoc.perl.org/Math/Trig.html
# previous disptance.pl, with no use of SIMGEAR
# 19/04/2016 - If distance between point is less than 1 Km, show meters and feet
# 08/07/2015 - Move into scripts repo
# 29/11/2014 - Added -a ICAO1:ICAO2[;ICAO3...] to get airport distances
# 11/10/2014 - allow bgn-lat,bgn-lon,end-lat,end-lon - 4 comma separated values
# 17/12/2013 - Give precise info, unless verbosity raised
# 08/09/2011 - Minor adjustment - when -v2 output SG_Head in FULL - see possible error in az2!!! 
#              And -i <NUM> option, to output a list of points inbetween
# 06/08/2011 - Add -s speed in knots, default = 100 kt, and FIX inadvertent lat,lon reversal ;=))
# 26/02/2011 - Improved Distance: display
# 18/12/2010 - Fix heading from reverse track to heading (true)...
# 05/12/2010 - 01/12/2010 - Allow two comma separated pairs of input
# 20/11/2010 (c) Geoff R. McLane http://geoffair.net/mperl - GNU GPL v2 (or +)
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Math::Trig qw(great_circle_distance great_circle_direction deg2rad rad2deg);
use Time::HiRes qw( gettimeofday tv_interval );
use Cwd;
# my $perl_dir = 'C:/GTools/perl'; 
# unshift(@INC, $perl_dir);
my $cwd = cwd();
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
unshift(@INC, $perl_dir);
my $temp_dir = $perl_dir . "/temp";
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
require 'lib_fgio.pl' or die "Unable to load 'lib_fgio.pl'! Check location and \@INC content.\n";

my $VERS = "0.0.8 2016-04-19"; # enhance display when distance small
# my $VERS = "0.0.7 2015-07-15"; # some functions moved to library
# my $VERS = "0.0.6 2015-07-08"; # add to scripts repo
# my $VERS = "0.0.5 2014-11-29"; # allow ICAO inputs
# my $VERS = "0.0.4 2014-10-11"; # allow single 4 value input
# my $VERS = "0.0.3 2011-09-08"; # added --inter <NUM>, to output a SET of points between
# my $VERS = "0.0.2 2011-08-06"; # updated version
# my $VERS = "0.0.1 2010-12-01" # premier version

# references
# air naviagtion - http://www.raeng.org.uk/publications/other/1-aircraft-navigation
# Cosine Rule
# aspd^2 = wspd^2 + gspd^2 - 2 * apsd * gspd * cos(whdg);
#            0 =  b^2   -      2acos(C)b                  + c;
# quadratic: 0 = gspd^2 - (2 * apsd * cos(whdg)) * gspd + (wspd^2 - aspd^2)

# log file stuff
our ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
$outfile = ($os =~ /win/i) ? path_u2d($outfile) : path_d2u($outfile);
open_log($outfile);

my $load_log = 0;

# 1 knots = 1.85200 kph
my $K2KPH = 1.85200;
my $Km2NMiles = 1 / $K2KPH; # Nautical Miles.
#my $Km2NMiles = 0.53995680346; # Nautical Miles.
my $MAD_LL = -200;
# /** Feet to Meters */
my $SG_FEET_TO_METER = 0.3048;
# /** Meters to Feet */
my $SG_METER_TO_FEET = 3.28083989501312335958;

my $M_PI = 3.141592653589793;
my $M_D2R = $M_PI / 180;    # degree to radian
my $M_R2D = 180.0 / $M_PI;

my $xg_out = $temp_dir."/tempdist.xg";

# London and Tokyo - not used
#my $lonlon = -0.5;
#my $lonlat = 51.3;
#my $toklon = 139.8;
#my $toklat = 35.7;

my $g_lat1 = $MAD_LL;
my $g_lon1 = $MAD_LL;
my $g_lat2 = $MAD_LL;
my $g_lon2 = $MAD_LL;

my $aptdat = "X:\\fgdata\\Airports\\apt.dat.gz";
my $g_ias = 100; # Knots - c182
#my $g_ias = 80; # Knots - c152-c172
my $g_speed = $g_ias * $K2KPH; # Knots to Kilometers/Hour
# my $CP_EPSILON = 0.00001;
my $CP_EPSILON = 0.0000001; # EQUALS SG_EPSILON 20101121
my $g_interval = $MAD_LL;
my $got_icao = 0;
my $do_global_vals = 0;
my $verbosity = 0;

my ($usr_wind_dir,$usr_wind_spd);
my $got_wind = 0;

# Debug
my $debug_on = 0;
#anno 148.576583049264 -31.6521054356504 TL
my $tl_lon = 148.576583049264;
my $tl_lat = -31.6521054356504;
#anno 148.617914716388 -31.7624265822579 BL
my $bl_lon = 148.617914716388;
my $bl_lat = -31.7624265822579;
#  -31.7462205,148.6980507 -31.6254689,148.6527077 -w 80@3

my @warnings = ();
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

sub VERB1() { return ($verbosity >= 1); }
sub VERB2() { return ($verbosity >= 2); }
sub VERB5() { return ($verbosity >= 5); }
sub VERB9() { return ($verbosity >= 9); }

# constants
#/** Feet to Meters */
my $FEET_TO_METER = 0.3048;
sub prtw($) {
   my ($tx) = shift;
   $tx =~ s/\n$//;
   prt("$tx\n");
   push(@warnings,$tx);
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

sub in_world($$) {
    my ($lat,$lon) = @_;
    if (($lat < -90)||
        ($lat >  90)||
        ($lon < -180)||
        ($lon >  180)) {
        return 0;   # FAILED
    }
    return 1;
}

sub in_world_show($$) {
    my ($lat,$lon) = @_;
    if (($lat < -90)||
        ($lat >  90)||
        ($lon < -180)||
        ($lon >  180)) {
        prt("Testing lat=$lat, lon=$lon ");
        prt("lat LT -90 ") if ($lat < -90);
        prt("lat GT  90 ") if ($lat >  90);
        prt("lon LT -180 ") if ($lon < -180);
        prt("lon GT  180 ") if ($lon >  180);
        prt("\n");
        return 0;   # FAILED
    }
    return 1;
}


##sub set_decimal1_stg($) {
##    my $r = shift;
##    ${$r} =  int((${$r} + 0.05) * 10) / 10;
##    ${$r} = "0.0" if (${$r} == 0);
##    ${$r} .= ".0" if !(${$r} =~ /\./);
##}
##sub set_decimal2_stg($) {
##    my $r = shift;
##    ${$r} =  int((${$r} + 0.005) * 100) / 100;
##    ${$r} = "0.00" if (${$r} == 0);
##    ${$r} .= ".00" if !(${$r} =~ /\./);
##}

sub set_decimal_stg($) {
    my $r = shift;
    #if (${$r} < 10) {
    #    set_decimal2_stg($r);
    #} else {
        set_decimal1_stg($r);
    #}
}


 # Notice the 90 - latitude: phi zero is at the North Pole
sub NESW { deg2rad($_[0]), deg2rad(90 - $_[1]) }

# moved to lib_fgio.pl library
#sub GetHeadingError($$) {
#    my ($initial,$final) = @_;
#    if ($initial > 360 || $initial < 0 || $final > 360 || $final < 0) {
#        pgm_exit(1,"Internal ERROR: GetHeadingError invalid params $initial $final\n");
#    }
#
#    my $diff = $final - $initial;
#    my $absDiff = abs($diff);
#    if ($absDiff <= 180) {
#        # Edit 1:27pm
#        return $absDiff == 180 ? $absDiff : $diff;
#    } elsif ($final > $initial) {
#        return $absDiff - 360;
#    }
#    return 360 - $absDiff;
#}
#
#sub get_hdg_diff($$) {
#    my ($chdg,$nhdg) = @_;
#    return GetHeadingError($chdg,$nhdg);
#}


sub show_sg_distance_vs_est($$$$$$) {
    my ($lat1,$lat2,$lon1,$lon2,$estdist,$esthdg) = @_;
    my ($sg_az1,$sg_az2,$sg_dist,$res,$sg_km,$sg_ikm,$dsg_az1,$dsg_az2);
    my ($eddiff,$edpc,$ahdg,$ahdiff,$hdgpc,$adhdg,$distmsg,$hdgmsg);
    $res = fg_geo_inverse_wgs_84 ($lat1,$lon1,$lat2,$lon2,\$dsg_az1,\$dsg_az2,\$sg_dist);
    $sg_km = $sg_dist / 1000;
    $sg_ikm = int($sg_km + 0.5);
    $sg_az1 = int(($dsg_az1 * 10) + 0.05) / 10;
    $sg_az2 = int(($dsg_az2 * 10) + 0.05) / 10;
    $eddiff = abs($sg_km - $estdist);
    $edpc = ($eddiff / $sg_km) * 100;
    $edpc = int(($edpc * 10) + 0.05) / 10;
    if ($eddiff < $CP_EPSILON) {
        $edpc = "SAME";
    } elsif ($edpc < 1) {
        $edpc = 'lt 1';
    }
    $edpc = " $edpc" while (length($edpc) < 5);

    $adhdg = abs($sg_az1 - $esthdg);
    $ahdiff = ($adhdg / $sg_az1);
    $hdgpc = ($ahdiff / 360);
    $hdgpc = int(($hdgpc * 10) + 0.05) / 10;
    if ($ahdiff < $CP_EPSILON) {
        $hdgpc = "SAME";
    } elsif ($hdgpc < 1) {
        $hdgpc = 'lt 1';
    }
    $hdgpc = " $hdgpc" while (length($hdgpc) < 5);
    prt( "SG_Dist : $sg_ikm kilometers ($sg_km) ($edpc \% diff)\n");
    if (VERB2()) {
        prt("SG_Head : $dsg_az1 degs (inverse $dsg_az2) ($hdgpc \% diff)\n");
    } else {
        prt("SG_Head : $sg_az1 degs (inverse $sg_az2) ($hdgpc \% diff)\n");
    }
    if (VERB9()) {
        # fly the distance, and report heading changes, if any
        # direction is $dsg_az1, $sg_dist 
        my $flat = $lat1;
        my $flon = $lon1;
        my $fhdg = $dsg_az1;
        my $fdist = 1000;
        ### my $rem = $sg_km;
        my $rem = $sg_dist;
        my ($wplat,$wplon,$wpaz,$wdlat,$wdlon);
        my ($naz1,$naz2,$ndist);
        my ($nhdg,$ndistnm,$degs,$chg,$ndistkm);
        $chg = int( $rem / $fdist );
        $ndistkm = ''.int($fdist / 1000).'Km';
        $ndistnm = get_dist_stg_nm($fdist);
        prt("Show $chg way points, computed each $ndistkm ($ndistnm)\n");
        while ($rem > $fdist) {
            # jump to next wp, on heading
            $res = fg_geo_direct_wgs_84($flat,$flon,$fhdg,$fdist, \$wplat, \$wplon, \$wpaz);
            $res = fg_geo_inverse_wgs_84($wplat,$wplon,$lat2,$lon2,\$naz1,\$naz2,\$ndist);

            $degs = get_hdg_diff($fhdg,$naz1);
            $chg = 1;
            if ( ($degs > -0.1) && ($degs < 0.1) ) {
                $chg = 0;   # difference in heading too small
            }
            $naz2 = $naz1;
            set_hdg_stg(\$naz2);
            $nhdg = $naz1;
            set_hdg_stg(\$nhdg);
            set_decimal1_stg(\$degs);
            ### $ndistkm = ''.int($ndist / 1000).'Km';
            $ndistkm = get_dist_stg_km($ndist);
            $ndistnm = get_dist_stg_nm($ndist);
            $wdlat = $wplat;
            $wdlon = $wplon;
            set_lat_stg(\$wdlat);
            set_lon_stg(\$wdlon);
            if ($chg) {
                prt("At wp $wdlat,$wdlon, turn from $naz2 to $nhdg ($degs), dist $ndistnm $ndistkm\n");
            } else {
                $nhdg = $naz1;
                set_decimal1_stg(\$nhdg);
                prt("At wp $wdlat,$wdlon, cont hdg $nhdg, dist $ndistnm $ndistkm\n");
            }
            $flat = $wplat;
            $flon = $wplon;
            
            $fhdg = $naz1;
            $rem -= $fdist;
        }
    }
}

my $flag_show_sg_stg = 0;
my $flag_show_sg_rev = 0;
my ($sg_clat,$sg_clon,$sg_hdg);
# get_sg_distance_vs_est( $lat1,$lon1,$lat2,$lon2,$d_km,$t_degs, \$cmpdist, \$cmphdg );
sub get_sg_distance_vs_est($$$$$$$$) {
    my ($lat1,$lon1,$lat2,$lon2,$estdist,$esthdg,$rdist,$rhdg) = @_;
    my ($sg_az1,$sg_az2,$sg_dist,$res,$sg_km,$sg_ikm);
    my ($eddiff,$edpc,$ahdg,$ahdiff,$hdgpc,$adhdg,$distmsg,$hdgmsg,$caz1);
    my $flag = 0;
    #$res = fg_geo_inverse_wgs_84 ($lat1,$lon1,$lat2,$lon2,\$sg_az1,\$sg_az2,\$sg_dist);
    $res = fg_geo_inverse_wgs_84( $lat1,$lon1,$lat2,$lon2,\$sg_az2,\$sg_az1,\$sg_dist);
    $sg_hdg = $sg_az2;  # keep SG heading, and get SG center point
    $res = fg_geo_direct_wgs_84(  $lat1,$lon1,$sg_az2,($sg_dist / 2), \$sg_clat, \$sg_clon, \$caz1 );

    $sg_km = $sg_dist / 1000;
    $sg_ikm = int($sg_km + 0.5);
    $sg_az1 = int(($sg_az1 * 10) + 0.05) / 10;
    $sg_az2 = int(($sg_az2 * 10) + 0.05) / 10;
    $eddiff = abs($sg_km - $estdist);
    $edpc = ($eddiff / $sg_km) * 100;
    $edpc = int(($edpc * 10) + 0.05) / 10;
    if ($eddiff < $CP_EPSILON) {
        $edpc = "SAME";
        $flag |= 1;
    } elsif ($edpc < 1) {
        $edpc = 'lt 1';
        $flag |= 1;
    }
    $edpc = " $edpc" while (length($edpc) < 5);

    # could be subtraction 359 from 1 - max difference = 360 degrees
    $adhdg = abs($sg_az1 - $esthdg);
    $ahdiff = $adhdg; # ($adhdg / $sg_az1);
    $ahdiff -= 180 if ($ahdiff >= 180);
    $hdgpc = ($ahdiff / 180); # ($ahdiff / 360);
    $hdgpc = int(($hdgpc * 10) + 0.05) / 10;
    # prt("Comparing HEADINGS SG $sg_az1 EST $esthdg... diff [$adhdg] [$ahdiff] [$hdgpc]\n");
    if ($ahdiff < $CP_EPSILON) {
        $hdgpc = "SAME";
        $flag |= 2;
    } elsif ($hdgpc < 0.001) {
        $hdgpc = 'lt 1';
        $flag |= 2;
    } else {
        $hdgpc = int($hdgpc * 100);
    }
    $hdgpc = " $hdgpc" while (length($hdgpc) < 5);
    #${$rdist} = " SG_Dist : $sg_ikm kilometers ($sg_km) ($edpc \% diff)";
    #${$rhdg} = " SG_Head : $sg_az1 degs (inverse $sg_az2) ($hdgpc \% diff)";
    if ( !$flag_show_sg_stg && ($flag == 3) ) {
        ${$rdist} = " (SG ok)";
        ${$rhdg}  = " (SG ok)";
    } else {
        ${$rdist} = " SG_Dist : $sg_ikm km ($edpc \% diff)";
        if ($flag_show_sg_rev) {
            $sg_az2 = int($sg_az2 + 0.5);
            ${$rhdg}  = " SG_Head : $sg_az1/$sg_az2 degs ($hdgpc \% diff)";
        } else {
            ${$rhdg}  = " SG_Head : $sg_az1 degs ($hdgpc \% diff)";
        }
    }
    return $flag;
}

sub get_latlon_stg($) {
    my ($ll) = shift;
    my $stg = "";
    my $len = length($ll);
    my ($i,$ch);
    for ($i = 0; $i < $len; $i++) {
        $ch = substr($ll,$i,1);
        last if ($ch eq '.');
        $stg .= $ch;
    }
    $stg = " ".$stg while (length($stg) < 4);
    $ch = '.' if ($ch ne '.');
    $stg .= $ch;
    $i++;
    for (; $i < $len; $i++) {
        $ch = substr($ll,$i,1);
        $stg .= $ch;
    }
    $stg .= " " while (length($stg) < 19);
    return $stg;
}
sub get_heading_stg($) {
    my $hdg = shift;
    my $stg = sprintf("%5.1f",$hdg);
    #$stg = " ".$stg while (length($stg) < 5);
    return $stg;
}


sub show_intervals($$$$) {
    my ($lat1,$lon1,$lat2,$lon2) = @_;
    my ($dsg_az1,$dsg_az2,$sg_dist,$dist_m,$ikm,$dnm);
    my ($i,$i2,$nlat,$nlon,$naz,$scnt,$nlat2,$nlon2,$naz2,$raz,$max);
    my $res = fg_geo_inverse_wgs_84 ($lat1,$lon1,$lat2,$lon2,\$dsg_az1,\$dsg_az2,\$sg_dist);
    $max = $g_interval;
    my $dist = $sg_dist;
    $dist = $sg_dist / $max if ($max > 0);
    ###if (VERB5()) {
    ###    prt("List of $g_interval intervals from $lat1,$lon1,\n");
    ###    prt("on azimuth $dsg_az1, $sg_dist meters, to $lat2,$lon2\n");
    ###} else {
        #$naz2 = get_heading_stg($dsg_az1);
        #prt("List $g_interval intervals, hdg $naz2\n");
        $dist_m = $dist;
        $ikm = $dist_m / 1000;
        $dnm = $ikm * $Km2NMiles;
        set_decimal_stg(\$ikm);
        set_decimal_stg(\$dnm);
        $scnt = sprintf("%3d:",0);
        $nlat2 = get_latlon_stg($lat1);
        $nlon2 = get_latlon_stg($lon1);
        $naz2  = get_heading_stg($dsg_az1);
        $scnt = " " x length($scnt);
        prt("$scnt $nlat2 $nlon2 in $g_interval legs.\n");
        ###prt("$scnt $nlat2 $nlon2 in $g_interval legs $ikm km. $dnm nm.\n");
    ###}
    $scnt = sprintf("%3d:",0);
    if (VERB9()) {
        $nlat2 = get_latlon_stg($lat1);
        $nlon2 = get_latlon_stg($lon1);
        $naz2  = get_heading_stg($dsg_az1);
        $scnt = " " x length($scnt);
        prt("$scnt $nlat2 $nlon2 $naz2\n");
    }
    for ($i = 0; $i < $max; $i++) {
        $i2 = $i + 1;
        $dist_m = $dist * $i2;
        fg_geo_direct_wgs_84( $lat1, $lon1, $dsg_az1, $dist_m, \$nlat, \$nlon, \$naz );
        $scnt = sprintf("%3d:",$i2);
        $ikm = $dist_m / 1000;
        $dnm = $ikm * $Km2NMiles;
        set_decimal_stg(\$ikm);
        set_decimal_stg(\$dnm);
        #if (VERB1()) {
            $nlat2 = get_latlon_stg($nlat);
            $nlon2 = get_latlon_stg($nlon);
            $raz = $naz + 180;
            $raz -= 360 if ($raz > 360);
            $naz2  = get_heading_stg($raz);
            prt("$scnt $nlat2 $nlon2 $naz2 $ikm km. $dnm nm.\n");
        #} else {
        #    prt("$scnt $nlat $nlon $naz\n");
        #}
    }
    $dist_m = $dist * $max;
    $ikm = $dist_m / 1000;
    $dnm = $ikm * $Km2NMiles;
    set_decimal_stg(\$ikm);
    set_decimal_stg(\$dnm);
    #if (VERB9()) {
        $scnt = sprintf("%3d:",0);
        $nlat2 = get_latlon_stg($lat2);
        $nlon2 = get_latlon_stg($lon2);
        $naz2  = get_heading_stg($dsg_az1);
        $scnt = " " x length($scnt);
        ###prt("$scnt $nlat2 $nlon2 $naz2 $ikm km. $dnm nm.\n");
        prt("$scnt $nlat2 $nlon2 $naz2\n");
    #}
}

sub get_wind_xg($$$$$$) {
    my ($wlat1,$wlon1,$wlat2,$wlon2,$whdg1,$wsize) = @_;
    my $degs = 30;
    my $xg = "# wsize $wsize\n";
    if ($wsize > 3) {
        my ($wlatv1,$wlonv1,$whdg,$wlatv2,$wlonv2,$waz1);

        # shift off wind direction by n degs
        $whdg = $whdg1 + $degs;
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

        $whdg = $whdg1 - $degs;
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
    return $xg;
}

sub get_hdg_diff2($$) {
    my ($initial,$final) = @_;
    if ($initial > 360 || $initial < 0 || $final > 360 || $final < 0) {
        pgm_exit(1,"Internal ERROR: get_hdg_diff2 invalid params $initial $final\n");
    }
    my $diff = $final - $initial;
    my $absDiff = abs($diff);
    if ($absDiff <= 180) {
        return $absDiff == 180 ? $absDiff : $diff;
    } elsif ($final > $initial) {
        return $absDiff - 360;
    }
    return 360 - $absDiff;
}


sub show_distance($$$$) {
    my ($lon1,$lat1,$lon2,$lat2) = @_;
    my ($cmpdist,$cmphdg);
    my @Pos1 = NESW( $lon1, $lat1);
    my @Pos2 = NESW( $lon2, $lat2);
    my $d_km = great_circle_distance(@Pos1, @Pos2, 6378); # About 9600 km Lon-Tok.
    my $t_degs = rad2deg(great_circle_distance(@Pos1, @Pos2)); # degrees to cover
    my $hdg = rad2deg(great_circle_direction(@Pos2, @Pos1)); # track
    my $rhdg = rad2deg(great_circle_direction(@Pos1, @Pos2)); # track
    my $d_nmiles = $d_km * $Km2NMiles;
    my ($whdg,$gspd,$gspd_kph,$wspd_kph,$tmp);
    my ($nlat,$nlon,$naz,$alat,$alon);
    #my ($rwhdg,$rgspd);
    my $ceta = '';
    my $chrs = 0;
    my $hrs = $d_km / $g_speed; # distance (km) / speed (kph)
    my $dsecs = $hrs * 60 * 60; # can be quite small, if distance short, and/or speed high
    my $mps = ($g_speed * 1000) / 3600;
    my $fps = $mps * $SG_METER_TO_FEET;
    my $etastg = get_hhmmss($hrs);

    if ($hrs < (1/60)) {
        # less than a minute
        # avoid   "00:00:35", use either
        #         "59  secs", or
        #         "0.58 sec", if really small
        my $tail = "  secs";
        my $msecs = int($dsecs);
        if ($msecs < 10) {
            if ($dsecs < 1) {
                $msecs = sprintf("%0.2f",$dsecs);
                $tail = " sec";
            } else {
                $msecs = "0$msecs";
            }
        } 
        $etastg = "$msecs$tail";
        ## $etastg = "$hrs  hrs";
    }

    $tmp = int($g_ias + 0.05);
    my $xg = "anno $lon1 $lat1 Start $tmp kts\n";

    $xg .= "color yellow\n";
    $xg .= "$lon1 $lat1\n";
    $xg .= "$lon2 $lat2\n";
    $xg .= "anno $lon2 $lat2 Dest.\n";
    $xg .= "NEXT\n";
    #$alat = ($lat1 + $lat2) / 2;
    #$alon = ($lon1 + $lon2) / 2;
    fg_geo_direct_wgs_84( $lat1, $lon1, $rhdg, ($d_km * 1000) / 3, \$alat, \$alon, \$naz );
    $tmp = int($hdg + 0.05); # only WHOLE degrees

    $xg .= "anno $alon $alat Targ: $tmp eta: $etastg\n";
    if ($got_wind) {
        $wspd_kph = $usr_wind_spd * $K2KPH;
        ##my $wtm = $d_km / $wspd_kph;    # estimate time
        my $wdist = $wspd_kph * 3600 * $hrs;
        my $wsize = $wdist / 8; # was 5;
        $xg .= "# Wind at $wspd_kph for $hrs = $wdist\n";
        my $rh = compute_wind_course($hdg,$g_ias,$usr_wind_dir,$usr_wind_spd);
        $whdg = ${$rh}{'heading'};
        $gspd = ${$rh}{'groundspeed'};
        ######## why add this reverse???? #######
        #$rh = compute_wind_course($rhdg,$g_ias,$usr_wind_dir,$usr_wind_spd);
        #$rwhdg = ${$rh}{'heading'};
        #$rgspd = ${$rh}{'groundspeed'};
        $gspd_kph = $gspd * $K2KPH;
        $chrs = $d_km / $gspd_kph; # distance (km) / speed (kph)
        if ($chrs < 0.001) {
            $ceta = "weta: BIG problem!";
        } else {
            $tmp = int($gspd + 0.05); # only WHOLE knots
            $ceta = "weta: ".get_hhmmss($chrs)." at $tmp kts";
        }

        ###################################################################################
        ### WIND: target lat,lon, in wind direction, for the dist appx covered in that time
        fg_geo_direct_wgs_84( $lat2, $lon2, $usr_wind_dir, $wdist, \$nlat, \$nlon, \$naz );

        $xg .= "color gray\n";
        $xg .= get_wind_xg($lat2,$lon2,$nlat,$nlon,$usr_wind_dir,$wsize);
        ##$xg .= get_wind_xg($nlat,$nlon,$lat2,$lon2,$usr_wind_dir,$wsize);

        $xg .= "color green\n";
        $xg .= "$lon2 $lat2\n";
        $xg .= "$nlon $nlat\n";
        $xg .= "NEXT\n";

        $alat = ($lat2 + $nlat) / 2;
        $alon = ($lon2 + $nlon) / 2;
        $xg .= "anno $alon $alat Wind: $usr_wind_dir".'@'."$usr_wind_spd\n";

        ###################################################################################
        ### TRACK: That should be taken
        $xg .= "color blue\n";
        $xg .= "$lon1 $lat1\n";
        $xg .= "$nlon $nlat\n";
        $xg .= "NEXT\n";
        $alat = ($lat1 + $nlat) / 2;
        $alon = ($lon1 + $nlon) / 2;
        $tmp = int($whdg + 0.05); # only WHOLE degrees
        $xg .= "anno $alon $alat Track: $tmp $ceta\n";

    }

    if (length($xg_out)) {
        $xg_out = ($os =~ /win/i) ? path_u2d($xg_out) : path_d2u($xg_out);
        write2file($xg,$xg_out);
        prt("Written xg output to $xg_out\n");
    }

    ########################################################################
    # derived (for display)
    ########################################################################
    # convert great circle distance, $d_km, to distance meters, $d_m, and feet $d_ft
    my $d_m = int(($d_km * 1000) + 0.5);
    my $d_ft = int(($d_km * 1000 * $SG_METER_TO_FEET) + 0.5);
    my $chdg = int($hdg + 0.05); # only WHOLE degrees
    $chdg = "0$chdg" while (length($chdg) < 3);
    my $crhdg = int($rhdg + 0.5);
    $crhdg = "0$crhdg" while (length($crhdg) < 3);
    my $thdg = $hdg;
    
    #my $ikm = int($d_km + 0.5);
    my $ikm = $d_km;
    set_decimal_stg(\$ikm);
    #my $inm = int(($d_nmiles + 0.05) * 10) / 10;
    my $inm = $d_nmiles;
    set_decimal_stg(\$inm);
    #$degs = int($degs + 0.5);
    #$degs = int($degs + 0.5);
    $t_degs = sprintf("%0.6f",$t_degs);
    get_sg_distance_vs_est( $lat1,$lon1,$lat2,$lon2,$d_km,$hdg, \$cmpdist, \$cmphdg );

    my $dias = "$g_ias Kts";
    my $ddisp = "$ikm Km, $inm Nm";
    if ($ikm < 1) {
        $ddisp = "$d_m m, $d_ft feet";
        # change $dias to mps, fps...
        $dias = sprintf("%0.1f mps, %0.1f fps", $mps, $fps );
    }

    if (VERB1()) {
        set_decimal1_stg(\$thdg);
        prt("Center: lat,lon $sg_clat,$sg_clon, heading $thdg, dist $d_m m, $d_ft ft..\n");
    }
    if (VERB2()) {
        prt("From (lon,lat): $lon1,$lat1 to $lon2,$lat2 is about -\n");
        prt("Distance: $ikm kilometers ($d_km) $inm Nm $cmpdist\n");
        prt("Heading : $chdg/$crhdg, for $t_degs degs $cmphdg\n");
        prt("ETA     : $etastg, at $dias\n");
        if ($got_wind) {
            $whdg = int($whdg + 0.5);
            $gspd = int($gspd + 0.5);
            #$rwhdg = int($rwhdg + 0.5);
            #$rgspd = int($rgspd + 0.5);
            #prt("Correct : Wind=".$usr_wind_dir.'@'.$usr_wind_spd." hdg $whdg at $gspd, rhdg $rwhdg at $rgspd.");
            prt("Correct : Wind=".$usr_wind_dir.'@'.$usr_wind_spd." hdg $whdg at $gspd $ceta.\n");
        }
    } else {
        prt("Dist: $ddisp, hdg $chdg, $etastg, at $dias.");
        if ($got_wind) {
            $whdg = int($whdg + 0.5);
            $gspd = int($gspd + 0.5);
            #$rwhdg = int($rwhdg + 0.5);
            #$rgspd = int($rgspd + 0.5);
            # prt(" Wind=".$usr_wind_dir.'@'.$usr_wind_spd." hdg $whdg/$rwhdg at $gspd/$rgspd.");
            prt(" Wind=".$usr_wind_dir.'@'.$usr_wind_spd." hdg $whdg at $gspd $ceta.");
        }
        prt("\n");
    }
    # print "km $km / spd $g_speed = $hours\n";
    if (VERB5()) {
        show_sg_distance_vs_est($lat1,$lat2,$lon1,$lon2,$d_km,$t_degs);
    }
    # =================================================
    if ($g_interval != $MAD_LL) {
        show_intervals($lat1,$lon1,$lat2,$lon2);
    }
    return $d_km;
}

sub get_hhmmss($) {
    my ($hours) = @_;
    my $hrs = int($hours);
    my $mins = ($hours * 60) - ($hrs * 60);
    my $min = int($mins);
    my $secs = ($mins * 60) - ($min * 60);
    my $days = 0;
    if ($hrs >= 24) {
        $days++;
        $hrs -= 24;
    }
    $min = ($min < 10) ? "0$min" : $min;
    $secs = int( $secs + 0.5 );
    $secs = ($secs < 10) ? "0$secs" : $secs;
    $hrs = ($hrs < 10) ? "0$hrs" : $hrs;
    my $stg = '';
    $stg .= "Days $days, " if ($days);
    $stg .= "$hrs:$min:$secs";
    return $stg;
}

# Airport Line. eg '1 5355 1 0 KABQ Albuquerque Intl Sunport'
# 0 1    - this as an airport header line. 16 is a seaplane/floatplane base, 17 a heliport.
# 1 5355 - Airport elevation (in feet above MSL).  
# 2 1    - Airport has a control tower (1=yes, 0=no).
# 3 0   - Display X-Plane’s default airport buildings (1=yes, 0=no).
# 4 KABQ   - Identifying code for the airport (the ICAO code, if one exists).
# 5+Albuquerque Intl Sunport - Airport name.
sub find_apts($) {
    my $icaos = shift;
    my ($i,$line,@arr,$type,$len,$icao,$gotapt,$ra);
    my @airs = split(":",$icaos);
    $len = scalar @airs;
    if ($len < 2) {
        pgm_exit(1,"ICAO string $icaos did NOT split into 2 or more on ':'!\n");
    }
    my $t1 = [gettimeofday];
    my %icaoh = ();
    for ($i = 0; $i < $len; $i++) {
        $icao = $airs[$i];
        $icaoh{$icao} = 0;
    }
    if (! -f $aptdat) {
        pgm_exit(1,"Failed to 'stat' file '$aptdat'!\n");
    }
    prt("Processing file $aptdat... for $len ICAO, ".join(":",@airs)."... moment...\n") if (VERB1());
    if (!open(INF,"gzip -cdq $aptdat|")) {
        pgm_exit(1,"Failed to 'open' file '$aptdat'!\n");
    }
    my $ver = 0;
    my $lncnt = 0;
    while ($line = <INF>) {
        $lncnt++;
        chomp $line;
        $line = trim_all($line);
        if ($line =~ /^(\d+)\s+Version/) {
            $ver = $1;
            last;
        }
    }
    my %fnd_airports = ();
    my ($alat,$alon,$rwcnt,$rlat,$rlon);
    my ($hdg,$rlen,$hdgr,$glat,$glon);
    my ($elat1,$elon1,$elat2,$elon2,$eaz1,$eaz2);
    my ($rwycnt,$res,$elap);
    $rwycnt = 0;
    if ($ver) {
        $gotapt = 0;
        while ($line = <INF>) {
            $lncnt++;
            chomp $line;
            $line = trim_all($line);
            $len = length($line);
            next if ($len == 0);
            @arr = split(/\s+/,$line);
            $type = $arr[0];
            last if ($type == 99);
            $icao = $arr[4];
            if (($type == 1) && (defined $icaoh{$icao})) {
                $gotapt = 1;
                while ($gotapt) {
                    $gotapt = 0;
                    my @a = @arr;
                    $icaoh{$icao} = 1;
                    $fnd_airports{$icao} = [];
                    $ra = $fnd_airports{$icao};
                    my $got_twr = 0;
                    $rwycnt = 0;
                    $glat = 0;
                    $glon = 0;
                    $alat = 0;
                    $alon = 0;
                    while ($line = <INF>) {
                        $lncnt++;
                        chomp $line;
                        $line = trim_all($line);
                        $len = length($line);
                        next if ($len == 0);
                        @arr = split(/\s+/,$line);
                        $type = $arr[0];
                        last if ($type == 99);
                        last if ($type == 1);
                        if ($type == 14) {
                            # tower location
                            # 14  52.911007  156.878342    0 0 Tower Viewpoint
                            $got_twr = 1;
                            $alat = $arr[1];
                            $alon = $arr[2];
                        } elsif ($type == 10) {
                            $rlat = $arr[1];
                            $rlon = $arr[2];
                            $hdg  = $arr[4];
                            $rlen = ($arr[5] * $FEET_TO_METER);  # length, in feet to meters
                            $hdgr = $hdg + 180;
                            $hdgr -= 360 if ($hdgr >= 360);
                            $res = fg_geo_direct_wgs_84( $rlat, $rlon, $hdg , ($rlen / 2), \$elat1, \$elon1, \$eaz1 );
                            $res = fg_geo_direct_wgs_84( $rlat, $rlon, $hdgr, ($rlen / 2), \$elat2, \$elon2, \$eaz2 );
                            $glat += $rlat;
                            $glon += $rlon;
                            $rwycnt++;
                        } elsif ($type == 100) {
                            $elat1 = $arr[9];
                            $elon1 = $arr[10];
                            $elat2 = $arr[18];
                            $elon2 = $arr[19];
                            $res = fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$hdg,\$hdgr,\$rlen);
                            $res = fg_geo_direct_wgs_84( $elat1, $elon1, $hdg, ($rlen / 2), \$rlat, \$rlon, \$eaz1 );
                            $glat += $rlat;
                            $glon += $rlon;
                            $rwycnt++;
                        }
                    }
                    if (!$got_twr && $rwycnt) {
                        $alat = $glat / $rwycnt;
                        $alon = $glon / $rwycnt;
                    }
                    push(@{$ra}, [$alat,$alon]);
                    $elap = secs_HHMMSS( tv_interval( $t1, [gettimeofday] ) );
                    prt("Found apt $icao, $alat,$alon, in $lncnt lines... in $elap\n") if (VERB5());

                    $icao = $arr[4];
                    if (($type == 1) && (defined $icaoh{$icao})) {
                        $gotapt = 1;
                    }
                }   # while $gotapt
            }
        }
        while ($line = <INF>) {
            $lncnt++;
        }
        $len = scalar @airs;
        $rwycnt = 0;
        $elat1 = 0;
        $elon1 = 0;
        $icao = '';
        my $tot_km = 0;
        $elap = secs_HHMMSS( tv_interval( $t1, [gettimeofday] ) );
        for ($i = 0; $i < $len; $i++) {
            $line = $icao;
            $icao = $airs[$i];
            $elon2 = $elon1;
            $elat2 = $elat1;
            if (defined $fnd_airports{$icao}) {
                $ra = $fnd_airports{$icao};
                my $ra2 = ${$ra}[0]; 
                $elat1 = ${$ra2}[0];
                $elon1 = ${$ra2}[1];
                if ($rwycnt) {
                    if (VERB2()) {
                        prt( "$rwycnt: $line $elon2,$elat2 to $icao $elon1,$elat1\n");
                    } else {
                        prt("$line - $icao: ");
                    }
                    $tot_km += show_distance( $elon2, $elat2, $elon1, $elat1 );
                }
            } else {
                @arr = keys %fnd_airports;
                $lncnt = get_nn($lncnt);
                pgm_exit(1,"ICAO '$icao' NOT found in $lncnt lines of $aptdat!\nDid find (".join(":",@arr).") in $elap. But aborting...\n");
            }
            $rwycnt++;
        }
        if ($rwycnt > 2) {
            my $d_nmiles = $tot_km * $Km2NMiles;
            my $hrs = $tot_km / $g_speed;
            my $eta = get_hhmmss($hrs);
            my $ikm = $tot_km;
            set_decimal_stg(\$ikm);
            my $inm = $d_nmiles;
            set_decimal_stg(\$inm);
            $line = $airs[0];
            $icao = $airs[-1];
            prt("Total: $line to $icao: $ikm Km, $inm Nm, $eta, at $g_ias\n");
        }

    } else {
        pgm_exit(1,"Version NOT found in $aptdat!\n");
    }
    close INF;
    return $rwycnt;
}

sub test_get_apts() {
    my $icaos = "KSFO:KABQ:KFLG";
    find_apts($icaos);
    pgm_exit(1,"TEMP EXIT");
}

# ==========================
# ### MAIN ###
###test_get_apts();
parse_args(@ARGV);
show_distance( $g_lon1, $g_lat1, $g_lon2, $g_lat2 ) if ($do_global_vals);
exit(0);

# ==========================

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have following argument!\n") if (!@av);
}

sub pre_process_verbosity($) {
    my $ra = shift;
    my ($arg,$sarg,$i);
    my $argcnt = scalar @{$ra};
    ### prt("Preprocessing $argcnt args...\n");
    for ($i = 0; $i < $argcnt; $i++) {
        $arg = ${$ra}[$i];
        if ( ($arg =~ /^-/) && !($arg =~ /^-\d+/) ) {
            $sarg = substr($arg,1);
            $sarg = substr($sarg,1) while ($sarg =~ /^-/);
            if ($sarg =~ /^v/) {
                if ($sarg =~ /^v(\d+)$/) {
                    $verbosity = $1;
                } else {
                    while ($sarg =~ /^v/) {
                        $verbosity++;
                        $sarg = substr($sarg,1);
                    }
                }
                prt("Set verbosity to [$verbosity].\n") if (VERB1());
            }
        }
    }
}


sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg,$cnt,@arr1,@arr2,$len);
    my $argcnt = scalar @av;
    my $rev = 0;
    my $xchg = 0;
    my $icaos = '';
    $cnt = 0;
    pre_process_verbosity(\@av);
    while (@av) {
        $arg = $av[0];
        if ( ($arg =~ /^-/) && !($arg =~ /^-\d+/) ) {
            $sarg = substr($arg,1);
            $sarg = substr($sarg,1) while ($sarg =~ /^-/);
            if (($sarg =~ /^h/i)||($sarg eq '?')) {
                give_help();
                pgm_exit(0,"Help exit(0)");
            } elsif ($sarg =~ /^a/) {
                need_arg(@av);
                shift @av;
                $icaos = $av[0];
            } elsif ($sarg =~ /^f/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $aptdat = $sarg;
                if (! -f $aptdat) {
                    pgm_exit(1,"Error: Can NOT locate '$aptdat' file! *** FIX ME ***\n");
                }
                prt("Set airport data to $aptdat.\n") if (VERB5());
            } elsif ($sarg =~ /^r/) {
                $rev = 1;
            } elsif ($sarg =~ /^g/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $xg_out = $sarg;
            } elsif ($sarg =~ /^i/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if (($sarg =~ /^\d+$/)&&($sarg > 0)&&(int($sarg) == $sarg)) {
                    $g_interval = $sarg; # interval
                    prt("List $g_interval betweeen.\n") if (VERB5());
                } else {
                    pgm_exit(1,"ERROR: Argument [$arg], must be followed by integer number of intervals! Got [$sarg]\n");
                }
            } elsif ($sarg =~ /^s/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if ($sarg =~ /^\d+$/) {
                    $g_ias = $sarg; # Knots
                    $g_speed = $g_ias * $K2KPH; # Knots to Kilometers/Hour
                    prt("Set speed to $g_ias Knots, and KPH.\n") if (VERB5());
                } else {
                    pgm_exit(1,"ERROR: Argument [$arg], must be followed by Number of Knots! Got [$sarg]\n");
                }
            } elsif ($sarg =~ /^v/) {
                # done
            } elsif ($sarg =~ /^w/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                @arr1 = split('@',$sarg);
                $len = scalar @arr1;
                if ($len == 2) {
                    $usr_wind_dir = $arr1[0];
                    $usr_wind_spd = $arr1[1];
                    if ($usr_wind_dir =~ /^\d+$/) {
                        if ($usr_wind_dir < 0) {
                            pgm_exit(1,"Wind dir of $sarg NOT positive! Got $usr_wind_dir?\n");
                        } elsif ($usr_wind_dir > 360) {
                            pgm_exit(1,"Wind dir of $sarg greater than 360! Got $usr_wind_dir?\n");
                        }
                    } else {
                        pgm_exit(1,"Wind var $sarg NOT an integer! Got $usr_wind_dir?\n");
                    }
                    if ($usr_wind_spd =~ /^\d+$/) {
                        if ($usr_wind_spd < 0) {
                            pgm_exit(1,"Wind speed of $sarg NOT positive! Got $usr_wind_spd?\n");
                        ##} elsif ($usr_wind_dir > 360) {
                        ##    pgm_exit(1,"Wind dir of $sarg greater than 360! Got $usr_wind_dir?\n");
                        }
                    } else {
                        pgm_exit(1,"Wind var $sarg NOT an integer! Got $usr_wind_dir?\n");
                    }

                    $got_wind = 1;
                } else {
                    pgm_exit(1,"Wind var $sarg did not split in 2 on '\@'! $sarg\n".
                        "Expect like 120\@12, 150\@9, etc...\n");
                }
            } elsif ($sarg =~ /^x/) {
                $xchg = 1;
            } else {
                give_help();
                pgm_exit(1,"ERROR: Invalid argument [$arg]!\n");
            }
        } else {
            # assume 4 bare args, or two comma sepearated pairsn...
            if ($cnt == 0) {
                if ($arg =~ /,/) {
                    @arr1 = split(',',$arg);
                    $len = scalar @arr1;
                    $g_lat1 = $arr1[0];
                    $g_lon1 = $arr1[1];
                    if ($len == 2) {
                        $cnt++;
                    } elsif ($len == 4) {
                        $g_lat2 = $arr1[2];
                        $g_lon2 = $arr1[3];
                        $cnt += 3;
                    } else {
                        pgm_exit(1,"ERROR: Invalid argument [$arg]! Did not split 2 or 4 on comma?\n");
                    }
                } else {
                    $g_lat1 = $arg; # set LAT1
                    prt("Set lat 1 $g_lat1\n") if (VERB5());
                }
            } elsif ($cnt == 1) {
                $g_lon1 = $arg;     # set LON1
                prt("Set lon 1 $g_lon1\n") if (VERB5());
            } elsif ($cnt == 2) {
                if ($arg =~ /,/) {
                    @arr2 = split(',',$arg);
                    $g_lat2 = $arr2[0];
                    $g_lon2 = $arr2[1];
                    $cnt++;
                } else {
                    $g_lat2 = $arg; # set LAT2
                    prt("Set lat 2 $g_lat2\n") if (VERB5());
                }
            } elsif ($cnt == 3) {
                $g_lon2 = $arg;     # set LON2
                prt("Set lon 2 $g_lon1\n") if (VERB5());
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Only max 4 bare args?\n");
            }
            $cnt++;
        }
        shift @av;
    }

    if ($debug_on) {
        prtw("WARNING: Debug is ON!\n");
        if ( !(in_world($g_lat1,$g_lon1) &&
               in_world($g_lat2,$g_lon2) ) ) {
            $g_lat1 = $tl_lat;
            $g_lon1 = $tl_lon;
            $g_lat2 = $bl_lat;
            $g_lon2 = $bl_lon;
            prt("Setting DEFAULT $g_lat1,$g_lon1 $g_lat2,$g_lon2\n");
            $verbosity = 5;
        }
    }


    if ($xchg) {
        prt("Exchanging lat and lon...\n") if (VERB1());
        my $tmp = $g_lat1;
        $g_lat1 = $g_lon1;
        $g_lon1 = $tmp;
        $tmp = $g_lat2;
        $g_lat2 = $g_lon2;
        $g_lon2 = $tmp;
    }
    if (length($icaos)) {
        if (!find_apts($icaos)) {
            pgm_exit(1,"Failed...\n");
        }
        $got_icao = 1;
    }

    if ($rev) {
        my $tmp = $g_lat1;
        $g_lat1 = $g_lat2;
        $g_lat2 = $tmp;
        $tmp = $g_lon1;
        $g_lon1 = $g_lon2;
        $g_lon2 = $tmp;
        prt("Reversed direction...\n") if (VERB1());
    }
    if (in_world($g_lat1,$g_lon1) &&
        in_world($g_lat2,$g_lon2) ) {
        prt("Input (lat,lon) $g_lat1,$g_lon1 to $g_lat2,$g_lon2\n") if (VERB2());
        $do_global_vals = 1;
    } elsif (!$got_icao) {
        #in_world_show($g_lat1,$g_lon1);
        #in_world_show($g_lat2,$g_lon2);
        #prt("Input ONE $g_lat1,$g_lon1 ");
        #prt( (in_world($g_lat1,$g_lon1) ? "ok" : "NIW!") );
        #prt(" TWO $g_lat2,$g_lon2 ");
        #prt( (in_world($g_lat2,$g_lon2) ? "ok" : "NIW!") );
        #prt("\n");
        give_help();
        prt("ERROR: No valid input! Need 4 bare args lat1 lon1 lat2 lon2,\nor -a with 2 more ICAO colon separated!\n");
        pgm_exit(1,"\n");
    }
}

sub give_help {
    prt("\n");
    prt("$pgmname: version $VERS\n");
    prt("\n");
    prt("Usage: $pgmname [options] lat1 lon1 lat2 lon2\n");
    prt("Options:\n");
    prt(" --help     (-h or -?) = This help, and exit 0.\n");
    prt(" --inter Num     (-i) = Show intervals between points. (def=off)\n");
    prt(" --rev           (-r) = Reverse the calculation. (def=off)\n");
    prt(" --speed         (-s) = Set the speed, in knots. (def=$g_ias)\n");
    prt(" --air APT1:APT2 (-a) = Distance between airports, as 2 or more ICAO.\n");
    prt(" --xchange       (-x) = Exchange lat and lon\n");
    prt(" --file <file>   (-f) = Set the FG airport dat file to use.\n");
    prt("   Def file $aptdat ".((-f $aptdat) ? "ok" : "*** NOT FOUND *** FIX ME ***")."\n");
    prt(" --graph <file>  (-g) = Output an xg graph file of points.\n");
    prt(" -v[N]                = Bump or set verbosity. (def=$verbosity).\n");
    prt(" -v1 will show the center lat,lon, heading, and distance in meters.\n");
    prt(" --wind deg\@kt   (-w) = Set wind direction (deg) and speed knots.\n");
    prt("\n");
    prt(" The lat/lon can be input as comma separated pairs.\n");
    prt("\n");
    prt(" The calculation is first done using Math::Trig qw(great_circle_distance ...), and\n");
    prt(" then repeated using a perl rendition of simgear fg_geo_inverse_wgs_84(), and\n");
    prt(" the results are compared. Bumping verbosity will display the SG values.\n");
    prt("\n");
}


# eof - distance02.pl
