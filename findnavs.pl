#!/usr/bin/perl -w
# NAME: findnavs.pl
# AIM: Given a lat,lon, search for navaids nearby...
# 23/08/2015 - Added to the scripts repo
# 11/10/2014 - Add -b bounding box, and find/list all navs in that bbox
# 14/02/2014 - Add -i input file - line separated command
# 12/02/2014 - Also search by NAME
# 13/01/2013 geoff mclane http://geoffair.net/mperl
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use Math::Trig;
my $cwd = cwd();
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
my $PATH_SEP = '/';
my $CDATROOT="/media/Disk2/FG/fg22/fgdata"; # 20150716 - 3.5++
if ($os =~ /win/i) {
    $PATH_SEP = "\\";
    $CDATROOT="F:/fgdata"; # 20140127 - 3.1
}
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
require "Bucket2.pm" or die "Unable to load Bucket2.pm ...\n";
require 'lib_fgio.pl' or die "Unable to load 'lib_fgio.pl' Check paths in \@INC...\n";
# log file stuff
our ($LF);
my $outfile = $temp_dir.$PATH_SEP."temp.$pgmname.txt";
open_log($outfile);

my $VERS = "0.0.5 2015-08-23";
###my $VERS = "0.0.4 2014-10-11";
###my $VERS = "0.0.3 2014-02-14";
###my $VERS = "0.0.2 2014-01-13";

# user variables
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';
my $m_lat = -1;
my $m_lon = -1;
my $m_icao = '';
my $max_out = 20;
my $use_xplane_dat = 0;
my $nav_name = '';
my $nav_id = '';
my @nav_list = ();
my @nav_ids = ();
my $find_vor_only = 1;
my $search_by_name = 0;
my $filter_vor_pairs = 1;
my $add_json_output = 0;
my $need_only_one = 0;  # accept if id equal, OR name contains find string
my $out_ils_csv = 0;

# output files
my $xgfile = $temp_dir.$PATH_SEP."temptrack.xg";
my $ilscsv_out = $temp_dir.$PATH_SEP."tempils.csv";

my ($u_min_lon,$u_min_lat,$u_max_lon,$u_max_lat);
my $u_got_bbox = 0;
my ($bgn_lon,$bgn_lat,$end_lon,$end_lat);
my $got_track = 0;
my $fudge = 0.01;    # degrees

our $HOST = "localhost";
our $PORT = 5556;
our $TIMEOUT = 1;
our $DELAY = 5;

#============================================================================
# This NEEDS to be adjusted to YOUR particular default location of these files.
my $FGROOT  = $CDATROOT;    # 20150823 - "F:/fgdata"; # 20140110 - 2.99
###my $FGROOT  ="F:/FG/fgdata"; # 20140110 - 2.99
my $APTFILE = "$FGROOT/Airports/apt.dat.gz";	# the airports data file
my $NAVFILE = "$FGROOT/Navaids/nav.dat.gz";	# the NAV, NDB, etc. data file
# add these files
my $FIXFILE = "$FGROOT/Navaids/fix.dat.gz";	# the FIX data file
my $AWYFILE = "$FGROOT/Navaids/awy.dat.gz";   # Airways data
#============================================================================
# =============================================================================
# This NEEDS to be adjusted to YOUR particular default location of these files.
my $XPROOT = "D:/FG/xplane/1000";
my $APT_FILE 	= "$XPROOT/apt.dat";	# the airports data file
my $NAV_FILE 	= "$XPROOT/earth_nav.dat";	# the NAV, NDB, etc. data file
my $FIX_FILE    = "$XPROOT/earth_fix.dat";	# the FIX data file
# =============================================================================

my $g_aptdat  = $APTFILE;
my $g_navdat  = $NAVFILE;
my $g_fixfile = $FIXFILE;
my $g_awyfile = $AWYFILE;

my $x_aptdat = $APT_FILE;
my $x_navdat = $NAV_FILE;

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'MODESTO';

### program variables
my @warnings = ();
my @g_nav_lines = ();
my $actnav = '';
my @navlist = ();
my $actnavdat = '';
my @found_navs = ();
my $in_input = 0;

my $M2NM = 0.000539957;
my $NM2KM = 1.852;

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

sub mycmp_decend_n9 {
   return -1 if (${$a}[9] < ${$b}[9]);
   return 1 if (${$a}[9] > ${$b}[9]);
   return 0;
}


sub load_nav_file() {
	prt("\n[v9] Loading $g_navdat file ...\n") if (VERB9());
	mydie("ERROR: Can NOT locate [$g_navdat]!\n") if ( !( -f $g_navdat) );
	open NIF, "gzip -d -c $g_navdat|" or mydie( "ERROR: CAN NOT OPEN $g_navdat...$!...\n" );
	@g_nav_lines = <NIF>;
	close NIF;
    prt("[v9] Got ".scalar @g_nav_lines." lines to scan...\n") if (VERB9());
    $actnavdat = $g_navdat;
}

sub load_xnav_file {
	prt("\nLoading $x_navdat file ...\n");
	mydie("ERROR: Can NOT locate [$x_navdat]!\n") if ( !( -f $x_navdat) );
	open NIF, "<$x_navdat" or mydie( "ERROR: CAN NOT OPEN $x_navdat...$!...\n" );
	@g_nav_lines = <NIF>;
	close NIF;
    prt("[v9] Got ".scalar @g_nav_lines." lines to scan...\n") if (VERB9());
    $actnavdat = $x_navdat;
}

