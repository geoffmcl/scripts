#!/usr/bin/perl -w
# NAME: findaps.pl
# AIM: There is a BIG findap[nn].pl - This is a SIMPLER version
# 25/08/2015 - add to scripts repo
# 17/10/2014 - Change -i -c = no case change on name
# 16/10/2014 - Use later fgdata 3.3, thus add typ=100
# 14/04/2013 - Use later fgdata 2.10
# 19/05/2012 - Add more output according to verbosity
# 20/03/2012 - On help output the apt.dat file name
# 20/01/2012 - Output airport names correctly 'cased', and FIX sub not_on_track($)
#              and add nav, fixes and airways loads
# 2011-12-12 - Also compiled and run in Ubuntu, and added -m num to change output count
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
my $os = $^O;
my $cwd = cwd();
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
unshift(@INC, $perl_dir);
my $PATH_SEP = '/';
my $CDATROOT="/media/Disk2/FG/fg22/fgdata"; # 20150716 - 3.5++
if ($os =~ /win/i) {
    $PATH_SEP = "\\";
    $CDATROOT="F:/fgdata"; # 20140127 - 3.1
}
my $XDROOT="X:\\fgdata";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
require "Bucket2.pm" or die "Unable to load Bucket2.pm ...\n";
# my $CDATROOT="C:/FGCVS/FlightGear/data";
if (-d $XDROOT) {
    $CDATROOT=$XDROOT;
}
# =============================================================================
# This NEEDS to be adjusted to YOUR particular default location of these files.
my $FGROOT = (exists $ENV{'FG_ROOT'})? $ENV{'FG_ROOT'} : $CDATROOT;
#my $FGROOT = (exists $ENV{'FG_ROOT'})? $ENV{'FG_ROOT'} : "C:/FG/27/data";
# file spec : http://data.x-plane.com/file_specs/Apt810.htm
my $APTFILE 	  = "$FGROOT/Airports/apt.dat.gz";	# the airports data file
my $NAVFILE 	  = "$FGROOT/Navaids/nav.dat.gz";	# the NAV, NDB, etc. data file
# add these files
my $FIXFILE 	  = "$FGROOT/Navaids/fix.dat.gz";	# the FIX data file
my $AWYFILE       = "$FGROOT/Navaids/awy.dat.gz";   # Airways data
# =============================================================================

my $MY_F2M = 0.3048;
my $MY_M2F = 3.28083989501312335958;
my $SG_METER_TO_NM = 0.0005399568034557235;

# log file stuff
our ($LF);
my $outfile = $temp_dir.$PATH_SEP."temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.5 2015-08-28";  # adapt to use in scripts repo
#my $VERS = "0.0.4 2014-10-16";  # output nicely cased airport names, and add nav, fixes and airways
# $VERS = "0.0.3 2012-01-20";  # output nicely cased airport names, and add nav, fixes and airways
# $VERS = "0.0.2 2011-12-12";
my $load_log = 0;
my $in_icao = '';
my $verbosity = 0;
#my $out_xml = '';
my $g_max_out = 20;
# EXCLUDED from list
my $g_xhele = 0;
my $g_xsea  = 0;
my $g_xold  = 0;
my $g_track = -1;   # no track
my $g_spread = 30;  # +/- this spread
my $name_as_is = 0;
my $show_navaids = 0;
my $show_fixes = 0;
my $show_airways = 0;
my $show_bounds = 0;
my $only_with_ils = 0;

my $aptdat = $APTFILE;
my $navdat = $NAVFILE;
my $g_fixfile = $FIXFILE;
my $g_awyfile = $AWYFILE;

# format constants
my $g_distmin = 7;
my $g_altmin = 7;
my $g_frqmin = 5;
my $g_rngmin = 5;

### Debug
my $debug_on = 0;
my $del_icao = 'KTEX';

### program variables
my @warnings = ();

my $rnavaids;

my $g_clat = 400;
my $g_clon = 400;

my ($g_minlat,$g_minlon,$g_maxlat,$g_maxlon,$g_minalt,$g_maxalt);

# apt.dat.gz CODES - see http://x-plane.org/home/robinp/Apt810.htm for DETAILS
my $aln =     '1';	# airport line
my $rln =    '10';	# runways/taxiways line
my $sealn =  '16'; # Seaplane base header data.
my $heliln = '17'; # Heliport header data.  
my $twrln =  '14'; # Tower view location. 
my $rampln = '15'; # Ramp startup position(s) 
my $bcnln =  '18'; # Airport light beacons  
my $wsln =   '19'; # windsock

# Radio Frequencies # AWOS (Automatic Weather Observation System), ASOS (Automatic Surface Observation System)
my $minatc = '50'; # ATIS (Automated Terminal Information System). AWIS (Automatic Weather Information Service)
my $unicom = '51'; # Unicom or CTAF (USA), radio (UK) - open channel for pilot position reporting at uncontrolled airports.
my $cleara = '52'; # Clearance delivery.
my $goundf = '53'; # ground
my $twrfrq = '54';	# like 12210 TWR
my $appfrq = '55';  # like 11970 ROTTERDAM APP
my $maxatc = '56'; # Departure.
my %off2name = (
    0 => 'ATIS',
    1 => 'Unicom',
    2 => 'Clearance',
    3 => 'Ground',
    4 => 'Tower',
    5 => 'Approach',
    6 => 'Departure'
);

# offset 10 in runway array
my %runway_surface = (
    1  => 'Asphalt',
    2  => 'Concrete',
    3  => 'Turf/grass',
    4  => 'Dirt',
    5  => 'Gravel',
    6  => 'H-Asphalt', # helepad (big 'H' in the middle).
    7  => 'H-Concrete', # helepad (big 'H' in the middle).
    8  => 'H-Turf', # helepad (big 'H' in the middle).
    9  => 'H-Dirt', # helepad (big 'H' in the middle). 
    10 => 'T-Asphalt', # taxiway - with yellow hold line across long axis (not available from WorldMaker).
    11 => 'T-Concrete', # taxiway - with yellow hold line across long axis (not available from WorldMaker).
    12 => 'Dry Lakebed', # (eg. at KEDW Edwards AFB).
    13 => 'Water' # runways (marked with bobbing buoys) for seaplane/floatplane bases (available in X-Plane 7.0 and later). 
);

# =====================================================================================================
my $lastln = '99'; # end of file

# =============================
# NAV FILE INFO
# nav.dat.gz CODES
my $navNDB = '2';
my $navVOR = '3';
my $navILS = '4';
my $navLOC = '5';
my $navGS  = '6';
my $navOM  = '7';
my $navMM  = '8';
my $navIM  = '9';
my $navVDME = '12';
my $navNDME = '13';
# my @navset = ($navNDB, $navVOR, $navILS, $navLOC, $navGS, $navOM, $navMM, $navIM, $navVDME, $navNDME);
my %nav2type = (
    $navNDB => 'NDB',
    $navVOR => 'VOR',
    $navILS => 'ILS',
    $navLOC => 'LOC',
    $navGS  => 'GS',
    $navOM  => 'OM',
    $navMM  => 'MM',
    $navIM  => 'IM',
    $navVDME => 'VDME',
    $navNDME => 'NDME'
    );

sub get_nav_type_stg($) {
    my $typ = shift;
    if (defined $nav2type{$typ}) {
        return $nav2type{$typ};
    }
    return "Type $typ unknown";
}
sub is_defined_nav_type($) {
    my $typ = shift;
    return 1 if (defined $nav2type{$typ});
    return 0;
}

# =============================

# program variables
my @g_aptlist = ();
my $totaptcnt = 0;
my $totrwycnt = 0;

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

sub in_world_range($$) {
    my ($lat,$lon) = @_;
    return 0 if (($lat > 90)||($lat < -90)||($lon > 180)||($lon < -180));
    return 1;
}

#//////////////////////////////////////////////////////////////////////
#//
#// Convert a cartexian XYZ coordinate to a geodetic lat/lon/alt.
#// This function is a copy of what's in SimGear,
#//  simgear/math/SGGeodesy.cxx.
#//
#////////////////////////////////////////////////////////////////////////
#// High-precision versions of the above produced with an arbitrary
#// precision calculator (the compiler might lose a few bits in the FPU
#// operations).  These are specified to 81 bits of mantissa, which is
#// higher than any FPU known to me:
my $SGD_PI = 3.1415926535;

my $SQUASH  = 0.9966471893352525192801545;
my $STRETCH = 1.0033640898209764189003079;
my $POLRAD  = 6356752.3142451794975639668;

my $SG_RAD_TO_NM  = 3437.7467707849392526;
my $SG_NM_TO_METER  = 1852.0000;
my $SG_METER_TO_FEET  = 3.28083989501312335958;
my $SGD_PI_2    = 1.57079632679489661923;
my $SG_RADIANS_TO_DEGREES = 180.0 / $SGD_PI;

my $EQURAD = 6378137.0;

my $E2 = abs(1 - ($SQUASH*$SQUASH));
my $ra2 = 1/($EQURAD*$EQURAD);
my $e2 = $E2;
my $e4 = $E2*$E2;

#//////////////////////////////////////////////////////////////////////
#//  This is the inverse of the algorithm in localLat().  It
#//  returns the (cylindrical) coordinates of a surface latitude
#//  expressed as an "up" unit vector.
#//////////////////////////////////////////////////////////////////////
#static void surfRZ (double upr, double upz, double* r, double* z)
sub surfRZ($$$$) {
    my ($upr,$upz,$rr,$rz) = @_;
    # // We are
    #// converting a (2D, cylindrical) "up" vector defined by the
    #// geodetic latitude into unitless R and Z coordinates in
    #// cartesian space.
    my $R = $upr * $STRETCH;
    my $Z = $upz * $SQUASH;
    #// Now we need to turn R and Z into a surface point.  That is,
    #// pick a coefficient C for them such that the point is on the
    #// surface when converted to "squashed" space:
    #//  (C*R*SQUASH)^2 + (C*Z)^2 = POLRAD^2
    #//   C^2 = POLRAD^2 / ((R*SQUASH)^2 + Z^2)
    my $sr = $R * $SQUASH;
    my $c = $POLRAD / sqrt($sr*$sr + $Z*$Z);
    $R *= $c;
    $Z *= $c;
    ${$rr} = $R;
    ${$rz} = $Z;
}   #// surfRZ()
#//////////////////////////////////////////////////////////////////////

