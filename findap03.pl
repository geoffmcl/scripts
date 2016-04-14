#!/usr/bin/perl
# NAME: findap03.pl
# AIM: Read FlightGear apt.dat, and find an airport given the name,
# 12/04/2016 - Add to -Xopts, L/R only, H500, ...
# 10/04/2016 - Add xg output options - see $add_anno
# 16/07/2015 - Move into scripts repo
# 18/12/2014 - Switch to using the terrasync update directory, if AVAILABLE
# 17/11/2014 - Use -s to attempt generate SID/STAR patterns - TODO - how to show well???
# 17/10/2014 - Change from -s to -n to show navaids
# 09/10/2014 - Add reverse bearing to runways
# 02/07/2014 - Add -a to output xgraph anoo for airports/runways
# 29/05/2014 - Add -S to show ALL navaiad components - $ALLNAVS
# 21/05/2014 - Show apt.dat used
# 16/08/2013 - Add -out file to output ap text, and nav if -s, to a file.
# 10/04/2013 - Add -xml to output an ICAO.threshold.xml file
# 08/04/2013 - Point to the latest apt.dat.gz - 2.10
# 16/11/2011 - A little more information if -v9
# 16/09/2011 - Fix bug $$g_acnt to $g_acnt about line 650
# 02/05/2011 - Add the tile INDEX to the fg=<chunk>/<tile>/index
# 21/02/2011 - Add AMSL (Airport altitude) to airport output
# 20/02/2011 - If VERB1, add runway center, if VERB2, add runway ends
# 09/02/2011 - Add more information about runways.
# 25/01/2011 - If the raw input looks like a 4 letter ICAO, then search for that
# 29/12/2010 - Add altitude, and frequencies, to airport display ($aalt)
# 15/12/2010 - Fix in the display of the FG CHUNK - now show chunk/tile path, and rwy opp nums
# 26/11/2010 - No show of navs if search a/p, and none found
# 12/11/2010-11/11/2010 - Rel 03 - check out... reduce noise...
# 09/11/2010 - Some UI enhancements... Skip NAV version line, ... FIX20101109
# 17/08/2010 - Fix for windows command -latlon=5,10 becomes -latlon 5 10
# 13/02/2010 - Change to using C:\FGCVS\FLightGear\data files...
# 18/11/2009 - Added Bucket2.pm, to show bucket details - OOPS, would NOT work
# 18/12/2008 - Used tested include 'fg_wsg84.pl' for distance services
# 12/12/2008 - Switch to using DISTANCE, rather than DEGREES, for searching
# for close NAVAIDS ... Add a -range=nn Kilometers
# 19/11/2008 - Added $tryharder, when NO navaid found
# updated 20070526 fixes to run from command line
# Updated 20070405 to parse inputs, added help, 
# 20061127 - Use gz (gzip) files directly from $FG_ROOT
# geoff mclane - http://geoffmclane.com/mperl/index.htm - 20061127
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Time::HiRes qw( gettimeofday tv_interval );
use Math::Trig;
use Data::Dumper;
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
unshift(@INC, $perl_dir);
###require 'logfile.pl' or die "Error: Unable to locate logfile.pl ...\n";
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
require "Bucket2.pm" or die "Unable to load Bucket2.pm ...\n";
require 'lib_fgio.pl' or die "Unable to load 'lib_fgio.pl' Check paths in \@INC...\n";

my $DSCNROOT = 'D:\Scenery\terrascenery\data\Scenery';
my $DAPTROOT = 'D:\Scenery\terrascenery\data\Scenery\Airports';

# =============================================================================
# This NEEDS to be adjusted to YOUR particular default location of these files.
my $FGROOT = (exists $ENV{'FG_ROOT'})? $ENV{'FG_ROOT'} : $CDATROOT;
my $SCENEROOT = (exists $ENV{'FG_SCENERY'})? $ENV{'FG_SCENERY'} : $DSCNROOT;
my $TSSCENERY = 'X:\fgsvnts';

#my $FGROOT = (exists $ENV{'FG_ROOT'})? $ENV{'FG_ROOT'} : "C:/FG/27/data";
# file spec : http://data.x-plane.com/file_specs/Apt810.htm
my $APTFILE 	  = "$FGROOT/Airports/apt.dat.gz";	# the airports data file
my $NAVFILE 	  = "$FGROOT/Navaids/nav.dat.gz";	# the NAV, NDB, etc. data file
# add these files
my $FIXFILE 	  = "$FGROOT/Navaids/fix.dat.gz";	# the FIX data file
my $AWYFILE       = "$FGROOT/Navaids/awy.dat.gz";   # Airways data
# =============================================================================
my $VERS="Apr 10, 2016. version 1.0.8";
###my $VERS="Jul 16, 2015. version 1.0.7";
###my $VERS="Nov 17, 2014. version 1.0.6";
###my $VERS="Sep 3, 2014. version 1.0.5";
###my $VERS="Jan 10, 2014. version 1.0.4";
###my $VERS="Apr 10, 2013. version 1.0.3";
###my $VERS="Feb 10, 2011. version 1.0.2";

# log file stuff
my ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
$outfile = path_u2d($outfile) if ($os =~ /win/i);
open_log($outfile);
my $t0 = [gettimeofday];

# program variables - set during running
# different searches -icao=LFPO, -latlon=1,2, or -name="airport name"
# KSFO San Francisco Intl (37.6208607739872,-122.381074803838)
my $aptdat = $APTFILE;
my $navdat = $NAVFILE;
my $g_fixfile = $FIXFILE;
my $g_awyfile = $AWYFILE;

my $SRCHICAO = 0;	# search using icao id ... takes precedence
my $SRCHONLL = 0;	# search using lat,lon
my $SRCHNAME = 0;	# search using name
my $SHOWNAVS = 0;	# show navaids around airport found
my $ALLNAVS  = 0;   # show ALL ILS components

my $g_max_name_len = 24; # was 32; # was 24
my $aptname = "strasbourg";
my $apticao = 'KSFO';
my $g_center_lat = 0; # 37.6;
my $g_center_lon = 0; # -122.4;
my $g_circuit = '';
my %g_rwy_ends = ();

my $maxlatd = 0.5;
my $maxlond = 0.5;
my $nmaxlatd = 0.1;
my $nmaxlond = 0.1;
my $max_cnt = 0;	# maximum airport count - 0 = no limit
my $max_range_km = 5;   # range search using KILOMETERS
my $g_fix_name = "ASKIK";
my $out_xg1 = $temp_dir.$PATH_SEP."tempap1.xg";
my $out_xg = $temp_dir.$PATH_SEP."tempap.xg";
my $out_xg2 = $temp_dir.$PATH_SEP."tempap2.xg";

# features
my $tryharder = 0;  # Expand the search for NAVAID, until at least min. found
my $usekmrange = 0; # search using KILOMETER range - see $max_range_km
my $sortbyfreq = 0; # sort NAVAIDS by FREQUENCY
my $sort_by_distance = 1; # sort NAVAIDS by DISTANCE from CENTER
my $verbosity = 0; # just info neeeded...
my $vor_only = 0;
my $loadlog = 0;
my $check_sg_dist = 0; # do calc again, and show...
my $add_apt_off = 0;   # show offset to airport
my $ex_helipads = 1;    # exclude helipads if a lat/lon search
my $g_version = 0;
my $gen_sidstar = 0;    # TODO: This is HARD - maybe should be another app...
my $add_bbox = 0;
my $xgbbox = '';
my $new_x_opts = 1; # xg airport gen options, with anno, etc...

# radio frequency listing
my $use_full_list = 0; # seems better to GROUP frequencies
my $add_name_show = 0;  # does NOT seem helpful
my $use_short_names = 1; # Use APP instead of Approach

my $gen_threshold_xml = 0;
my $exclude_markers = 1;    # in NAVAID search EXCLUDE OM, MM and IM marker beacons
my $exclude_gs_ils  = 1;     # exclude the GS, since has the same frequency as associated ILS
my $min_nav_aids = 10;
my $out_file = '';
my $add_anno = 0;   # -Xa == -a - add xgraph anno output for airport
my $xg_output = '';
my $xgmsg = ''; # header for XG file otuput...
my $add_xg = 0;
my $add_circuit = 3;    # -XR == 1, -XL == 2
my $HOST = "localhost";
my $PORT = 5556;
my $TIMEOUT = 1;
my $DELAY = 5;

# variables for range using distance calculation
my $PI = 3.1415926535897932384626433832795029;
my $D2R = $PI / 180;
my $R2D = 180 / $PI;
my $ERAD = 6378138.12;
my $DIST_FACTOR = $ERAD;
my $SG_EPSILON = 0.0000001;
#/** Feet to Meters */
my $FEET_TO_METER = 0.3048;
my $METER_TO_FEET = 3.28084;
##my $SG_NM_TO_METER = 1852;
##my $SG_METER_TO_NM = 0.0005399568034557235;

# debug tests
# ===================
my $test_name = 0;	# to TEST a NAME search
my $def_name = "hong kong";

my $test_ll = 0;	# to TEST a LAT,LON search
my $def_lat = 37.228;    # 37.6;
my $def_lon = -121.9703; # -122.4;

my $test_icao = 0;	# to TEST an ICAO search
my $def_icao = 'VHHH'; ## 'KHAF';  ## LFPO'; ## 'KSFO';
my $dbg1 = 0;	# show airport during finding ...
my $dbg_fa02 = 0;	# show navaid during finding ...
my $dbg3 = 0;	# show count after finding
my $verb3 = 0;
my $dbg_fa04 = 0; # show NAV center search...

# ===================
my $total_apts = 0;
my ($icao_lat,$icao_lon);
my $apt_xg = '';

my $av_apt_lat = 0;	# later will be $tlat / $ac;
my $av_apt_lon = 0; # later $tlon / $ac;

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