my @fnd_list = ();
my $act_find = '';
my $act_id = '';
sub is_in_nav_list($$) {
    my ($nid,$name) = @_;
    $act_find = $nav_name;
    $act_id = $nav_id;
    # prt("Find $act_find in $nid $name\n");
    return 1 if (($nid eq $act_find)&&($name =~ /$act_find/i));
    if ($need_only_one) {
        return 1 if (($nid eq $act_find)||($name =~ /$act_find/i));
    }
    my ($i,$cnt,$tstid,$tstnm);
    $cnt = scalar @nav_list;
    for ($i = 0; $i < $cnt; $i++) {
        $tstnm = $nav_list[$i];
        $tstid = $nav_ids[$i];
        $act_find = $tstnm;
        $act_id = $tstid;
        return 1 if (($nid eq $tstid)&&($name =~ /$tstnm/i));
        if ($need_only_one) {
            return 1 if (($nid eq $tstid)||($name =~ /$tstnm/i));
        }
    }
    return 0;
}

sub show_missed_names() {
    my ($name,$tst,$fnd,$msg,$msg2,$id,$cnt,$i,$cmb);
    $msg = '';
    $msg2 = '';
    $cnt = scalar @nav_list;
    for ($i = 0; $i < $cnt; $i++) {
        $name = $nav_list[$i];
        $id = $nav_ids[$i];
        $cmb = "$name:$id";
        # get user requested name
        $fnd = 0;
        foreach $tst (@fnd_list) {
            if ($cmb eq $tst) {
                $fnd = 1;
                last;
            }
        }
        if ($fnd) {
            # found this one
            $msg2 .= ' ' if (length($msg2));
            $msg2 .= $cmb;
        } else {
            $msg .= ' ' if (length($msg));
            $msg .= $cmb;
        }
    }
    if (length($msg)) {
        prt("Note: ");
        prt("Found $msg2, BUT ") if (length($msg2));
        prt("did NOT find $msg\n");
    } else {
        #if (length($msg2)) {
        #    prt("Found $msg2\n");
        #}
        my $cnt = scalar @nav_list;
        $cnt = 1 if (($cnt == 0) && length($nav_name));
        prt("Appear to have found all $cnt names...\n");
    }
}

sub mycmp_decend_n0 {
   return -1 if (${$a}[0] < ${$b}[0]);
   return 1 if (${$a}[0] > ${$b}[0]);
   return 0;
}

sub order_by_distance($) {
    my $ra = shift;
    my $max = scalar @{$ra};
    my @narr = ();
    my @ind = ();
    my ($i,$j,$dist,$az1,$az2,$line,@arr,$res);
    my ($nlat,$nlon);
    for ($i = 0; $i < $max; $i++) {
        $line = ${$ra}[$i];
        @arr = split(/\s+/,$line);
        $nlat = $arr[1];
        $nlon = $arr[2];
        $res = fg_geo_inverse_wgs_84($bgn_lat,$bgn_lon,$nlat,$nlon,\$az1,\$az2,\$dist);
        push(@ind,[$dist,$i]);
    }
    @ind = sort mycmp_decend_n0 @ind;
    for ($j = 0; $j < $max; $j++) {
        $i = $ind[$j][1];
        $line = ${$ra}[$i];
        push(@narr,$line);
    }

    return @narr;
}

sub in_bounding_box($$) {
    my ($nlat,$nlon) = @_;
    return 0 if ($nlat < $u_min_lat);
    return 0 if ($nlat > $u_max_lat);
    return 0 if ($nlon < $u_min_lon);
    return 0 if ($nlon > $u_max_lon);
    return 1;
}