# void sgCartToGeod ( const Point3D& CartPoint , Point3D& GeodPoint )
sub sgCartToGeod($$) {
    my ($rCartPoint,$rGeodPoint) = @_;
    #// according to
    #// H. Vermeille,
    #// Direct transformation from geocentric to geodetic ccordinates,
    #// Journal of Geodesy (2002) 76:451-454
    my $x = ${$rCartPoint}[0];
    my $y = ${$rCartPoint}[1];
    my $z = ${$rCartPoint}[2];
    my $XXpYY = $x*$x+$y*$y;
    my $sqrtXXpYY = sqrt($XXpYY);
    my $p = $XXpYY*$ra2;
    my $q = $z*$z*(1-$e2)*$ra2;
    my $r = 1/6.0*($p+$q-$e4);
    my $s = $e4*$p*$q/(4*$r*$r*$r);
    my $t = pow(1+$s+sqrt($s*(2+$s)), 1/3.0);
    my $u = $r*(1+$t+1/$t);
    my $v = sqrt($u*$u+$e4*$q);
    my $w = $e2*($u+$v-$q)/(2*$v);
    my $k = sqrt($u+$v+$w*$w)-$w;
    my $D = $k*$sqrtXXpYY/($k+$e2);
    ${$rGeodPoint}[0] = (2*atan2($y, $x+$sqrtXXpYY)) * $SG_RADIANS_TO_DEGREES; # lon
    my $sqrtDDpZZ = sqrt($D*$D+$z*$z);
    ${$rGeodPoint}[1] = (2*atan2($z, $D+$sqrtDDpZZ)) * $SG_RADIANS_TO_DEGREES; # lat
    ${$rGeodPoint}[2] = (($k+$e2-1)*$sqrtDDpZZ/$k) * $SG_METER_TO_FEET;        # alt
}   #// sgCartToGeod()

#//////////////////////////////////////////////////////////////////////
#// opposite of sgCartToGeod
#//////////////////////////////////////////////////////////////////////
#void sgGeodToCart ( double lat, double lon, double alt, double* xyz )
sub sgGeodToCart($$$$) {
    my ($lat, $lon, $alt, $rxyz) = @_;
    #// This is the inverse of the algorithm in localLat().  We are
    #// converting a (2D, cylindrical) "up" vector defined by the
    #// geodetic latitude into unitless R and Z coordinates in
    #// cartesian space.
    my $upr = cos($lat);
    my $upz = sin($lat);
    my ($r, $z);
    surfRZ($upr, $upz, \$r, \$z);
    #// Add the altitude using the "up" unit vector we calculated
    #// initially.
    $r += $upr * $alt;
    $z += $upz * $alt;
    #// Finally, convert from cylindrical to cartesian
    ${$rxyz}[0] = $r * cos($lon);
    ${$rxyz}[1] = $r * sin($lon);
    ${$rxyz}[2] = $z;
}   #// sgGeodToCart()
#//////////////////////////////////////////////////////////////////////