my %off2name2 = (
    0 => 'ATIS',
    1 => 'UNICOM',
    2 => 'CLR',
    3 => 'GRD',
    4 => 'TWR',
    5 => 'APP',
    6 => 'DEP'
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

my @navset   =   ( $navNDB, $navVOR, $navILS, $navLOC, $navGS, $navOM, $navMM, $navIM, $navVDME, $navNDME );
my @navtypes = qw( NDB      VOR      ILS      LOC      GS       OM      MM     IM      VDME      NDME     );

# set lengths for common outputs
my $maxnnlen = 4;
my $g_maxnaltl = 5;
my $g_maxnfrql = 5;
my $g_maxnrngl = 5;
my $g_maxnfq2l = 10;
my $g_maxnnidl = 4;
my $g_maxnlatl = 12;
my $g_maxnlonl = 13;
my $g_nav_hdr = "Type  Latitude     Logitude        Alt.  Freq.  Range  Frequency2    ID  Name";

# global program variables
my $actnav = '';
my @g_naptlist = (); # ALL airports found, for research, if needed
#                 0      1      2      3      4      5   6  7  8  9      10     11    12     13   14        15
#push(@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@runways,$aalt]);
my @aptlist2 = ();
my @navlist = ();
my @navlist2 = ();
my @near_list = (); # seems when -t triharder is ON, the near LIST is NOT re-found???
my @g_navlist3 = ();
my %found_nav_hash = (); # $hid = "$typ:$nfrq:$nid";   # sort of a hash id for this item

my $totaptcnt = 0;
my $g_acnt = 0;
my $outcount = 0;
my @tilelist = ();
my $in_input_file = 0;

#program variables
my @warnings = ();
my %g_dupe_shown = ();
my $nav_file_version = 0;
my $got_center_latlon = 0; # 1 if latlon given in command, or ...
my $g_total_aps = 0; # push(@g_naptlist, [$diff, $icao, $name, $alat, $alon, ....]);

sub VERB1() { return $verbosity >= 1; }
sub VERB2() { return $verbosity >= 2; }
sub VERB5() { return $verbosity >= 5; }
sub VERB9() { return $verbosity >= 9; }

sub prtw {
    my ($tx) = shift;
    $tx =~ s/\n$//;
    prt("$tx\n");
    push(@warnings,$tx);
}

sub show_warnings {
	my ($dbg) = shift;
    if (@warnings) {
        prt( "\nGot ".scalar @warnings." WARNINGS ...\n" );
        foreach my $line (@warnings) {
            prt("$line\n" );
        }
        prt("\n");
    } elsif ($dbg) {
        prt("\nNo warnings issued.\n\n");
    }
}

sub pgm_exit($$) {
    my ($val,$msg) = @_;
    show_warnings(0);
    if (length($msg)) {
        $msg =~ s/\n$//;
        prt("$msg\n");
    }
    $loadlog = 1 if ($outcount > 30);
    close_log($outfile,$loadlog);
    ### unlink($outfile);
    exit($val);
}

sub get_bucket_info {
   my ($lon,$lat) = @_;
   my $b = Bucket2->new();
   $b->set_bucket($lon,$lat);
   return $b->bucket_info();
}

sub show_scenery_tiles() {
    my ($name);
    my $cnt = scalar @tilelist;
    if ($cnt) {
        if (VERB9()) {
            prt( "Scenery Tile" );
            if ($cnt > 1) {
                prt( "s" );
            }
            prt( ": " );
            foreach $name (@tilelist) {
                prt( "$name " );
            }
            prt( "\n" );
        } elsif (VERB5()) {
            prt( "Scenery Tile Count $cnt\n" );
        }
    }
}

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

sub load_fix_file { return load_gzip_file($g_fixfile); }
sub load_awy_file { return load_gzip_file($g_awyfile); }

########################################################################
### ONLY SUBS BELOW HERE
sub elim_the_dupes($) {
    my ($name) = @_;
    my @arr = split(/\s+/,$name);
    my %dupes = ();
    my @narr = ();
    my ($itm);
    foreach $itm (@arr) {
        if (!defined $dupes{$itm}) {
            $dupes{$itm} = 1;
            push(@narr,$itm);
        }
    }
    return join(" ",@narr);
}

sub ctr_latlon_stg() {
    return "$g_center_lat,$g_center_lon";
}

sub get_fg_dist_dir($$$$) {
    my ($lat1,$lon1,$lat2,$lon2) = @_;
    my ($sg_az1,$sg_az2,$sg_dist);
    my $res = fg_geo_inverse_wgs_84 ($lat1,$lon1,$lat2,$lon2,\$sg_az1,\$sg_az2,\$sg_dist);
    my $sg_km = $sg_dist / 1000;
    my $sg_im = int($sg_dist);
    my $sg_ikm = int($sg_km + 0.5);
    # if (abs($sg_pdist) < $CP_EPSILON)
    my $dist_hdg = ""; # or say "(SG: ";
    $sg_az1 = int(($sg_az1 * 10) + 0.05) / 10;
    if (abs($sg_km) > $SG_EPSILON) { # = 0.0000001; # EQUALS SG_EPSILON 20101121
        if ($sg_ikm && ($sg_km >= 1)) {
            $sg_km = int(($sg_km * 10) + 0.05) / 10;
            $dist_hdg .= "$sg_km km";
        } else {
            $dist_hdg .= "$sg_im m, <1km";
        }
    } else {
        $dist_hdg .= "0 m";
    }
    $dist_hdg .= " on $sg_az1 d.";
    #$dist_hdg .= ")";
    return $dist_hdg;
}

##                  0      1      2      3      4      5     6     7     8
#push(@g_naptlist, [$diff, $icao, $name, $alat, $alon, \@ra, \@wa, \@ha, \@fa ]);
sub write_runway_csv($) {
    my ($file) = @_;
    my $max = scalar @g_naptlist;
    my ($i,$raa);
    my ($res,$diff, $icao, $name, $alat, $alon, $ra, $rwa, $rha, $rfa,$ra1);
    my ($type, $rwid, $surf,$rwy1,$elat1,$elon1,$rwy2,$elat2,$elon2,$az1,$az2,$s);
    my ($clat,$clon);
    my $rcsv = "icao,lat1,lon1,lat2,lon2,width,sign\n";
    for ($i = 0; $i < $max; $i++) {
        $raa = $g_naptlist[$i];
        $icao = ${$raa}[1];
        $ra1  = ${$raa}[5];
        next if (!defined $ra1);    # no LAND runways
        ###prt(Dumper($raa));
        ###prt(Dumper($ra));
        ###pgm_exit(1,"TEMP EXIT\n");
        foreach $ra (@{$ra1}) {
            $type = ${$ra}[0];
            if (! defined $type) {
                prt("raa...\n");
                prt(Dumper($raa));
                prt("ra1...\n");
                prt(Dumper($ra1));
                prt("ra...\n");
                prt(Dumper($ra));
                $loadlog = 1;
                pgm_exit(1,"type NOT defined!\n");
            }
            if ($type == 100) {
                # See full version 1000 specs below
                # 0   1     2 3 4    5 6 7 8  9           10           11   12   13 14 15 16 17 18          19           20   21   22 23 24 25
                # 100 29.87 3 0 0.00 1 2 1 16 43.91080605 004.90321905 0.00 0.00 2  0  0  0  34 43.90662331 004.90428974 0.00 0.00 2  0  0  0
                $rwid  = ${$ra}[1];  # WIDTH in meters? NOT SHOWN
                $surf  = ${$ra}[2];  # add surface type
                $rwy1  = ${$ra}[8];
                $elat1 = ${$ra}[9];
                $elon1 = ${$ra}[10];
                $rwy2 = ${$ra}[17];
                $elat2 = ${$ra}[18];
                $elon2 = ${$ra}[19];
                $rcsv .= "$icao,$elat1,$elon1,$elat2,$elon2,$rwid,$rwy1\n";
                # $res = fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
                # $clat = ($elat1 + $elat2) / 2;
                # $clon = ($elon1 + $elon2) / 2;
            } elsif ($type == 10) {
                # 0   1          2          3   4       5    6         7           8   9      10 ...
                # 10  36.962213  127.031071 14x 131.52  8208 1595.0620 0000.0000   150 321321  1 0 3 0.25 0 0300.0300
                # 10  36.969145  127.020106 xxx 221.51   329 0.0 0.0    75 161161  1 0 0 0.25 0 
                $elat1 = ${$ra}[1];
                $elon1 = ${$ra}[2];
                $rwy1  = ${$ra}[3]; # text 'xxx'=taxiway, 'H1x'=heleport, else a runway
                ###prt( "$line [$rlat, $rlon]\n" );
                if ( $rwy1 ne "xxx" ) {
                    $rwy1 =~ s/x*$//;    # remove trailing 'x'
                    $az1 = ${$ra}[4];
                    $s   = ${$ra}[5] * $FEET_TO_METER;
                    $res = fg_geo_direct_wgs_84($elat1,$elon1, $az1, $s, \$elat2, \$elon2, \$az2 );
                    $rwid = 50;
                    $rcsv .= "$icao,$elat1,$elon1,$elat2,$elon2,$rwid,$rwy1\n";
                }
            }
        }
    }
    write2file($rcsv,$file);
    prt("Written runway csv to file $file\n");
}

##                 0      1      2      3      4      5      6
#push(@g_aptlist, [$diff, $icao, $name, $alat, $alon, $aalt, \@f]);
##                  0      1      2      3      4      5     6     7     8
#push(@g_naptlist, [$diff, $icao, $name, $alat, $alon, \@ra, \@wa, \@ha, \@fa ]);
sub get_g_aptlist_off($) {
    my ($icao) = @_;
    my $max = scalar @g_naptlist;
    my ($i,$t);
    for ($i = 0; $i < $max; $i++) {
        $t = $g_naptlist[$i][1];
        if ($icao eq $t) {
            return ($i + 1);
        }
    }
    return 0;
}

sub get_atis_info($$$$$$$) {
    my ($ii,$scnt,$raptlist2,$gaoff,$alat,$alon,$aalt) = @_;
    my $info = '';
    my $rfa = $g_naptlist[$gaoff-1][8]; # get the ATIS, Tower, ..., frequecies array (ref)
    ###my $rfa = $g_aptlist[$gaoff-1][6]; # get the ATIS, Tower, ..., frequecies array (ref)
    my $rfc = scalar @{$rfa};   # get count for this airport
    my $rj = 0;
    my ($rfna,$line,$block,$len,$tmp,$rtlen);
    my %names = ();
    my $max_line = 100;
    $info = '';
    $info .= "\n"; # if (VERB1());
    if ($rfc) {
        $tmp = "rt:".$rfc." [";
        $rtlen = length($tmp);
        $info .= $tmp;
        for ($rj = 0; $rj < $rfc; $rj++) {
            my $ev = ${$rfa}[$rj][0]; # number in file 50, 51, ...., 56
            my $fr = (${$rfa}[$rj][1] / 100); # frequency x 100
            my $fn = ${$rfa}[$rj][2];   # type AWIS, CTAF, ...
            # prepare information
            my $evnm = 'UNK'.$ev.'?';
            my $ftyp = $ev - 50;
            if (($ftyp >= 0)&&($ftyp <= 6)) {
                if ($use_short_names) {
                    $evnm = $off2name2{$ftyp};
                } else {
                    $evnm = $off2name{$ftyp};
                }
            }
            #$info .= " $ev $fr $fn";
            #$info .= " $evnm $fn $fr";
            if ($use_full_list) {
                $info .= " $evnm $fr ($fn)";
            } else {
                $names{$evnm} = [] if (!defined $names{$evnm});
                $rfna = $names{$evnm};
                if ($add_name_show) {
                    push(@{$rfna}, "$fr ($fn)");
                } else {
                    push(@{$rfna},$fr);
                }
            }
        }
        if (!$use_full_list) {
            my ($key,$val,$wrap);
            if ($add_name_show) {
                $wrap = 0;
                foreach $key (sort keys %names) {
                    $rfna = $names{$key};
                    $info .= " $key:";
                    foreach $val (@{$rfna}) {
                        $info .= " $val";
                    }
                    $wrap++;
                    if ($wrap == 3) {
                        $wrap = 0;
                        $info .= "\n";
                    }
                }
            } else {
                $line = $info;  # start the line
                $info = '';
                foreach $key (sort keys %names) {
                    $rfna = $names{$key};
                    $block = '';
                    foreach $val (@{$rfna}) {
                        $block .= ' ' if (length($block));
                        $block .= $val;
                    }
                    $block = "$key: $block";
                    $len = length($line) + length($block); 
                    #prt("got len $len\n");
                    if ($len > $max_line) {
                        $info .= "$line\n" if (length($line));
                        $line = ' ' x $rtlen;
                        #prt("wrapped line\n");
                    }
                    $line .= "$block ";
                }
                $info .= $line if (length($line));
                $info =~ s/\s+$//;
            }
        }
        $info .= ']';
    } else {
        $info .= " [No freq. info]";
    }
    return $info;
}

sub get_current_threshold($$) {
    my ($icao,$rt) = @_;
    return 0 if (length($icao) < 3);
    my $scene = $TSSCENERY;
    $scene = $SCENEROOT if (! -d $scene);
    return 0 if (! -d $scene);
    my $dir = $scene.$PATH_SEP."Airports";
    return 0 if (! -d $dir);
    $dir .= $PATH_SEP.substr($icao,0,1);
    $dir .= $PATH_SEP.substr($icao,1,1);
    $dir .= $PATH_SEP.substr($icao,2,1);
    $dir .= $PATH_SEP.$icao.".threshold.xml";
    return 0 if (! -f $dir);
    ${$rt} = $dir;
    return 1;
}

# 18/12/2014 - First try terrasync updated directory
# If that is not found fall back to SCENEROOT
sub check_ground_net($$) {
    my ($icao,$rt) = @_;
    return 0 if (length($icao) < 3);
    my $scene = $TSSCENERY;
    $scene = $SCENEROOT if (! -d $scene);
    if (! -d $scene) {
        prt("check_ground_net: Directory $scene NOT found!\n") if (VERB9());
        return 0;
    }
    my $dir = $scene.$PATH_SEP."Airports";
    if (! -d $dir) {
        prt("check_ground_net: Directory $dir NOT found!\n") if (VERB9());
        return 0;
    }
    $dir .= $PATH_SEP.substr($icao,0,1);
    $dir .= $PATH_SEP.substr($icao,1,1);
    $dir .= $PATH_SEP.substr($icao,2,1);
    $dir .= $PATH_SEP.$icao.".groundnet.xml";
    if (! -f $dir) {
        if ($scene eq $TSSCENERY) {
            $scene = $SCENEROOT;
            $dir = $scene.$PATH_SEP."Airports";
            if (! -d $dir) {
                prt("check_ground_net: Directory $dir NOT found!\n") if (VERB9());
                return 0;
            }
            $dir .= $PATH_SEP.substr($icao,0,1);
            $dir .= $PATH_SEP.substr($icao,1,1);
            $dir .= $PATH_SEP.substr($icao,2,1);
            $dir .= $PATH_SEP.$icao.".groundnet.xml";
            if ( -f $dir) {
                ${$rt} = $dir;
                return 1;
            }
        }
        prt("check_ground_net: File $dir NOT found!\n") if (VERB9());
        return 0;
    }
    ${$rt} = $dir;
    return 1;
}

sub get_ll_stg($$) {
    my ($lat,$lon) = @_;
    my $stg = sprintf("%.8f,%.8f",$lat,$lon);
    $stg .= ' ' while (length($stg) < 23);
    return $stg;
}

#####################################################################
### control the size of the circuit
my $stand_glide_degs = 3; # degrees
my $stand_patt_alt = 1000; # feet - default student altitude - -XH500 - to change
my $stand_cross_nm = 2.1; # nm, but this will depend on the aircraft
my $ac_speed_kts = 80;  # Knots
#####################################################################
### constants
my $SGD_PI = 3.1415926535;
my $SGD_DEGREES_TO_RADIANS = $SGD_PI / 180.0;
my $SGD_RADIANS_TO_DEGREES = 180.0 / $SGD_PI;
# /** Feet to Meters */
my $SG_FEET_TO_METER = 0.3048;
# /** Meters to Feet */
my $SG_METER_TO_FEET = 3.28083989501312335958;
my $SG_NM_TO_METER = 1852;
my $SG_METER_TO_NM = 0.0005399568034557235;
my $use_full_msg = 0;

sub get_mid_point($$$$$$) {
    my ($elat1,$elon1,$elat2,$elon2,$rclat,$rclon) = @_;
    my ($az1,$az2,$s,$az5,$clat,$clon);
    my $res = fg_geo_inverse_wgs_84($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
    $res = fg_geo_direct_wgs_84($elat1,$elon1, $az1, ($s / 2), \$clat, \$clon, \$az5);
    ${$rclat} = $clat;
    ${$rclon} = $clon;
}

my $x_min_lat = 400;
my $x_min_lon = 400;
my $x_max_lat = -400;
my $x_max_lon = -400;

sub add_to_bbox($$) {
    my ($lon,$lat) = @_;
    $x_min_lat = $lat if ($lat < $x_min_lat);
    $x_min_lon = $lon if ($lon < $x_min_lon);
    $x_max_lat = $lat if ($lat > $x_max_lat);
    $x_max_lon = $lon if ($lon > $x_max_lon);
}

sub get_x_bbox() {
    my $xg = "# bbox $x_min_lon $x_min_lat $x_max_lon $x_max_lat\n";
    if (($x_min_lat == 400) ||
        ($x_min_lon == 400) ||
        ($x_max_lat == -400) ||
        ($x_max_lon == -400))
    {
        $xg = "# no bbox\n";
    } else {
        $xg .= "color blue\n";
        $xg .= "$x_min_lon $x_min_lat\n";
        $xg .= "$x_min_lon $x_max_lat\n";
        $xg .= "$x_max_lon $x_max_lat\n";
        $xg .= "$x_max_lon $x_min_lat\n";
        $xg .= "$x_min_lon $x_min_lat\n";
        $xg .= "NEXT\n";
    }
    return $xg;
}


##############################################################
### get RUNWAY xg string
##############################################################
sub rwy_xg_stg($$$$$$$$) {
    my ($icao,$elat1,$elon1,$elat2,$elon2,$widm,$rwy1,$rwy2) = @_;
    my $hwidm = $widm / 2;
    my ($az1,$az2,$s,$az3,$az4,$az5);
    my ($lon1,$lon2,$lon3,$lon4,$lat1,$lat2,$lat3,$lat4);
    my ($clat,$clon,$msg);
    my $xg = '';
    #################################################
    my $res = fg_geo_inverse_wgs_84($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
    $res = fg_geo_direct_wgs_84($elat1,$elon1, $az1, ($s / 2), \$clat, \$clon, \$az5);
    #################################################
    my $distft = int($s * $SG_METER_TO_FEET);

    ###############################################################################
    $xg .= "# begin runway description\n";
    $xg .= "anno $elon1 $elat1 rwyid: $rwy1\n";
    $xg .= "anno $elon2 $elat2 rwyid: $rwy2\n";

    # center line of runway
    $xg .= "color blue\n";
    # $xg .= "anno $clon $clat rwy:\"$rwy1/$rwy2\", len:\"$distft\", u=\"ft\"\n";
    $xg .= "anno $clon $clat rwy:$rwy1/$rwy2, len:$distft ft\n";
    $xg .= "$elon1 $elat1\n";
    $xg .= "$elon2 $elat2\n";
    $xg .= "NEXT\n";

    #################################################
    # outline of runway, with width
    $xg .= "color red\n";
    my $rwlen2 = $s;
    $az3 = $az1 + 90;
    $az3 -= 360 if ($az3 >= 360);
    $az4 = $az1 - 90;
    $az4 += 360 if ($az4 < 0);
    $res = fg_geo_direct_wgs_84($elat1,$elon1, $az3, $hwidm, \$lat1, \$lon1, \$az5);
    $xg .= "$lon1 $lat1\n";
    $res = fg_geo_direct_wgs_84($elat1,$elon1, $az4, $hwidm, \$lat2, \$lon2, \$az5);
    $xg .= "$lon2 $lat2\n";
    $res = fg_geo_direct_wgs_84($elat2,$elon2, $az4, $hwidm, \$lat3, \$lon3, \$az5);
    $xg .= "$lon3 $lat3\n";
    $res = fg_geo_direct_wgs_84($elat2,$elon2, $az3, $hwidm, \$lat4, \$lon4, \$az5);
    $xg .= "$lon4 $lat4\n";
    $xg .= "$lon1 $lat1\n";
    $xg .= "NEXT\n";

    ######################################################################################
    # CIRCUIT GENERATION
    # We have the RUNWAY ends - now extend out to first turn to crosswind leg, and turn to final
    # but by how MUCH - ok decide from runway end, out to where it is a 3 degree glide from 1000 feet
    my $dist = ($stand_patt_alt * $SG_FEET_TO_METER) / tan($stand_glide_degs * $SGD_DEGREES_TO_RADIANS);

    ######################################################################################
    my ($plat11,$plon11,$plat12,$plon12,$plat13,$plon13,$paz1);
    my ($plat21,$plon21,$plat22,$plon22,$plat23,$plon23,$paz2);
    my ($hdg1L,$hdg1R,$crossd,$tmp);
    # get the outer end of the circuit
    fg_geo_direct_wgs_84( $clat, $clon, $az1, $rwlen2+$dist, \$plat11, \$plon11, \$paz1 );
    fg_geo_direct_wgs_84( $clat, $clon, $az2, $rwlen2+$dist, \$plat21, \$plon21, \$paz2 );
    $hdg1L = $az1 - 90;
    $hdg1L += 360 if ($hdg1L < 0);
    $hdg1R = $az1 + 90;
    $hdg1R -= 360 if ($hdg1R > 360);
    $crossd = $stand_cross_nm * $SG_NM_TO_METER;
    $crossd = $dist if ($dist < $crossd);

    $msg = "# ";
    $msg .= "Gen $icao CIRCUIT AI $stand_glide_degs gs";
    $tmp = int($stand_patt_alt + 0.5);
    $msg .= ", alt $tmp ft.";
    $tmp = int(($stand_patt_alt * $SG_FEET_TO_METER) + 0.5);
    $msg .= "($tmp".'m)';
    $tmp = int($dist + 0.5) / 1000;
    $msg .= ", Km dist $tmp";
    my $mps = ($ac_speed_kts * $SG_NM_TO_METER) / 3600; # get meter per second
    my $sec = $dist / $mps;
    $tmp = int($sec + 0.5);
    $msg .= ", $tmp secs";
    $tmp = int($mps + 0.5);
    $msg .= " at $tmp mps";
    $msg .= ", ".int($ac_speed_kts)." kts ias";
    $tmp = int(($stand_patt_alt / $sec) * 60);
    $msg .= ", -$tmp fpm";
    #$tmp = int($rwlen2 + 0.5) / 1000;
    #$msg .= ", rlen $tmp";
    #$tmp = int(($rwlen2+$dist) * 2) / 1000;
    #$msg .= ", circuit $tmp x ";
    #$tmp = int($crossd + 0.5) / 1000;
    #$msg .= "$tmp";
    #############################################
    ### set xg message - comment added to xg output - show options used
    $xgmsg = $msg if (length($xgmsg) == 0);
    #############################################

    if (VERB2()) {
        prt("$msg\n");
    }
    # ON $rhdg to $elat1, $elon1 to ... turn point, go LEFT and to get NEXT points, this end
    fg_geo_direct_wgs_84( $plat11, $plon11, $hdg1L, $crossd, \$plat12, \$plon12, \$paz1 );
    fg_geo_direct_wgs_84( $plat21, $plon21, $hdg1L, $crossd, \$plat13, \$plon13, \$paz1 );

    # from the turn point, go LEFT and RIGHT to get NEXT points, this other end
    fg_geo_direct_wgs_84( $plat21, $plon21, $hdg1R, $crossd, \$plat22, \$plon22, \$paz2 );
    fg_geo_direct_wgs_84( $plat11, $plon11, $hdg1R, $crossd, \$plat23, \$plon23, \$paz2 );

    my ($l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon);
    my ($r_tl_lat,$r_tl_lon,$r_bl_lat,$r_bl_lon,$r_br_lat,$r_br_lon,$r_tr_lat,$r_tr_lon);
    my ($m_lat,$m_lon);

    #################################################
    # RIGHT CIRCUIT
    # At YGIL, this is a 15 circuit (the prevailing wind! SSE...
    # At LEIG, runway 17 circuit
    $r_tl_lat = $plat12;
    $r_tl_lon = $plon12;
    $r_bl_lat = $plat13;
    $r_bl_lon = $plon13;
    $r_br_lat = $plat21;
    $r_br_lon = $plon21;
    $r_tr_lat = $plat11;
    $r_tr_lon = $plon11;
    # RIGHT CIRCUIT
    ###############
    if ($add_circuit & 1) {
        $xg .= "# RIGHT circuit - green\n";
        $xg .= "color green\n";
        if ($add_anno) {
            $xg .= "anno $r_tr_lon $r_tr_lat ____ R-TR\n";
        }
        $xg .= "$r_tr_lon $r_tr_lat\n";

        add_to_bbox($r_tr_lon,$r_tr_lat);

        get_mid_point($r_tr_lat,$r_tr_lon,$r_tl_lat,$r_tl_lon,\$m_lat,\$m_lon); # TR->TL - cross

        if ($add_anno) {
            if ($use_full_msg) {
                $xg .= "anno $m_lon $m_lat cross TR->TL\n";
            } else {
                $xg .= "anno $m_lon $m_lat cross\n";
            }

            $xg .= "anno $r_tl_lon $r_tl_lat R-TL\n";
        }

        $xg .= "$r_tl_lon $r_tl_lat\n";

        add_to_bbox($r_tl_lon,$r_tl_lat);

        get_mid_point($r_tl_lat,$r_tl_lon,$r_bl_lat,$r_bl_lon,\$m_lat,\$m_lon); # TL->BL - downwind

        if ($add_anno) {
            if ($use_full_msg) {
                $xg .= "anno $m_lon $m_lat downwind TL->BL\n";
            } else {
                $xg .= "anno $m_lon $m_lat downwind\n";
            }

            $xg .= "anno $r_bl_lon $r_bl_lat R-BL\n";
        }

        $xg .= "$r_bl_lon $r_bl_lat\n";

        add_to_bbox($r_bl_lon,$r_bl_lat);

        get_mid_point($r_bl_lat,$r_bl_lon,$r_br_lat,$r_br_lon,\$m_lat,\$m_lon); # BL->BR - base

        if ($add_anno) {
            if ($use_full_msg) {
                $xg .= "anno $m_lon $m_lat base BL->BR\n";
            } else {
                $xg .= "anno $m_lon $m_lat base\n";
            } 

            $xg .= "anno $r_br_lon $r_br_lat ____ R-BR\n";
        }

        $xg .= "$r_br_lon $r_br_lat\n";

        add_to_bbox($r_br_lon,$r_br_lat);

        # on final
        # get_mid_point($r_br_lat,$r_br_lon,$r_tr_lat,$r_tr_lon,\$m_lat,\$m_lon); # BR->TR - runway
        get_mid_point($r_br_lat,$r_br_lon,$elat2,$elon2,\$m_lat,\$m_lon); # BR->RWY - final

        if ($add_anno) {
            $xg .= "anno $m_lon $m_lat final $rwy1\n";
        }

        $xg .= "$r_tr_lon $r_tr_lat\n";
        $xg .= "NEXT\n";

    }

    #################################################
    # At YGIL, this is a 33 circuit
    $l_tl_lat = $plat22; #-31.684063;
    $l_tl_lon = $plon22; #148.614120;
    $l_bl_lat = $plat23; #-31.723495;
    $l_bl_lon = $plon23; #148.633003;
    $l_br_lat = $plat11; #-31.716778;
    $l_br_lon = $plon11; #148.666992;
    $l_tr_lat = $plat21; #-31.672960;
    $l_tr_lon = $plon21; #148.649139;
    ###########################################################
    # LEFT circuit
    ########################
    if ($add_circuit & 2) {
        $xg .= "# LEFT circuit - white\n";
        $xg .= "color white\n";

        if ($add_anno) {
            $xg .= "anno $l_tr_lon $l_tr_lat L-TR\n";
        }

        get_mid_point($l_tr_lat,$l_tr_lon,$l_tl_lat,$l_tl_lon,\$m_lat,\$m_lon); # TR->TL - cross

        if ($add_anno) {
            if ($use_full_msg) {
                $xg .= "anno $m_lon $m_lat cross TR->TL\n";
            } else {
                $xg .= "anno $m_lon $m_lat cross\n";
            }
            $xg .= "anno $l_tl_lon $l_tl_lat L-TL\n";
        }

        $xg .= "$l_tr_lon $l_tr_lat\n";
        $xg .= "$l_tl_lon $l_tl_lat\n";
        add_to_bbox($l_tr_lon,$l_tr_lat);   # L-TR
        add_to_bbox($l_tl_lon,$l_tl_lat);   # L-TL

        get_mid_point($l_tl_lat,$l_tl_lon,$l_bl_lat,$l_bl_lon,\$m_lat,\$m_lon); # TL->BL - downwind

        if ($add_anno) {
            if ($use_full_msg) {
                $xg .= "anno $m_lon $m_lat downwind TL->BL\n";
            } else {
                $xg .= "anno $m_lon $m_lat downwind\n";
            } 

            $xg .= "anno $l_bl_lon $l_bl_lat L-BL\n";
        }

        $xg .= "$l_bl_lon $l_bl_lat\n";
        add_to_bbox($l_bl_lon,$l_bl_lat);   # L-BL

        get_mid_point($l_bl_lat,$l_bl_lon,$l_br_lat,$l_br_lon,\$m_lat,\$m_lon); # BL->BR - base

        if ($add_anno) {
            if ($use_full_msg) {
                $xg .= "anno $m_lon $m_lat base BL->BR\n";
            } else {
                $xg .= "anno $m_lon $m_lat base\n";
            } 

            $xg .= "anno $l_br_lon $l_br_lat L-BR\n";
        }

        $xg .= "$l_br_lon $l_br_lat\n";
        add_to_bbox($l_br_lon,$l_br_lat);   # L-BR

        # on final
        # get_mid_point($l_br_lat,$l_br_lon,$l_tr_lat,$l_tr_lon,\$m_lat,\$m_lon); # BR->TR - runway
        get_mid_point($l_br_lat,$l_br_lon,$elat1,$elon1,\$m_lat,\$m_lon); # BR->RWY - final

        if ($add_anno) {
            $xg .= "anno $m_lon $m_lat final $rwy2\n";
        }

        $xg .= "$l_tr_lon $l_tr_lat\n";
        $xg .= "NEXT\n";
    }

    $xg .= "# end runway description\n";
    ###############################################################################
    $g_circuit = $rwy2;
    $g_rwy_ends{$rwy2} = 1;
    $g_rwy_ends{$rwy1} = 1;
    ###############################################################################
    #### prt($xg);
    return $xg;
}

sub show_ground_net($) {
    my $gnf = shift;
    return if (!VERB1());
    if (!open GNF,"<$gnf") {
        prtw("WARNING: Unable to open ground net file $gnf\n");
        return;
    }
    my @lines = <GNF>;
    close GNF;
    my $lncnt = scalar @lines;


}

sub get_bbox_xg($$$$) {
    my ($min_lat,$min_lon,$max_lat,$max_lon) = @_;
    my $xg = '';
    $xg .= "$min_lon $min_lat\n";
    $xg .= "$min_lon $max_lat\n";
    $xg .= "$max_lon $max_lat\n";
    $xg .= "$max_lon $min_lat\n";
    $xg .= "$min_lon $min_lat\n";
    return $xg;
}

#                  0=typ, 1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid, 8=name, 9=off, 10=dist, 11=az);
#push(@g_navlist3, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid,  $name,  $off,  $dist,   $az]);
sub show_airports_found {
	my ($mx) = shift;	# limit the AIRPORT OUTPUT
	my $scnt = $g_acnt;
	my $tile = '';
    my ($dist,$az,$adkm,$ahdg,$alat,$alon,$line,$diff,$icao,$name,$msg,$out);
    my ($rrwys,$aalt);
    my $c_lat = $g_center_lat;
    my $c_lon = $g_center_lon;
    my ($dlat,$dlon);
    $msg = '[v1] Listing ';
	if ($mx && ($mx < $scnt)) {
		$scnt = $mx;
		$msg .= "$scnt of $g_acnt aiports ";
	} else {
		$msg .= "$scnt aiport(s) ";
	}

	if ($SRCHICAO) {
		$msg .= "with ICAO [$apticao] ...";
	} elsif ($SRCHONLL) {
		$msg .= "around lat,lon [".ctr_latlon_stg()."], using diff [$maxlatd,$maxlond] ...";
	} else {
		$msg .= "matching [$aptname] ...";
	}
    prt("$msg\n") if (VERB1());
    # =========================================================================================================
    # search the airport list
    #                 0      1      2      3      4      5   6  7  8  9      10     11    12     13   14        15
    #push(@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@runways,$aalt]);
    @aptlist2 = sort mycmp_decend_ap_dist @aptlist2 if ($got_center_latlon);
    my ($i,$ra,$rtyp,$info,$rwycnt,$hdg,$rhdg,$gaoff,$tmp,$surf);
    my ($rlen,$displ1,$displ2,$stopw1,$stopw2,$rwid,$rlit,$xml,$oicao,$type);
    my ($rwy1,$rwy2);
    my ($rwlen2,$elat1,$elon1,$eaz1,$elat2,$elon2,$eaz2,$hdgr,$hdg1,$hdg2,$az1,$az2);
    my ($lato1,$lono1,$lato2,$lono2,$s);
    my ($min_lon,$min_lat,$max_lon,$max_lat);
    my ($min_lons,$min_lats,$max_lons,$max_lats);
    # OUTPUT OF AN AIRPORT ENTRY
    $out = '';
    my $skip_helis = 0;
    my $annoxg = '';    # add xg anno for airport
    $min_lons = 400;
    $min_lats = 400;
    $max_lons = -400;
    $max_lats = -400;

	for ($i = 0; $i < $scnt; $i++) {
        $xml = "<?xml version=\"1.0\"?>\n<PropertyList>\n";
		$diff = $aptlist2[$i][0];
		$icao = $aptlist2[$i][1];
		$name = $aptlist2[$i][2];
        $name = elim_the_dupes($name);

        # locations
		$dlat = $aptlist2[$i][3];   # LAT
		$dlon = $aptlist2[$i][4];   # LON
        $aalt = $aptlist2[$i][15];  # ALT (AMSL)
        $rrwys = $aptlist2[$i][14]; # extract RUNWAY reference
        $rwycnt = scalar @{$rrwys};
        # anno 148.636305809373 -31.6965632128734 YGIL Airport circuit 33
        if ($add_anno) {
            $annoxg .= "anno $dlon $dlat $icao $name circuit $g_circuit\n";
        }
        $alat = $dlat;
        $alon = $dlon;
        $oicao = $icao;

        # from center point, if there is one
        $dist = $aptlist2[$i][12];
        $az   = $aptlist2[$i][13];

        # get airport reference from main @g_naptlist
        $gaoff = get_g_aptlist_off($icao);

        if ($SRCHONLL) {
            #if (int($az) == 400) {}
            if ($ex_helipads) {
                if ($name =~ /\[H\]/) {
                    $skip_helis++;
                    next;
                }
            }
        }

        ################################
        ### Set min, max...
        $min_lon = 400;
        $min_lat = 400;
        $max_lon = -400;
        $max_lat = -400;
        # @runways reference
        # 0   1=lat      2=lon      3=s 4=hdg  5=len 6=offsets 7=stopway 8=wid 9=lights 10=surf 11 12 13   14 15
        # 10  36.962213  127.031071 14x 131.52  8208 1595.0620 0000.0000 150   321321   1       0  3  0.25 0  0300.0300
        # 11=shoulder 12=marks 13=smooth 14=signs 15=GS angles
        # 0           3        0.25      0        0300.0300
        # ====================================================
        # Version 1000 - runways in x-plane style
        # Land runways
        # General details             One end                                              Second end
        # 0   1     2 3 4    5 6 7  | 8  9           10           11   12   13 14 15 16  | 17 18          19           20   21   22 23 24 25
        # 100 29.87 3 0 0.00 1 2 1  | 16 43.91080605 004.90321905 0.00 0.00 2  0  0  0   | 34 43.90662331 004.90428974 0.00 0.00 2  0  0  0
        # Water runways
        # 0   1      2 3  4           5             6  7           8
        # 101 243.84 0 16 29.27763293 -089.35826258 34 29.26458929 -089.35340410
        # 101 22.86  0 07 29.12988952 -089.39561501 25 29.13389936 -089.38060001
        # TODO - This only does LAND runways - what about helipads and water runways
        # ==========================================================================
        #$rrwys = $aptlist2[$i][14]; # extract RUNWAY reference
        #$rwycnt = scalar @{$rrwys};
        $info = "rwy:$rwycnt: ";
        foreach $ra (@{$rrwys}) {
            $tmp = scalar @{$ra};
            $type = ${$ra}[0];  # get first 'type' entry
            ###prt(join(" ",@{$ra})." t=$type c=$tmp\n");
            ###next;
            if ($type == 10) {
                if ($tmp < 15) {
                    foreach $hdg (@{$ra}) {
                        $info .= "[$hdg] ";
                    }
                    pgm_exit(1,"ERROR: Invalid runway array cnt $tmp! $info\n");
                }
                $rtyp = ${$ra}[3];
                $hdg  = ${$ra}[4];
                $rlen = ${$ra}[5];  # length, in feet
                # For example, for displaced threshold lengths of 543 feet and 1234 feet, 
                # the code would be 543.1234.
                $tmp    = ${$ra}[6];  # get displacements - feet - threshold
                $displ1 = int($tmp);
                $displ2 = ($tmp - $displ1) * 10000;
                $tmp    = ${$ra}[7];  # get stopway - feet
                $stopw1 = int($tmp);
                $stopw2 = ($tmp - $stopw1) * 10000;
                $rwid   = ${$ra}[8];  # WIDTH in feet
                $rlit   = ${$ra}[9];  # LIGHTS
                $surf   = ${$ra}[10]; # add surface type

                $rtyp =~ s/x+$//;   # REMOVE any TRAILIN 'x', but may have 'L', 'R', 'C', 'S' appended
                if ($rtyp =~ /^\d+$/) {
                    $rhdg = $rtyp * 10; # 2010-12-15 - get opposite end numbers
                } else {
                    $rhdg = $hdg; # get opp heading, but may NOT be per numbers
                }
                $rhdg += 180; # reverse it
                $rhdg -= 360 if ($rhdg >= 360); # drop wrap
                $rwy1 = $rtyp;
                $rwy2 = int($rhdg / 10);
                $rhdg = int($rhdg / 10);
                $rhdg = "0$rhdg" if ($rhdg < 10);
                # display it
                #######################################################
                $info .= "\n"; #  if (VERB1()); # new line
                $info .= " $rtyp/$rhdg ($hdg) ";
                $info .= $rlen." ft.";  # length in FEET
                if (defined $runway_surface{$surf}) {
                    $info .= " (s=".$runway_surface{$surf}.")";
                }
                $rwlen2 = (${$ra}[5] * $FEET_TO_METER) / 2;
                $hdgr = $hdg + 180;
                $hdgr -= 360 if ($hdgr >= 360);
                fg_geo_direct_wgs_84( ${$ra}[1], ${$ra}[2], $hdg , $rwlen2, \$elat1, \$elon1, \$eaz1 );
                fg_geo_direct_wgs_84( ${$ra}[1], ${$ra}[2], $hdgr, $rwlen2, \$elat2, \$elon2, \$eaz2 );
                $hdg1 = $hdg;
                $hdg2 = $hdgr;
                $az1 = $hdg1;
                $az2 = $hdg2;
                if (VERB1()) {
                    $info .= " ".${$ra}[1].",".${$ra}[2];
                    if (VERB2()) {
                        # show ENDS of runway
                        $info .= "\n $rtyp: $elat1,$elon1 $rhdg: $elat2,$elon2";
                        $info .= " th=$displ1/$displ2 sp=$stopw1/$stopw2";
                    }
                }
                # =======================================================
                $apt_xg .= rwy_xg_stg($icao,$elat1,$elon1,$elat2,$elon2,feet_2_meter($rwid),$rtyp,$rhdg);
                # =======================================================
                # add runway ends to BOUNDS (bbox)
                $min_lon = $elon1 if ($elon1 < $min_lon);
                $min_lat = $elat1 if ($elat1 < $min_lat);
                $max_lat = $elat1 if ($elat1 > $max_lat);
                $max_lon = $elon1 if ($elon1 > $max_lon);

                $min_lon = $elon2 if ($elon2 < $min_lon);
                $min_lat = $elat2 if ($elat2 < $min_lat);
                $max_lat = $elat2 if ($elat2 > $max_lat);
                $max_lon = $elon2 if ($elon2 > $max_lon);

                # sum of multiple passes
                $min_lats = $elat1 if ($elat1 < $min_lats);
                $max_lats = $elat1 if ($elat1 > $max_lats);
                $min_lons = $elon1 if ($elon1 < $min_lons);
                $max_lons = $elon1 if ($elon1 > $max_lons);
                $min_lats = $elat2 if ($elat2 < $min_lats);
                $max_lats = $elat2 if ($elat2 > $max_lats);
                $min_lons = $elon2 if ($elon2 < $min_lons);
                $max_lons = $elon2 if ($elon2 > $max_lons);

                ### do the work, even if not used - if ($gen_threshold_xml) {
                    $lato1 = $elat1;
                    $lono1 = $elon2;
                    $lato2 = $elat2;
                    $lono2 = $elon2;
                    if (($displ1 + $stopw1) > 0) {
                        $s = ($displ1 + $stopw1) * $FEET_TO_METER;
                        fg_geo_direct_wgs_84( $elat1, $elon1, $hdg1, $s, \$lato1, \$lono1, \$az2 );
                    }
                    $xml .= "  <runway>\n";
                    $xml .= "    <threshold>\n";
                    $xml .= "      <rwy>$rwy1</rwy>\n";
                    $xml .= "      <lat>$lato1</lat>\n";
                    $xml .= "      <lon>$lono1</lon>\n";
                    $xml .= "      <hdg-deg>$hdg1</hdg-deg>\n";
                    $xml .= "      <displ-m>";
                    $xml .= $displ1 * $FEET_TO_METER;
                    $xml .= "</displ-m>\n";
                    $xml .= "      <stopw-m>";
                    $xml .= $stopw1 * $FEET_TO_METER;
                    $xml .= "</stopw-m>\n";
                    $xml .= "    </threshold>\n";
                    if (($displ2 + $stopw2) > 0) {
                        $s = ($displ2 + $stopw2) * $FEET_TO_METER;
                        fg_geo_direct_wgs_84( $elat2, $elon2, $hdg2, $s, \$lato2, \$lono2, \$az2 );
                    }
                    $xml .= "    <threshold>\n";
                    $xml .= "      <rwy>$rwy2</rwy>\n";
                    $xml .= "      <lat>$lato2</lat>\n";
                    $xml .= "      <lon>$lono2</lon>\n";
                    $xml .= "      <hdg-deg>$hdg2</hdg-deg>\n";
                    $xml .= "      <displ-m>";
                    $xml .= $displ2 * $FEET_TO_METER;
                    $xml .= "</displ-m>\n";
                    $xml .= "      <stopw-m>";
                    $xml .= $stopw2 * $FEET_TO_METER;
                    $xml .= "</stopw-m>\n";
                    $xml .= "    </threshold>\n";
                    $xml .= "  </runway>\n";
                ### always gen the xml }
            } elsif ($type == 100) {
    
                $rwid  = ${$ra}[1];  # WIDTH in meters? NOT SHOWN
                $surf  = ${$ra}[2];  # add surface type
                $rwy1  = ${$ra}[8];
                $elat1 = ${$ra}[9];
                $elon1 = ${$ra}[10];

                $rwy2 = ${$ra}[17];
                $elat2 = ${$ra}[18];
                $elon2 = ${$ra}[19];
                my $res = fg_geo_inverse_wgs_84 ($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
                # =======================================================
                $apt_xg .= rwy_xg_stg($icao,$elat1,$elon1,$elat2,$elon2,$rwid,$rwy1,$rwy2);
                # =======================================================
                # add runway ends to BOUNDS (bbox)
                $min_lon = $elon1 if ($elon1 < $min_lon);
                $min_lat = $elat1 if ($elat1 < $min_lat);
                $max_lat = $elat1 if ($elat1 > $max_lat);
                $max_lon = $elon1 if ($elon1 > $max_lon);

                $min_lon = $elon2 if ($elon2 < $min_lon);
                $min_lat = $elat2 if ($elat2 < $min_lat);
                $max_lat = $elat2 if ($elat2 > $max_lat);
                $max_lon = $elon2 if ($elon2 > $max_lon);

                # sum of multiple passes
                $min_lats = $elat1 if ($elat1 < $min_lats);
                $max_lats = $elat1 if ($elat1 > $max_lats);
                $min_lons = $elon1 if ($elon1 < $min_lons);
                $max_lons = $elon1 if ($elon1 > $max_lons);
                $min_lats = $elat2 if ($elat2 < $min_lats);
                $max_lats = $elat2 if ($elat2 > $max_lats);
                $min_lons = $elon2 if ($elon2 < $min_lons);
                $max_lons = $elon2 if ($elon2 > $max_lons);


                # display it
                # ==========================================================================
                $info .= "\n"; #  if (VERB1()); # new line
                $s *= $METER_TO_FEET;
                $s = int($s + 0.5);
                #$az1 = (int(($az1 + 0.05) * 10) / 10);
                #$az2 = (int(($az2 + 0.05) * 10) / 10);
                $az1 = int($az1 + 0.5);
                $az2 = int($az2 + 0.5);
                # runway markings - magnetic azimuth of the centerline
                $rwy1 .= ' ' while (length($rwy1) < 3);
                $rwy2 .= ' ' while (length($rwy2) < 3);
                $info .= " $rwy1: ".get_ll_stg($elat1,$elon1)." $rwy2: ".get_ll_stg($elat2,$elon2);
                $info .= " b=$az1/$az2 l=$s ft";
                if (defined $runway_surface{$surf}) {
                    $info .= " (".$runway_surface{$surf}.")";
                }
            } else {
                pgm_exit(1,"Uncoded RUNWAY type $type - FIX ME!\n".join(" ",@{$ra})."\n");
            }

            # see above rwy_xg_stg() - now generate runway rectangles
            #$annoxg .= "$elon1 $elat1\n";
            #$annoxg .= "$elon2 $elat2\n";
            #$annoxg .= "NEXT\n";

        }

		$tile = get_bucket_info( $alon, $alat );
        $adkm = sprintf( "%0.2f", ($dist / 1000.0));    # get kilometers
        $ahdg = sprintf( "%0.1f", $az );    # and azimuth

		while (length($icao) < 4) {
			$icao .= ' ';
		}

        # start the OUTPUT of an airport
		#$line = $diff;
		$line = $aalt;  # start with ALTITUDE (AMSL) feet
		$line = ' '.$line while (length($line) < 6);

        # name length = 'Chavenay Villepreux ' - say 24 for unique
        $name .= " " while (length($name) < 24);
        $name = substr($name,0,24) if (!VERB1() && (length($name) > 24));

        # expand to standard
        $alat = sprintf("%2.9f",$alat);
        $alon = sprintf("%3.9f",$alon);
        #$alat = ' '.$alat while (length($alat) < 12);
        #$alon = ' '.$alon while (length($alon) < 13);
		#$line .= ' '.$icao.' '.$name.' ('.$alat.','.$alon.") tile=$tile";
		$line .= ' '.$icao.' '.$name.' '.$alat.','.$alon;
        $line .= " ";
        if ($SRCHONLL) {
            # more information on a/p found...
            # $line .= ", ".$adkm."Km on $ahdg";
            $line .= get_fg_dist_dir($c_lat,$c_lon,$dlat,$dlon)." ";
            if (!VERB1()) {
                prt("$line\n");
                $out .= "$line\n";
        		$outcount++;
                next;
            }
        }
        $line .= "\n"; # if (VERB1());
        $line .= $info;
        if ($gaoff) {
            $info = get_atis_info($i,$scnt,\@aptlist2,$gaoff,$dlat,$dlon,$aalt);
            $line .= $info;
        }
        $line .= " fg=".get_tile($alon,$alat); # +/or? ." (".get_tile_calc($alon,$alat).")";
        # $line .= ")"; # close
        # show it
		prt("$line\n"); # print
        $out .= "$line\n";
		$outcount++;
        ############################
        if (check_ground_net($oicao,\$tmp)) {
            prt("See $tmp\n");
            #show_ground_net($tmp);
        }
        ############################
		add_2_tiles($tile);

        if ($gen_threshold_xml) {
            $icao = $aptlist2[$i][1]; # get ICAO back
            $xml .= "</PropertyList>\n";
            prt($xml) if (VERB9());
            my $xfil = $icao.".threshold.xml";
            my $file = $temp_dir.$PATH_SEP."temp.".$xfil;
            rename_2_old_bak($file);    # rename any previous
            write2file($xml,$file);
            prt("Threshold XML written to [$file]\n");
            if (get_current_threshold($icao,\$tmp)) {
                prt("Compare this with [$tmp]\n");
            }
        }
        prt("bounds: $min_lat $min_lon $max_lat $max_lon\n") if ($add_bbox);
	}
    prt("bounds: $min_lats $min_lons $max_lats $max_lons\n") if ($add_bbox && ($scnt > 1));
    if ($add_xg) {
        my $len = length($annoxg);
        $annoxg .= "$xgmsg\n" if (length($xgmsg));
        if ($add_bbox) {
            $annoxg .= get_x_bbox();
            $annoxg .= "# bounds: $min_lat, $min_lon, $max_lat $max_lon\n";
            $annoxg .= "color gray\n";
            $annoxg .= get_bbox_xg($min_lat,$min_lon,$max_lat,$max_lon);    # get a SQUARE
            $annoxg .= "NEXT\n";
        }
        if ($len) {
            $name = trim_all($name);
            $annoxg = "# Airport:[ icao=\"$icao\", name:\"$name\", lon:$dlon, lat:$dlat, alt:$aalt, rwys:$rwycnt";
            my @a = keys %g_rwy_ends;
            if (@a) {
                $annoxg .= ", ids:\"";
                $annoxg .= join("/",@a);
                $annoxg .= "\"";
            }
            $annoxg .= "]\n";
            $annoxg .= "anno $dlon $dlat $apticao Airport circuit $g_circuit\n";
        }
        $annoxg .= $apt_xg;
        #prt("$annoxg");
        if (length($xg_output) && length($annoxg)) {
            $out_xg1 = $xg_output;
            rename_2_old_bak($out_xg1); # never overwrite previous
            write2file($annoxg,$out_xg1);
            prt("Written airport XG file $out_xg1\n");
        } else {
            prt("No \$xg_output, or \$apt_xg to write...\n");
        }
    }
    # ==========================================================
	prt("[v2] Done $scnt list ...\n" ) if (VERB2());
    if ($SRCHONLL) {
        prt("Above list of $outcount airports near [".ctr_latlon_stg()."], using diff [$maxlatd,$maxlond]\n");
        if (!VERB1() || ($ex_helipads && $skip_helis)) {
            prt("Use -v to see more details. ") if (!VERB1());
            prt("Use -H to not skip $skip_helis helipads.") if ($ex_helipads && $skip_helis);
            prt("\n");
        }
    }
    if (length($out_file)) {
        write2file($out,$out_file);
        prt("Airport information written to [$out_file]\n");
    }
    return $scnt;
}

# 14/12/2010 - Switch to using the Bucket2.pm
# 02/05/2011 - add the tile INDEX
sub get_tile { # $alon, $alat
	my ($lon, $lat) = @_;
    my $b = Bucket2->new();
    $b->set_bucket($lon,$lat);
    return $b->gen_base_path()."/".$b->gen_index();
}

# 14/12/2010 - Add a fix for latitude south
# that is -30 is s40
sub get_tile_calc { # $alon, $alat
	my ($lon, $lat) = @_;
	my $tile = 'e';
	if ($lon < 0) {
		$tile = 'w';
		$lon = -$lon;
	}
	my $ilon = int($lon / 10) * 10;
	if ($ilon < 10) {
		$tile .= "00$ilon";
	} elsif ($ilon < 100) {
		$tile .= "0$ilon";
	} else {
		$tile .= "$ilon"
	}
	if ($lat < 0) {
		$tile .= 's';
		$lat = -$lat;
        $lat += 10;
	} else {
		$tile .= 'n';
	}
	my $ilat = int($lat / 10) * 10;
	if ($ilat < 10) {
		$tile .= "0$ilat";
	} elsif ($ilon < 100) {
		$tile .= "$ilat";
	} else {
		$tile .= "$ilat" # SHOULD NOT EXIST
	}
	return $tile;
}

sub add_2_tiles {	# $tile
	my ($tl) = shift;
	if (@tilelist) {
		foreach my $t (@tilelist) {
			if ($t eq $tl) {
				return 0;
			}
		}
	}
	push(@tilelist, $tl);
	return 1;
}

sub is_valid_nav {
	my ($t) = shift;
    if ($t && length($t)) {
        my $txt = "$t";
        my $cnt = 0;
        foreach my $n (@navset) {
            if ($n eq $txt) {
                $actnav = $navtypes[$cnt];
                return 1;
            }
            $cnt++;
        }
    }
	return 0;
}

sub set_average_apt_latlon {
    $g_acnt = scalar @aptlist2;
    $g_total_aps = scalar @g_naptlist;
	my $ac = $g_acnt;
	my $tlat = 0;
	my $tlon = 0;
    my ($alat,$alon);
    prt( "Found $g_acnt, of $totaptcnt, airports ...getting average...\n" ) if ($dbg3 || VERB9());
	if ($ac) {
		for (my $i = 0; $i < $ac; $i++ ) {
			$alat = $aptlist2[$i][3];
			$alon = $aptlist2[$i][4];
			$tlat += $alat;
			$tlon += $alon;
		}
		$av_apt_lat = $tlat / $ac;
		$av_apt_lon = $tlon / $ac;
        if ($SRCHICAO) {
            prt( "Found $g_acnt matching $apticao ...(av. $av_apt_lat,$av_apt_lon)\n" ) if ($dbg3 || VERB9());
        } elsif ($SRCHONLL) {
            prt( "Found $g_acnt matching ".ctr_latlon_stg()." ...(av. $av_apt_lat,$av_apt_lon)\n" ) if ($dbg3 || VERB9());
        } else {
            prt( "Found $g_acnt matching $aptname ... (av. $av_apt_lat,$av_apt_lon)\n" ) if ($dbg3 || VERB9());
        }
	}
}

#                 0      1      2      3      4      5   6  7  8  9      10     11    12     13   14        15
#push(@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@runways,$aalt]);
# my $nmaxlatd = 1.5;
# my $nmaxlond = 1.5;
sub near_an_airport {
	my ($lt, $ln, $dist, $az) = @_;
    my ($az1, $az2, $s, $ret);
	my $ac = scalar @aptlist2;
    my ($x,$y,$z) = fg_ll2xyz($ln,$lt);    # get cart x,y,z
    my $d2 = $max_range_km * 1000;      # get meters
    my ($alat,$alon,$diff,$icao,$name);
	for (my $i = 0; $i < $ac; $i++ ) {
		$diff = $aptlist2[$i][0];
		$icao = $aptlist2[$i][1];
		$name = $aptlist2[$i][2];
		$alat = $aptlist2[$i][3];
		$alon = $aptlist2[$i][4];
        if ($usekmrange) {
            my ($xb, $yb, $yz) = fg_ll2xyz($alon, $alat);
            my $dst = sqrt( fg_coord_dist_sq( $x, $y, $z, $xb, $yb, $yz ) ) * $DIST_FACTOR;
            if ($dst < $d2) {
                $s = -1;
                $az1 = -1;
                $ret = fg_geo_inverse_wgs_84($alat, $alon, $lt, $ln, \$az1, \$az2, \$s);
                $$dist = $s;
                $$az = $az1;
                return ($i + 1);
            }
        } else {
    		my $td = abs($lt - $alat);
	    	my $nd = abs($ln - $alon);
		    if (($td < $nmaxlatd)&&($nd < $nmaxlond)) {
                $s = -1;
                $az1 = -1;
                $ret = fg_geo_inverse_wgs_84($alat, $alon, $lt, $ln, \$az1, \$az2, \$s);
                $$dist = $s;
                $$az = $az1;
			    return ($i + 1);
		    }
        }
	}
	return 0;
}

sub not_in_world_range($$) {
    my ($lt,$ln) = @_;
    return 1 if ($lt < -90);
    return 1 if ($lt >  90);
    return 1 if ($ln < -180);
    return 1 if ($ln >  180);
    return 0;
}

# like sub near_an_airport {
sub near_given_point {
	my ($lt, $ln, $rdist, $raz) = @_;
    if ( not_in_world_range($lt,$ln) ) {
        prtw("WARNING: near_given_point given OUT OF WORLD RANGE [$lt,$ln]\n");
        return 0;
    }
    my ($az1, $az2, $s, $ret);
    my ($x,$y,$z) = fg_ll2xyz($ln,$lt);    # get cart x,y,z
    my $d2 = $max_range_km * 1000;      # get meters
    my $ngp_ret = 0;
    my ($alat,$alon);
    if ($SRCHONLL) {
	# for (my $i = 0; $i < $ac; $i++ ) {
	#	$diff = $aptlist2[$i][0];
	#	$icao = $aptlist2[$i][1];
	#	$name = $aptlist2[$i][2];
		$alat = $g_center_lat;
		$alon = $g_center_lon;
        if ($usekmrange) {
            my ($xb, $yb, $yz) = fg_ll2xyz($alon, $alat);
            my $dst = sqrt( fg_coord_dist_sq( $x, $y, $z, $xb, $yb, $yz ) ) * $DIST_FACTOR;
            if ($dst < $d2) {
                $s = -1;
                $az1 = -1;
                $ret = fg_geo_inverse_wgs_84($alat, $alon, $lt, $ln, \$az1, \$az2, \$s);
                ${$rdist} = $s;
                ${$raz}   = $az1;
                $ngp_ret = 1;
            }
        } else {
    		my $td = abs($lt - $alat);
	    	my $nd = abs($ln - $alon);
		    if (($td < $nmaxlatd)&&($nd < $nmaxlond)) {
                $s = -1;
                $az1 = -1;
                $ret = fg_geo_inverse_wgs_84($alat, $alon, $lt, $ln, \$az1, \$az2, \$s);
                ${$rdist} = $s;
                ${$raz} = $az1;
			    $ngp_ret = 1;
		    }
        }
	}
	return $ngp_ret;
}

sub show_nav_list($) {
    my ($rnl) = @_;
    my $cnt = scalar @{$rnl};
    my ($ic,$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name,$off,$dist,$az,$line);
    prt("$g_nav_hdr\n");
    for ($ic = 0; $ic < $cnt; $ic++) {
		$typ   = ${$rnl}[$ic][0];
		$nlat  = ${$rnl}[$ic][1];
		$nlon  = ${$rnl}[$ic][2];
		$nalt  = ${$rnl}[$ic][3];
		$nfrq  = ${$rnl}[$ic][4];
		$nrng  = ${$rnl}[$ic][5];   # nm
		$nfrq2 = ${$rnl}[$ic][6];   # ?????
		$nid   = ${$rnl}[$ic][7];
		$name  = ${$rnl}[$ic][8];
		$off   = ${$rnl}[$ic][9];
        $dist  = ${$rnl}[$ic][10];
        $az    = ${$rnl}[$ic][11];
		is_valid_nav($typ); # set global $actnav

        # for display only
        $nalt  = ' '.$nalt while (length($nalt) < $g_maxnaltl);
        $nfrq  = ' '.$nfrq while (length($nfrq) < $g_maxnfrql);
        $nrng  = ' '.$nrng while (length($nrng) < $g_maxnrngl);
        $nfrq2 = ' '.$nfrq2 while (length($nfrq2) < $g_maxnfq2l);
        $nid   = ' '.$nid while (length($nid) < $g_maxnnidl);
        $nlat  = ' '.$nlat while (length($nlat) < $g_maxnlatl);
        $nlon  = ' '.$nlon while (length($nlon) < $g_maxnlonl);

		# is_valid_nav($typ); # set global $actnav
        $line   = $actnav;
        $line  .= ' ' while (length($line) < $maxnnlen);
        $line  .= ' ';
        $line .= "$nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name";
        prt("$line\n");
    }
}

sub get_fg_coms() {
    set_lib_fgio_verb(0);
    if (fgfs_connect($HOST,$PORT,$TIMEOUT)) {
        prt("Connection established...\n") if (VERB5());
       	fgfs_send("data");  # switch exchange to data mode
        my $rc = fgfs_get_comms();
        show_comms($rc);
        fgfs_disconnect();
    } else {
        prt("Connection FAILED!\n") if (VERB5());
    }
}


#########################################################################
### Display of NAVAIDS found 'nearby', in @navlist2, or @g_navlist3 if any
#########################################################################
sub show_navaids_found {
	my ($ic, $in, $line, $lcnt, $dnone);
	my ($icao, $alat, $alon);
    # my ($diff); 20110221 - remove display of this DIFF???
	my ($typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off);
    my ($dist, $az, $adkm, $ahdg);
    my ($apds,$apaz,$dist_hdg,$add,$ap_line,$amsl);
    my $msg = '';
    my $out = '';
    my $hdr = "Type  Latitude     Logitude        Alt.  Freq.  Range  Frequency2    ID  Name";
	#prt( "$actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name ($off)\n");
	#push(@navlist2, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off]);
    my $nearna = scalar @g_navlist3;
	my $ac = scalar @aptlist2; # found APT list count
    # found within range of AP (or CENTER)
    if ($sort_by_distance) {
        @navlist2 = sort mycmp_decend_dist @navlist2;
    } elsif ($sortbyfreq) {
        @navlist2 = sort mycmp_ascend_n4 @navlist2;
    }
	my $nc = scalar @navlist2;
    my $tot = $nc + $nearna;
    my $dspcnt = 0;
    $msg = "For ";
    $msg .= "$nearna 'near' aids, " if ($nearna);
    $msg .= "$ac airports, found $tot ($nearna+$nc) NAVAIDS, ";
    if ($usekmrange) {
    	$msg .= "within [$max_range_km] Km ...";
    } else {
    	$msg .= "within [$nmaxlatd,$nmaxlond] degrees ...";
    }
    prt("$msg\n") if (VERB1());
	$lcnt = 0;
    prt("List $nearna NEAR [".ctr_latlon_stg()."]...\n") if ($nearna && VERB1());
    #my @navlist3 = sort mycmp_decend_dist @g_navlist3;
    #my $rnavlist3 = \@navlist3;
    @g_navlist3 = sort mycmp_decend_dist @g_navlist3;
    my $rnavlist_d = \@g_navlist3;
    my @g_navlist_az = sort mycmp_decend_az @g_navlist3;
    my $rnavlist3 = \@g_navlist_az;
    $dspcnt = 0;
    $dnone = 0; # header display line control
    my ($dlat,$dlon);   # here $nlat is often 'extended' for display, but this is the NUMBER
    # This list can be ZERO
    # =====================
	for ($ic = 0; $ic < $nearna; $ic++) {
		$typ = ${$rnavlist3}[$ic][0];
		$dlat = ${$rnavlist3}[$ic][1];
		$dlon = ${$rnavlist3}[$ic][2];
		$nlat = ${$rnavlist3}[$ic][1];
		$nlon = ${$rnavlist3}[$ic][2];
		$nalt = ${$rnavlist3}[$ic][3];
		$nfrq = ${$rnavlist3}[$ic][4];
		$nrng = ${$rnavlist3}[$ic][5];
		$nfrq2 = ${$rnavlist3}[$ic][6];
		$nid = ${$rnavlist3}[$ic][7];
		$name = ${$rnavlist3}[$ic][8];
		$off = ${$rnavlist3}[$ic][9];
        $dist = ${$rnavlist3}[$ic][10];
        $az = ${$rnavlist3}[$ic][11];
		is_valid_nav($typ); # set global $actnav
        if ($vor_only) {
            if (($actnav =~ /VOR/) || ($actnav =~ /NBD/)) {
                # these are OK
            } else {
                next;
            }
        }
        $dspcnt++;

        # set up the DISPLAY
        $line = $actnav;
        $line .= ' ' while (length($line) < $maxnnlen);

        $line .= ' ';
        $nalt = ' '.$nalt while (length($nalt) < 5);

        $nfrq = ' '.$nfrq while (length($nfrq) < 5);
        $nrng = ' '.$nrng while (length($nrng) < 5);
        $nfrq2 = ' '.$nfrq2 while (length($nfrq2) < 10);
        $nid = ' '.$nid while (length($nid) < 4);
        $nlat = ' '.$nlat while (length($nlat) < 12);
        $nlon = ' '.$nlon while (length($nlon) < 13);
        $adkm = sprintf( "%0.2f", ($dist / 1000.0));    # get kilometers
        $ahdg = sprintf( "%0.1f", $az );    # and azimuth
        $name = elim_the_dupes($name);
        $name .= ' ' while (length($name) < $g_max_name_len);
        $dist_hdg = "(".$adkm."Km on $ahdg, ap$off)"; # keep separate
        $line .= "$nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name";
        if ($dnone == 0) {
            #prt( "Type  Latitude     Logitude        Alt.  Freq.  Range  Frequency2    ID  Name\n" );
            prt( "$hdr\n" ); # if (VERB1());
            $dnone++;
        }
        if (defined $g_dupe_shown{$line}) {
            prt( "[v5] DupeNR: Shown [$actnav $nlat,$nlon $name] - SHOWN\n") if (VERB5());
        } else {
            prt( "$line $dist_hdg\n" ) if (VERB9());
            $outcount++;
            $lcnt++;
            $g_dupe_shown{$line} = 1;
            $msg = $actnav;
            $msg .= ' ' while (length($msg) < $maxnnlen);
            $adkm = sprintf( "%03.1f", ($dist / 1000.0));    # get kilometers
            $adkm = " $adkm" while (length($adkm) < 6);
            $ahdg = sprintf( "%03.1f", $az );    # and azimuth
            $ahdg = " $ahdg" while (length($ahdg) < 5);
            $msg .= "$adkm"."Km on hdg $ahdg";
            $msg .= ", freq $nfrq, ident $nid $name $nlat $nlon";
            prt("$msg\n");
            $out .= "$msg\n";
        }
    }
    prt("Done $dspcnt of $nearna NEAR [".ctr_latlon_stg()."]...\n") if ($nearna && VERB1());
	$lcnt = 0;
    # count objects for display...
    $dspcnt = 0;
    # go through found airport list
	for ($ic = 0; $ic < $ac; $ic++) {
		# $diff = $aptlist2[$ic][0];
		$icao = $aptlist2[$ic][1];
		$name = $aptlist2[$ic][2];
		$alat = $aptlist2[$ic][3];
		$alon = $aptlist2[$ic][4];
        $apds = $aptlist2[$ic][12];
        $apaz = $aptlist2[$ic][13];
        $amsl = $aptlist2[$ic][15]; # get APT altitude (AMSL) feet
		$icao .= ' ' while (length($icao) < 4);
		# $line = $diff; # this 'diff' is what exactly? 
		$line = $amsl; # 20110221 - Now start with AMSL (feet)
		$line = ' '.$line while (length($line) < 6);
		$line .= ' '.$icao.' '.$name.' ('.$alat.','.$alon.')';
		$dnone = 0;
        # show those in @navlist2, which was populated using $tryharder
		for ( $in = 0; $in < $nc; $in++ ) {
			$typ = $navlist2[$in][0];
            $dlat = ${$rnavlist3}[$ic][1];
            $dlon = ${$rnavlist3}[$ic][2];
			$nlat = $navlist2[$in][1];
			$nlon = $navlist2[$in][2];
			$nalt = $navlist2[$in][3];
			$nfrq = $navlist2[$in][4];  # frequency
			$nrng = $navlist2[$in][5];
			$nfrq2 = $navlist2[$in][6];
			$nid = $navlist2[$in][7];
			$name = $navlist2[$in][8];
			$off = $navlist2[$in][9];
            $dist = $navlist2[$in][10];
            $az = $navlist2[$in][11];
			if ($off == ($ic + 1)) {
				# it is FOR this airport
				is_valid_nav($typ);
                if ($vor_only) {
                    if (($actnav =~ /VOR/) || ($actnav =~ /NBD/)) {
                        # these are OK
                    } else {
                        next;
                    }
                }
    			#     NDB  50.049000, 008.328667,   490,   399,    25,      0.000,  WBD, Wiesbaden NDB (ap=2 nnnKm on 270.1)
                #     Type Latitude   Logitude     Alt.  Freq.  Range  Frequency2    ID  Name
                #     VOR  37.61948300, -122.37389200,    13, 11580,    40,       17.0,  SFO, SAN FRANCISCO VOR-DME (ap=1 nnnKm on 1.1)
				#prt( "$actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name ($off)\n");
                $dspcnt++;
			}
		}
		# prt( "$hdr\n" ) if ($dnone && VERB1());
	}
    prt("List for $ac airports... near [".ctr_latlon_stg()."]... display $dspcnt...\n") if ($ac && VERB1());
    $lcnt = 0;
    $ap_line = '';
    my %freqs = ();
    my @freqlist = ();
	for ($ic = 0; $ic < $ac; $ic++) {
		# $diff = $aptlist2[$ic][0];
		$icao = $aptlist2[$ic][1];
		$name = $aptlist2[$ic][2];
		$alat = $aptlist2[$ic][3];
		$alon = $aptlist2[$ic][4];
        $apds = $aptlist2[$ic][12];
        $apaz = $aptlist2[$ic][13];
        $amsl = $aptlist2[$ic][15];
        
		$icao .= ' ' while (length($icao) < 4);

		# $line = $diff; # start with 'offset' from center point
        $line = $amsl; # start with ALTITUDE (AMSL) feet
		$line = ' '.$line while (length($line) < 6);
		$line .= ' '.$icao.' '.$name.' ('.$alat.','.$alon.')';

        $dspcnt = 0;
        # check the LIST of viable items to DISPLAY
		for ( $in = 0; $in < $nc; $in++ ) {
			$typ = $navlist2[$in][0];
			$off = $navlist2[$in][9];
			if ($off == ($ic + 1)) {
				is_valid_nav($typ);
                if ($vor_only) {
                    if (($actnav =~ /VOR/) || ($actnav =~ /NBD/)) {
                        $dspcnt++; # these are OK
                    }
                } else {
                    $dspcnt++;
                }
            }
        }
        $line .= " ($dspcnt)";
        prt("\n") if ($ic && $dspcnt && VERB1());
		# prt("$line\n");
        $ap_line = $line;   # setup to SHOW, only if a NAV AID is to be displayed
		$outcount++;
		$dnone = 0;
        $line = '';
		for ( $in = 0; $in < $nc; $in++ ) {
			$typ = $navlist2[$in][0];
			$dlat = $navlist2[$in][1];
			$dlon = $navlist2[$in][2];
			$nalt = $navlist2[$in][3];
			$nfrq = $navlist2[$in][4];  # frequency
			$nrng = $navlist2[$in][5];  # nm
			$nfrq2 = $navlist2[$in][6];
			$nid = $navlist2[$in][7];
			$name = $navlist2[$in][8];
			$off = $navlist2[$in][9];
            $dist = $navlist2[$in][10];
            $az = $navlist2[$in][11];
			$nlat = $dlat;
			$nlon = $dlon;
			if ($off == ($ic + 1)) {
				# it is FOR this airport
				is_valid_nav($typ);
                if ($vor_only) {
                    if (($actnav =~ /VOR/) || ($actnav =~ /NBD/)) {
                        # these are OK
                    } else {
                        next;
                    }
                }

                if (!defined $freqs{$nfrq}) {
                    $freqs{$nfrq} = 1;
                    push(@freqlist,$nfrq);
                }
    			#     NDB  50.049000, 008.328667,   490,   399,    25,      0.000,  WBD, Wiesbaden NDB (ap=2 nnnKm on 270.1)
                #     Type Latitude   Logitude     Alt.  Freq.  Range  Frequency2    ID  Name
                #     VOR  37.61948300, -122.37389200,    13, 11580,    40,       17.0,  SFO, SAN FRANCISCO VOR-DME (ap=1 nnnKm on 1.1)
				#prt( "$actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name ($off)\n");
                # start line
				$line = $actnav;
				$line .= ' ' while (length($line) < $maxnnlen);
				$line .= ' ';

				$nalt = ' '.$nalt while (length($nalt) < 5);
				$nfrq = ' '.$nfrq while (length($nfrq) < 5);
				$nrng = ' '.$nrng while (length($nrng) < 5);
				$nfrq2 = ' '.$nfrq2 while (length($nfrq2) < 10);
				$nid = ' '.$nid while (length($nid) < 4);
                $nlat = ' '.$nlat while (length($nlat) < 12);
                $nlon = ' '.$nlon while (length($nlon) < 13);
                $adkm = sprintf( "%0.2f", ($dist / 1000.0));    # get kilometers
                $ahdg = sprintf( "%0.1f", $az );    # and azimuth
                $name = elim_the_dupes($name);
                $name .= ' ' while (length($name) < $g_max_name_len);
                if ($add_apt_off) {
                    $dist_hdg = "(".$adkm."Km on $ahdg, ap$off)";
                } else {
                    $dist_hdg = "(".$adkm."Km on $ahdg)";
                }
				$line .= "$nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name";
                $add = 0;
                if (defined $g_dupe_shown{$line}) {
                    if (VERB5()) {
                        $add = 1;
                    }
                } else {
                    $add = 1;
                }

				if ($add && ($dnone == 0)) {
					#prt( "Type  Latitude     Logitude        Alt.  Freq.  Range  Frequency2    ID  Name\n" );
                    #if (VERB1()) {
                        if (length($ap_line)) {
                            prt("$ap_line\n");
                            $ap_line = '';
                        }
    					prt( "$hdr\n" );

                    #}
					$dnone = 1;
				}
  				$outcount++;
    			$lcnt++;
                if (defined $g_dupe_shown{$line}) {
                    if (VERB5()) {
                        prt( "DupeAID: Shown [$actnav $nlat,$nlon $name] - SHOWN\n");
                    }
                } else {
                    if (length($ap_line)) {
                        prt("$ap_line\n");
                        $ap_line = '';
                    }
                    if ($check_sg_dist) {
                        my ($sg_az1,$sg_az2,$sg_dist);
                        my $res = fg_geo_inverse_wgs_84 ($g_center_lat,$g_center_lon,$dlat,$dlon,\$sg_az1,\$sg_az2,\$sg_dist);
                        my $sg_km = $sg_dist / 1000;
                        my $sg_im = int($sg_dist);
                        my $sg_ikm = int($sg_km + 0.5);
                        # if (abs($sg_pdist) < $CP_EPSILON)
                        $dist_hdg .= " (SGDist: ";
                        $sg_az1 = int(($sg_az1 * 10) + 0.05) / 10;
                        if (abs($sg_km) > $SG_EPSILON) { # = 0.0000001; # EQUALS SG_EPSILON 20101121
                            if ($sg_ikm && ($sg_km >= 1)) {
                                $sg_km = int(($sg_km * 10) + 0.05) / 10;
                                $dist_hdg .= "$sg_km km";
                            } else {
                                $dist_hdg .= "$sg_im m, <1km";
                            }
                        } else {
                            $dist_hdg .= "0 m";
                        }
                        $dist_hdg .= " on $sg_az1";
                        $dist_hdg .= ")";
                    }
                    #prt( "$lcnt: $line $dist_hdg\n" );
                    prt( "$line $dist_hdg\n" );
                    $out .= "$line $dist_hdg\n";
                    $g_dupe_shown{$line} = 1;
		    		add_2_tiles( get_bucket_info( $nlon, $nlat ) );
                }
			}
		}
		prt( "$hdr\n" ) if ($dnone &&  VERB1() );
	}
    if (@freqlist) {
        prt("Frequency List: ".join(" ",@freqlist)."\n");
        get_fg_coms();
    }
    if (length($out_file) && length($out)) {
        append2file($out,$out_file);
        prt("List appended to [$out_file]\n");
    }
	prt( "[v5] Listed $lcnt NAVAIDS ...\n" ) if (VERB5());
}

# LOAD apt.dat.gz
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
# 100 in Rev 1000 data
sub load_apt_data {
    my ($cnt,$msg);
    prt("[v9] Loading $aptdat file ...\n") if (VERB9());
    mydie("ERROR: Can NOT locate $aptdat ...$!...\n") if ( !( -f $aptdat) );
    ###open IF, "<$aptdat" or mydie("OOPS, failed to open [$aptdat] ... check name and location ...\n");
    open IF, "gzip -d -c $aptdat|" or mydie( "ERROR: CAN NOT OPEN $aptdat...$!...\n" );
    my @lines = <IF>;
    close IF;
    $cnt = scalar @lines;
    prt("[v9] Got $cnt lines to scan...\n") if (VERB9());
    my ($add,$alat,$alon);
    # ================
    # SEARCH THE LINES
    # search ICAO, POSITION, or NAME...
    # ================
    $add = 0;
    my ($off,$dist,$az,@arr,@arr2,$rwyt,$glat,$glon,$dlat,$dlon,$rlat,$rlon);
    my ($line,$apt,$diff,$rwycnt,$icao,$name,@runways);
    my ($aalt,$actl,$abld,$ftyp,$cfrq,$frqn,@freqs);
    my ($len,$type);
    my ($rlat1,$rlon1,$rlat2,$rlon2,$wwcnt,$helicnt,$trwycnt);
    my $total_lat = 0;
    my $total_lon = 0;
    my $c_lat = $g_center_lat;
    my $c_lon = $g_center_lon;
    my $got_twr = 0;
    $off = 0;
    $dist = 0;
    $az = 0;
    $glat = 0;
    $glon = 0;
    $apt = '';
    $rwycnt = 0;
    $wwcnt = 0;
    $helicnt = 0;
    @runways = ();
    @freqs = ();
    my @line_array = ();
    my @waterways = ();
    my @heliways = ();
    $msg = '[v1] ';
    if ($SRCHICAO) {
        $msg .= "Search ICAO [$apticao]...";
    } elsif ($SRCHONLL) {
        $msg .= "Search LAT,LON [".ctr_latlon_stg()."], w/diff [$maxlatd,$maxlond]...";
    } else {
        $msg .= "Search NAME [$aptname]...";
    }
    $msg .= " got $cnt lines, FOR airports,rwys,txwys... ";
    $g_version = 0;
    foreach $line (@lines) {
        $line = trimall($line);
        if ($line =~ /\s+Version\s+/i) {
            @arr2 = split(/\s+/,$line);
            $g_version = $arr2[0];
            $msg .= "Version $g_version";
            last;
        }
    }
    prt("$msg\n") if (VERB1());
    my $lncnt = 0;
    #my $acsv = "icao,latitude,longitude,name\n";
    foreach $line (@lines) {
        $lncnt++;
        $line = trimall($line);
        $len = length($line);
        next if ($len == 0);
        next if ($line =~ /^I/);
        if ($line =~ /^\d+\s+Version\s+/) {
            #    my $ind = index($line,',');
            $len = index($line,',');
            $len = 80 if ($len <= 0);
            prt(substr($line,0,$len)." ($g_version) file: $aptdat\n");
            next;
        }
        ###prt("$line\n");
        my @arr = split(/ /,$line);
        push(@line_array,$line);
        $type = $arr[0];
        ###if ($line =~ /^1\s+/) {	# start with '1'
        # if 1=Airport, 16=SeaPlane, 17=Heliport
        if (($type == 1)||($type == 16)||($type == 17)) {	# start with 1, 16, 17
            # 0  1   2 3 4     
            # 17 126 0 0 EH0001 [H] VU medisch centrum
            # ID ALT C B NAME++
            $trwycnt = $rwycnt;
            $trwycnt += $wwcnt;
            $trwycnt += $helicnt;
            if (length($apt) && ($trwycnt > 0)) {
                if (!$got_twr) {
                    # average position
                    $alat = $glat / $trwycnt;
                    $alon = $glon / $trwycnt;
                }
                $off = -1;
                $dist = 9999000;
                $az = 400;
                #$off = near_given_point( $alat, $alon, \$dist, \$az );
                $dlat = abs( $c_lat - $alat );
                $dlon = abs( $c_lon - $alon );
                $diff = int( ($dlat * 10) + ($dlon * 10) );
                @arr2 = split(/\s+/,$apt);
                $aalt = $arr2[1]; # Airport (general) ALTITUDE AMSL
                $actl = $arr2[2]; # control tower
                $abld = $arr2[3]; # buildings
                $icao = $arr2[4]; # ICAO
                $name = join(' ', splice(@arr2,5)); # Name
                ##prt("$diff [$apt] (with $rwycnt runways at [$alat, $alon]) ...\n");
                ##prt("$diff [$icao] [$name] ...\n");
                my @ra = @runways;
                my @wa = @waterways;
                my @ha = @heliways;
                my @fa = @freqs;
                #               0      1      2      3      4      5     6     7     8
                push(@g_naptlist, [$diff, $icao, $name, $alat, $alon, \@ra, \@wa, \@ha, \@fa ]);
                ##                 0      1      2      3      4      5      6
                ##push(@g_aptlist, [$diff, $icao, $name, $alat, $alon, $aalt, \@fa]);
                #prt("$icao, $name, $alat, $alon, $aalt, $rwycnt runways\n");
                # $acsv .= "$icao,$alat,$alon,$name\n";
                $add = 0;   # add to FOUND a/p, IFF
                if ($SRCHICAO) {
                    # 1 - ICAO matches
                    $add = 1 if ($icao =~ /$apticao/);
                } elsif ($SRCHONLL) {
                    # 2 - searching by LAT,LON position
                    if (($dlat < $maxlatd) && ($dlon < $maxlond)) {
                        $add = 1;
                    }
                } else {
                    # 3 - searching by airport name
                    $add = 1 if ($name =~ /$aptname/i);
                }
                if ($add) {
                    $off = near_given_point( $alat, $alon, \$dist, \$az ); # if ($SRCHONLL), near GLOBAL center
                    prt("[v1] Adding: $icao, $name, $alat, $alon, rwys $rwycnt...\n") if ($dbg1 || VERB1());
    				#                  0=typ, 1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid, 8=name, 9=off, 10=dist, 11=az);
	    			#push(@g_navlist3, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az]);
                    my @a = @runways;
                    #                 0     1      2      3      4      5   6  7  8  9      10     11    12     13   14   15
                    push(@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@a, $aalt]); # = @runways
                    $total_lat += $alat;
                    $total_lon += $alon;
                    $icao_lat = $alat;
                    $icao_lon = $alon;
                    $total_apts++;
                    if (VERB9()) {
                        prt("push(\@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@a, $aalt]);");
                        pop @line_array; # remove last added line
                        foreach $apt (@line_array) {
                            prt("$apt\n");
                        }
                    }
                }
            }
            @line_array = ();   # clear ALL lines of this AIRPORT
            push(@line_array,$line);
            $apt = $line;
            $rwycnt = 0;
            $wwcnt = 0;
            $helicnt = 0;
            @runways = ();  # clear RUNWAY list
            @waterways = ();  # clear RUNWAY list
            @heliways = ();  # clear RUNWAY list
            @freqs = (); # clear frequencies
            $glat = 0;
            $glon = 0;
            $got_twr = 0;
            $totaptcnt++;	# count another AIRPORT
        ###} elsif ($line =~ /^$rln\s+/) {
        } elsif ($type == 10) {
            # 10  36.962213  127.031071 14x 131.52  8208 1595.0620 0000.0000   150 321321  1 0 3 0.25 0 0300.0300
            # 10  36.969145  127.020106 xxx 221.51   329 0.0 0.0    75 161161  1 0 0 0.25 0 
            $rlat = $arr[1];
            $rlon = $arr[2];
            $rwyt = $arr[3]; # text 'xxx'=taxiway, 'H1x'=heleport, else a runway
            ###prt( "$line [$rlat, $rlon]\n" );
            if ( $rwyt ne "xxx" ) {
                # $rwyt =~ s/x//g;    # remove trailing 'x'
                $glat += $rlat;
                $glon += $rlon;
                $rwycnt++;
                my @ar3 = @arr;
                push(@runways, \@ar3);
            }
        ###} elsif ($line =~ /^5(\d+)\s+/) {
        } elsif (($type >= 50)&&($type <= 56)) {
            # frequencies
            $ftyp = $type - 50;
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
            } else {
                pgm_exit(1,"Unknown [$line]\n");
            }
            if ($add) {
                push(@freqs, \@arr); # save the freq array
            } else {
                pgm_exit(1, "WHAT IS THIS [5$ftyp $cfrq $frqn] [$line]\n FIX ME!!!");
            }
        } elsif ($type == 14) {
            # tower location
            # 14  52.911007  156.878342    0 0 Tower Viewpoint
            $got_twr = 1;
            $alat = $arr[1];
            $alon = $arr[2];
        } elsif ($type == 15) {
            # ramp startup
        } elsif ($type == 18) {
            # Airport light beacon
        } elsif ($type == 19) {
            # Airport windsock
        # =============================================================================
        # 20140110 - Switch to LATEST git fgdata - IE 1000 Version - data cycle 2013.10
        # So must ADD all the NEW 'types', just like x-plane
        } elsif ($type == 20) {
            # 20 22.32152700 114.19750500 224.10 0 3 {@Y,^l}31-13{^r}
        } elsif ($type == 21) {
            # 21 22.31928000 114.19800800 3 134.09 3.10 13 PAPI-4R
        } elsif ($type == 100) {
            # See full version 1000 specs below
            # 0   1     2 3 4    5 6 7 8  9           10           11   12   13 14 15 16 17 18          19           20   21   22 23 24 25
            # 100 29.87 3 0 0.00 1 2 1 16 43.91080605 004.90321905 0.00 0.00 2  0  0  0  34 43.90662331 004.90428974 0.00 0.00 2  0  0  0
            $rlat1 = $arr[9];  # $of_lat1
            $rlon1 = $arr[10]; # $of_lon1
            $rlat2 = $arr[18]; # $of_lat2
            $rlon2 = $arr[19]; # $of_lon2
            $rlat = ($rlat1 + $rlat2) / 2;
            $rlon = ($rlon1 + $rlon2) / 2;
            ###prt( "$line [$rlat, $rlon]\n" );
            $glat += $rlat;
            $glon += $rlon;
            my @a2 = @arr;
            push(@runways, \@a2);
            $rwycnt++;
        } elsif ($type == 101) {	# Water runways
            # 0   1      2 3  4           5             6  7           8
            # 101 243.84 0 16 29.27763293 -089.35826258 34 29.26458929 -089.35340410
            # 101 22.86  0 07 29.12988952 -089.39561501 25 29.13389936 -089.38060001
            # prt("$.: $line\n");
            $rlat1 = $arr[4];
            $rlon1 = $arr[5];
            $rlat2 = $arr[7];
            $rlon2 = $arr[8];
            $rlat = sprintf("%.8f",(($rlat1 + $rlat2) / 2));
            $rlon = sprintf("%.8f",(($rlon1 + $rlon2) / 2));
            if (!in_world_range($rlat,$rlon)) {
                prtw( "WARNING: $.: $line [$rlat, $rlon] NOT IN WORLD\n" );
                next;
            }
            $glat += $rlat;
            $glon += $rlon;
            my @a2 = @arr;
            push(@waterways, \@a2);
            $wwcnt++;
        } elsif ($type == 102) {	# Heliport
            # my $heli =   '102'; # Helipad
            # 0   1  2           3            4      5     6     7 8 9 10   11
            # 102 H2 52.48160046 013.39580674 355.00 18.90 18.90 2 0 0 0.00 0
            # 102 H3 52.48071507 013.39937648 2.64   13.11 13.11 1 0 0 0.00 0
            # prt("$.: $line\n");
            $rlat = sprintf("%.8f",$arr[2]);
            $rlon = sprintf("%.8f",$arr[3]);
            if (!in_world_range($rlat,$rlon)) {
                prtw( "WARNING: $.: $line [$rlat, $rlon] NOT IN WORLD\n" );
                next;
            }
            $glat += $rlat;
            $glon += $rlon;
            my @a2 = @arr;
            push(@heliways, \@a2);
            $helicnt++;
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
        } elsif ($type == 99) {
        ### } elsif ($line =~ /^$lastln\s?/) {	# 99, followed by space, count 0 or more ...
            prt( "Reached END OF FILE ... \n" ) if ($dbg1 || VERB9());
            last;
        } else {
            $cnt = scalar @lines;
            my $elapsed = tv_interval ( $t0, [gettimeofday]);
            $elapsed = secs_HHMMSS($elapsed);
            prt("FIX ME - LINE UNCASED $type - Line ".get_nn($lncnt)." of ".get_nn($cnt)." - $elapsed\n");
            prt("$line\n");
            pgm_exit(1,"");
        }
    }

    # do any LAST entry
    $add = 0;
    $off = -1;
    $dist = 0;
    $az = 0;
    $trwycnt = $rwycnt;
    $trwycnt += $wwcnt;
    $trwycnt += $helicnt;
    if (length($apt) && ($trwycnt > 0)) {
        $alat = $glat / $trwycnt;
        $alon = $glon / $trwycnt;
        $off = -1;
        $dist = 999999;
        $az = 400;
        #$off = near_given_point( $alat, $alon, \$dist, \$az );
        $dlat = abs( $c_lat - $alat );
        $dlon = abs( $c_lon - $alon );
        $diff = int( ($dlat * 10) + ($dlon * 10) );
        @arr2 = split(/\s+/,$apt);
        $aalt = $arr2[1];
        $actl = $arr2[2]; # control tower
        $abld = $arr2[3]; # buildings
        $icao = $arr2[4];
        $name = join(' ', splice(@arr2,5));
        ###prt("$diff [$apt] (with $rwycnt runways at [$alat, $alon]) ...\n");
        ###prt("$diff [$icao] [$name] ...\n");
        ###push(@g_aptlist, [$diff, $icao, $name, $alat, $alon]);
        ##push(@g_aptlist, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az]);
        my @ra = @runways;
        my @wa = @waterways;
        my @ha = @heliways;
        my @fa = @freqs;
        #               0      1      2      3      4      5     6     7     8
        push(@g_naptlist, [$diff, $icao, $name, $alat, $alon, \@ra, \@wa, \@ha, \@fa ]);
        #                 0      1      2      3      4      5      6
        # push(@g_aptlist, [$diff, $icao, $name, $alat, $alon, $aalt, \@f]);
        # $acsv .= "$icao,$alat,$alon,$name\n";
        $totaptcnt++;	# count another AIRPORT
        $add = 0;
        if ($SRCHICAO) {
            $add = 1 if ($name =~ /$apticao/);
        } else {
            if ($SRCHONLL) {
                if (($dlat < $maxlatd) && ($dlon < $maxlond)) {
                    $add = 1;
                }
            } else {
                $add = 1 if ($name =~ /$aptname/i);
            }
        }
        if ($add) {
             $off = near_given_point( $alat, $alon, \$dist, \$az ); # if ($SRCHONLL), near GLOBAL center
             prt("$icao, $name, $alat, $alon, rwycnt $rwycnt - LAST\n") if ($dbg1);
             #                  0      1      2      3      4      5   6  7  8  9      10     11    12     13   14        15
             # push(@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@runways,$aalt]);
    		 #                  0=typ, 1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid, 8=name, 9=off, 10=dist, 11=az);
	    	 #push(@g_navlist3, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az]);
             my @a2 = @runways;
             #                0      1      2      3      4      5   6  7  8  9      10     11    12     13   14    15
             push(@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@a2, $aalt]); # = @runways + altitude
            $total_lat += $alat;
            $total_lon += $alon;
            $icao_lat = $alat;
            $icao_lon = $alon;
            $total_apts++;
        }
    }
    if ( (! $SRCHONLL) && $total_apts) {
        # either by ICAO or Name search, so this become CENTER lat/lon
        $g_center_lat = $total_lat / $total_apts;
        $g_center_lon = $total_lon / $total_apts;
        prt( "[v1] Set CENTER LAT,LON [".ctr_latlon_stg()."]\n" ) if (VERB1());

    }
    ### pgm_exit(1,"TEMP EXIT");
    $cnt =scalar @g_naptlist;
    prt("[v9] Done scan of $lncnt lines for $cnt airports...\n") if (VERB9());
    #if ($write_acsv_list) {
    #    write2file($acsv,'airports.csv');
    #    prt("Written airport list to 'airports.csv'\n");
    #    write_runway_csv('runways.csv');
    #}
}

sub load_nav_file {
	prt("\n[v9] Loading $navdat file ...\n") if (VERB9());
	mydie("ERROR: Can NOT locate [$navdat]!\n") if ( !( -f $navdat) );
	open NIF, "gzip -d -c $navdat|" or mydie( "ERROR: CAN NOT OPEN $navdat...$!...\n" );
	my @nav_lines = <NIF>;
	close NIF;
    prt("[v9] Got ".scalar @nav_lines." lines to scan...\n") if (VERB9());
    return @nav_lines;
}

# we have NOT found an airport by an ICAO name, search,
# and group by area nav with PART of this name...
sub search_nav_name() {
    my $cnt = 0;
    my @nav_lines = load_nav_file();
    my ($line,$lnn,$len,$nc,$vcnt);
    my ($nlat,$nlon,$nalt,$nfreq,$nid,$name,$i,$ln);
    my (@arr,$typ,$off,$nfrq,$nfrq2,$nrng,$dist,$az);
    my $rnls = \@nav_lines;
	my $nav_cnt = scalar @{$rnls};
    my $aptid = substr($apticao,1); # drop the country letter
    my $found = 0;
    my @navlist = ();
    prt("Searching $nav_cnt navaid records...using ICAO [$apticao], apt-id [$aptid]...\n");
    for ($ln = 0; $ln < $nav_cnt; $ln++) {
        $line = ${$rnls}[$ln];
		$line = trimall($line);
        $len = length($line);
        $lnn++;
        next if ($line =~ /\s+Version\s+/i);
        next if ($line =~ /^I/);
        next if ($len == 0);
		@arr = split(/ /,$line);
		$nc = scalar @arr;
		$typ = $arr[0];
        last if ($typ == 99);
        if ($nc < 8) {
            prt("Type: [$typ] - Handle this line [$line] - count = $nc...\n");
            pgm_exit(1,"ERROR: FIX ME FIRST!\n");
        }
        # Check for type number in @navset, and set $actnav to name, like VOR, NDB, etc
        $off = 0;
		if ( is_valid_nav($typ) ) {
			$vcnt++;
			$nlat  = $arr[1];
			$nlon  = $arr[2];
			$nalt  = $arr[3];
			$nfrq  = $arr[4];
			$nrng  = $arr[5];
			$nfrq2 = $arr[6];
			$nid   = $arr[7];
			$name  = '';
			for ($i = 8; $i < $nc; $i++) {
				$name .= ' ' if length($name);
				$name .= $arr[$i];
			}
            if ($nid =~ /$aptid/) {
                $off  = 0;
                $dist = -1; # this is by NAME, not location
                $az   = 400;
                prt( "[04] $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name\n"); # if ($dbg_fa04);
                #                 0=typ, 1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid, 8=name, 9=off, 10=dist, 11=az);
                push(@navlist, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az]);
                $found++;
            }
        }
    }
    prt("Searched $vcnt navais records... found $found with [$aptid]...\n");
    if ($found) {
        show_nav_list(\@navlist);
    }
}