sub search_nav_bbox() {
    my $rnls = \@g_nav_lines;
    my $nav_cnt = scalar @{$rnls};
    prt("Processing $nav_cnt navaid records, get those in box $u_min_lon,$u_min_lat,$u_max_lon,$u_max_lat, fudge=$fudge.\n");
    my ($ln,$lnn,$line,@arr,$nc,$typ);
    my ($nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name,$i,$len,$nmmx);
    my @navsinbox = ();
    if ($fudge > 0) {
        $u_min_lon -= $fudge;
        $u_min_lat -= $fudge;
        $u_max_lon += $fudge;
        $u_max_lat += $fudge;
    }
    $nmmx = 0;
    for ($ln = 0; $ln < $nav_cnt; $ln++) {
        $lnn = $ln + 1;
        $line = ${$rnls}[$ln];
		$line = trim_all($line);
        $len = length($line);
        next if ($line =~ /\s+Version\s+/i);
        next if ($line =~ /^I/);
        next if ($len == 0);
		@arr = split(/\s+/,$line);
		$nc = scalar @arr;
		$typ = $arr[0];
        last if ($typ == 99);
        if ($nc < 8) {
            prt("Type: [$typ] - Handle this line [$line] - count = $nc...\n");
            pgm_exit(1,"ERROR: FIX ME FIRST!\n");
        }
		if ( is_valid_nav($typ) ) {
			$nlat  = $arr[1];
			$nlon  = $arr[2];
            next if (!in_bounding_box($nlat,$nlon));
            $name  = '';
            for ($i = 8; $i < $nc; $i++) {
                $name .= ' ' if length($name);
                $name .= $arr[$i];
            }
            $len = length($name);
            $nmmx = $len if ($len > $nmmx);
            push(@navsinbox,$line);
        } else {
            pgm_exit(1,"ERROR: FIX ME! Unknown type [$line]\n");
        }
    }
    if ($got_track) {
        @navsinbox = order_by_distance(\@navsinbox);
    }
    $nav_cnt = scalar @navsinbox;
    prt("Found $nav_cnt navaids in bbox...\n");
    my ($nav,$res,$dist,$az1,$az2,$nm);
    my ($s,$lat1,$lon1,$lat2,$lon2);
    my $xg = '';
    my $inc = 10;
    for ($ln = 0; $ln < $nav_cnt; $ln++) {
        $line = $navsinbox[$ln];
		@arr = split(/\s+/,$line);
        $nc = scalar @arr;
        # prt("$line\n");
		$typ   = $arr[0];
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
        is_valid_nav($typ);
        $nav = $actnav;
        if (($typ == 2)||($typ == 3)||($typ == 12)) {
            $xg .= "anno $nlon $nlat $actnav $name\n";
            if ($nrng > 0) {
                $s = $nrng * $NM2KM * 1000;
                $az1 = 0;
                $res = fg_geo_direct_wgs_84( $nlat, $nlon, $az1, $s, \$lat1, \$lon1, \$az2 );
                $az1 = 180;
                $res = fg_geo_direct_wgs_84( $nlat, $nlon, $az1, $s, \$lat2, \$lon2, \$az2 );
                $xg .= "$lon1 $lat1\n";
                $xg .= "$lon2 $lat2\n";
                $xg .= "NEXT\n";
                $az1 = 90;
                $res = fg_geo_direct_wgs_84( $nlat, $nlon, $az1, $s, \$lat1, \$lon1, \$az2 );
                $az1 = 270;
                $res = fg_geo_direct_wgs_84( $nlat, $nlon, $az1, $s, \$lat2, \$lon2, \$az2 );
                $xg .= "$lon1 $lat1\n";
                $xg .= "$lon2 $lat2\n";
                $xg .= "NEXT\n";
                for ($az1 = 0; $az1 <= 360; $az1 += $inc) {
                    $res = fg_geo_direct_wgs_84( $nlat, $nlon, $az1, $s, \$lat1, \$lon1, \$az2 );
                    $xg .= "$lon1 $lat1\n";
                }
                $xg .= "NEXT\n";
            }
        }
        if ($got_track) {
             $res = fg_geo_inverse_wgs_84($bgn_lat,$bgn_lon,$nlat,$nlon,\$az1,\$az2,\$dist);
        }
        # for display
        $nav .= ' ' while (length($nav) < 4);
        $typ .= ' ' while (length($typ) < 2);
        $nalt = ' '.$nalt while (length($nalt) < 4);
        $nfrq = ' '.$nfrq while (length($nfrq) < 5);
        $nrng = ' '.$nrng while (length($nrng) < 3);
        $nid .= ' ' while (length($nid) < 4);
        $name .= ' ' while (length($name) < $nmmx);
        prt("$nav,$typ,$nlat,$nlon, $nalt, $nfrq, $nrng, $nid, $name ");
        if ($got_track) {
            $nm = int($M2NM * $dist * 10) / 10;
            $az1 = int($az1 + 0.5);
            $az2 = int($az2 + 0.5);
            if (! ($nm =~ /\./) ) {
                $nm .= ".0";
            }
            $nm = ' '.$nm while (length($nm) < 6);
            prt("$nm nm, on $az1/$az2");
        }
        prt("\n");
    }
    if ($got_track) {
        prt("Listed $nav_cnt navaids in distance from begin lat/lon $bgn_lat,$bgn_lon...\n");
    }
    if (length($xg) && length($xgfile)) {
        if (open XG, ">$xgfile") {
            print XG "# Navaids on route\n";
            print XG "anno $bgn_lon $bgn_lat Begin of track\n";
            print XG "color gray\n";
            print XG $xg;
            print XG "anno $end_lon $end_lat End of track\n";
            print XG "color red\n";
            print XG "$bgn_lon $bgn_lat # Begin of track\n";
            print XG "$end_lon $end_lat # End of track\n";
            print XG "NEXT\n";
            close XG;
            prt("Navaids XG written to $xgfile\n");
        }
    }

}

sub search_nav_lines() {
    my $rnls = \@g_nav_lines;
    my $nav_cnt = scalar @{$rnls};
    my $by_name = $search_by_name;
    prt("Processing $nav_cnt navaid records");
    if ($by_name) {
        prt(", to find $nav_name...");
    } else {
        if (($m_lat == -1)||($m_lon == -1)) {
            pgm_exit(1,"\n, but do not have a search point!\n");
        } else {
            prt(", get distance to $m_lat,$m_lon...");
        }
    }
    prt("\n");
    my ($ln,$line,$len,$lnn,@arr,$typ,$nc,$i,$dist,$az1,$az2,$res);
    my ($nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name1,$km,$az);
    my ($icao,$rwy1,$name4);
    my $ilscsv = "type,lat,lon,alt,frq,rng,frq2,id,icao,rwy,name\n";
    my $ilscnt = 0;
    for ($ln = 0; $ln < $nav_cnt; $ln++) {
        $lnn = $ln + 1;
        $line = ${$rnls}[$ln];
		$line = trim_all($line);
        $len = length($line);
        next if ($len == 0);
        next if ($line =~ /\d+\s+Version\s+/i);
        next if ($line =~ /^I/);
		# 0   1 (lat)   2 (lon)        3     4   5           6   7  8++
		# 2   38.087769 -077.324919  284   396  25       0.000 APH  A P Hill NDB
		# 3   57.103719  009.995578   57 11670 100       1.000 AAL  Aalborg VORTAC
		# 0   1 (lat)   2 (lon)        3     4   5           6   7  8   9  10
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
		@arr = split(/\s+/,$line);
		$nc = scalar @arr;
		$typ = $arr[0];
        last if ($typ == 99);
        if ($nc < 8) {
            prt("Type: [$typ] - Handle this line [$line] - count = $nc...\n");
            pgm_exit(1,"ERROR: FIX ME FIRST!\n");
        }
		if ( is_valid_nav($typ) ) {
			$nlat  = $arr[1];
			$nlon  = $arr[2];
			$nalt  = $arr[3];
			$nfrq  = $arr[4];
			$nrng  = $arr[5];
			$nfrq2 = $arr[6];
			$nid   = $arr[7];
			$name1  = '';
			for ($i = 8; $i < $nc; $i++) {
				$name1 .= ' ' if length($name1);
				$name1 .= $arr[$i];
			}
            if (($typ > 3)&&($typ < 12)&&($typ != 6)) {
            ## if ($typ == 4) {
                if ($nc < 11) {
                    prt("$lnn: Type: [$typ] - Handle this line [$line] - count = $nc...\n");
                    pgm_exit(1,"ERROR: FIX ME FIRST!\n");
                }
                $icao = $arr[8];
                $rwy1 = $arr[9];
                $name4  = join(' ', splice(@arr,10)); # Name
                #prt("$nc $typ $icao $rwy1 $name4\n");
                if ($out_ils_csv && ($typ == 4)) {
                    $ilscsv .= "$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$icao,$rwy1,$name4\n";
                    $ilscnt++;
                }
            }
            $az1  = 400;
            $az2  = 400; 
            if ($by_name) {
                $dist = -1; # this is by NAME, not location
                if (is_in_nav_list($nid,$name1)) {
                    #               0=typ,1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid,   8=name,9=find,10=az1,11=az2
                    push(@found_navs, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name1, $act_find, $az1, $az2]);
                    push(@fnd_list,"$act_find:$act_id");  # keep the fact we found one for this name
                }
            } else {
                $res = fg_geo_inverse_wgs_84 ($m_lat,$m_lon,$nlat,$nlon,\$az1,\$az2,\$dist);
                $km = $dist / 1000;
                $km = (int(($km + 0.05) * 10) / 10);
                $az = (int(($az1 + 0.05) * 10) / 10);
            }
            prt( "[v5] $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name1, $km, $az\n") if (VERB5());
            #               0=typ,1=lat, 2=lon, 3=alt, 4=frq, 5-rng, 6-frq2, 7=nid,8=name,9=dist,10=az1,11=az2
            push(@navlist, [$typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nfrq2, $nid, $name1, $dist, $az1, $az2]);
        } else {
            pgm_exit(1,"ERROR: FIX ME! Unknown type [$line]\n");
        }
    }
    $nc = scalar @navlist;
    if ($out_ils_csv) {
        rename_2_old_bak($ilscsv_out);
        write2file($ilscsv,$ilscsv_out);
        prt("Loaded $nc navaids... from $actnavdat... written $ilscnt ils csv to $ilscsv_out\n");
    } else {
        prt("Loaded $nc navaids... from $actnavdat...\n");
    }

}