# LOAD apt.dat.gz
# details see : http://data.x-plane.com/file_specs/Apt810.htm
# Line codes used in apt.dat (810 version and 1000 version) 
# Airport Line - eg 
# 0  1    2   3   4    5++
# 1  1050 0   0   YGIL Gilgandra
# ID AMSL Twr Bld ICAO Name
# Code (apt.dat) Used for 
# 1 Airport header data. 
# 16 Seaplane base header data. No airport buildings or boundary fences will be rendered in X-Plane. 
# 17 Heliport header data.  No airport buildings or boundary fences will be rendered in X-Plane. 
# 10 Runway or taxiway at an airport. 
# 14 Tower view location. 
# 15 Ramp startup position(s) 
# 18 Airport light beacons (usually "rotating beacons" in the USA).  Different colours may be defined. 
# 19 Airport windsocks. 
# 50 to 56 Airport ATC (Air Traffic Control) frequencies. 
# runway
# 0  1           2          3   4       5    6         7             8 9      10  11   12    13    14     15
# 10 -31.696928  148.636404 15x 162.00  4204 0000.0000 0000.0000    98 121121  5   0    2    0.25   0     0000.0000
# rwy lat        lon        num true    feet displament/extension  wid lights surf shld mark smooth signs VASI
sub load_apt_data {
    my ($i,$max,$msg);
    prt("Loading $aptdat file ... moment...\n"); # if (VERB1());
    mydie("ERROR: Can NOT locate $aptdat ...$!...\n") if ( !( -f $aptdat) );
    ###open IF, "<$aptdat" or mydie("OOPS, failed to open [$aptdat] ... check name and location ...\n");
    open IF, "gzip -d -c $aptdat|" or mydie( "ERROR: CAN NOT OPEN $aptdat...$!...\n" );
    my @lines = <IF>;
    close IF;
    $max = scalar @lines;
    prt("Got $max lines to scan... moment...\n"); # if (VERB9());
    my ($add,$alat,$alon);
    $add = 0;
    my ($off,$atyp,$az,@arr,@arr2,$rwyt,$glat,$glon,$rlat,$rlon);
    my ($line,$apt,$diff,$rwycnt,$icao,$name,@runways,$version);
    my ($aalt,$actl,$abld,$ftyp,$cfrq,$frqn,@freqs);
    my ($len,$type);
    my ($rwid,$surf,$rwy1,$rwy2,$elat1,$elon1,$elat2,$elon2,$az1,$az2,$s,$res);
    $off = 0;
    $az = 0;
    $glat = 0;
    $glon = 0;
    $apt = '';
    $rwycnt = 0;
    @runways = ();
    @freqs = ();
    $msg = '[v1] ';
    #$msg .= "Search ICAO [$apticao]...";
    $msg .= " got $max lines, FOR airports,rwys,txwys... ";
    for ($i = 0; $i < $max; $i++) {
        $line = $lines[$i];
        $line = trim_all($line);
        if ($line =~ /\s+Version\s+/i) {
            @arr2 = split(/\s+/,$line);
            $version = $arr2[0];
            $msg .= "Version $version";
            $i++;
            last;
        }
    }
    prt("$msg\n") if (VERB1());
    for ( ; $i < $max; $i++) {
        $line = $lines[$i];
        $line = trim_all($line);
        $len = length($line);
        next if ($len == 0);
        ###prt("$line\n");
        my @arr = split(/\s+/,$line);
        $type = $arr[0];
        if (($line =~ /^$aln\s+/)||	    # start with '1'
            ($line =~ /^$sealn\s+/)||   # =  '16'; # Seaplane base header data.
            ($line =~ /^$heliln\s+/)) { # = '17'; # Heliport header data.  
            # 0  1   2 3 4     
            # 17 126 0 0 EH0001 [H] VU medisch centrum
            # ID ALT C B NAME++
            if (length($apt)) {
                if ($rwycnt > 0) {
                    # average position
                    $alat = $glat / $rwycnt;
                    $alon = $glon / $rwycnt;
                    $off = -1;
                    $az = 400;
                    @arr2 = split(/ /,$apt);
                    $atyp = $arr2[0]; # airport, heleiport, or seaport
                    $aalt = $arr2[1]; # Airport (general) ALTITUDE AMSL
                    $actl = $arr2[2]; # control tower
                    $abld = $arr2[3]; # buildings
                    $icao = $arr2[4]; # ICAO
                    $name = join(' ', splice(@arr2,5)); # Name
                    ##prt("$diff [$apt] (with $rwycnt runways at [$alat, $alon]) ...\n");
                    ##prt("$diff [$icao] [$name] ...\n");
                    #push(@g_aptlist, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az]);
                    my @f = @freqs;
                    my @r = @runways;
                    #                 0      1      2      3      4      5      6    7
                    push(@g_aptlist, [$atyp, $icao, $name, $alat, $alon, $aalt, \@f, \@r]);
                    ### prt("[v9] $icao, $name, $alat, $alon, $aalt, $rwycnt runways\n") if (VERB9());
                } else {
                    prtw("WARNING: Airport with NO runways! $icao, $name, $alat, $alon, $aalt\n");
                }
            }
            $apt = $line;
            $rwycnt = 0;
            @runways = ();  # clear RUNWAY list
            @freqs = (); # clear frequencies
            $glat = 0;
            $glon = 0;
            $totaptcnt++;	# count another AIRPORT
        } elsif ($line =~ /^$rln\s+/) {
            # 10  36.962213  127.031071 14x 131.52  8208 1595.0620 0000.0000   150 321321  1 0 3 0.25 0 0300.0300
            # 10  36.969145  127.020106 xxx 221.51   329 0.0 0.0    75 161161  1 0 0 0.25 0 
            $rlat = $arr[1];
            $rlon = $arr[2];
            $rwyt = $arr[3]; # text 'xxx'=taxiway, 'H1x'=heleport, else a runway
            ###prt( "$line [$rlat, $rlon]\n" );
            if ( $rwyt ne "xxx" ) {
                $glat += $rlat;
                $glon += $rlon;
                $rwycnt++;
                my @ar = @arr;
                push(@runways, \@ar);
                $totrwycnt++;
            }
        } elsif ($line =~ /^5(\d+)\s+/) {
            # frequencies
            $ftyp = $1;
            $cfrq = $arr[1];
            $frqn = $arr[2];
            $add = 0;
            if ($ftyp == 0) {
                $add = 1; # ATIS
            } elsif ($ftyp == 1) {
                $add = 1; # Unicom
            } elsif ($ftyp == 2) {
                $add = 1; # clearance
            } elsif ($ftyp == 3) {
                $add = 1; # ground
            } elsif ($ftyp == 4) {
                $add = 1; # tower
            } elsif ($ftyp == 5) {
                $add = 1; # approach
            } elsif ($ftyp == 6) {
                $add = 1; # departure
            }
            if ($add) {
                my @af = @arr;
                push(@freqs, \@af); # save the freq array
            } else {
                pgm_exit(1, "WHAT IS THIS [5$ftyp $cfrq $frqn] [$line]\n FIX ME!!!");
            }
        } elsif ($line =~ /^$lastln\s?/) {	# 99, followed by space, count 0 or more ...
            prt( "Reached END OF FILE ... \n" ) if (VERB9());
            last;
        } elsif ($type == 14) {
            # Tower view location(s).
        } elsif ($type == 15) {
            # parking Ramp startup position(s) 
        } elsif ($type == 18) {
            # 18 Airport light beacons (usually "rotating beacons" in the USA).  Different colours may be defined. 
        } elsif ($type == 19) {
            # 19 Airport windsocks.
        # ===============================================================================
        } elsif ($type == 20) {
            # 20 22.32152700 114.19750500 224.10 0 3 {@Y,^l}31-13{^r}
        } elsif ($type == 21) {
            # 21 22.31928000 114.19800800 3 134.09 3.10 13 PAPI-4R
        } elsif ($type == 100) {
            # 0   1          2          3   4       5      6         7         8   9      10 11 12 13   14 15
            # typ lat        lon        mrk bearing alt-ft
            # 10  36.962213  127.031071 14x 131.52  8208   1595.0620 0000.0000 150 321321  1  0  3 0.25 0  0300.0300
            # version 1000 runway
            # 0   1     2 3 4    5 6 7 8  9           10           11   12   13 14 15 16 17 18          19           20   21   22 23 24 25
            # 100 29.87 3 0 0.00 1 2 1 16 43.91080605 004.90321905 0.00 0.00 2  0  0  0  34 43.90662331 004.90428974 0.00 0.00 2  0  0  0
            $rwid  = $arr[1];  # WIDTH in meters? NOT SHOWN
            $surf  = $arr[2];  # add surface type
            $rwy1  = $arr[8];
            $elat1 = $arr[9];
            $elon1 = $arr[10];

            $rwy2 = $arr[17];
            $elat2 = $arr[18];
            $elon2 = $arr[19];
            $res = fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
            $s = int($s * $MY_M2F);
            $rlat = ($elat1 + $elat2) / 2;
            $rlon = ($elon1 + $elon2) / 2;
            $glat += $rlat;
            $glon += $rlon;
            $rwycnt++;
            # 0   1=lat      2=lon      3=s 4=hdg  5=len 6=offsets 7=stopway 8=wid 9=lights 10=surf 11 12 13   14 15
            # 10  36.962213  127.031071 14x 131.52  8208 1595.0620 0000.0000 150   321321   1       0  3  0.25 0  0300.0300
            # 11=shoulder 12=marks 13=smooth 14=signs 15=GS angles
            # 0           3        0.25      0        0300.0300
            #        0  1     2     3     4    5
            $rwy2 = [10,$rlat,$rlon,$rwy2,$az1,$s,6,7,8,9,$surf,11,12,13,14,15];
            #  push(@runways, \@arr);
            push(@runways,$rwy2);
        } elsif ($type == 101) {	# Water runways
            # Water runways
            # 0   1      2 3  4           5             6  7           8
            # 101 243.84 0 16 29.27763293 -089.35826258 34 29.26458929 -089.35340410
            # 101 22.86  0 07 29.12988952 -089.39561501 25 29.13389936 -089.38060001
            $elat1 = $arr[4];
            $elon1 = $arr[5];
            $elat2 = $arr[7];
            $elon2 = $arr[8];
            $surf  = 13;
            $res = fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
            $s = int($s * $MY_M2F);
            $rwy1 = int(($az1 / 10) + 0.5);
            $rlat = sprintf("%.8f",(($elat1 + $elat2) / 2));
            $rlon = sprintf("%.8f",(($elon1 + $elon2) / 2));
            $glat += $rlat;
            $glon += $rlon;
            $rwycnt++;
            $rwy2 = [10,$rlat,$rlon,$rwy2,$az1,$s,6,7,8,9,$surf,11,12,13,14,15];
            # push(@waterways, \@a2);
            push(@runways,$rwy2);
        } elsif ($type == 102) {	# Heliport
            # 0   1  2           3            4      5     6     7 8 9 10   11
            # 102 H2 52.48160046 013.39580674 355.00 18.90 18.90 2 0 0 0.00 0
            # 102 H3 52.48071507 013.39937648 2.64   13.11 13.11 1 0 0 0.00 0
            $rwy1  = $arr[1];
            $elat1 = $arr[2];
            $elon1 = $arr[3];
            $az1   = $arr[4];
            $s     = int($arr[5] * $MY_M2F);
            $surf  = 6;
            $rlat = sprintf("%.8f",$elat1);
            $rlon = sprintf("%.8f",$elon1);
            $glat += $rlat;
            $glon += $rlon;
            $rwycnt++;
            $rwy2 = [10,$rlat,$rlon,$rwy2,$az1,$s,6,7,8,9,$surf,11,12,13,14,15];
            push(@runways,$rwy2);
        } elsif ($type == 110) {
            # 110 2 0.00 134.10 runway sholder
        } elsif ($type == 111) {
            # 111 22.30419700 114.21613100
        } elsif ($type == 112) {
            # 112 22.30449500 114.21644400 22.30480900 114.21677000 51 102
        } elsif ($type == 113) {
            # 113 22.30370300 114.21561700
        } elsif ($type == 114) {
            # 114 43.29914799 -008.38013558 43.29965322 -008.37970933
        } elsif ($type == 115) {
            # 115 22.31009400 114.21038500
        } elsif ($type == 116) {
            # 116 43.30240028 -008.37799316 43.30271076 -008.37878407
        } elsif ($type == 120) {
            # 120 hold lines W A13
        } elsif ($type == 130) {
            # 130 Airport Boundary
        } elsif ($type == 1000) {
            # 1000 Northerly flow
        } elsif ($type == 1001) {
            # 1001 KGRB 270 020 999
        } elsif ($type == 1002) {
            # 1002 KGRB 0
        } elsif ($type == 1003) {
            # 1003 KGRB 0
        } elsif ($type == 1004) {
            # 1004 0000 2400
        } elsif ($type == 1100) {
            # 1100 36 12654 all heavy|jets|turboprops|props 000360 000360 Northerly
        } elsif ($type == 1101) {
            # 1101 36 left
        } elsif ($type == 1200) {
            # ????
        } elsif ($type == 1201) {
            # 1201 42.75457409 -073.80880021 both 2110 _start
        } elsif ($type == 1202) {
            # 1202 2110 2112 twoway taxiway
        } elsif ($type == 1204) {
            # 1204 arrival 01,19
        } elsif ($type == 1300) {
            # 1300 30.32875704 -009.41140596 323.85 misc jets|props Ramp
        # ===============================================================================
        } else {
            pgm_exit(1,"Line type $type NOT USED [$line]\n*** FIX ME ***");
        }
    }

    # do any LAST entry
    $add = 0;
    $off = -1;
    $az = 0;
    if (length($apt) && ($rwycnt > 0)) {
        $alat = $glat / $rwycnt;
        $alon = $glon / $rwycnt;
        $off = -1;
        $az = 400;
        #$off = near_given_point( $alat, $alon, \$dist, \$az );
        #$dlat = abs( $c_lat - $alat );
        #$dlon = abs( $c_lon - $alon );
        #$diff = int( ($dlat * 10) + ($dlon * 10) );
        @arr2 = split(/ /,$apt);
        $atyp = $arr2[0];
        $aalt = $arr2[1];
        $actl = $arr2[2]; # control tower
        $abld = $arr2[3]; # buildings
        $icao = $arr2[4];
        $name = join(' ', splice(@arr2,5));
        ###prt("$diff [$apt] (with $rwycnt runways at [$alat, $alon]) ...\n");
        ###prt("$diff [$icao] [$name] ...\n");
        ###push(@g_aptlist, [$diff, $icao, $name, $alat, $alon]);
        ##push(@g_aptlist, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az]);
        my @f = @freqs;
        my @r = @runways;
        #                 0      1      2      3      4      5      6    7
        push(@g_aptlist, [$atyp, $icao, $name, $alat, $alon, $aalt, \@f, \@r]);
        $totaptcnt++;	# count another AIRPORT
    }
    my $cnt = scalar @g_aptlist;
    prt("Done scan of $max lines for $cnt airports, $totrwycnt runways...\n"); # if (VERB1());
}

sub mycmp_decend_dist {
   return -1 if (${$a}[8] < ${$b}[8]);
   return 1 if (${$a}[8] > ${$b}[8]);
   return 0;
}

# 12345678901
# -18.0748140
sub set_lat_stg($) {
    my ($rl) = @_;
    ${$rl} = sprintf("%2.7f",${$rl});
    ${$rl} = ' '.${$rl} while (length(${$rl}) < 11);
}

# 123456789012
# -140.9458860
sub set_lon_stg($) {
    my ($rl) = @_;
    ${$rl} = sprintf("%3.7f",${$rl});
    ${$rl} = ' '.${$rl} while (length(${$rl}) < 12);
}

sub set_azimuth_stg($) {
    my ($rl) = @_;
    ${$rl} = sprintf("%03.1f",${$rl});
    ${$rl} = ' '.${$rl} while (length(${$rl}) < 5);
}

sub not_on_track($) {
    my ($trk) = shift; # = $az1
    my $diff = abs($trk - $g_track);    # get absolute difference current and desired
    # but then the case - azimuth is 345, g_track is zero(0), spread is 30
    $diff = 360 - $diff if ($diff > 180);
    return 0 if ($diff <= $g_spread);   # if abs difference less than or equal to desired spread = ON TRACK
    return 1;   # is OFF TRACK
}