# ---------------------------------------------------------
# sub search_nav 
# Scan the NAVAID lines
# Run 1:
# Populate @g_navlist3 with navaids found within a given range of a CENTER point ($g_lat,$g_lon)
#                  0=typ, 1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid, 8=name, 9=off, 10=dist, 11=az);
# push(@g_navlist3, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az]);
# Run 2:
# Populate @navlist2 with navaids found within a given range of the AIRPORTS found, else the CENTER point
#prt( "[02] $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name ($off)\n") if ($dbg_fa02);
#                 0     1      2      3      4      5      6       7     8      9     10     11
#push(@navlist2, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az]);
#
# ---------------------------------------------------------
sub search_nav {
	my ($typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off);
    my ($alat, $alon);
    my ($dist, $az,$msg);
    my $cnt = 0;
    my @nav_lines = load_nav_file();
	my $nav_cnt = scalar @nav_lines;
	my $ac = scalar @aptlist2;  # airport FOUND list
    $msg = '';
    $msg .= "Search FOR [".ctr_latlon_stg()."]... ";
    #                 0      1      2      3      4      5   6  7  8  9      10     11    12     13   14        15
    #push(@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@runways,$aalt]);
    if ($ac == 1) {
   		$alat = $aptlist2[0][3];
		$alon = $aptlist2[0][4];
        if ($usekmrange) {
            $msg .= "Use max [$max_range_km] Km from $ac ap at $alat,$alon.";
        } else {
            $msg .= "Use dev [$nmaxlatd,$nmaxlond] from $ac ap at $alat,$alon.";
        }
    } else {
        if ($usekmrange) {
            $msg .= "Use max dist [$max_range_km] Km from $ac apts.";
        } else {
            $msg .= "Use dev [$nmaxlatd,$nmaxlond] from $ac apts.";
        }
    }
    $msg .= " in $nav_cnt NAV lines...";

    prt("$msg\n") if (VERB1());
	my $vcnt = 0;
    my $navs_found = 0;
    my (@arr,$nc,$lnn,$len,$dnvers,$line,$i);
    my $skip_version = 0;
    $lnn = 0;
    $lnn = 0;
    $dnvers = 0;
    $cnt = 0;
	### foreach $line (@nav_lines) {
    for ($i = 0; $i < $nav_cnt; $i++) {
        $cnt++;
        $line = trimall($nav_lines[$i]);
        $lnn++;
        # 810 Version - data cycle 2009.12, build 20091080, metadata NavXP810
        if ($line =~ /\s+Version\s+/i) {
            if ($line =~ /\s*(\n+)\s+Version\s+/) {
                $nav_file_version = $1;
            }
            $typ = length($line) > 80 ? substr($line,0,80) : $line;
            prt( "[v2] NAVAID: $typ\n" ) if (VERB2());
            $dnvers = 1;
            $i++;
            $skip_version = $i;
            last;
        }
    }
    #$lnn = 0;
    $cnt = scalar @nav_lines;
	prt( "[04] Doing 'center' search... $cnt NAV objects\n") if ($dbg_fa04);
    #$cnt = 0;
    $vcnt = 0;
	###foreach $line (@nav_lines)
    my %nav_freqs = (); # avoid repeated frequencies unless VERV5()
    for ( ; $i < $nav_cnt; $i++) {
        $line = trimall($nav_lines[$i]);
        $len = length($line);
        $lnn++;
        ##next if ($line =~ /\s+Version\s+/i);
        next if ($len == 0);
		@arr = split(/\s+/,$line);
		$nc = scalar @arr;
		$typ = $arr[0];
        # Check for type number in @navset, and set $actnav to name, like VOR, NDB, etc
        $off = 0;
		if ( is_valid_nav($typ) ) {
			$vcnt++;
			$nlat = $arr[1];
			$nlon = $arr[2];
			$nalt = $arr[3];
			$nfrq = $arr[4];
			$nrng = $arr[5];
			$nfrq2 = $arr[6];
			$nid = $arr[7];
			$name = '';
			for (my $i = 8; $i < $nc; $i++) {
				$name .= ' ' if length($name);
				$name .= $arr[$i];
			}
            $off = near_given_point( $nlat, $nlon, \$dist, \$az );
			if ($off) {
                $off = 2;
				prt( "[04] $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name ($off)\n") if ($dbg_fa04);
                #                 0=typ, 1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid, 8=name, 9=off, 10=dist, 11=az);
                push(@g_navlist3, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az]);
                $cnt++;
			}
        }
    }
  	prt( "[04] Done 'center' search, $vcnt valid, found $cnt...\n") if ($dbg_fa04);

    $lnn = 0;
    $vcnt = 0;
    my $hid = '';
    for ($i = 0; $i < $nav_cnt; $i++) {
        $line = trimall($nav_lines[$i]);
        $lnn++;
        # 810 Version - data cycle 2009.12, build 20091080, metadata NavXP810
        if ($line =~ /\s+Version\s+/i) {
            if ($line =~ /\s*(\n+)\s+Version\s+/) {
                $nav_file_version = $1;
            }
            $typ = length($line) > 80 ? substr($line,0,80) : $line;
            prt( "[v2] NAVAID: $typ\n" ) if (VERB2() && !$dnvers);
            $i++;
            last;
        }
    }
    my $skipcnt = 0;
    for (; $i < $nav_cnt; $i++) {
        $line = trimall($nav_lines[$i]);
        $len = length($line);
        $lnn++;
        next if ($len == 0);
        my ($tmp);
		###prt("$line\n");
		@arr = split(/\s+/,$line);
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
		$nc = scalar @arr;
		$typ = $arr[0];
        # Check for type number in @navset, and set $actnav to name, like VOR, NDB, etc
        last if ($typ == 99);
        next if ($exclude_markers && (($typ == 7)||($typ == 8)||($typ == 9)));
        next if ($exclude_gs_ils && ($typ == 6));
		if ( is_valid_nav($typ) ) {
			$vcnt++;
			$nlat = $arr[1];
			$nlon = $arr[2];
			$nalt = $arr[3];
			$nfrq = $arr[4];
			$nrng = $arr[5];
			$nfrq2 = $arr[6];
			$nid = $arr[7];
			$name = '';
			for (my $i = 8; $i < $nc; $i++) {
				$name .= ' ' if length($name);
				$name .= $arr[$i];
			}
            $hid = "$typ:$nfrq:$nid";   # sort of a hash id for this item
			push(@navlist, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name]);
            # Using $nmaxlatd, $nmaxlond, check airports in @aptlist2;
			$off = near_an_airport( $nlat, $nlon, \$dist, \$az );
            $off = near_given_point( $nlat, $nlon, \$dist, \$az ) if (!$off);
			if ($off) {
				prt( "[02] $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name ($off)\n") if ($dbg_fa02);
                if ($ALLNAVS || VERB5() || !defined $nav_freqs{$nfrq}) {
                    #                0     1      2      3      4      5      6       7     8      9     10     11
	    			push(@navlist2, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az]);
                    $nav_freqs{$nfrq} = 1;
                    if (!defined $found_nav_hash{$hid}) {
                        $found_nav_hash{$hid} = [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az];
                    } elsif ($nid ne '----') {
                        prtw("WARNING: Found a nearby DUPLICATED has ID [$hid]\n");
                    }
                } else {
                    $skipcnt++;
                }
			}
        #} elsif ($line =~ /^\d+\s+Version\s+-\s+DAFIF\s+/) {
        #    my $ind = index($line,',');
        #    prt( "NAVAID: ".substr($line, 0, (($ind > 0) ? $ind : 50) )."\n" );   # 810 Version - DAFIF ...
		} else {
            #$typ = $line;
            $typ = length($line) > 80 ? substr($line,0,80) : $line;
            prtw("WARNING: What is this line? [$typ]???\n".
                "from $navdat file ...\n");
        }
	}
    ###############################################
    ### Have some NAVAIDS been found
    @near_list = @navlist2;  # keep the NEAR LIST
    $navs_found = scalar @navlist2;
    if ($tryharder && ($navs_found < $min_nav_aids)) {
        my $def_latd = $nmaxlatd;
        my $def_lond = $nmaxlond;
        my $def_dist = $max_range_km;
        while ($navs_found < $min_nav_aids) {
            $nmaxlatd += 0.1;
            $nmaxlond += 0.1;
            $max_range_km += 0.1;
            if ($usekmrange) {
                prt("Expanded to [$max_range_km] Km from $ac airport(s)...\n" ) if (VERB1());
            } else {
                prt("Expanded to [$nmaxlatd,$nmaxlond] from $ac airport(s)...\n" ) if (VERB1());
            }
            @navlist2 = (); # restart nearby list
            for ($i = $skip_version ; $i < $nav_cnt; $i++) {
                $line = trimall($nav_lines[$i]);
                $len = length($line);
                $lnn++;
                ##next if ($line =~ /\s+Version\s+/i);
                next if ($len == 0);
                @arr = split(/\s+/,$line);
                $nc = scalar @arr;
                $typ = $arr[0];
                last if ($typ == 99);
                next if ($exclude_markers && (($typ == 7)||($typ == 8)||($typ == 9)));
                next if ($exclude_gs_ils && ($typ == 6));
                # Check for type number in @navset, and set $actnav to name, like VOR, NDB, etc
                if ( is_valid_nav($typ) ) {
                    $nlat = $arr[1];
                    $nlon = $arr[2];
                    $nalt = $arr[3];
                    $nfrq = $arr[4];
                    $nrng = $arr[5];
                    $nfrq2 = $arr[6];
                    $nid = $arr[7];
                    $name = '';
                    for (my $i = 8; $i < $nc; $i++) {
                        $name .= ' ' if length($name);
                        $name .= $arr[$i];
                    }
                    $hid = "$typ:$nfrq:$nid";   # sort of a hash id for this item
                    # Using $nmaxlatd, $nmaxlond, check airports in @aptlist2;
                    $off = near_an_airport( $nlat, $nlon, \$dist, \$az );
                    if ($off) {
                        prt( "[02] $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name ($off)\n") if ($dbg_fa02);
                        if (VERB5() || !defined $nav_freqs{$nfrq}) {
                            push(@navlist2, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az]);
                            $nav_freqs{$nfrq} = 1;
                            if (!defined $found_nav_hash{$hid}) {
                                $found_nav_hash{$hid} = [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name, $off, $dist, $az];
                            }
                        } else {
                            $skipcnt++;
                        }
                    }
                }
            }
            $navs_found = scalar @navlist2;
        }
        if ($usekmrange) {
            prt("tryhard: Expanded to [$max_range_km] Km from $ac airport(s)...\n" ); # if (VERB1());
        } else {
            prt("tryhard: Expanded to [$nmaxlatd,$nmaxlond] from $ac airport(s)...\n" ); # if (VERB1());
        }
        $msg = "Found $navs_found nearby NAVAIDS, ";
        if ($usekmrange) {
            $msg .= "using distance $max_range_km Km...";
        } else {
            $msg .= "using difference $nmaxlatd, $nmaxlond...";
        }
        prt("$msg\n") if (VERB1());

        $nmaxlatd = $def_latd;
        $nmaxlond = $def_lond;
        $max_range_km = $def_dist;
    }
	prt("[v5] Done - Found $navs_found nearby NAVAIDS, of $vcnt searched...\n" ) if (VERB5());
}