sub is_vor_type($) {
    my $t = shift;
    return 1 if ($t == 3);
    return 2 if ($t == 12);
    return 3 if ($t == 13);
    return 0;
}
sub is_ndb_type($) {
    my $t = shift;
    return 1 if ($t == 2);
    return 0;
}

#          VDME, 12, 37.61948333, -122.37389167,    7, 11580,  40, SFO , SAN FRANCISCO VOR-DME   ,  17.9, 229.4
my $hdr = 'type, # , latitude    , longitude    , elev, freq., rng, ID  , Name                    , dist., brng'; 
my $done_hdr = 0;
my $min_lat = 90;
my $min_lon = 180;
my $max_lat = -90;
my $max_lon = -180;
my $min_alt = 9999;
my $max_alt = -9999;

sub prtnav($$$$$$$$$$$) {
    my ($nav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nid, $name, $km, $az) = @_;
    prt("$hdr\n") if (!$done_hdr);
    $done_hdr = 1;
    if ($nlat > $max_lat) {
        $max_lat = $nlat;
    }
    if ($nlat < $min_lat) {
        $min_lat = $nlat;
    }
    if ($nlon > $max_lon) {
        $max_lon = $nlon;
    }
    if ($nlon < $min_lon) {
        $min_lon = $nlon;
    }
    if ($nalt > $max_alt) {
        $max_alt = $nalt;
    }
    if ($nalt < $min_alt) {
        $min_alt = $nalt;
    }

    $nav .= ' ' while (length($nav) < 4);
    $typ .= ' ' while (length($typ) < 2);
    $nalt = ' '.$nalt while (length($nalt) < 4);
    $nfrq = ' '.$nfrq while (length($nfrq) < 5);
    $nrng = ' '.$nrng while (length($nrng) < 3);
    $nid .= ' ' while (length($nid) < 4);
    $name .= ' ' while (length($name) < 24);
    $km = ' '.$km while (length($km) < 5);

    my $msg = "$nav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nid, $name, $km, $az\n";
    prt($msg);
    return $msg;
}

sub prtnav2($$$$$$$$$) {
    my ($nav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nid, $name) = @_;
    
    $nav .= ' ' while (length($nav) < 4);
    $typ .= ' ' while (length($typ) < 2);
    $nalt = ' '.$nalt while (length($nalt) < 4);
    $nfrq = ' '.$nfrq while (length($nfrq) < 5);
    $nrng = ' '.$nrng while (length($nrng) < 3);
    $nid .= ' ' while (length($nid) < 4);
    $name .= ' ' while (length($name) < 24);
    my $msg = "$nav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nid, $name\n";
    prt($msg);
    return $msg;
}

sub ind_in_array($$) {
    my ($ind,$ra) = @_;
    my ($i);
    foreach $i (@{$ra}) {
        return 1 if ($ind == $i);
    }
    return 0;
}