sub cased_name($) { # if (!$name_as_is);
    my $name = shift;
    my @arr = split(/\s+/,$name);
    my $nname = "";
    my ($part,$nm,$len);
    foreach $part (@arr) {
        $len = length($part);
        next if ($len == 0);
        $nname .= ' ' if (length($nname));
        if ($part =~ /^\[.+\]/) {
            $nname .= $part;
        } else {
            $nm = uc(substr($part,0,1));
            $nm .= lc(substr($part,1)) if ($len > 1);
            $nname .= $nm;
        }
    }
    return $nname;
}

# @runways reference
# 0   1=lat      2=lon      3=s 4=hdg  5=len 6=offsets 7=stopway 8=wid 9=lights 10=surf 11 12 13   14 15
# 10  36.962213  127.031071 14x 131.52  8208 1595.0620 0000.0000 150   321321   1       0  3  0.25 0  0300.0300
# 11=shoulder 12=marks 13=smooth 14=signs 15=GS angles
# 0           3        0.25      0        0300.0300

sub get_runways_stg($) {
    my $rrwys = shift;
    my $cnt = scalar @{$rrwys};
    my ($i,$ra,$max,$rlen,$hdg);
    $max = 0;
    $hdg = 0;
    for ($i = 0; $i < $cnt; $i++) {
        $ra = ${$rrwys}[$i];
        $rlen = ${$ra}[5];
        if ($rlen > $max) {
            $max = $rlen;
            $hdg  = ${$ra}[4]
            ##$hdg  = ${$ra}[3];
            ##$hdg =~ s/x$//;
        }
    }
    $hdg = int($hdg);
    my $txt = "rw:$cnt:$max:$hdg";
    return $txt;
}

# 0   1 (lat)   2 (lon)        3     4   5           6   7  8++
# 2   38.087769 -077.324919  284   396  25       0.000 APH  A P Hill NDB
# 3   57.103719  009.995578   57 11670 100       1.000 AAL  Aalborg VORTAC
# 4   39.980911 -075.877814  660 10850  18     281.662 IMQS 40N 29 ILS-cat-I
# 4  -09.458922  147.231225  128 11010  18     148.650 IWG  AYPY 14L ILS-cat-I
# 5   40.034606 -079.023281 2272 10870  18     236.086 ISOZ 2G9 24 LOC
# parsed and put in an array
##              0    1     2     3     4     5     6      7     8  9    10
#push(@navlist,[$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nid  ,$name,$s,$az1,$az2]);

sub get_ils_cnt($) {
    my ($icao) = shift;
    my $icnt = 0;
    my $max = scalar @{$rnavaids};
    my ($i,$typ,$ra,$name,$tmp,@arr);
    # prt("Finding ILS for [$icao] in $max navaids...\n");
    for ($i = 0; $i < $max; $i++) {
        $ra = ${$rnavaids}[$i];
        $typ = ${$ra}[0];
        next if ($typ != 4);
        $name = ${$ra}[7]; 
        @arr = split(/\s+/,$name);
        $tmp = $arr[0];
        next if ($icao ne $tmp);
        $icnt++;
    }
    return $icnt;
}

sub show_distance_list($) {
    my ($find_icao) = @_;
    my $rapts = \@g_aptlist;
    my $cnt = scalar @{$rapts};
    my ($i,$atyp,$icao,$name,$alat,$alon,$aalt,$rfreq,$rrwys,$rwycnt,$len);
    my ($fatyp,$ficao,$fname,$falat,$falon,$faalt,$frfreq,$frrwys,$frwycnt);
    my ($s,$az1,$az2,$distnm,$arwys);
    my $minn = 0;
    # SORT list in decending DISTANCE order
    prt("Show list of $g_max_out nearest airports to $find_icao... ");
    if ($g_track != -1) {
        prt("On track $g_track, +/-$g_spread degrees... ");
    }
    if ($only_with_ils) {
        prt("with ILS ");
    }
    prt("\n");
    # ============================================
    my @newarr = sort mycmp_decend_dist @{$rapts};
    # ============================================
    $rapts = \@newarr;
    my $max = $g_max_out;
    my $xhele = $g_xhele;
    my $xsea = $g_xsea;
    my $xold = $g_xold;
    my $dn_hdr = 0;
    my $x_hel = 0;
    my $x_sea = 0;
    my $x_old = 0;
    my $x_trk = 0;
    my $done = 0;
    my $ilscnt = 0;
    $minn = 0;
    $done = 0;
    # run only to get minimum NAME length
    for ($i = 0; $i < $cnt; $i++) {
        $name = ${$rapts}[$i][2];
        $az1   = ${$rapts}[$i][9];
        if ($done) {
            if ($g_track != -1) {
                if (not_on_track($az1)) {
                    $x_trk++;
                    next;
                }
            }
            if (($name =~ /\[H\]/) && $xhele) {
                $x_hel++;
                next;
            }
            if (($name =~ /\[S\]/) && $xsea) {
                $x_sea++;
                next;
            }
            if (($name =~ /\[X\]/) && $xold) {
                $x_old++;
                next;
            }
            if ($only_with_ils) {
                $icao = ${$rapts}[$i][1];
                $ilscnt = get_ils_cnt($icao);
                next if ($ilscnt == 0);
            }

        }
        $len = length($name);
        $minn = $len if ($len > $minn);
        $done++;
        last if ($done == $max);
    }

    # display run
    # ==========================================
    $done = 0; # restart done counter
    for ($i = 0; $i < $cnt; $i++) {
        $name = ${$rapts}[$i][2];
        $az1   = ${$rapts}[$i][9];
        if ($done) {
            next if (($g_track != -1) && not_on_track($az1));
            next if (($name =~ /\[H\]/) && $xhele);
            next if (($name =~ /\[S\]/) && $xsea);
            next if (($name =~ /\[X\]/) && $xold);
            if ($only_with_ils) {
                $icao = ${$rapts}[$i][1];
                $ilscnt = get_ils_cnt($icao);
                next if ($ilscnt == 0);
            }
        }
        $atyp = ${$rapts}[$i][0];
        $icao = ${$rapts}[$i][1];
        $alat = ${$rapts}[$i][3];
        $alon = ${$rapts}[$i][4];
        $aalt = ${$rapts}[$i][5];
        $rfreq = ${$rapts}[$i][6];  # ATC frequ
        $rrwys = ${$rapts}[$i][7];  # Runways
        $s     = ${$rapts}[$i][8];
        $az2   = ${$rapts}[$i][10];

        # set BOUNDS
        $g_minlat = $alat if ($alat < $g_minlat);
        $g_minlon = $alon if ($alon < $g_minlon);
        $g_maxlat = $alat if ($alat > $g_maxlat);
        $g_maxlon = $alon if ($alon > $g_maxlon);
        $g_minalt = $aalt if ($aalt < $g_minalt);
        $g_maxalt = $aalt if ($aalt > $g_maxalt);

        # FORMAT the display
        ##############################################
        $arwys = get_runways_stg($rrwys);
        $ilscnt = get_ils_cnt($icao);
        if ($ilscnt) {
            $arwys .= ":ils:".$ilscnt;
        } else {
            ### $arwys .= ":ni";
        }
        $name = cased_name($name) if (!$name_as_is);
        $distnm = $s * $SG_METER_TO_NM;
        $distnm = (int($distnm * 10) / 10);
        if ($distnm == int($distnm)) {
            $distnm .= ".0";
        }
        $distnm = ' '.$distnm while (length($distnm) < $g_distmin);
        $name .= ' ' while (length($name) < $minn);
        $icao .= ' ' while (length($icao) < 4);
        set_lat_stg(\$alat);
        set_lon_stg(\$alon);
        $aalt = ' '.$aalt while (length($aalt) < $g_altmin);
        set_azimuth_stg(\$az1);
        if (!$dn_hdr) {
            prt("ICAO, ");
            my $tmp = "Name";
            $tmp .= ' ' while (length($tmp) < $minn);
            prt("$tmp, ");
            $tmp = "Latitude";
            $tmp = ' '.$tmp while (length($tmp) < length($alat));
            prt("$tmp, ");
            $tmp = "Longitude";
            $tmp = ' '.$tmp while (length($tmp) < length($alon));
            prt("$tmp, ");
            $tmp = "Alt(ft)";
            $tmp = ' '.$tmp while (length($tmp) < length($aalt));
            prt("$tmp, ");
            $tmp = "D(nm)";
            $tmp = ' '.$tmp while (length($tmp) < $g_distmin);
            prt("$tmp, ");
            $tmp = "Degs";
            $tmp = ' '.$tmp while (length($tmp) < length($az1));
            prt("$tmp");
            prt("\n");
            $dn_hdr = 1;
        }
        # skip the first, which is the user target airport
        prt("$icao, $name, $alat, $alon, $aalt, $distnm, $az1, $arwys\n") if ($done);
        $done++;
        last if ($done == $max);
    }
    if ($x_hel || $x_sea || $x_old || $x_trk) {
        prt("NOTE: Excluded: ");
        prt("$x_trk not on track $g_track, +/-$g_spread degs. ") if ($x_trk);
        prt("$x_hel heleports. ") if ($x_hel);
        prt("$x_sea seaports. ") if ($x_sea);
        prt("$x_old closed. ") if ($x_old);
        prt("\n");
    }

}