# put least first
sub mycmp_ascend_n4 {
   if (${$a}[4] < ${$b}[4]) {
      return -1;
   }
   if (${$a}[4] > ${$b}[4]) {
      return 1;
   }
   return 0;
}

# put least first
sub mycmp_ascend {
   if (${$a}[0] < ${$b}[0]) {
      prt( "-[".${$a}[0]."] < [".${$b}[0]."]\n" ) if $verb3;
      return -1;
   }
   if (${$a}[0] > ${$b}[0]) {
      prt( "+[".${$a}[0]."] < [".${$b}[0]."]\n" ) if $verb3;
      return 1;
   }
   prt( "=[".${$a}[0]."] == [".${$b}[0]."]\n" ) if $verb3;
   return 0;
}

sub mycmp_decend {
   if (${$a}[0] < ${$b}[0]) {
      prt( "+[".${$a}[0]."] < [".${$b}[0]."]\n" ) if $verb3;
      return 1;
   }
   if (${$a}[0] > ${$b}[0]) {
      prt( "-[".${$a}[0]."] < [".${$b}[0]."]\n" ) if $verb3;
      return -1;
   }
   prt( "=[".${$a}[0]."] == [".${$b}[0]."]\n" ) if $verb3;
   return 0;
}

# 0=typ, 1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid, 8=name, 9=off, 10=dist, 11=az);
sub mycmp_decend_dist {
   return -1 if (${$a}[10] < ${$b}[10]);
   return 1 if (${$a}[10] > ${$b}[10]);
   return 0;
}
sub mycmp_decend_az {
   return -1 if (${$a}[11] < ${$b}[11]);
   return 1 if (${$a}[11] > ${$b}[11]);
   return 0;
}