sub filter_vor_pair() {
    my ($i,$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name,$dist,$az1,$km,$az,$out,$msg,$clat,$clon,$cfrq);
    my $max = scalar @found_navs;
    if ($filter_vor_pairs) {
        my @navs = ();
        my ($ra,$ra2,$j,$j2,$typ2,$dist2,$fnd,$i2);
        my $max = scalar @found_navs;
        prt("Filter $max for pairs...\n") if (VERB5());
        my @excu = ();
        for ($i = 0; $i < $max; $i++) {
            $i2 = $i + 1;
            $ra = $found_navs[$i];
            $typ = ${$ra}[0];
            if ($find_vor_only) {
                next if (is_ndb_type($typ));
            }
            next if (ind_in_array($i,\@excu));
            $dist = ${$ra}[9];
            $fnd = 0;
            for ($j = 0; $j < $max; $j++) {
                next if ($i == $j);
                next if (ind_in_array($j,\@excu));
                $j2 = $j + 1;
                $ra2 = $found_navs[$j];
                $typ2 = ${$ra2}[0];
                if ($find_vor_only) {
                    next if (is_ndb_type($typ2));
                }
                $dist2 = ${$ra2}[9];
                next if (length($dist2) == 0);
                # prt("Comparing $dist with $dist2\n");
                if ($dist eq $dist2) {
                    # same 'name' - decide which
                    prt("$i2:$j2: Equal names $dist type $typ and $typ2 ") if (VERB9());
                    if (($typ == 3)&&($typ2 == 12)) {
                        push(@excu,$j);
                        push(@navs,$ra2);
                        $fnd = 1;
                        prt("Stored $typ2\n") if (VERB9());
                    } elsif (($typ == 12)&&($typ2 == 3)) {
                        push(@navs,$ra);
                        push(@excu,$i);
                        $fnd = 1;
                        prt("Stored $typ\n") if (VERB9());
                    } elsif ((($typ == 13)&&($typ2 == 3))||($typ == 3)&&($typ2 == 13)||
                        (($typ == $typ2)&&(($typ == 3)||($typ ==13)))) {
                        push(@navs,$ra);
                        push(@excu,$i);
                        $fnd = 1;
                        prt("Stored $typ\n") if (VERB9());
                    } else {
                        prtw("WARNING: Presently NO filter of types $typ and $typ2 - ** FIX ME **\n");
                    }
                }
            }
            if ($fnd == 0) {
                prt("$i2: Not found $dist twice, or more...\n") if (VERB5());
                push(@navs,$ra);
            }

        }
        $max = scalar @navs;
        prt("Return $max after filtering.\n") if (VERB5());
        return @navs;
    } else {
        prt("No filtering of $max found...\n") if (VERB5());
    }
    return @found_navs;
}

sub filter_dupes() {
    my ($i,$ra,$max,$tst,$nfrq,$nid,$name,$typ);
    $max = scalar @found_navs;
    my @navs = ();
    my %dupes = ();
    for ($i = 0; $i < $max; $i++) {
        $ra = $found_navs[$i];
        $nfrq = ${$ra}[4];
        $nid  = ${$ra}[7];
        $name = trim_all(${$ra}[8]);
        $tst = $nfrq.$nid.$name;
        if (defined $dupes{$tst}) {
            $typ = ${$ra}[0];
            prt("Dropping: $typ $nfrq $nid $name\n");
            next;
        }
        $dupes{$tst} = 1;
        push(@navs,$ra);
    }
    return @navs;
}

sub show_found_navs() {
    my ($i,$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name,$dist,$az1,$km,$az,$out,$msg,$clat,$clon,$cfrq);
    @found_navs = filter_dupes();
    $out = scalar @nav_list;
    $out = 1 if (($out == 0)&&(length($nav_name)));
    my $max = scalar @found_navs;
    my @nav_list = filter_vor_pair();
    $i = scalar @nav_list;
    prt("Found $max matching $out navaids");
    if ($i < $max) {
        prt(", REDUCED to $i after filtering. Use -A to stop filtering ");
        $max = $i;
    }
    prt("\n");
    my $rnl = \@nav_list;
    $out = 0;
    $msg = '';
    if ($max) {
        #    VOR , 3 , 37.62736111, -120.95786111,   93, 11460, 130, MOD , MODESTO VOR-DME
        prt("type,cod, latitude,    longitude,      alt, freq,  rng, id,   name\n");
    }
    my $json = "\"navaids\":[\n";
    for ($i = 0; $i < $max; $i++) {
        $typ  = ${$rnl}[$i][0];
        if ($find_vor_only) {
            next if (is_ndb_type($typ));
        }
        $nlat = ${$rnl}[$i][1];
        $nlon = ${$rnl}[$i][2];
        $nalt = ${$rnl}[$i][3];
        $nfrq = ${$rnl}[$i][4];
        $nrng = ${$rnl}[$i][5];
        $nfrq2 = ${$rnl}[$i][6];
        $nid  = ${$rnl}[$i][7];
        $name = ${$rnl}[$i][8];
        $dist = ${$rnl}[$i][9];
        $az1  = ${$rnl}[$i][10];
		is_valid_nav($typ);
        $msg .= prtnav2( $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nid, $name );
        $clat = sprintf("%.8f",$nlat);
        $clon = sprintf("%.8f",$nlon);
        $cfrq = sprintf("%.2f", $nfrq / 100);
        $json .= ",\n" if ($out);
        #$json .= "{\"type\":\"$actnav\",\"lat\":$clat,\"lon\":$clon,\"alt\":$nalt,\"freq\":$cfrq,\"rng\":$nrng,\"id\":\"$nid\",\"name\":\"$name\"}";
        $json .= "{\"N\":\"$dist\",\"id\":\"$nid\",\"type\":\"$actnav\",\"lat\":$clat,\"lon\":$clon,\"alt\":$nalt,\"freq\":$cfrq,\"rng\":$nrng,\"fn\":\"$name\"}";
        $out++;
    }
    $json .= "\n]\n";
    if ($out) {
        if (length($out_file)) {
            write2file($json,$out_file);
            prt("Written json to $out_file\n");
        } elsif ($add_json_output) {
            prt($json);
        }
    }
}