sub process_in_icao($) {
    my ($find_icao) = @_;   # user ICAO
    my $rapts = \@g_aptlist;    # find AIRPORT
    my @found = ();
    my $cnt = scalar @{$rapts};
    ##                 0      1      2      3      4      5      6    7
    #push(@g_aptlist, [$diff, $icao, $name, $alat, $alon, $aalt, \@f, \@r]);
    my ($i,$atyp,$icao,$name,$alat,$alon,$aalt,$rfreq,$rrwys,$rwycnt,$len);
    prt("[v1] Searching $cnt airports for ICAO [$find_icao]...\n") if (VERB1());
    my $minn = 0;
    my $fndcnt = 0;
    $g_minlat =  200;
    $g_minlon =  200;
    $g_maxlat = -200;
    $g_maxlon = -200;
    $g_minalt =  9999999;
    $g_maxalt = -9999999;
    for ($i = 0; $i < $cnt; $i++) {
        $icao = ${$rapts}[$i][1];
        $name = ${$rapts}[$i][2];
        if ($icao eq $find_icao) {
            $atyp = ${$rapts}[$i][0];
            $alat = ${$rapts}[$i][3];
            $alon = ${$rapts}[$i][4];
            $aalt = ${$rapts}[$i][5];
            $rfreq = ${$rapts}[$i][6];
            $rrwys = ${$rapts}[$i][7];
            $rwycnt = scalar @{$rrwys};
            # set BOUNDS
            $g_minlat = $alat if ($alat < $g_minlat);
            $g_minlon = $alon if ($alon < $g_minlon);
            $g_maxlat = $alat if ($alat > $g_maxlat);
            $g_maxlon = $alon if ($alon > $g_maxlon);
            $g_minalt = $aalt if ($aalt < $g_minalt);
            $g_maxalt = $aalt if ($aalt > $g_maxalt);

            $name = cased_name($name) if (!$name_as_is);
            prt("Found $icao, $name, $alat, $alon, $aalt ft, $rwycnt runways\n"); # if (VERB1());
            push(@found, $i);
            $fndcnt++;
        }
        $len = length($name);
        $minn = $len if ($len > $minn);
    }
    if (!$fndcnt) {
        prt("No airport found with ICAO of $find_icao!\n");
        return 0;
    }
    if ($fndcnt > 1) {
        prtw("WARNING: Found $fndcnt matching ICAO! Only nearest first shown\n");
    }
    my $fnd = $found[0];
    $i = $fnd;
    my ($fatyp,$ficao,$fname,$falat,$falon,$faalt,$frfreq,$frrwys,$frwycnt);
    $fatyp = ${$rapts}[$i][0];
    $ficao = ${$rapts}[$i][1];
    $fname = ${$rapts}[$i][2];
    $falat = ${$rapts}[$i][3];
    $falon = ${$rapts}[$i][4];
    $faalt = ${$rapts}[$i][5];
    $frfreq = ${$rapts}[$i][6];
    $frrwys = ${$rapts}[$i][7];
    $g_clat = $falat;
    $g_clon = $falon;
    ${$rapts}[$i][8] = 0;
    ${$rapts}[$i][9] = 0;
    ${$rapts}[$i][10] = 0;
    my ($s,$az1,$az2,$distnm);
    ##                 0      1      2      3      4      5      6    7
    #push(@g_aptlist, [$diff, $icao, $name, $alat, $alon, $aalt, \@f, \@r]);
    for ($i = 0; $i < $cnt; $i++) {
        next if ($i == $fnd);
        $alat = ${$rapts}[$i][3];
        $alon = ${$rapts}[$i][4];
        #sub fg_geo_inverse_wgs_84 {
        #my ($lat1, $lon1, $lat2, $lon2, $az1, $az2, $s) = @_;
        fg_geo_inverse_wgs_84($falat,$falon,$alat,$alon,\$az1,\$az2,\$s);
        ${$rapts}[$i][8] = $s;      # distance from FOUND
        ${$rapts}[$i][9] = $az1;    # direction from found
        ${$rapts}[$i][10] = $az1;   # direction to found
    }

    return $fndcnt;
}

# **************************
sub load_gzip_lines($) {
    my $file = shift;
	prt("\n[v9] Loading $file file ...\n") if (VERB9());
	mydie("ERROR: Can NOT locate [$file]!\n") if ( !( -f $file) );
	open NIF, "gzip -d -c $file|" or mydie( "ERROR: CAN NOT OPEN $file...$!...\n" );
	my @nav_lines = <NIF>;
	close NIF;
    prt("[v9] Got ".scalar @nav_lines." lines to scan...\n") if (VERB9());
    return \@nav_lines;
}

# NAV.DAT FIX.DAT AWY.DAT
sub load_nav_lines() { return load_gzip_lines($navdat); }
sub load_fix_lines() { return load_gzip_lines($g_fixfile); }
sub load_awy_lines() { return load_gzip_lines($g_awyfile); }

####################################################################
### load navaids, and keep DISTANCE from the airport given
sub load_nav_file() {
    my $rnav = load_nav_lines();
    my $cnt = scalar @{$rnav};
    prt("[v1] Loaded $cnt lines, from [$navdat]...\n") if (VERB1());
    my ($i,$line,$len,$lnn,@arr,$nc);
    my ($typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name,$navcnt);
    my ($s,$az1,$az2);
    $nlat = $g_clat;
    $nlon = $g_clon;
    set_lat_stg(\$nlat);
    set_lon_stg(\$nlon);
    #prt("Show  $g_max_out closest navaids to $nlat,$nlon\n");
    $lnn = 0;
    $navcnt = 0;
    my @navlist = ();
    for ($i = 0; $i < $cnt; $i++) {
        $line = trim_all(${$rnav}[$i]);
        $len = length($line);
        next if ($len == 0);
        next if ($line =~ /\s+Version\s+/i);
		@arr = split(/\s+/,$line);
		$nc = scalar @arr;
		$typ = $arr[0];
        next if ($typ eq 'I');
        last if ($typ eq '99');
        if (!is_defined_nav_type($typ)) {
            prt("$lnn: Undefined [$line]\n");
            next;
        }
        $navcnt++;
		# 0   1 (lat)   2 (lon)        3     4   5           6   7  8++
		# 2   38.087769 -077.324919  284   396  25       0.000 APH  A P Hill NDB
		# 3   57.103719  009.995578   57 11670 100       1.000 AAL  Aalborg VORTAC
		# 4   39.980911 -075.877814  660 10850  18     281.662 IMQS 40N 29 ILS-cat-I
		# 4  -09.458922  147.231225  128 11010  18     148.650 IWG  AYPY 14L ILS-cat-I
		# 5   40.034606 -079.023281 2272 10870  18     236.086 ISOZ 2G9 24 LOC
		# 5   67.018506 -050.682072  165 10955  18      61.600 ISF  BGSF 10 LOC
		# 6   39.977294 -075.860275  655 10850  10  300281.205 ---  40N 29 GS
		# 6  -09.432703  147.216444  128 11010  10  302148.785 ---  AYPY 14L GS
		# 7   39.960719 -075.750778  660     0   0     281.205 ---  40N 29 OM
		# 7  -09.376150  147.176867  146     0   0     148.785 JSN  AYPY 14L OM
		# 8  -09.421875  147.208331   91     0   0     148.785 MM   AYPY 14L MM
		# 8  -09.461050  147.232544  146     0   0     328.777 PY   AYPY 32R MM
		# 9   65.609444 -018.052222   32     0   0      22.093 ---  BIAR 01 IM
		# 9   08.425319  004.475597 1126     0   0      49.252 IL   DNIL 05 IM
		# 12 -09.432703  147.216444   11 11010  18       0.000 IWG  AYPY 14L DME-ILS
		# 12 -09.449222  147.226589   11 10950  18       0.000 IBB  AYPY 32R DME-ILS
        $nlat = $arr[1];
        $nlon = $arr[2];
        $nalt = $arr[3];
        $nfrq = $arr[4];
        $nrng = $arr[5];
        $nfrq2 = $arr[6];
        $nid = $arr[7];     # this is an ICAO if it is an ILS
        $name = '';
        for (my $i = 8; $i < $nc; $i++) {
            $name .= ' ' if length($name);
            $name .= $arr[$i];
        }
        fg_geo_inverse_wgs_84($g_clat,$g_clon,$nlat,$nlon,\$az1,\$az2,\$s);
        #push(@navlist,[$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$name,$s,$az1,$az2]);
        #              0    1     2     3     4     5     6      7     8  9    10
        push(@navlist,[$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nid  ,$name,$s,$az1,$az2]);
    }
    prt("Loaded $navcnt navigation aids...\n") if (VERB5());
    @navlist = sort mycmp_decend_dist @navlist;
    prt("[v1] $navcnt navaids sorted per distance from $g_clat,$g_clon...\n") if (VERB1());
    return \@navlist;
}