# $dist = $aptlist2[$i][12];
#                 0      1      2      3      4      5   6  7  8  9      10     11    12     13   14        15
#push(@aptlist2, [$diff, $icao, $name, $alat, $alon, -1, 0, 0, 0, $icao, $name, $off, $dist, $az, \@runways,$aalt]);
sub mycmp_decend_ap_dist {
   return -1 if (${$a}[12] < ${$b}[12]);
   return 1 if (${$a}[12] > ${$b}[12]);
   return 0;
}


##############
### functions
sub trimall {	# version 20061127
	my ($ln) = shift;
	chomp $ln;			# remove CR (\n)
	$ln =~ s/\r$//;		# remove LF (\r)
	$ln =~ s/\t/ /g;	# TAB(s) to a SPACE
	while ($ln =~ /\s\s/) {
		$ln =~ s/\s\s/ /g;	# all double space to SINGLE
	}
	while ($ln =~ /^\s/) {
		$ln = substr($ln,1); # remove all LEADING space
	}
	while ($ln =~ /\s$/) {
		$ln = substr($ln,0, length($ln) - 1); # remove all TRAILING space
	}
	return $ln;
}

# 12/12/2008 - Additional distance calculations
# from 'signs' perl script
# Melchior FRANZ <mfranz # aon : at>
# $Id: signs,v 1.37 2005/06/01 15:53:00 m Exp $