sub vor_pair_filter($) {
    my $rnl = shift;
    my $max = $max_out;
    $max *= 2;
    $max += 4;
    my $tot = scalar @{$rnl};
    if ($tot < $max) {
        $max = $tot;
    }
    my @navs = ();
    my ($i,$typ,$nfrq,$j,$typ2,$nfrq2,$rn,$rn2,$fnd,%inds);

    for ($i = 0; $i < $max; $i++) {
        $rn = ${$rnl}[$i];
        $typ  = ${$rn}[0];
        if (!is_vor_type($typ)) {
            push(@navs,$rn);    # not a VOR
            next;
        }
        $nfrq = ${$rn}[4];
        $fnd = 0;
        %inds = ();
        for ($j = 0; $j < $max; $i++) {
            next if ($i == $j);
            $rn2 = ${$rnl}[$j];
            $typ2  = ${$rn2}[0];
            next if (!is_vor_type($typ2));
            $nfrq2 = ${$rn2}[4];
            if ($nfrq == $nfrq2) {
                # decide which of these to keep
                $fnd = 1;
                $inds{$i} = 1;
                $inds{$j} = 1;
            }
        }
        if ($fnd) {
            # decide which indexed item to keep - usually of 2, but could be more
            my @arr = keys %inds;
            my ($k,$icnt,$in1,$in2,$rnk);
            $icnt = scalar @arr;
            $rnk = $rn;
            for ($k = 0; $k < $icnt - 1; $k++) {
                $in1 = $arr[$k];
                $in2 = $arr[$k+1];
                $rn = ${$rnl}[$in1];
                $rn2 = ${$rnl}[$in2];
                $typ  = ${$rn}[0];
                $typ2 = ${$rn2}[0];
                if ($typ == $typ2) {
                    $rnk = $rn;
                } elsif (($typ == 3)&&($typ2 == 12)) {
                    $rnk = $rn2;
                } elsif (($typ == 12)&&($typ2 == 3)) {
                    $rnk = $rn;
                }
            }
            push(@navs,$rnk);
        } else {
            push(@navs,$rn);
        }
    }
    return @navs;
}