sub show_nav_list($) {
    my ($rnavs) = @_;
    my $cnt = scalar @{$rnavs};
    my ($ctyp,$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name,$navcnt);
    my ($i,$s,$az1,$az2,$distnm,$minnm,$len,$msg);
    my $max = $g_max_out;
    my $done = 0;
    $minnm = 0;
    for ($i = 0; $i < $cnt; $i++) {
        last if ($done == $max);
        #               0    1     2     3     4     5     6      7     8  9    10
        #push(@navlist,[$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nid  ,$name,$s,$az1,$az2]);
        $name = ${$rnavs}[$i][7];
        $len = length($name);
        $minnm = $len if ($len > $minnm);
        $done++;
    }
    $done = 0;
    #           VDME -32.2196810, 148.5776610     935 11440    50    31.4 185.5 DUBBO VOR-DME DME 
    my $head = "Type Latitude    Longitude     Alt.   Freq  Range Dist.NM Hdg   Name";
    prt("$head\n");
    for ($i = 0; $i < $cnt; $i++) {
        last if ($done == $max);
        #               0    1     2     3     4     5     6      7     8  9    10
        #push(@navlist,[$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$name,$s,$az1,$az2]);
        $typ = ${$rnavs}[$i][0];
        $nlat = ${$rnavs}[$i][1];
        $nlon = ${$rnavs}[$i][2];
        $nalt = ${$rnavs}[$i][3];
        $nfrq = ${$rnavs}[$i][4];
        $nrng = ${$rnavs}[$i][5];
        $nfrq2 = ${$rnavs}[$i][6];
        $name = ${$rnavs}[$i][7];
        $s = ${$rnavs}[$i][8];
        $az1 = ${$rnavs}[$i][9];
        $az2 = ${$rnavs}[$i][10];
        $distnm = $s * $SG_METER_TO_NM;
        $msg = '';
        # No range for 
        # my $navOM  = '7';
        # my $navMM  = '8';
        # my $navIM  = '9';
        if (("$typ" eq $navOM)|| ("$typ" eq $navMM) || ("$typ" eq $navIM)) {
            # these have NO range - very short anyway
        } else {
            $msg = '(Rng!)' if ($distnm > $nrng);
        }
        # get display FORMAT
        $ctyp = get_nav_type_stg($typ);
        $ctyp .= ' ' while (length($ctyp) < 4);
        $distnm = (int($distnm * 10) / 10);
        if ($distnm == int($distnm)) {
            $distnm .= ".0";
        }
        $distnm = ' '.$distnm while (length($distnm) < $g_distmin);
        set_lat_stg(\$nlat);
        set_lon_stg(\$nlon);
        $nalt = ' '.$nalt while (length($nalt) < $g_altmin);
        $nfrq .= ' ' while (length($nfrq) < $g_frqmin);
        $nrng = ' '.$nrng while (length($nrng) < $g_rngmin);
        set_azimuth_stg(\$az1);
        $name .= ' ' while (length($name) < $minnm);
        #prt("$ctyp,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$name,$s,$az1,$az2\n");
        prt("$ctyp $nlat,$nlon $nalt $nfrq $nrng $distnm $az1 $name $msg\n");
        $done++;
    }
    $nlat = $g_clat;
    $nlon = $g_clon;
    set_lat_stg(\$nlat);
    set_lon_stg(\$nlon);
    prt("Shown $done closest navaids to $nlat,$nlon\n");
}

sub load_fix_hash($) {
    my ($rfa) = @_;
    my $max = scalar @{$rfa};
    my ($line,$len,@arr,$cnt,$typ,$flat,$flon,$fname,$name,$key);
    my %h;
    foreach $line (@{$rfa}) {
        chomp $line;
        $line = trim_all($line);
        $len = length($line);
        next if ($len == 0);
        next if ($line =~ /^I/);
        next if ($line =~ /Version/i);
        @arr = split(/\s+/,$line);
        $cnt = scalar @arr;
        $typ = $arr[0];
        next if ($typ == 600);
        last if ($typ == 99);
        if ($cnt >= 3) {
            $flat = $arr[0];
            $flon = $arr[1];
            $name = trim_all($arr[2]);
            #  $name      0      1
            $h{$name} = [ $flat, $flon ];
        }
    }
    return \%h;
}

sub load_fix_file() {
    my $rfixs = load_fix_lines();
    my $cnt = scalar @{$rfixs};
    prt("Loaded $cnt lines of fixes...\n") if (VERB9());
    my $rfh = load_fix_hash($rfixs);
    my @fixarr = ();
    my ($name,$val,$flat,$flon,$fcnt);
    my ($s,$az1,$az2);
    $fcnt = 0;
    foreach $name (keys %{$rfh}) {
        $val = ${$rfh}{$name};
        $flat = ${$val}[0];
        $flon = ${$val}[1];
        if (in_world_range($flat,$flon)) {
            fg_geo_inverse_wgs_84($g_clat,$g_clon,$flat,$flon,\$az1,\$az2,\$s);
            #              0     1     2    3 4 5 6 7 8  9    10
            push(@fixarr,[$name,$flat,$flon,0,0,0,0,0,$s,$az1,$az2]);
            $fcnt++;
        } else {
            prt("$name $flat $flon - OUT OF WORLD RANGE!\n");
        }
    }
    @fixarr = sort mycmp_decend_dist @fixarr;
    prt("Loaded $fcnt fixes... sorted by distance...\n") if (VERB9());
    return \@fixarr;
}

sub show_fix_list($) {
    my ($rfixs) = @_;
    my $cnt = scalar @{$rfixs};
    my ($i,$name,$flat,$flon,$s,$az1,$done,$minnm,$len,$distnm);
    my $max = $g_max_out;
    $done = 0;
    $minnm = 0;
    for ($i = 0; $i < $cnt; $i++) {
        last if ($done == $max);
        #               0     1     2    3 4 5 6 7 8  9    10
        #push(@fixarr,[$name,$flat,$flon,0,0,0,0,0,$s,$az1,$az2]);
        $name = ${$rfixs}[$i][0];
        $len = length($name);
        $minnm = $len if ($len > $minnm);
        $done++;
    }
    $done = 0;
    #           HILAR -31.6452780, 148.4861110     8.3 291.9
    my $head = "Name  Latitude    Longitude    Dist.NM Hdg";
    prt("$head\n");
    for ($i = 0; $i < $cnt; $i++) {
        last if ($done == $max);
        #               0     1     2    3 4 5 6 7 8  9    10
        #push(@fixarr,[$name,$flat,$flon,0,0,0,0,0,$s,$az1,$az2]);
        $name = ${$rfixs}[$i][0];
        $flat = ${$rfixs}[$i][1];
        $flon = ${$rfixs}[$i][2];
        $s    = ${$rfixs}[$i][8];
        $az1  = ${$rfixs}[$i][9];
        #prt("$name,$flat,$flon,$s,$az1\n");

        # get display FORMAT
        $name .= ' ' while (length($name) < $minnm);
        set_lat_stg(\$flat);
        set_lon_stg(\$flon);
        $distnm = $s * $SG_METER_TO_NM;
        $distnm = (int($distnm * 10) / 10);
        if ($distnm == int($distnm)) {
            $distnm .= ".0";
        }
        $distnm = ' '.$distnm while (length($distnm) < $g_distmin);
        set_azimuth_stg(\$az1);
        prt("$name $flat,$flon $distnm $az1\n");
        $done++;
    }
}

# FG airways file
# 0      1          2          3      4          5          6  7   8   9
# ASKIK  50.052778  008.533611 RUDUS  50.047500  008.078333 1  050 240 L984
# from   lat        lon        to     lat        lon       cat bfl efl name
#
# Basic to air traffic control are special air routes called airways.
# Airways are defined on charts and are provided with radio ranges, 
# devices that allow the pilot whose craft has a suitable receiver 
# to determine the plane's bearing and distance from a fixed location. 
# The most common beacon is a very high frequency omnidirectional 
# radio beacon, which emits a signal that varies according to the 
# direction in which it is transmitted. Using a special receiver, 
# an air navigator can obtain an accurate bearing on the transmitter 
# and, using distance-measuring equipment (DME), distance from it as well.
#
# The system of radio ranges around the United States is often called 
# the VORTAC system. For long distances other electronic navigation 
# systems have been developed: 
# Omega, accurate to about two miles (3 km); 
# Loran-C, accurate to within .25 mi (.4 km) but available only in the United States; 
# and the Global Positioning System (GPS), a network of 24 satellites that 
# is accurate to within a few yards and is making radio ranging obsolete.

sub load_awy_file() {
    my $raa = load_awy_lines();
    my $max = scalar @{$raa};
    my ($line,$len,@arr,$cnt,$typ,$flat,$flon,$fname,$name,$key);
    my ($tlat,$tlon,$from,$to,$hadver);
    my ($cat,$bfl,$efl,$ra,$lnn,$num);
    my ($s,$az1,$az2);
    my @airways = ();
    prt("Loaded $max lines of airways...\n") if (VERB9());
    $lnn = 0;
    $hadver = 0;
    $num = 0;
    foreach $line (@{$raa}) {
        $lnn++;
        chomp $line;
        $line = trim_all($line);
        $len = length($line);
        next if ($len == 0);
        next if (($line =~ /^I/)&&($hadver == 0));
        if ($line =~ /\s+Version\s+/) {
            $hadver = 1;
            #next if ($typ == 640);
            next;
        }
        @arr = split(/\s+/,$line);
        $cnt = scalar @arr;
        $typ = $arr[0];
        last if ($typ =~ /^99/);
        if ($cnt >= 10) {
            # 0      1          2          3      4          5          6  7   8   9
            # ASKIK  50.052778  008.533611 RUDUS  50.047500  008.078333 1  050 240 L984
            # from   lat        lon        to     lat        lon       cat bfl efl name
            $from = $arr[0];
            $flat = $arr[1];
            $flon = $arr[2];
            $to   = $arr[3];
            $tlat = $arr[4];
            $tlon = $arr[5];
            # 1 115 285 W73
            $cat  = $arr[6]; # category 1 == low altitude, 2 == high altitude
            $bfl  = $arr[7]; # begin flight level
            $efl  = $arr[8]; # end flight level
            $name = trim_all($arr[9]);
            #$ids{$name} = [ ] if (!defined $ids{$name});
            #$ra = $ids{$name};
            #push(@{$ra}, [ $from, $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl ]);
            $num++;
            fg_geo_inverse_wgs_84($g_clat,$g_clon,$flat,$flon,\$az1,\$az2,\$s);
            #                0      1      2      3      4     5     6     7  8   9     10    11
            push(@airways, [ $name, $from, $flat, $flon, $cat, $bfl, $efl, 0, $s, $az1, $az2, $num ]);
            fg_geo_inverse_wgs_84($g_clat,$g_clon,$tlat,$tlon,\$az1,\$az2,\$s);
            #                0      1      2      3      4     5     6     7  8   9     10    11
            push(@airways, [ $name, $to,   $tlat, $tlon, $cat, $bfl, $efl, 1, $s, $az1, $az2, $num ]);
        }
    }

    @airways = sort mycmp_decend_dist @airways;
    prt("Loaded $num airways... sorted by distance...\n") if (VERB9());
    return \@airways;
}