# sub ll2xyz($$) {
sub ll2xyz {
	my $lon = (shift) * $D2R;
	my $lat = (shift) * $D2R;
	my $cosphi = cos $lat;
	my $di = $cosphi * cos $lon;
	my $dj = $cosphi * sin $lon;
	my $dk = sin $lat;
	return ($di, $dj, $dk);
}


# sub xyz2ll($$$) {
sub xyz2ll {
	my ($di, $dj, $dk) = @_;
	my $aux = $di * $di + $dj * $dj;
	my $lat = atan2($dk, sqrt $aux) * $R2D;
	my $lon = atan2($dj, $di) * $R2D;
	return ($lon, $lat);
}

# sub coord_dist_sq($$$$$$) {
sub coord_dist_sq {
	my ($xa, $ya, $za, $xb, $yb, $zb) = @_;
	my $x = $xb - $xa;
	my $y = $yb - $ya;
	my $z = $zb - $za;
	return $x * $x + $y * $y + $z * $z;
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
    return \%h;
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
            $flat  = ' '.$flat while (length($flat) < $g_maxnlatl);
            $flon  = ' '.$flon while (length($flon) < $g_maxnlonl);
            prt("FIX: $key $flat $flon\n");
            $cnt++;
        }
    }
    return $cnt;
}

sub get_awy_sample() {
    my $stg = <<EOF;
I
640 Version - data cycle 2009.12, build 20091080, metadata AwyXP700.  Copyright (c) 2009, Robin A. Peel (robin\@xsquawkbox.net). 
ASKER  38.273889  038.774722 ERH    38.463333  038.112222 1 115 285 W73
ASKER  38.273889  038.774722 GAZ    36.950278  037.473333 1 255 285 W701
ASKIK  50.052778  008.533611 DONIS  49.930556  008.859444 1 120 240 Z74
ASKIK  50.052778  008.533611 FFM    50.053742  008.637092 1 050 240 L984
ASKIK  50.052778  008.533611 MODAU  49.815000  008.811944 1 050 240 T840
ASKIK  50.052778  008.533611 RUDUS  50.047500  008.078333 1 050 240 L984
ASKIK  50.052778  008.533611 TABUM  50.290833  008.405000 1 050 240 T840
ASKIL  54.503333  031.086667 KOSAN  54.775000  029.278333 1 100 190 L736
99
EOF
    return $stg;
}

sub show_awy_item($$$$$$$$$$) {
    my ($name,$from,$flat,$flon,$to,$tlat,$tlon,$cat,$bfl,$efl) = @_;
    my ($sg_az1,$sg_az2,$sg_dist);
    my $ret = fg_geo_inverse_wgs_84($flat, $flon, $tlat, $tlon, \$sg_az1, \$sg_az2, \$sg_dist);
    my $sg_km = $sg_dist / 1000;
    my $sg_im = int($sg_dist);
    my $sg_ikm = int($sg_km + 0.5);
    my $sg_idegs = int($sg_az1 + 0.5);
    $sg_idegs = " $sg_idegs" while (length($sg_idegs) < 3);
    $sg_ikm = " $sg_ikm" while (length($sg_ikm) < 3);

    # begin bulding a display line
    my $line = "$name ";
    my $len = 6+1;
    my $max = 0;
    $line .= ' ' while (length($line) < $len);

    $len += 6+1;
    $line .= "$from ";
    $line .= ' ' while (length($line) < $len);

    $max = $g_maxnlatl - (length($line) - $len);
    $flat = ' '.$flat while (length($flat) < $max);
    $len += $g_maxnlatl+1;
    $line .= "$flat ";
    $line .= ' ' while (length($line) < $len);

    $max = $g_maxnlonl - (length($line) - $len);
    $flon = ' '.$flon while (length($flon) < $max);
    $len += $g_maxnlatl+1;
    $line .= "$flon ";
    $line .= ' ' while (length($line) < $len);

    $line .= "$to ";
    $len += 6 + 1;
    $line .= ' ' while (length($line) < $len);
    $max = $g_maxnlatl - (length($line) - $len);
    $tlat = ' '.$tlat while (length($tlat) < $max);
    $len += $g_maxnlatl+1;
    $line .= "$tlat ";
    $line .= ' ' while (length($line) < $len);

    $max = $g_maxnlonl - (length($line) - $len);
    $tlon = ' '.$tlon while (length($tlon) < $max);
    $len += $g_maxnlatl+1;
    $line .= "$tlon ";
    $line .= ' ' while (length($line) < $len);

    prt("AWY: $line (on $sg_idegs for $sg_ikm km).\n");
}

# from airways.cxx
# in >> identStart;
# if (identStart == "99") { break; }
# in >> latStart >> lonStart >> identEnd >> latEnd >> lonEnd >> type >> base >> top >> name;
# // type = 1; low-altitude
# // type = 2; high-altitude
# Network* net = (type == 1) ? static_lowLevel : static_highLevel;
sub load_awy_hash($) {
    my ($raa) = @_;
    my $max = scalar @{$raa};
    my ($line,$len,@arr,$cnt,$typ,$flat,$flon,$fname,$name,$key);
    my ($tlat,$tlon,$from,$to,$hadver);
    my ($cat,$bfl,$efl,$ra,$lnn);
    my %ids = ();
    $lnn = 0;
    $hadver = 0;
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
            # 0      1          2          3      4          5          6 7   8   9
            # ASKIK  50.052778  008.533611 RUDUS  50.047500  008.078333 1 050 240 L984
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
            $ids{$name} = [ ] if (!defined $ids{$name});
            $ra = $ids{$name};
            push(@{$ra}, [ $from, $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl ]);
        }
    }
    return \%ids;
}


# from airways.cxx
# in >> identStart;
# if (identStart == "99") { break; }
# in >> latStart >> lonStart >> identEnd >> latEnd >> lonEnd >> type >> base >> top >> name;
# // type = 1; low-altitude
# // type = 2; high-altitude
# Network* net = (type == 1) ? static_lowLevel : static_highLevel;
sub search_awy_file($) {
    my ($name) = @_;
    my ($from,$flat,$flon,$rll,$key);
    my $raa = load_awy_file();
    # my $raa = load_awy_file();
    my $tah = load_awy_hash($raa);
    my $cnt = scalar keys %{$tah};
    my ($acnt,$to,$tlat,$tlon,$cat,$bfl,$efl,$id,$i);
    prt("[v2] Searching $cnt airway records for [$name]\n") if (VERB2());
    $cnt = 0;
    foreach $key (keys %{$tah}) {
        if ($key =~ /$name/) {
            $rll = ${$tah}{$key};
            $acnt = scalar @{$rll};
            for ($i = 0; $i < $acnt; $i++) {
                ##               0      1      2      3    4      5      6     7     8
                #$ids{$name} = [ $from, $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl ];
                $from = ${$rll}[$i][0];
                $flat = ${$rll}[$i][1];
                $flon = ${$rll}[$i][2];
                $to   = ${$rll}[$i][3];
                $tlat = ${$rll}[$i][4];
                $tlon = ${$rll}[$i][5];
                # 1 115 285 W73 
                $cat  = ${$rll}[$i][6]; # category 1 = low, 2 = high
                $bfl  = ${$rll}[$i][7]; # begin flight level
                $efl  = ${$rll}[$i][8]; # end flight level
                show_awy_item($key,$from,$flat,$flon,$to,$tlat,$tlon,$cat,$bfl,$efl);
                $cnt++;
            }
        }
    }
    return $cnt;
}

sub show_awy_array($$) {
    my ($name,$ra) = @_;
    #my $tmp = ref($ra);
    #prt("Got ref [$tmp]\n");
    ##               0      1      2      3    4      5      6     7     8
    #$ids{$name} = [ $from, $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl ];
    my $from = ${$ra}[0];
    my $flat = ${$ra}[1];
    my $flon = ${$ra}[2];
    my $to   = ${$ra}[3];
    my $tlat = ${$ra}[4];
    my $tlon = ${$ra}[5];
    # 1 115 285 W73 
    my $cat  = ${$ra}[6]; # category 1 = low, 2 = high
    my $bfl  = ${$ra}[7]; # begin flight level
    my $efl  = ${$ra}[8]; # end flight level
    show_awy_item($name,$from,$flat,$flon,$to,$tlat,$tlon,$cat,$bfl,$efl);
}

sub list_awy_file() {
    my $raa = load_awy_file();
    my $tah = load_awy_hash($raa);
    my $cnt = scalar keys %{$tah};
    prt("Listing $cnt airway records..\n"); # if (VERB2());
    my ($name,$val,$acnt,$i,$ra,$tmp);
    foreach $name (sort keys %{$tah}) {
        $val = ${$tah}{$name};
        $acnt = scalar @{$val};
        for ($i = 0; $i < $acnt; $i++) {
            $ra = ${$val}[$i];
            $tmp = ref($ra);
            # prt("Extracted a [$tmp]\n");
            show_awy_array($name,$ra);
        }
    }
}

sub load_awy_hash2($) {
    my ($raa) = @_;
    my $max = scalar @{$raa};
    my ($line,$len,@arr,$cnt,$typ,$flat,$flon,$fname,$name,$key);
    my ($tlat,$tlon,$from,$to,$hadver);
    my ($cat,$bfl,$efl,$ra,$lnn);
    my %h = ();
    $lnn = 0;
    $hadver = 0;
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
            # 0      1          2          3      4          5          6 7   8   9
            # ASKIK  50.052778  008.533611 RUDUS  50.047500  008.078333 1 050 240 L984
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
            $h{$from} = [ ] if (!defined $h{$from});
            $ra = $h{$from};
            #              0      1      2    3      4      5     6     7     8
            push(@{$ra}, [ $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl, $name ]);
            $h{$to} = [ ] if (!defined $h{$to});
            $ra = $h{$to};
            push(@{$ra}, [ $tlat, $tlon, $from, $flat, $flon, $cat, $bfl, $efl, $name ]);
        }
    }
    return \%h;
}

sub search_awy_file_prev($) {
    my ($name) = @_;
    my ($flat,$flon,$rll,$key);
    my $raa = load_awy_file();
    # my $raa = load_awy_file();
    my $tah = load_awy_hash2($raa);
    my $cnt = scalar keys %{$tah};
    my ($acnt,$to,$tlat,$tlon,$cat,$bfl,$efl,$id,$i);
    my ($ret,$sg_az1,$sg_az2,$sg_dist);
    prt("[v2] Searching $cnt airway records for [$name]\n") if (VERB2());
    $cnt = 0;
    foreach $key (keys %{$tah}) {
        if ($key =~ /$name/) {
            $rll = ${$tah}{$key};
            $acnt = scalar @{$rll};
            for ($i = 0; $i < $acnt; $i++) {
                $flat = ${$rll}[$i][0];
                $flon = ${$rll}[$i][1];
                $to   = ${$rll}[$i][2];
                $tlat = ${$rll}[$i][3];
                $tlon = ${$rll}[$i][4];
                # 1 115 285 W73 
                $cat  = ${$rll}[$i][5]; # category 1 = low, 2 = high
                $bfl  = ${$rll}[$i][6]; # begin flight level
                $efl  = ${$rll}[$i][7]; # end flight level
                $id   = ${$rll}[$i][8]; # airway NAME
                $ret = fg_geo_inverse_wgs_84($flat, $flon, $tlat, $tlon, \$sg_az1, \$sg_az2, \$sg_dist);
                my $sg_km = $sg_dist / 1000;
                my $sg_im = int($sg_dist);
                my $sg_ikm = int($sg_km + 0.5);
                my $sg_idegs = int($sg_az1 + 0.5);
                $sg_idegs = " $sg_idegs" while (length($sg_idegs) < 3);
                $sg_ikm = " $sg_ikm" while (length($sg_ikm) < 3);
                $flat = ' '.$flat while (length($flat) < $g_maxnlatl);
                $flon = ' '.$flon while (length($flon) < $g_maxnlonl);
                $to .= ' ' while (length($to) < 6);
                $tlat = ' '.$tlat while (length($tlat) < $g_maxnlatl);
                $tlon = ' '.$tlon while (length($tlon) < $g_maxnlonl);
                prt("AWY: $key $flat $flon $to $tlat $tlon on $sg_az1 ($sg_idegs at $sg_ikm km).\n");
                $cnt++;
            }
        }
    }
    return $cnt;
}


sub do_looks_like_fix() {
    # looks like a FIX...
    my $cnt = 0;
    prt("ICAO has len greater than 4, so assume a FIX... [$apticao]\n");
    $g_fix_name = $apticao;
    if (search_fix_file($g_fix_name)) {
        prt("Found the above fix...\n");
        $cnt++;
    }
    if (search_awy_file($g_fix_name)) {
        prt("Found the above airways...\n");
        $cnt++;
    }
    if ($cnt) {
        prt("Hope your search for $apticao is one of these ;=)) Or try another name...\n");
    } else {
        prt("ICAO $apticao NOT found ;=(( Try another name...\n");
    }
    pgm_exit(0,"");
}

sub mycmp_ascend_n3 {
   return -1 if (${$a}[3] < ${$b}[3]);
   return 1 if (${$a}[3] > ${$b}[3]);
   return 0;
}