sub show_nearest_navs() {
    my ($i);
    my @navs = sort mycmp_decend_n9 @navlist; 
    # TODO - 
    #if ($filter_vor_pairs) { 
    #    @navs = vor_pair_filter(\@navs); 
    #}
    my $rnl = \@navs;
    my ($typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name,$dist,$az1,$km,$az,$out);
    $out = 0;
    my $msg = '';
    my $max = $max_out;
    if (scalar @{$rnl} < $max) {
        $max = scalar @{$rnl};
    }
    if ($max == 0) {
        pgm_exit(1,"Failed to find any navs suiting criteria!\n");
    }
    if ($u_got_bbox) {
        prt("Listing $max in bbox $u_min_lon,$u_min_lat,$u_max_lon,$u_max_lon, VOR/DME first, then NDB, then ILS...\n");
    } else {
        prt("Listing closest $max, VOR/DME first, then NDB, then ILS...\n");
    }
    for ($i = 0; $i < $max; $i++) {
        $typ  = ${$rnl}[$i][0];
        next if (!is_vor_type($typ));
        $nlat = ${$rnl}[$i][1];
        $nlon = ${$rnl}[$i][2];
        $nalt = ${$rnl}[$i][3];
        $nfrq = ${$rnl}[$i][4];
        $nrng = ${$rnl}[$i][5];
        $nfrq2 = ${$rnl}[$i][6];
        $nid  = ${$rnl}[$i][7];
        $name = ${$rnl}[$i][8];
        $dist = ${$rnl}[$i][9];
        $az1  = ${$rnl}[$i][10];
        $km = $dist / 1000;
        $km = (int(($km + 0.05) * 10) / 10);
        $az = (int(($az1 + 0.05) * 10) / 10);
		is_valid_nav($typ);
        $msg .= prtnav( $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nid, $name, $km, $az );
        $out++;
    }
    prt("Listed $out VOR\n") if ($out);
    $done_hdr = 0;
    $out = 0;
    for ($i = 0; $i < $max; $i++) {
        $typ  = ${$rnl}[$i][0];
        next if (!is_ndb_type($typ));
        $nlat = ${$rnl}[$i][1];
        $nlon = ${$rnl}[$i][2];
        $nalt = ${$rnl}[$i][3];
        $nfrq = ${$rnl}[$i][4];
        $nrng = ${$rnl}[$i][5];
        $nfrq2 = ${$rnl}[$i][6];
        $nid  = ${$rnl}[$i][7];
        $name = ${$rnl}[$i][8];
        $dist = ${$rnl}[$i][9];
        $az1  = ${$rnl}[$i][10];
        $km = $dist / 1000;
        $km = (int(($km + 0.05) * 10) / 10);
        $az = (int(($az1 + 0.05) * 10) / 10);
		is_valid_nav($typ);
        $msg .= prtnav( $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nid, $name, $km, $az );
        $out++;
    }
    prt("Listed $out NDB\n") if ($out);
    $out = 0;
    $done_hdr = 0;
    for ($i = 0; $i < $max; $i++) {
        $typ  = ${$rnl}[$i][0];
        next if (is_vor_type($typ) || is_ndb_type($typ));
        $nlat = ${$rnl}[$i][1];
        $nlon = ${$rnl}[$i][2];
        $nalt = ${$rnl}[$i][3];
        $nfrq = ${$rnl}[$i][4];
        $nrng = ${$rnl}[$i][5];
        $nfrq2 = ${$rnl}[$i][6];
        $nid  = ${$rnl}[$i][7];
        $name = ${$rnl}[$i][8];
        $dist = ${$rnl}[$i][9];
        $az1  = ${$rnl}[$i][10];
        $km = $dist / 1000;
        $km = (int(($km + 0.05) * 10) / 10);
        $az = (int(($az1 + 0.05) * 10) / 10);
		is_valid_nav($typ);
        $msg .= prtnav( $actnav, $typ, $nlat, $nlon, $nalt, $nfrq, $nrng, $nid, $name, $km, $az );
        $out++;
    }
    prt("Listed $out ILS and components\n") if ($out);
    $nlat = ($min_lat + $max_lat) / 2;
    $nlon = ($min_lon + $max_lon) / 2;
    $nfrq = $max_lat - $min_lat;
    $nfrq2 = $max_lon - $min_lon;
    prt("Range: lat,lon,alt min $min_lat,$min_lon,$min_alt max $max_lat,$max_lon,$max_alt\n");
    prt("Center: $nlat,$nlon ranges lat/lon $nfrq/$nfrq2\n");
    if (length($out_file)) {
        write2file($msg,$out_file);
        prt("List written to [$out_file]\n");
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

sub is_a_double($) {
    my $val = shift;
    return 1 if ($val =~ /^-?\d+\.?\d*$/); # { print "is a real number\n" }
    return 1 if ($val =~ /^\d+$/); # { print "is a whole number\n" }
    return 1 if ($val =~ /^-?\d+$/); # { print "is an integer\n" }
    return 1 if ($val =~ /^[+-]?\d+$/); # { print "is a +/- integer\n" }
    return 1 if ($val =~ /^-?(?:\d+(?:\.\d*)?|\.\d+)$/); # { print "is a decimal number\n" }
    return 1 if ($val =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/); # { print "a C float\n" }
    return 0 if ($val =~ /\D/); # { print "has nondigits\n" }
    return 0;
}

sub show_pos($) {
    my $rc = shift;
    $m_lon = ${$rc}{'lon'};
    $m_lat = ${$rc}{'lat'};
    prt("Got aircraft position lat=$m_lat, lon=$m_lon\n");
}

sub get_fg_pos() {
    set_lib_fgio_verb(0);
    if (fgfs_connect($HOST,$PORT,$TIMEOUT)) {
        prt("Connection established...\n") if (VERB5());
       	fgfs_send("data");  # switch exchange to data mode
        my $rc = fgfs_get_position();
        show_pos($rc);
        fgfs_disconnect();
    } else {
        prt("Connection FAILED!\n") if (VERB5());
    }
}


#########################################
### MAIN ###
# get_fg_pos();
parse_args(@ARGV);
if ($use_xplane_dat) {
    load_xnav_file();
} else {
    load_nav_file();
}
if ($u_got_bbox) {
    search_nav_bbox();
} else {
    search_nav_lines();
    if (length($nav_name) == 0) {
        show_nearest_navs();
    } else {
        show_found_navs();
        show_missed_names();
    }
}
pgm_exit(0,"");
########################################

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub load_input_file($) {
    my $file = shift;
    if (open INP, "<$file") {
        my @lines = <INP>;
        close INP;
        my ($line);
        my @inputs = ();
        foreach $line (@lines) {
            chomp $line;
            $line = trim_all($line);
            next if (length($line) == 0);
            push(@inputs,$line);
        }
        if (@inputs) {
            parse_args(@inputs);
        }
    } else {
        pgm_exit(1,"Error: Unable to load input file $file\n");
    }
}

sub in_world($$) {
    my ($lon,$lat) = @_;
    if (($lat < -90)||
        ($lat > 90)||
        ($lon < -180)||
        ($lon > 180)) {
        return 0;
    }
    return 1;
}

sub get_bbox($) {
    my $bbox = shift;
    my @arr = split(",",$bbox);
    my $cnt = scalar @arr;
    if ($cnt != 4) {
        prt("bbox $bbox failed to split into 4 on comma!\n");
        return 0;
    }
    $u_min_lon = $arr[0];
    $u_min_lat = $arr[1];
    if (!in_world($u_min_lon,$u_min_lat)) {
        prt("min-lon $u_min_lon or min-lat $u_min_lat NOT in world range!\n");
        return 0;
    }
    $u_max_lon = $arr[2];
    $u_max_lat = $arr[3];
    if (!in_world($u_max_lon,$u_max_lat)) {
        prt("max-lon $u_max_lon or max-lat $u_max_lat NOT in world range!\n");
        return 0;
    }
    if ($u_min_lon >= $u_max_lon) {
        prt("min-lon $u_min_lon GTE max-lon $u_max_lon!\n");
        return 0;
    }
    if ($u_min_lat >= $u_max_lat) {
        prt("min-lat $u_min_lat GTE max-lat $u_max_lat!\n");
        return 0;
    }
    $u_got_bbox = 1;
    return 1;
}

sub get_track($) {
    my $bbox = shift;
    my @arr = split(",",$bbox);
    my $cnt = scalar @arr;
    if ($cnt != 4) {
        prt("track $bbox failed to split into 4 on comma!\n");
        return 0;
    }
    $bgn_lat = $arr[0];
    $bgn_lon = $arr[1];
    if (!in_world_range($bgn_lat,$bgn_lon)) {
        prt("bgn-lat $bgn_lat or bgn-lon $bgn_lon NOT in world range!\n");
        return 0;
    }
    $end_lat = $arr[2];
    $end_lon = $arr[3];
    if (!in_world_range($end_lat,$end_lon)) {
        prt("end-lat $end_lat or end-lon $end_lon NOT in world range!\n");
        return 0;
    }
    my ($minlat,$minlon,$maxlat,$maxlon);
    $minlat = $bgn_lat < $end_lat ? $bgn_lat : $end_lat;
    $minlon = $bgn_lon < $end_lon ? $bgn_lon : $end_lon;
    $maxlat = $bgn_lat > $end_lat ? $bgn_lat : $end_lat;
    $maxlon = $bgn_lon > $end_lon ? $bgn_lon : $end_lon;
    $bbox = "$minlon,$minlat,$maxlon,$maxlat";
    if (!get_bbox($bbox)) {
        prt("get_bbox($bbox) failed!\n");
        return 0;
    }
    $got_track = 1;
    return 1;
}


sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg,@arr);
    my $verb = VERB2();
    my %dupes = ();
    while (@av) {
        $arg = $av[0];
        if ( ($arg =~ /^-/) && (!is_a_double($arg)) ) {
            $sarg = substr($arg,1);
            $sarg = substr($sarg,1) while ($sarg =~ /^-/);
            if (($sarg =~ /^h/i)||($sarg eq '?')) {
                give_help();
                pgm_exit(0,"Help exit(0)");
            } elsif ($sarg =~ /^a/) {
                $filter_vor_pairs = 0;
                prt("Set to NO filtering of navaids.\n") if ($verb);
            } elsif ($sarg =~ /^A/) {
                $find_vor_only = 0;
                prt("Set to find ALL matching navaids.\n") if ($verb);
            } elsif ($sarg =~ /^b/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if (!get_bbox($sarg)) {
                    pgm_exit(1,"Error: Failed to get min-lon,min-lat,max-lon,max_lat from '$sarg'!\n");
                }
            } elsif ($sarg =~ /^f/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $fudge = $sarg;
            } elsif ($sarg =~ /^t/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if (!get_track($sarg)) {
                    pgm_exit(1,"Error: Failed to get bgn-lat,bgn-lon,end-lat,end-lon from '$sarg'!\n");
                }
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
            } elsif ($sarg =~ /^n/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if (!defined $dupes{$sarg}) {
                    $dupes{$sarg} = 1;
                    @arr = split(":",$sarg);
                    if (scalar @arr == 2) {
                        $nav_name = $arr[0];
                        $nav_id   = $arr[1];
                        push(@nav_list,$nav_name);
                        push(@nav_ids,$nav_id);
                    } else {
                        #pgm_exit(1,"Need to give NAME:ID pair! Arg $sarg did NOT split in 2 in ':'!!\n");
                        $nav_name = $sarg;
                        push(@nav_list,$nav_name);
                        push(@nav_ids,$nav_name);
                        $need_only_one = 1;
                    }
                    prt("Set nav name to [$nav_name], id to [$nav_id].\n") if ($verb);
                    $search_by_name = 1;
                }
            } elsif ($sarg =~ /^o/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_file = $sarg;
                prt("Set out file to [$out_file].\n") if ($verb);
            } elsif ($sarg =~ /^x/) {
                $use_xplane_dat = 1;
                prt("Set to use x-plane data [$x_navdat].\n") if ($verb);
            } elsif ($sarg =~ /^i/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $in_input++;
                load_input_file($sarg);
                $in_input--;
            } elsif ($sarg =~ /^j/) {
                $add_json_output = 1;
            } elsif ($sarg =~ /^m/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if ($sarg =~ /^\d+$/) {
                    $max_out = $sarg;
                } else {
                    pgm_exit(1,"Error: command $arg must be followed by an integer, not $sarg!\n");
                }
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            if ($arg =~ /,/) {
                @arr = split(",",$arg);
                if (scalar @arr == 2) {
                    $m_lat = $arr[0];
                    $m_lon = $arr[1];
                    prt("Set lat [$m_lat], lon [$m_lon]\n") if ($verb);
                } else {
                    pgm_exit(1,"Command [$arg] did not split into 2 lat,lon\n");
                }
            } elsif ($arg =~ /:/) {
                @arr = split(":",$arg);
                if (scalar @arr == 2) {
                    $nav_name = $arr[0];
                    $nav_id   = $arr[1];
                    push(@nav_list,$nav_name);
                    push(@nav_ids,$nav_id);
                } else {
                    pgm_exit(1,"Need to give NAME:ID pair! Arg $arg did NOT split in 2 in ':'!!\n");
                }
                prt("Set nav name to [$nav_name], id to [$nav_id].\n") if ($verb);
                $search_by_name = 1;
            } elsif ($m_lat == -1) {
                $m_lat = $arg;
                prt("Set lat to [$m_lat]\n") if ($verb);
            } elsif ($m_lon == -1) {
                $m_lon = $arg;
                prt("Set lon to [$m_lon]\n") if ($verb);
            } else {
                pgm_exit(1,"What is this? [$arg]! Already have lat $m_lat, lon $m_lon\n");
            }
        }
        shift @av;
    }

    if (!$in_input) {
        if ($debug_on) {
            prtw("WARNING: DEBUG is ON!\n");
            if (length($nav_name) ==  0) {
                $nav_name = $def_file;
                prt("Set DEFAULT search name to [$nav_name]\n");
                $need_only_one = 1;
                $search_by_name = 1;
                $filter_vor_pairs = 0;
    }
        }
        if ((($m_lat ==  -1) || ($m_lon == -1)) && (length($nav_name) == 0) && ($u_got_bbox == 0)) {
            give_help();
            pgm_exit(1,"\nERROR: No lat,lon, navaid name (-n), nor bbox (-b) found in command!\n\n");
        }
    }
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] lat,lon\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>  (-o) = Write output to this file.\n");
    prt(" --xplane      (-x) = Use x-plane data (def=$x_navdat)\n");
    prt(" --name <name> (-n) = Search using a name. Give NAME:ID pair.\n");
    prt(" --in <file>   (-i) = Use file line separated list of inputs.\n");
    prt(" --json        (-j) = Also output in json format.\n");
    prt(" --all         (-a) = No filtering of found navaids.\n");
    prt(" --ALL         (-A) = Include ALL navaids. Default is VOR(3) and VOR-DME(12) only.\n");
    prt(" --max <num>   (-m) = Set the maximum output list. (def=$max_out)\n");
    prt(" --bbox <bbox> (-b) = Find all navs within the bounding box.\n");
    prt(" --track <b,e> (-t) = Find all navs along a track, bgn-lat,bgn-lon,end-lat,end-lon.\n");
    prt(" --fudge <deg> (-f) = Expand bbox by this fudge factor. (def=$fudge)\n");
    prt(" bbox = min-lon,min-lat,max-lon,max-lat\n");
    prt(" Default nav data file used is [$g_navdat]\n");
    prt(" Given a bear lat,lon pair search for all navaids, sorted by distance, and output closest $max_out,\n");
    prt(" OR if given a -name name:id pair, search for all navaids with this name:id\n");
}

# eof - findnavs.pl