sub show_awy_list($) {
    my $rawys = shift;
    my $cnt = scalar @{$rawys};
    #                 0      1      2      3      4     5     6     7  8   9     10    11
    #push(@airways, [ $name, $from, $flat, $flon, $cat, $bfl, $efl, 0, $s, $az1, $az2, $num ]);
    #push(@airways, [ $name, $to,   $tlat, $tlon, $cat, $bfl, $efl, 1, $s, $az1, $az2, $num ]);
    my $max = $g_max_out;
    my ($i,$done,$minnm,$name,$from,$flat,$flon,$cat,$bfl,$efl,$tf,$distnm);
    my ($s,$az1,$minnm2,$tfm1,$tfm2,$len);
    my ($j,$to,$tlat,$tlon,$num,$minnm3,$minnm4, $nxt);
    $done = 0;
    $minnm = 0;
    $minnm2 = 0;
    $minnm3 = 0;
    $minnm4 = 0;
    my @arr = ();
    for ($i = 0; $i < $cnt; $i++) {
        last if ($done == $max);
        $name = ${$rawys}[$i][0];
        $len = length($name);
        $minnm = $len if ($len > $minnm);
        $from = ${$rawys}[$i][1];
        $len = length($from);
        $minnm2 = $len if ($len > $minnm2);
        $done++;
        $num  = ${$rawys}[$i][11];
        ### ${$rawys}[$i][12] = 0;
        $nxt = $i;
        for ($j = 0; $j < $cnt; $j++) {
            next if ($i == $j);
            if ($num == ${$rawys}[$j][11]) {
                $len = length(${$rawys}[$j][1]);
                $minnm3 = $len if ($len > $minnm3);
                $nxt = $j;
                last;
            }
        }
        $s    = ${$rawys}[$i][8];
        $distnm = $s * $SG_METER_TO_NM;
        $distnm = (int($distnm * 10) / 10);
        $distnm .= ".0" if ($distnm == int($distnm));
        $len = length($distnm);
        $minnm4 = $len if ($len > $minnm4);
        push(@arr,[$i,$nxt]);
    }
    $done = 0;
    #           Y23   fr OKAPI -31.8644440, 148.6538890 10.0 175.1 to TW    -31.0662030, 150.8300220 1 180 600
    my $head = "Name  tf Code  Latitude    Longigude    NM   Hdg   tf Code  Latitude    Longitude    C BFL EFL";
    prt("$head\n");
    for ($i = 0; $i < $cnt; $i++) {
        last if ($done == $max);
        $name = ${$rawys}[$i][0];
        $from = ${$rawys}[$i][1];
        $flat = ${$rawys}[$i][2];
        $flon = ${$rawys}[$i][3];
        $cat  = ${$rawys}[$i][4];
        $bfl  = ${$rawys}[$i][5];
        $efl  = ${$rawys}[$i][6];
        $tf   = ${$rawys}[$i][7];
        $s    = ${$rawys}[$i][8];
        $az1  = ${$rawys}[$i][9];
        $num  = ${$rawys}[$i][11];
        $to = "NOTFND";
        $tlat = 0;
        $tlon = 0;
        for ($j = 0; $j < $cnt; $j++) {
            next if ($i == $j);
            if ($num == ${$rawys}[$j][11]) {
                $to   = ${$rawys}[$j][1];
                $tlat = ${$rawys}[$j][2];
                $tlon = ${$rawys}[$j][3];
                last;
            }
        }
        $done++;

        # display format
        if ($tf) {
            $tfm1 = "to";
            $tfm2 = "fr";
        } else {
            $tfm2 = "to";
            $tfm1 = "fr";
        }
        $name .= ' ' while (length($name) < $minnm);
        $from .= ' ' while (length($from) < $minnm2);
        $to   .= ' ' while (length($to) < $minnm3);
        set_lat_stg(\$flat);
        set_lon_stg(\$flon);
        $distnm = $s * $SG_METER_TO_NM;
        $distnm = (int($distnm * 10) / 10);
        $distnm .= ".0" if ($distnm == int($distnm));
        #$distnm = ' '.$distnm while (length($distnm) < $g_distmin);
        $distnm = ' '.$distnm while (length($distnm) < $minnm4);
        set_lat_stg(\$tlat);
        set_lon_stg(\$tlon);
        set_azimuth_stg(\$az1);
        prt("$name $tfm1 $from $flat,$flon $distnm $az1 $tfm2 $to $tlat,$tlon $cat $bfl $efl\n");
    }
}

sub get_bucket_info {
   my ($lon,$lat) = @_;
   my $b = Bucket2->new();
   $b->set_bucket($lon,$lat);
   return $b->bucket_info();
}

# 14/12/2010 - Switch to using the Bucket2.pm
# 02/05/2011 - add the tile INDEX
sub get_tile { # $alon, $alat
	my ($lon, $lat) = @_;
    my $b = Bucket2->new();
    $b->set_bucket($lon,$lat);
    return $b->gen_base_path()."/".$b->gen_index();
}

sub get_bucket_wid($$) {
	my ($lon, $lat) = @_;
    my $b = Bucket2->new();
    my $wid = $b->get_width();
    return $wid;
}

sub get_bucket_hgt($$) {
	my ($lon, $lat) = @_;
    my $b = Bucket2->new();
    my $hgt = $b->get_height();
    return $hgt;
}

sub get_bucket_index($$) { # $alon, $alat
	my ($lon, $lat) = @_;
    my $b = Bucket2->new();
    $b->set_bucket($lon,$lat);
    return $b->gen_index();
}

sub show_touching_buckets($$) {
    my ($lon,$lat) = @_;
    my $b = Bucket2->new();
    $b->set_bucket($lon,$lat);
    my ($i,$i2,$nb,$line,$nbt,$bpos);
    $nbt = $b->gen_base_path()."/".$b->gen_index();
    prt("[v2] Set of 8 touching bucket to $nbt\n");
    my %pos = (
        0 => 'BL',
        1 => 'BC',
        2 => 'BR',
        3 => 'CR',
        4 => 'TR',
        5 => 'TC',
        6 => 'TL',
        7 => 'CL' );
    for ($i = 0; $i <= 7; $i++) {
        $i2 = $i + 1;
        $nb = $b->get_next_bucket($i);
        $nbt = $nb->gen_base_path()."/".$nb->gen_index();
        $bpos = $pos{$i};
        $line = "$i2: $bpos: $nbt";
        prt("$line\n");
    }
}

#########################################
### MAIN ###
parse_args(@ARGV);
load_apt_data();
if (process_in_icao($in_icao)) {
    #               0    1     2     3     4     5     6      7     8  9    10
    #push(@navlist,[$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nid  ,$name,$s,$az1,$az2]);
    $rnavaids = load_nav_file();
    show_distance_list($in_icao);
    ##prt("Bounds:lat,lon: -minmax=$g_minlat,$g_minlon,$g_maxlat,$g_maxlon alt-minmax=$g_minalt,$g_maxalt\n");
    prt("Bounds minlat=$g_minlat minlon=$g_minlon maxlat=$g_maxlat maxlon=$g_maxlon\n");
    prt("Altitude range min=$g_minalt max=$g_maxalt\n");
    my ($lat,$lon);
    if (VERB1()) {
        my $clat = ($g_minlat + $g_maxlat) / 2;
        my $clon = ($g_minlon + $g_maxlon) / 2;
        my $alat = sprintf("%2.9f",$clat);
        my $alon = sprintf("%3.9f",$clon);
        my $line = "Center: lat=$alat lon=$alon ";
        $line .= " fg=".get_tile($clon,$clat);
		prt("$line\n"); # print
        $line = "Bucket: ".get_bucket_info($clon,$clat);
		prt("$line\n"); # print
        show_touching_buckets($clon,$clat) if (VERB2());
        if (VERB5()) {
            my $b = Bucket2->new();
            $b->set_bucket($clon,$clat);
            my ($i,$i2,$nb,$line,$nbt,$bpos,$ind);
            $ind = $b->gen_index();

            my $wid = get_bucket_wid($clon,$clat) / 5;
            my $hgt = get_bucket_hgt($clon,$clat) / 5;
            my $cnt = 0;
            my %indexes =();
            for ($lon = $g_minlon; $lon <= $g_maxlon; $lon += $wid) {
                for ($lat = $g_minlat; $lat < $g_maxlat; $lat += $hgt) {
                    $b->set_bucket($lon,$lat);
                    $ind = $b->gen_index();
                    if (!defined $indexes{$ind}) {
                        $indexes{$ind} = 1;
                        $cnt++;
                    }
                }
            }
            prt("[v5] Area spans $cnt SG buckets...\n");
            my $len = length($cnt);
            my $form = '%'.sprintf("%d",$len)."d";
            my $acnt = sprintf($form,$cnt);
            $cnt = 0;
            %indexes = ();
            for ($lon = $g_minlon; $lon <= $g_maxlon; $lon += $wid) {
                for ($lat = $g_minlat; $lat <= $g_maxlat; $lat += $hgt) {
                    $b->set_bucket($lon,$lat);
                    $ind = $b->gen_index();
                    if (!defined $indexes{$ind}) {
                        $indexes{$ind} = 1;
                        $cnt++;
                        $acnt = sprintf($form,$cnt);
                        #prt(" $acnt: Bucket: ".get_bucket_info($lon,$lat)."\n");
                        prt(" $acnt: Tile: ".get_tile($lon,$lat)."\n");
                    }
                }
            }
        }
    }
    if ($show_navaids && in_world_range($g_clat,$g_clon) && (-f $navdat)) {
        $lat = $g_clat;
        $lon = $g_clon;
        set_lat_stg(\$lat);
        set_lon_stg(\$lon);
        prt("Show  $g_max_out closest NAVAIDS to $lat,$lon...\n");
        ###my $rnavs = load_nav_file();
        show_nav_list($rnavaids);
    }
    if ($show_fixes && (-f $g_fixfile) && in_world_range($g_clat,$g_clon)) {
        $lat = $g_clat;
        $lon = $g_clon;
        set_lat_stg(\$lat);
        set_lon_stg(\$lon);
        prt("Show   $g_max_out closest FIXES to $lat,$lon...\n");
        my $rfixes = load_fix_file();
        show_fix_list($rfixes);
    }
    if ($show_airways && (-f $g_awyfile) && in_world_range($g_clat,$g_clon)) {
        $lat = $g_clat;
        $lon = $g_clon;
        set_lat_stg(\$lat);
        set_lon_stg(\$lon);
        prt("Show   $g_max_out closest AIRWAYS to $lat,$lon...\n");
        my $rawys = load_awy_file();
        show_awy_list($rawys);
    }
}
pgm_exit(0,"");
########################################