sub add_sidstar() {
    my $rfa = load_fix_file();
    # 39.955873 -081.753000 ZZV65
    #99
    my $max = scalar @{$rfa};
    my $max_show = 30;
    prt("Processing $max fix lines... closest to $icao_lat,$icao_lon\n");
    my ($line,@arr,$lat,$lon,$nam,$res,$s,$az1,$az2,$dist);
    my $min_dist = 40000;   # 40 km
    my @nf = ();
    my ($max_lat,$max_lon,$min_lat,$min_lon);
    my $xg = '';
    $max_lat = -400;
    $min_lat = 400;
    $max_lon = -400;
    $min_lon = 400;
    foreach $line (@{$rfa}) {
        chomp $line;
        $line = trim_all($line);
        @arr = split(/\s+/,$line);
        next if (scalar @arr != 3);
        $lat = $arr[0];
        $lon = $arr[1];
        $nam = $arr[2];
        $res = fg_geo_inverse_wgs_84( $icao_lat,$icao_lon,$lat,$lon,\$az1,\$az2,\$s);
        next if ($s > $min_dist);
        #         0    1    2    3
        push(@nf,[$lat,$lon,$nam,$s]);
        $xg .= "anno $lon $lat $nam\n";
        $max_lat = $lat if ($lat > $max_lat);
        $min_lat = $lat if ($lat < $min_lat);
        $max_lon = $lon if ($lon > $max_lon);
        $min_lon = $lon if ($lon < $min_lon);
    }
    $res = scalar @nf;
    prt("From $max got $res within 40 km... $max_lat,$max_lon,$min_lat,$min_lon\n");
    $xg .= "color gray\n";
    $xg .= "$min_lon $min_lat\n";
    $xg .= "$min_lon $max_lat\n";
    $xg .= "$max_lon $max_lat\n";
    $xg .= "$max_lon $min_lat\n";
    $xg .= "$min_lon $min_lat\n";
    $xg .= "NEXT\n";
    $xg .= $apt_xg;;
    write2file($xg,$out_xg);
    prt("xg map witten to $out_xg\n");
    ############################################################
    ### just the closest
    @arr = sort mycmp_ascend_n3 @nf;
    my ($ra,$i);
    $res = $max_show if ($res > $max_show);
    # $s = int(meter_2_nm($s));
    $max_lat = -400;
    $min_lat = 400;
    $max_lon = -400;
    $min_lon = 400;
    $xg = '';
    for ($i = 0; $i < $res; $i++) {
        $ra = $arr[$i];
        $lat = ${$ra}[0];
        $lon = ${$ra}[1];
        $nam = ${$ra}[2];
        $s   = ${$ra}[3];
        prt(join(" ",@{$ra})."\n");
        $xg .= "anno $lon $lat $nam\n";
        $max_lat = $lat if ($lat > $max_lat);
        $min_lat = $lat if ($lat < $min_lat);
        $max_lon = $lon if ($lon > $max_lon);
        $min_lon = $lon if ($lon < $min_lon);
    }
    $xg .= "color gray\n";
    $xg .= "$min_lon $min_lat\n";
    $xg .= "$min_lon $max_lat\n";
    $xg .= "$max_lon $max_lat\n";
    $xg .= "$max_lon $min_lat\n";
    $xg .= "$min_lon $min_lat\n";
    $xg .= "NEXT\n";
    $xg .= $apt_xg;;
    write2file($xg,$out_xg2);
    prt("xg map witten to $out_xg2\n");

}

#======================================================
### MAIN ###
# ==========

#search_fix_file($g_fix_name);
#pgm_exit(1,"");
#list_awy_file();
#$loadlog = 1;
#pgm_exit(1,"");

parse_args(@ARGV);	# collect command line arguments ...

prt( "$pgmname ... Hello, World ... ".scalar localtime(time())."\n" ) if (VERB9());

if ($SRCHICAO && (length($apticao) > 4)) {
    do_looks_like_fix();
}

load_apt_data();

set_average_apt_latlon();

#my @aptsort = sort mycmp_ascend @aptlist;
if ( show_airports_found($max_cnt) || $SRCHONLL ) {
    if ($SHOWNAVS) {
        search_nav();
        show_navaids_found();
        show_airports_found($max_cnt) if (VERB9());
    }
    show_scenery_tiles();
} elsif ( $SHOWNAVS ) {
    prt("No airport found, so no show of nav's around it...\n");
    if ($SRCHICAO) {
        search_nav_name();
    }
}
add_sidstar() if ($gen_sidstar && $SRCHICAO && ($total_apts == 1));

my $elapsed = tv_interval ( $t0, [gettimeofday]);
prt( "Ran for $elapsed seconds ...\n" ) if (VERB5());
pgm_exit(0,"");

#######################################################
### HELP AND COMMAND LINE

sub give_help {
    prt( "\n");
	prt( "*** FLIGHTGEAR AIRPORT SEARCH UTILITY - $VERS ***\n" );
	prt( "Usage: $pgmname options\n" );
	prt( "Options: A ? anywhere for this help.\n" );
    prt( " --Anno          (-A) = Anno the XG(raph) output for airports. (def=".
        ($add_anno ? "On" : "Off") . ")\n");
    prt( " --bbox          (-b) = Output a bounding box for the airport.\n");
    prt( " --file <file>   (-f) = Load commands from this 'file' of commands...\n");
	prt( " -icao=$apticao           = Search using icao.\n" );
	prt( " -latlon=lat,lon      = Search using latitude, longitude.\n" );
	prt( " -lonlat=lon,lat      = Search using longitude, latitude.\n" );
	prt( " -maxout=$max_cnt            = Limit the airport output. A 0 for ALL.\n" );
	prt( " -maxll=$maxlatd,$maxlond       = Maximum difference, when searching ariports using lat,lon.\n" );
	prt( " -name=\"$aptname\"   = Search using airport name. (A -name=. would match all.)\n" );
	prt( " -navaids        (-n) = Show NAVAIDS around airport found, if any. -N show all. " );
    prt( "(Def=". ($SHOWNAVS ? "On" : "Off") . ")\n" );
	prt( " -nmaxll=$nmaxlatd,$nmaxlond      = Maximum difference, when searching NAVAID lat,lon.\n" );
	prt( " -aptdata=file        = Use a specific AIRPORT data file. (def=$aptdat ".
        ((-f $aptdat) ? 'ok' : 'NF!').")\n" );
	prt( " -navdata=file        = Use a specific NAVAID data file. (def=$navdat ".
        ((-f $navdat) ? 'ok' : 'NF!').")\n" );
    prt( " -range=$max_range_km             = Set Km range when checking for NAVAIDS.\n" );
    prt( " -r                   = Use above range ($max_range_km Km) for searching.\n" );
    prt( " --sidstar       (-s) = Attempt SID/STAR generation. Implies -n, and needs ICAO search.\n");
    prt( " -tryhard        (-t) = Expand search if no NAVAIDS found in range. " );
    prt( "(Def=". ($tryharder ? "On" : "Off") . ")\n" );
    prt( " --verbosity (-v[nn]) = Increase or set verbosity. (def=$verbosity)\n");
    prt( " --VOR           (-V) = List only VOR (+NDB)\n");
    prt( " --loadlog       (-l) = Load log at end of display.\n");
    if (!$new_x_opts) {
        prt( " --Xml           (-X) = Generate ICAO.threshold.xml file (def=".
            ($gen_threshold_xml ? "on" : "off").")\n");
    }
    prt( " --out <file>    (-o) = Write found information to file. (def=".
        (length($out_file) ? $out_file : "none").")\n");
    # prt( " --xg <file>     (-x) = Write airport xg file. Implies -A\n");
    prt( " --xg <file>     (-x) = Write airport xg file.\n");
    if ($new_x_opts) {
        prt(" --X???          (-X) = set xg output options...\n");
        prt("    A    = add_anno to circuit.\n");
        prt("    B    = Add bbox outline.\n");
        prt("    H500 = Use circuit height.\n");
        prt("    R/L  = add only R or L circuit.\n");
        prt("    B    = Add bbox outline.\n");
        prt("    X    = Output ICAO.threshold.xml output.\n");
    }
    prt( "When searching by lat,lon, use -H to not skip helipads.\n");
	mydie( "                                                         Happy Searching.\n" );
}

# Ensure argument exists, or die.
sub require_arg {
    my ($arg, @arglist) = @_;
    mydie( "ERROR: no argument given for option '$arg' ...\n" ) if ! @arglist;
}

sub local_strip_both_quotes($) {
    my $txt = shift;
    if ($txt =~ /^'(.+)'$/) {
        return $1;
    }
    if ($txt =~ /^"(.+)"$/) {
        return $1;
    }
    return '' if ($txt eq '""');
    return '' if ($txt eq "''");
    #prt("Stripping [$txt] FAILED\n");
    return $txt;
}