sub out_xclude_list() {
    # show the set
    if ($g_xhele && $g_xsea && $g_xold) {
        prt("all of hele:sea:closed");
    } elsif ($g_xhele || $g_xsea || $g_xold) {
        my $tmp = '';
        if ($g_xhele) {
            $tmp .= ':' if (length($tmp));
            $tmp .= "hele";
        }
        if ($g_xsea) {
            $tmp .= ':' if (length($tmp));
            $tmp .= "sea";
        }
        if ($g_xold) {
            $tmp .= ':' if (length($tmp));
            $tmp .= "closed";
        }
        prt($tmp);
    } else {
        prt("none of hele:sea:closed");
    }
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] icao\n");
    prt("Options:\n");
    prt(" --help   (-h or -?) = This help, and exit 0.\n");
    prt(" --airways      (-a) = Load and show closest $g_max_out airways ends.\n");
    prt(" --bounds       (-b) = Show bounding box. (def=$show_bounds)\n");
    prt(" --case         (-c) = No case change. Show airport names as they appear in file.\n");
    prt(" --fix          (-f) = Load and show closest $g_max_out fixes.\n");
    prt(" --ils          (-i) = Show only airports with an ILS facility.\n");
    prt(" --load         (-l) = Load LOG at end. ($outfile)\n");
    prt(" --max <num>    (-m) = Maximum number of closest output. (def=$g_max_out)\n");
    prt(" --nav          (-n) = Load and show closest $g_max_out navaids.\n");
    prt(" --spread <deg> (-s) = Spread +/- degrees if track given. (def=$g_spread)\n");
    prt(" --track <deg>  (-t) = Find nearest on this heading in degs.");
    prt(" (def=".(($g_track == -1) ? "Off" : "$g_track, +/- spread below").")\n");
    prt(" --verb[n]      (-v) = Bump [or set] verbosity to 0,1,2,5,9. (def=$verbosity)\n");
    prt(" --xclude <typ> (-x) = eXclude type hele, sea, closed, all or none.");
    prt(" (def=");
    out_xclude_list();
    prt(")\n");
    prt(" Sources:\n");
	prt(" --aptdata=<file>    = Set apt.dat.gz file.\n");
    prt("  airports: [$aptdat] ".((-f $aptdat) ? "ok" : "NOT FOUND!")."\n");
    prt("  navaids:  [$navdat] ".((-f $navdat) ? "ok" : "NOT FOUND!")."\n");
    prt("  fixes:    [$g_fixfile] ".((-f $g_fixfile) ? "ok" : "NOT FOUND!")."\n");
    prt("  airways:  [$g_awyfile] ".((-f $g_awyfile) ? "ok" : "NOT FOUND!")."\n");
    prt(" Given an airport ICAO, find all others within $g_spread degrees, or\n");
    prt(" or/near the heading is one is given.\n");
}

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub set_apt_dat($) {
	my $file = shift;
	if (-f $file) {
		$aptdat = $file;
        prt("Set apt.dat.gz to $aptdat\n") if (VERB1());
		# my $APTFILE 	  = "$FGROOT/Airports/apt.dat.gz";	# the airports data file
		# my $NAVFILE 	  = "$FGROOT/Navaids/nav.dat.gz";	# the NAV, NDB, etc. data file
		# $navdat = $NAVFILE;
		# $g_fixfile = $FIXFILE;
		# $g_awyfile = $AWYFILE;
		my ($name,$dir) = fileparse($file);
		$dir =~ s/(\\|\/)$//;
		my ($n,$d) = fileparse($dir);
		my $nd = $d."Navaids".$PATH_SEP."nav.dat.gz";
		my $fd = $d."Navaids".$PATH_SEP."fix.dat.gz";
		my $ad = $d."Navaids".$PATH_SEP."awy.dat.gz";
		if (-f $nd) {
			$navdat = $nd;
	        prt("Set nav.dat.gz to $navdat\n") if (VERB1());
		}
		if (-f $fd) {
			$g_fixfile = $fd;
	        prt("Set fix.dat.gz to $g_fixfile\n") if (VERB1());
		}
		if (-f $ad) {
			$g_awyfile = $ad;
	        prt("Set awy.dat.gz to $g_awyfile\n") if (VERB1());
		}
	} else {
		pgm_exit(1,"Can NOT locate file $file!\n");
	}
}

sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg,@arr);
    while (@av) {
        $arg = $av[0];
        if ($arg =~ /^-/) {
            $sarg = substr($arg,1);
            $sarg = substr($sarg,1) while ($sarg =~ /^-/);
            if (($sarg =~ /^h/i)||($sarg eq '?')) {
                give_help();
                pgm_exit(0,"Help exit(0)");
            } elsif ($sarg =~ /^a/) {
				if ($sarg =~ /^aptdata/) {
					if ($sarg =~ /^aptdata=/) {
						@arr = split("=",$sarg);
						$sarg = $arr[1];
					} else {
		                need_arg(@av);
						shift @av;
						$sarg = $av[0];
					}
					set_apt_dat($sarg);
				} else {
	                $show_airways = 1;
		            prt("Set to load and display closest airways.\n") if (VERB1());
				}
            } elsif ($sarg =~ /^b/) {
                $show_bounds = 1;
                prt("Show max/min bounds.\n") if (VERB1());
            } elsif ($sarg =~ /^c/) {
                $name_as_is = 1;
                prt("Set to display airport name as is.\n") if (VERB1());
            } elsif ($sarg =~ /^f/) {
                $show_fixes = 1;
                prt("Set to load and display closest fixes.\n") if (VERB1());
            } elsif ($sarg =~ /^i/) {
                $only_with_ils = 1;
                prt("Set to load and display closest fixes.\n") if (VERB1());
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
            } elsif ($sarg =~ /^m/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if ($sarg =~ /^\d+$/) {
                    $g_max_out = $sarg;
                    prt("Set maximum output to $g_max_out\n") if (VERB1());
                } else {
                    pgm_exit(1,"ERROR: Argument $arg must be followed by integer only! Not $sarg\n");
                }
            } elsif ($sarg =~ /^n/) {
                $show_navaids = 1;
                prt("Show nearest navaids after airport list.\n") if (VERB1());
            } elsif ($sarg =~ /^t/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if (($sarg =~ /^\d+$/)&&($sarg >= 0)&&($sarg <= 360)) {
                    $g_track = $sarg;
                    prt("Set track to [$g_track] +/-$g_spread degs.\n") if (VERB1());
                } else {
                    pgm_exit(1,"ERROR: Argument $arg must be followed by integer 0-360 only! Not $sarg\n");
                }
            } elsif ($sarg =~ /^s/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if (($sarg =~ /^\d+$/)&&($sarg >= 0.0001)&&($sarg < 90)) {
                    $g_spread = $sarg;
                    prt("Set spread to +/-$g_spread, to track $g_track degs.\n") if (VERB1());
                } else {
                    pgm_exit(1,"ERROR: Argument $arg must be followed by integer >0 and <90 only! Not $sarg\n");
                }
            } elsif ($sarg =~ /^x/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                @arr = split(':',$sarg);
                foreach $sarg (@arr) {
                    if ($sarg eq 'hele') {
                        $g_xhele = 1;
                    } elsif ($sarg eq 'sea') {
                        $g_xsea = 1;
                    } elsif ($sarg eq 'closed') {
                        $g_xold = 1;
                    } elsif ($sarg eq 'all') {
                        $g_xhele = 1;
                        $g_xsea = 1;
                        $g_xold = 1;
                    } elsif ($sarg eq 'none') {
                        $g_xhele = 0;
                        $g_xsea = 0;
                        $g_xold = 0;
                    } else {
                        pgm_exit(1,"ERROR: Argument $arg must be followed by one of hele, sea, closed, all or none! NOT $sarg.\n");
                    }
                }
                if (VERB1()) {
                    prt("Set exclude to ");
                    out_xclude_list();
                    prt("\n");
                }
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            $in_icao = $arg;
            prt("Set input to [$in_icao]\n") if (VERB1());
        }
        shift @av;
    }
    if ($debug_on) {
        prtw("DEBUG is ON\n");
        if (length($in_icao) ==  0) {
            $in_icao = $del_icao;
            $verbosity = 9;
        }
    }
    if (length($in_icao) ==  0) {
		give_help();
        pgm_exit(1,"ERROR: No input ICAO found in command!\n");
    }
}

sub get_810_spec() {
    my $txt = <<EOF;
from : http://data.x-plane.com/file_specs/Apt810.htm
Code (apt.dat) Used for 
1  Airport header data. 
16 Seaplane base header data. No airport buildings or boundary fences will be rendered in X-Plane. 
17 Heliport header data.  No airport buildings or boundary fences will be rendered in X-Plane. 
10 Runway or taxiway at an airport. 
14 Tower view location. 
15 Ramp startup position(s) 
18 Airport light beacons (usually "rotating beacons" in the USA).  Different colours may be defined. 
19 Airport windsocks. 
50 to 56 Airport ATC (Air Traffic Control) frequencies. 
EOF
    return $txt;
}
# eof - findaps.pl