sub load_input_file($$) {
    my ($arg,$file) = @_;
    if (open INF, "<$file") {
        my @lines = <INF>;
        close INF;
        my @carr = ();
        my ($line,@arr,$tmp,$i);
        my $lncnt = scalar @lines;
        for ($i = 0; $i < $lncnt; $i++) {
            $line = $lines[$i];
            $line = trim_all($line);
            next if (length($line) == 0);
            next if ($line =~ /^\#/);
            # load CONTINUATION lines - ends in '\' back-slash
            while (($line =~ /\\$/)&&(($i+1) < $lncnt)) {
                $i++;
                $line =~ s/\\$//;
                $line .= trim_all($lines[$i]);
            }
            @arr = split(/\s/,$line);
            foreach $tmp (@arr) {
                $tmp = local_strip_both_quotes($tmp);
                push(@carr,$tmp);
            }
        }
        $in_input_file++;
        parse_args(@carr);
        $in_input_file--;
    } else {
        pgm_exit(1,"ERROR: Unable to 'open' file [$file]!\n")
    }
}

sub deal_with_verbosity($) {
    my ($rav) = @_;
    my ($arg,$sarg,$i,$cnt);
    $cnt = scalar @{$rav};
    #prt("Doing verbosity check of $cnt args...\n");
    for ($i = 0; $i < $cnt; $i++) {
        $arg = ${$rav}[$i];
        #prt("Checking [$arg]...\n");
        if ($arg =~ /^-/) {
            $sarg = substr($arg,1);
            $sarg = substr($sarg,1) while ($sarg =~ /^-/);
            if ($sarg =~ /^v/) {
                #prt("Got -v... [$arg]\n");
                if ($sarg =~ /^v.*(\d+)$/) {
                    $verbosity = $1;
                } else {
                    while ($sarg =~ /^v/i) {
                        $verbosity++;
                        $sarg = substr($sarg,1)
                    }
                }
                prt( "[v1] Set verbosity to $verbosity\n") if (VERB1());
            }

        }
    }
}

# set $SRCHICAO on/off
# set $SRCHONLL on/off
sub parse_args {
	my (@av) = @_;
	my (@arr,$arg,$sarg,$lcarg,$ch);
    my ($len,$i,$i2,$tmp);
    $arg = scalar @av;
    #prt("Deal with $arg command arguments...\n");
    deal_with_verbosity(\@av);
	while(@av) {
		$arg = $av[0]; # shift @av;
        $lcarg = lc($arg);
        $ch = substr($arg,0,1);
        $sarg = $arg;
        $sarg = substr($sarg,1) while ($sarg =~ /^-/);
		if ($arg =~ /\?/) {
			give_help();
        } elsif ($ch eq '-') {
            if ($sarg =~ /^v/) {
                # done verbosity
            } elsif ($sarg =~ /^A/) {
                $add_anno = 1;
                prt("[v1] Add xgraph anno output for airports.\n") if (VERB1());
            } elsif ($sarg =~ /^b/) {
                $add_bbox = 1;
                prt("[v1] Add bbox output for airports.\n") if (VERB1());
            } elsif ($sarg =~ /^f/) {
                require_arg(@av);
                shift @av;
                $sarg = $av[0];
                load_input_file($arg,$sarg);
            } elsif ($sarg =~ /^V/) {
                $vor_only = 1;
                prt( "[v1] Set VOR (NBD) ONLY flag\n") if (VERB1());
            } elsif (( $sarg =~ /^loadlog$/ )||($sarg =~ /^l$/)) {
                prt("[v1] Set load log at end of display.\n") if (VERB1());
                $loadlog = 1;
            ##########################################################
            } elsif ( $arg =~ /-icao=(.+)/i ) {
                # BY ICAO
                $apticao = $1;
                $SRCHICAO = 1;
                $SRCHONLL = 0;
                $SRCHNAME = 0;
                prt( "[v1] Set search using ICAO of [$apticao] ...\n" ) if (VERB1());
            ##########################################################
            } elsif ( $lcarg eq '-icao' ) {
                require_arg(@av);
                shift @av;
                $SRCHICAO = 1;
                $SRCHONLL = 0;
                $SRCHNAME = 0;
                $apticao = $av[0];
                prt( "[v1] Set search using ICAO of [$apticao] ...\n" ) if (VERB1());

            ##########################################################
            # BY LAT,LON
            } elsif ( $arg =~ /-latlon=(.+)/i ) {
                $SRCHICAO = 0;
                $SRCHONLL = 1;
                $SRCHNAME = 0;
                @arr = split(',', $1);
                if (scalar @arr == 2) {
                    $g_center_lat = $arr[0];
                    $g_center_lon = $arr[1];
                    prt( "[v1] Set search using LAT,LON of [".ctr_latlon_stg()."] ...\n" ) if (VERB1());
                } else {
                    # 17/08/2010 - assume lat and lon also split, and try harder
                    $g_center_lat = $arr[0];
                    require_arg(@av);
                    shift @av;
                    $g_center_lon = $av[0];
                    if (($g_center_lat =~ /^(\d|-|\+|\.)+$/) && ($g_center_lon =~ /^(\d|-|\+|\.)+$/)) {
                        prt( "[v1] Set search using LAT,LON of [".ctr_latlon_stg()."] ...\n" ) if (VERB1());
                    } else {
                        mydie( "ERROR: Failed to find lat,lon in [$arg] [".ctr_latlon_stg()."]...\n" );
                    }
                }
                $got_center_latlon = 1; # given *** CENTER OF WORLD *** position -latlon lat lon
            } elsif ( $lcarg eq '-latlon' ) {
                # set a center LAT,LON
                require_arg(@av);
                shift @av;
                $SRCHICAO = 0;
                $SRCHONLL = 1; # search using lat,lon input...
                $SRCHNAME = 0;
                @arr = split(',', $av[0]);
                if (scalar @arr == 2) {
                    $g_center_lat = $arr[0];
                    $g_center_lon = $arr[1];
                    prt( "[v1] Set search using LAT,LON of [".ctr_latlon_stg()."] ...\n" ) if (VERB1());
                } else {
                    # 17/08/2010 - assume lat and lon also split, and try harder
                    $g_center_lat = $arr[0];
                    require_arg(@av);
                    shift @av;
                    $g_center_lon = $av[0];
                    if (($g_center_lat =~ /^(\d|-|\+|\.)+$/) && ($g_center_lon =~ /^(\d|-|\+|\.)+$/)) {
                        prt( "[v1] Set search using LAT,LON of [".ctr_latlon_stg()."] ...\n" ) if (VERB1());
                    } else {
                        mydie( "ERROR: Failed to find lat,lon in [$arg] [".ctr_latlon_stg()."]...\n" );
                    }
                }
                $got_center_latlon = 1; # given *** CENTER OF WORLD *** position -latlon lat lon
            ##########################################################
            # BY LON,LAT
            } elsif ( $arg =~ /-lonlat=(.+)/i ) {
                $SRCHICAO = 0;
                $SRCHONLL = 1;
                $SRCHNAME = 0;
                @arr = split(',', $1);
                if (scalar @arr == 2) {
                    $g_center_lon = $arr[0];
                    $g_center_lat = $arr[1];
                    prt( "[v1] Set search using LAT,LON of [".ctr_latlon_stg()."] ...\n" ) if (VERB1());
                } else {
                    # 17/08/2010 - assume lat and lon also split, and try harder
                    $g_center_lon = $arr[0];
                    require_arg(@av);
                    shift @av;
                    $g_center_lat = $av[0];
                    if (($g_center_lat =~ /^(\d|-|\+|\.)+$/) && ($g_center_lon =~ /^(\d|-|\+|\.)+$/)) {
                        prt( "[v1] Set search using LAT,LON of [".ctr_latlon_stg()."] ...\n" ) if (VERB1());
                    } else {
                        mydie( "ERROR: Failed to find lat,lon in [$arg] [".ctr_latlon_stg()."]...\n" );
                    }
                }
                $got_center_latlon = 1; # given *** CENTER OF WORLD *** position -latlon lat lon
            } elsif ( $lcarg eq '-lonlat' ) {
                # set a center LON,LAT
                require_arg(@av);
                shift @av;
                $SRCHICAO = 0;
                $SRCHONLL = 1; # search using lat,lon input...
                $SRCHNAME = 0;
                @arr = split(',', $av[0]);
                if (scalar @arr == 2) {
                    $g_center_lon = $arr[0];
                    $g_center_lat = $arr[1];
                    prt( "[v1] Set search using LAT,LON of [".ctr_latlon_stg()."] ...\n" ) if (VERB1());
                } else {
                    # 17/08/2010 - assume lat and lon also split, and try harder
                    $g_center_lon = $arr[0];
                    require_arg(@av);
                    shift @av;
                    $g_center_lat = $av[0];
                    if (($g_center_lat =~ /^(\d|-|\+|\.)+$/) && ($g_center_lon =~ /^(\d|-|\+|\.)+$/)) {
                        prt( "[v1] Set search using LAT,LON of [".ctr_latlon_stg()."] ...\n" ) if (VERB1());
                    } else {
                        mydie( "ERROR: Failed to find lat,lon in [$arg] [".ctr_latlon_stg()."]...\n" );
                    }
                }
                $got_center_latlon = 1; # given *** CENTER OF WORLD *** position -latlon lat lon

            ##########################################################
            # By NAME
            } elsif ( $arg =~ /-name=(.+)/i ) {
                $aptname = $1;
                $SRCHICAO = 0;
                $SRCHONLL = 0;
                $SRCHNAME = 1;
                prt( "[v1] Set search using NAME of [$aptname] ...\n" ) if (VERB1());
            } elsif ( $lcarg eq '-name' ) {
                require_arg(@av);
                shift @av;
                $SRCHICAO = 0;
                $SRCHONLL = 0;
                $SRCHNAME = 1;
                $aptname = $av[0];
                prt( "[v1] Set search using NAME of [$aptname] ...\n" ) if (VERB1());
            } elsif ( $arg =~ /^-loadlog$/i ) {
                $loadlog = 1;
                prt( "[v1] Set load log into wordpad.\n" ) if (VERB1());
            } elsif ( $arg =~ /^-navaids$/i ) {
                $SHOWNAVS = 1;
                prt( "[v1] Set show NAVAIDS around airport, if any.\n" ) if (VERB1());
            } elsif ( $arg =~ /^-n$/i ) {
                $SHOWNAVS = 1;
                if ($arg =~ /^-N$/) {
                    $ALLNAVS = 1;
                    $vor_only = 0;
                    $exclude_markers = 0;   # (($typ == 7)||($typ == 8)||($typ == 9)));
                    $exclude_gs_ils = 0;    # ($typ == 6));
                    prt( "[v1] Set show ALL NAVAIDS around airport, if any.\n" ) if (VERB1());
                } else {
                    prt( "[v1] Set show NAVAIDS around airport, if any.\n" ) if (VERB1());
                }
            ##########################################################
            } elsif ( $sarg =~ /^s/ ) {
                $SHOWNAVS = 1;
                $gen_sidstar = 1;
                prt( "[v1] Attempt SID/STAR generation using fixes.\n" ) if (VERB1());
            ##########################################################
            } elsif ( $arg =~ /-maxll=(.+)/i ) {
                @arr = split(',', $1);
                if (scalar @arr == 2) {
                    $maxlatd = $arr[0];
                    $maxlond = $arr[1];
                    prt( "Search maximum difference LAT,LON of [$maxlatd,$maxlond] ...\n" ) if (VERB1());
                } else {
                    # 17/08/2010 - assume lat and lon also split, and try harder
                    $maxlatd = $arr[0];
                    require_arg(@av);
                    shift @av;
                    $maxlond = $av[0];
                    if (($maxlatd =~ /^(\d|-|\+|\.)+$/) && ($maxlond =~ /^(\d|-|\+|\.)+$/)) {
                        prt( "Search maximum difference LAT,LON of [$maxlatd,$maxlond] ...\n" ) if (VERB1());
                    } else {
                        mydie( "ERROR: Failed to find maximum lat,lon difference in [$arg] [$maxlatd,$maxlond]...\n" );
                    }
                }
            } elsif ( $lcarg eq '-maxll' ) {
                require_arg(@av);
                shift @av;
                @arr = split(',', $av[0]);
                if (scalar @arr == 2) {
                    $maxlatd = $arr[0];
                    $maxlond = $arr[1];
                    prt( "[v1] Set search maximum difference LAT,LON of [$maxlatd,$maxlond] ...\n" ) if (VERB1());
                } else {
                    # 17/08/2010 - assume lat and lon also split, and try harder
                    $maxlatd = $arr[0];
                    require_arg(@av);
                    shift @av;
                    $maxlond = $av[0];
                    if (($maxlatd =~ /^(\d|-|\+|\.)+$/) && ($maxlond =~ /^(\d|-|\+|\.)+$/)) {
                        prt( "[v1] Set search maximum difference LAT,LON of [$maxlatd,$maxlond] ...\n" ) if (VERB1());
                    } else {
                        mydie( "ERROR: Failed to find maximum lat,lon difference in [$arg] [$maxlatd,$maxlond]...\n" );
                    }
                }
            ##########################################################
            } elsif ( $arg =~ /-nmaxll=(.+)/i ) {
                @arr = split(',', $1);
                if (scalar @arr == 2) {
                    $nmaxlatd = $arr[0];
                    $nmaxlond = $arr[1];
                    prt( "[v1] Set search maximum NAV difference LAT,LON of [$nmaxlatd,$nmaxlond] ...\n" ) if (VERB1());
                } else {
                    # 17/08/2010 - assume lat and lon also split, and try harder
                    $nmaxlatd = $arr[0];
                    require_arg(@av);
                    shift @av;
                    $nmaxlond = $av[0];
                    if (($nmaxlatd =~ /^(\d|-|\+|\.)+$/) && ($nmaxlond =~ /^(\d|-|\+|\.)+$/)) {
                        prt( "[v1] Set search maximum NAV difference LAT,LON of [$nmaxlatd,$nmaxlond] ...\n" ) if (VERB1());
                    } else {
                        mydie( "ERROR: Failed to find maximum lat,lon NAV difference in [$arg] [$nmaxlatd,$nmaxlond]...\n" );
                    }
                }
            } elsif ( $lcarg eq '-nmaxll' ) {
                require_arg(@av);
                shift @av;
                @arr = split(',', $av[0]);
                if (scalar @arr == 2) {
                    $nmaxlatd = $arr[0];
                    $nmaxlond = $arr[1];
                    prt( "[v1] Set search maximum NAV difference LAT,LON of [$nmaxlatd,$nmaxlond] ...\n" ) if (VERB1());
                } else {
                    # 17/08/2010 - assume lat and lon also split, and try harder
                    $nmaxlatd = $arr[0];
                    require_arg(@av);
                    shift @av;
                    $nmaxlond = $av[0];
                    if (($nmaxlatd =~ /^(\d|-|\+|\.)+$/) && ($nmaxlond =~ /^(\d|-|\+|\.)+$/)) {
                        prt( "[v1] Set search maximum NAV difference LAT,LON of [$nmaxlatd,$nmaxlond] ...\n" ) if (VERB1());
                    } else {
                        mydie( "ERROR: Failed to find maximum lat,lon NAV difference in [$arg] [$nmaxlatd,$nmaxlond]...\n" );
                    }
                }
            ##########################################################
            } elsif ( $arg =~ /-aptdata=(.+)/i ) {
                $aptdat = $1;	# the airports data file
                prt( "[v1] Set using AIRPORT data file [$aptdat] ...\n" ) if (VERB1());
            } elsif ( $lcarg eq '-aptdata' ) {
                require_arg(@av);
                shift @av;
                $aptdat = $av[0];	# the airports data file
                prt( "[v1] Set using AIRPORT data file [$aptdat] ...\n" ) if (VERB1());
            } elsif ( $arg =~ /-navdata=(.+)/i ) {
                $navdat = $1;
                prt( "[v1] Set using NAVAID data file [$navdat] ...\n" ) if (VERB1());
            } elsif ( $lcarg eq '-navdata' ) {
                require_arg(@av);
                shift @av;
                $navdat = $av[0];
                prt( "[v1] Set Using NAVAID data file [$navdat] ...\n" ) if (VERB1());
            } elsif ( $arg =~ /-maxout=(.+)/i ) {
                $max_cnt = $1;
                prt( "[v1] Set AIRPORT output limited to $max_cnt. A zero (0), for no limit\n" ) if (VERB1());
            } elsif ( $lcarg eq '-maxout' ) {
                require_arg(@av);
                shift @av;
                $max_cnt = $av[0];
                prt( "[v1] Set AIRPORT output limited to $max_cnt. A zero (0), for no limit\n" ) if (VERB1());
            } elsif ( $arg =~ /-range=(.+)/i ) {
                $max_range_km = $1;
                # prt( "Set navaid search range $max_range_km Km. A zero (0), for no limit\n" ) if (VERB1());
                $usekmrange = 1;
                prt( "[v1] Set NAVAID search range $max_range_km Km.\n" ) if (VERB1());
            } elsif ( $lcarg eq '-range' ) {
                require_arg(@av);
                shift @av;
                $max_range_km = $av[0];
                #prt( "Navaid search using $max_range_km Km. A zero (0), for no limit\n" ) if (VERB1());
                $usekmrange = 1;
                prt( "[v1] Set NAVAID search range $max_range_km Km.\n" ) if (VERB1());
            } elsif ( $lcarg eq '-r' ) {
                $usekmrange = 1;
                prt( "[v1] Navaid search using $max_range_km Km.\n" ) if (VERB1());
            } elsif (( $lcarg eq '-tryhard' )||( $lcarg eq '-t' )) {
                $tryharder = 1;  # Expand the search for NAVAID, until at least 1 found
                prt( "[v1] Set NAVAID search 'tryharder'...\n" ) if (VERB1());
            } elsif ($sarg =~ /^X/) {
                if ($new_x_opts) {
                    # parse X opts, get past the '-X'
                    $sarg = substr($sarg,1);
                    $len = length($sarg);
                    if ($len) {
                        for ($i = 0; $i < $len; $i++) {
                            $i2 = $i + 1;
                            $ch = substr($sarg,$i,1);
                            if (uc($ch) eq 'A') {
                                $add_anno = 1;
                                prt("[v1] Add xgraph anno output for airports.\n") if (VERB1());
                            } elsif (uc($ch) eq 'R') {
                                $add_circuit = 1;
                            } elsif (uc($ch) eq 'L') {
                                $add_circuit = 2;
                            } elsif (uc($ch) eq 'B') {
                                # } elsif ($sarg =~ /^b/) {
                                $add_bbox = 1;
                                prt("[v1] Add bbox output for airports.\n") if (VERB1());
                            } elsif ((uc($ch) eq 'H')&&($i2 < $len)) {
                                $ch = substr($sarg,$i2,1);
                                if ($ch =~ /\d/) {
                                    # got a height to use - default 1000
                                    $tmp = substr($sarg,$i2);
                                    my $alt = int($tmp);
                                    if ($alt > 0) {
                                        # new circuit ***ALTITUDE***
                                        $stand_patt_alt = $alt;
                                        prt("[v1] Set stand alt for circuit to ' $stand_patt_alt`.\n") if (VERB1());
                                        $sarg = $tmp;
                                        $sarg =~ s/\d+//;
                                        $len = length($sarg);
                                    } else {
                                        pgm_exit(1,"Error: Unknown -XHxxxx option, '$ch', '$alt','$sarg',...\n");
                                    }
                                } else {
                                    pgm_exit(1,"Error: Unknown -XHnnn height option, '$ch'\n");
                                }
                            } elsif (uc($ch) eq 'X') {
                                $gen_threshold_xml = 1;
                                prt("[v1] Gen ICAO.thrshold.xml for airports.\n") if (VERB1());
                            } else {
                                pgm_exit(1,"Error: Unknown -Xxxxx option, '$ch'\n");
                            }
                        }
                    } else {
                        pgm_exit(1,"Error: -X must be followed by option\n");
                    }
                } else {
                    $gen_threshold_xml = 1;
                    prt( "[v1] Generate threshold xml for airport(s) found\n" ) if (VERB1());
                }
            } elsif ( $sarg =~ /^x/ ) {
                # set xg output for an airport
                require_arg(@av);
                shift @av;
                $sarg = $av[0];
                $xg_output = $sarg;
                ### $add_anno = 1;
                $add_xg = 1;
                prt( "[v1] Generate circuit xg $xg_output, for ap(s) found\n" ) if (VERB1());
            } elsif ($sarg =~ /^o/) {
                require_arg(@av);
                shift @av;
                $out_file = $av[0];
                prt( "[v1] Output found airports to $out_file\n" ) if (VERB1());
            } elsif ($sarg =~ /^H/) {
                $ex_helipads = 0;
                prt( "[v1] Set no Helepap skip if lat,lon search.\n" ) if (VERB1());
            } else {
                mydie( "ERROR: Unknown argument [$arg]. Try ? for HELP ...\n" );
            }
        } else {
            ##########################################################
            # ASSUME AN AIRPORT NAME UNLESS LENGTH 4 and is A-Z0-9 ONLY
            $SRCHICAO = 0;
            $SRCHONLL = 0;
            $SRCHNAME = 1;
            if ((length($arg) == 4)&&($arg =~ /^[A-Z0-9]+$/)) {
                # assume is an ICAO value
                # BY ICAO
                $apticao = $arg;
                $SRCHICAO = 1;
                $SRCHONLL = 0;
                $SRCHNAME = 0;
                prt( "[v1] Set search using ICAO of [$apticao] ...\n" ) if (VERB1());
            } else {
                $aptname = $arg;
                prt( "[v1] Search using NAME of [$aptname] ...\n" ) if (VERB1());
            }
        }
		shift @av;
	}

    if ( ! $in_input_file ) {
        # NOT in an INPUT file
        # *** ONLY FOR TESTING ***
        if ($test_name) {
            $SRCHICAO = 0;
            $SRCHONLL = 0;
            $SRCHNAME = 1;
            $SHOWNAVS = 1;
            $usekmrange = 1;
            $max_range_km = 5;
            $aptname = $def_name;
        } elsif ($test_ll) {
            $g_center_lat = $def_lat;
            $g_center_lon = $def_lon;
            # $maxlatd = 0.1;
            # $maxlond = 0.1;
            $SRCHICAO = 0;
            $SRCHONLL = 1;
            $SRCHNAME = 0;
        } elsif ($test_icao) {
            $SRCHICAO = 1;
            $SRCHONLL = 0;
            $SRCHNAME = 0;
            $SHOWNAVS = 1;
            $apticao = $def_icao;
            # now have $tryharder to expand this, if NO NAVAIDS found
            $tryharder = 1;
            $usekmrange = 1;
        }


        if ( ($SRCHICAO == 0) && ($SRCHONLL == 0) && ($SRCHNAME == 0) ) {
            prt( "ERROR: No valid command action found, like -\n" );
            prt( "By ICAO '-icao=KSFO', by LAT/LON '-latlon=21,-122', or '-name=something'!\n" );
            give_help();
        } elsif ($SRCHICAO) {
            prt("Searching for ICAO=$apticao\n");
        } elsif ($SRCHNAME) {
            prt("Searching for NAME=$aptname\n");
        } else {
            prt("Searching by lat,lon=$g_center_lat,$g_center_lon, spread $nmaxlatd,$nmaxlond degs\n");
        }
    }

}

sub get_810_spec() {
    my $txt = <<EOF;
from : http://data.x-plane.com/file_specs/XP%20APT1000%20Spec.pdf
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

Airport Line. eg '1 5355 1 0 KABQ Albuquerque Intl Sunport'
1	   - this as an airport header line. 16 is a seaplane/floatplane base, 17 a heliport.
5355   - Airport elevation (in feet above MSL).  
1	   - Airport has a control tower (1=yes, 0=no).
0	   - Display X-Plane's default airport buildings (1=yes, 0=no).
KABQ   - Identifying code for the airport (the ICAO code, if one exists).
Albuquerque Intl Sunport - Airport name.

Runway or taxiway at an airport. 
10          Identifies this as a data line for a runway or taxiway segment. 
35.044209   Latitude (in decimal degrees) of runway or taxiway segment center. 
-106.598557 Longitude (in decimal degrees) of runway or taxiway segment center.  
08x         Runway number (eg 25x or 24R).  If there is no runway suffix (eg. L, R, C or "S"), 
            then an x is used.  xxx identifies the entry as a taxiway.  
            Helipads at the same airport are numbered sequentially as "H1x", H2x".  
90.439      True (not magnetic) heading of the runway in degrees.  Must be between 0.00 and 360.00.   
13749       Runway or taxiway segment length in feet. 
1000.0000   Length of displaced threshold (1,000 feet) for runway 08 and for the reciprocal runway 26 (0 feet).  
            The length of the reciprocal runway's displaced threshold is expressed as the fractional part of 
            this number.  Take the runway 26 displaced threshold length  (in feet) and divide it by 10,000, 
            then add it to the displaced threshold length for runway 08.  For example, for displaced threshold 
            lengths of 543 feet and 1234 feet, the code would be 543.1234.
            Note that the displaced threshold length is included in the overall runway length but that the 
            stopway length is excluded from the overall runway length.  This code should be 0.0000 for 
            taxiway segments. FYI, the displaced threshold is usually marked (in the real world) with 
            long white arrows pointing toward the threshold.  The displaced threshold is not available 
            for use by aeroplanes landing, but may be used for take-off (in practice, if you use these 
            last few feet of the runway for take-off, you are probably in serious trouble!). 
0.1000      Length of stopway/blastpad/over-run at the approach end of runway 08 (0 feet) and for 
            runway 26 (1,000 feet), using the same coding structure defined above.  FYI, in the real world 
            the stopway/blastpad/over-run is usually marked with large yellow chevrons, and aeroplane 
            movements are not permitted. 
150         Runway or taxiway segment width in feet. 
252231      Runway or taxiway segment lighting codes. The first three digits ("252") define the lighting 
            for the runway as seen when approached from the direction implied by the runway number (08 in our example).
            The  final  three ("231") define the lighting for the runway as seen when approached from the 
            opposite end (26 in our example). 
            In order, these codes represent:
            Runway end A (08):  Visual approach path (VASI / PAPI etc.) lighting.  Here, code 2 corresponds to a VASI.
            Runway end A (08):  Runway lighting. Here, code 5 corresponds to TDZ lighting, which also implies centre-line 
            lighting, REIL and edge lighting.
            Runway end A (08):  Approach lighting.  Here, code 2 corresponds to SSALS.
            Other runway end (26):  Visual approach path (VASI / PAPI etc.) lighting. Here, code 2 corresponds to a VASI.
            Other runway end (26):  Runway lighting. Here, code 3 corresponds to REIL, which also implies edge lighting.
            Other runway end (26):  Approach lighting. Here, code 1 implies  no approach lighting.
02          Runway or taxiway surface code for the runway or taxiway segment.  The leading zero is optional - but 
            I always use it to keep all the columns neatly lined up. 
0           Runway shoulder code. These are only available in file version 701 and later. Here, code 0 implies 
            that there is no runway shoulder. 
3           Runway markings (the white painted markings on the surface of the runway.  Here, code 3 implies precision runway 
            markings (ie. there is an associated precision approach for the runway, either an ILS or MLS). 
0.25        Runway smoothness. Used to cause bumps when taxying or rolling along the runway in X-Plane.  It is on a scale of 
            0.0 to 1.0, with 0.0 being very smooth, and 1.0 being very, very rough.  X-Plane determines a baseline 
            smoothness based upon the runway surface type, and then uses this factor to determine the 'quality' 
            of the runway surface.  The default value is 0.25. 
1           Runway has 'distance remaining' signs (0=no signs, 1=show signs).  These are the white letters on a 
            black background on little illuminated signs along a runway, indicating the number of thousands of 
            feet of usable runway that remain.  They are inappropriate at small airports or on most dirt, 
            gravel or grass runways. 
0300.0350   NEW for file version 810:  Visual glideslope angle for the VASI or PAPI at each end of the 
            runway (3.00 degrees for runway 08 and 3.50 degrees for runway 26).  The angle for runway 08 
            is the whole part of this number divided by 100 (so "0300" becomes 3.00 degrees) and the angle for 
            the reciprocal runway (26) is the fractional part of this number multiplied by 100 (so "0.0350" 
            becomes 3.50 degrees).  This data is required for runways, but is NOT necessary for taxiways. 

# FOR Version 1000
Runway line
#   0   1     2 3 4    5 6 7 8   9            10            11    12   13 14 15 16 17  18           19           20     21   22 23 24 25
EG: 100 29.87 3 0 0.00 0 0 0 16  -24.20505300 151.89156100  0.00  0.00 1  0  0  0  34  -24.19732300 151.88585300 0.00   0.00 1  0  0  0
OR: 100 29.87 1 0 0.15 0 2 1 13L 47.53801700  -122.30746100 73.15 0.00 2  0  0  1  31R 47.52919200 -122.30000000 110.95 0.00 2  0  0  1
Land Runway
0  - 100 - Row code for a land runway (the most common) 100
1  - 29.87 - Width of runway in metres Two decimal places recommended. Must be >= 1.00
2  - 3 - Code defining the surface type (concrete, asphalt, etc) Integer value for a Surface Type Code
3  - 0 - Code defining a runway shoulder surface type 0=no shoulder, 1=asphalt shoulder, 2=concrete shoulder
4  - 0.15 - Runway smoothness (not used by X-Plane yet) 0.00 (smooth) to 1.00 (very rough). Default is 0.25
5  - 0 - Runway centre-line lights 0=no centerline lights, 1=centre line lights
6  - 0 - Runway edge lighting (also implies threshold lights) 0=no edge lights, 2=medium intensity edge lights
7  - 1 - Auto-generate distance-remaining signs (turn off if created manually) 0=no auto signs, 1=auto-generate signs

The following fields are repeated for each end of the runway

8  - 13L - Runway number (eg. 31R, 02). Leading zeros are required. Two to three characters. Valid suffixes: L, R or C (or blank)
9  - 47.53801700 - Latitude of runway threshold (on runway centerline) in decimal degrees Eight decimal places supported
10 - -122.30746100 - Longitude of runway threshold (on runway centerline) in decimal degrees Eight decimal places supported
11 - 73.15 - Length of displaced threshold in metres (this is included in implied runway length) Two decimal places (metres). Default is 0.00
12 - 0.00 - Length of overrun/blast-pad in metres (not included in implied runway length) Two decimal places (metres). Default is 0.00
13 - 2 - Code for runway markings (Visual, non-precision, precision) Integer value for Runway Marking Code
14 - 0 - Code for approach lighting for this runway end Integer value for Approach Lighting Code
15 - 0 - Flag for runway touchdown zone (TDZ) lighting 0=no TDZ lighting, 1=TDZ lighting
16 - 1 - Code for Runway End Identifier Lights (REIL) 0=no REIL, 1=omni-directional REIL, 2=unidirectional REIL

17 - 31R
18 - 47.52919200
19 - -122.30000000
20 - 110.95 
21 - 0.00 
22 - 2
23 - 0
24 - 0
25 - 1

Startup locations Example Usage 
15          Identifies this as a data line for an airport startup location (code 15).  Multiple startup 
            locations are allowed as separate data lines.  
35.047215   Latitude (in decimal degrees) of the startup location.   
-106.618576 Longitude (in decimal degrees) of the or startup location. 
0.00        True heading of the aeroplane in decimal degrees when placed at the startup location. 
Gate B1 (American Airlines) Name of a startup location (used in X-Plane 7.10 and later).
 
Tower viewpoints Example Usage 
14          Identifies this as a data line for a tower viewpoint (code 14).Only a single tower viewpoint is permitted. 
35.047005   Latitude (in decimal degrees) of the viewpoint. 
-106.608162 Longitude (in decimal degrees) of the viewpoint. 
100         Height (in feet) above ground level of viewpoint. 
1           Flag to indicate if a control tower object should be drawn at this location in X-Plane.  0=no tower, 1=draw tower. 
Tower viewpoint Name of this viewpoint 

Airport light beacons Example Usage 
18          Identifies this as a data line for an airport light beacon (code 18).  Note that if custom data 
            is not defined, then appropriate data will be generated automatically and included in apt.dat.  
            The light beacon types available (see list below) are in accordance with the US AM (Aeronautical 
            Information Manual) - other types may be added to cater for other light beacons used in other countries. 
35.045031   Latitude (in decimal degrees) of the light beacon. 
-106.598549 Longitude (in decimal degrees) of the light beacon. 
1           Identifies the colours of the light beacon.  Here code 1 implies a standard white-green flashing light.  
            Options are:
            Code 1: white-green flashing light (land airport).
            Code 2: white-yellow flashing light (seaplane base).
            Code 3: green-yellow-white flashing light (heliports).
            Code 4: white-white-green flashing light (military field).
            Code 5: white strobe light.
            Code 0: no beacon (can be used at 'closed' airports).  I suggest you use a dummy lat/lon based upon 
            one of the airport's runways.
BCN         Name for this light beacon (not used by X-Plane, so can be abbreviated to save file space).  

Airport windsocks Example Usage 
19          Identifies this row as an airport windsock (code 19). Note that: 
            If custom data is not defined, then appropriate data will be generated automatically by may data 
            export algorithms and included in apt.dat alongside the threshold of each runway.
            If at least one windsock is explicitly defined at an airport, then no 'automatic' windsocks will 
            be generated at that airport. Multiple windsocks are allowed.
            If you do not want any windsocks at an airport, then let me know in an e-mail and I will 
            suppress the generation of all automatic windsocks at that airport.
35.045176   Latitude (in decimal degrees) of the airport windsock.   
-106.621581 Longitude (in decimal degrees) of the airport windsock. 
1           Windsock lighting (1=illuminated, 0=not illuminated). 
WS          Name for this windsock (not used by X-Plane, so can be abbreviated to save file space). 

ATC frequencies Example Usage 
53          Identifies this as an airport ATC frequency line. Codes in the 50 - 59 range are used to identity 
            different ATC types. 
12190       Airport ATC frequency, in Megahertz multiplied by 100 (ie. 121.90 MHz in this example). 
GND         Name of the ATC frequency.  This is often an abbreviation (such as GND for "Ground"). 

=====================================
Threshold XML format
<?xml version="1.0"?>
<PropertyList>
  <runway>
    <threshold>
      <lon>-107.548332</lon>
      <lat>53.3667557256793</lat>
      <rwy>16</rwy>
      <hdg-deg>180.00</hdg-deg>
      <displ-m>0</displ-m>
      <stopw-m>0</stopw-m>
    </threshold>
    <threshold>
      <lon>-107.548331146226</lon>
      <lat>53.3598982743207</lat>
      <rwy>34</rwy>
      <hdg-deg>0.00</hdg-deg>
      <displ-m>0</displ-m>
      <stopw-m>0</stopw-m>
    </threshold>
  </runway>
</PropertyList>

fix.dat format
I
600 Version - data cycle 2009.12, build 20091080, metadata FixXP700. 

 00.000000  000.000000 0000E
 00.000000 -010.000000 0010N
...
 39.974122 -081.581098 ZZV14
 40.190260 -081.864151 ZZV15
 39.955873 -081.753000 ZZV65
99

awy.dat format
I
640 Version - data cycle 2009.12, build 20091080, metadata AwyXP700.  

00MKK  22.528056 -156.170961 BITTA  23.528031 -155.478836 1 012 460 R464
00MKK  22.528056 -156.170961 CKH99  22.316668 -156.341660 1 012 460 R464
...
ZLS    23.580556 -075.263889 ZSJ    24.061561 -074.534811 2 030 600 BR2L
ZMH    26.511111 -077.076944 ZQA    25.025517 -077.446428 2 060 600 BR70V
ZMR    41.530181 -005.639697 ZORBA  40.188067 -005.393864 2 245 460 UW990
99

EOF
    return $txt;
}

# eof - findap03.pl

