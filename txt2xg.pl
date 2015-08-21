#!/usr/bin/perl -w
# NAME: txt2xg.pl
# AIM: SPECIALISED! Just to load a sid/star/... txt file in a little like INI format,
# and out an xg(raph) of any esults found.
# 19/08/2015 geoff mclane http://geoffair.net/mperl
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use Math::Trig;
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
my $out_file = $temp_dir.$PATH_SEP."temptxt2xg.xg";
my $star_color = 'green';
my $sid_color  = 'blue';
my $app_color  = 'white';
my $usr_anno = '';

my $m_max_path = 300000;    # was 100000
my $m_path_widthm = 500; # was 300; # was 5000;   
my $m_arrow_angle = 30;
my $add_second_end = 1;
my $add_arrow_sides = 1;

# ### DEBUG ###
my $debug_on = 1;
#my $def_file = 'C:\Users\user\Documents\FG\LFPO.procedures.txt';
my $def_file = $perl_dir.'circuits'.$PATH_SEP.'LFPO.procedures.txt';
my $def_anno = "anno 2.308119 48.75584 Rue Pernoud, Antony";

### program variables
my @warnings = ();
my $tmp_xg = $temp_dir.$PATH_SEP."temptemp.xg";

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
my $nav_file = $CDATROOT.$PATH_SEP.'Navaids'.$PATH_SEP.'nav.dat.gz';

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
	prt("Loading fix file $fix_file... moment...\n");
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
        next if ($line =~ /^\d+\s+Version/);
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
    ### @arr = keys %h;
    @arr = keys %{$rfixhash};
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

sub find_fix_id($$$$) {
    my ($rfa,$id,$rlat,$rlon) = @_;
	my $cnt = scalar @{$rfa};
	my ($i,$ra,$nid,$nlat,$nlon,$line,$len,@arr,$val);
    my @fnd = ();
	for ($i = 0; $i < $cnt; $i++) {
        $line = trim_all(${$rfa}[$i]);
        $len = length($line);
        next if ($len == 0);
        @arr = split(/\s+/,$line);
        $len = scalar @arr;
        $val = $arr[0];
        next if ($val eq 'I');
        next if ($val == 600);
        last if ($val == 99);
        if ($len == 3) {
    		$nid = $arr[2];
            if ($nid eq $id) {
                $nlat = $arr[0];
                $nlon = $arr[1];
                ${$rlat} = $nlat;
                ${$rlon} = $nlon;
                return 1;
            }
        }
	}
    return 0;
}


#######################################################################
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

sub load_nav_lines() { 
	prt("Loading the navaids file $nav_file... moment...\n");
	return load_gzip_file($nav_file); 
}

####################################################################
### load navaids, and keep DISTANCE from the airport given
sub load_nav_file() {
    my $rnav = load_nav_lines();
    my $cnt = scalar @{$rnav};
    prt("[v1] Loaded $cnt lines, from [$nav_file]...\n") if (VERB1());
    my ($i,$line,$len,$lnn,@arr,$nc);
    my ($typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$nid,$name,$navcnt);
    my ($s,$az1,$az2);
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
            prtw("WARNING:$lnn: Undefined [$line]\n");
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
        #push(@navlist,[$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nfrq2,$name,$s,$az1,$az2]);
        #              0    1     2     3     4     5     6      7    
        push(@navlist,[$typ,$nlat,$nlon,$nalt,$nfrq,$nrng,$nid  ,$name]);
    }
    prt("Loaded $navcnt navigation aids...\n"); # if (VERB5());
    return \@navlist;
}

sub find_nav_id($$$$) {
    my ($rna,$id,$rlat,$rlon) = @_;
	my $cnt = scalar @{$rna};
	my ($i,$ra,$nid,$nlat,$nlon);
	my @arr = ();
	for ($i = 0; $i < $cnt; $i++) {
		$ra = ${$rna}[$i];
		$nid = ${$ra}[6];
		push(@arr,$ra) if ($nid eq $id);
	}
	# if more than one, get closest...
    $cnt = scalar @arr;
    if ($cnt) {
        $ra = $arr[0];
        $nlat = ${$ra}[1];
        $nlon = ${$ra}[2];
        ${$rlat} = $nlat;
        ${$rlon} = $nlon;
        prt("Found $id $nlat,$nlon\n");
    }
}

#######################################################################

# some utility functions
sub is_all_numeric($) {
    my ($txt) = shift;
    $txt = substr($txt,1) if ($txt =~ /^-/);
    return 1 if ($txt =~ /^(\d|\.)+$/);
    return 0;
}

my $show_set_dec_error = 1;
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

sub get_dist_stg_km($) {
    my ($dist) = @_;
    my $km = $dist / 1000;
    set_decimal1_stg(\$km);
    $km .= "Km";
    return $km;
}

#######################################################################
sub get_arrow_xg($$$$$$$$$) {
    my ($from,$wlat1,$wlon1,$to,$wlat2,$wlon2,$whdg1,$hwid,$color) = @_;
    my $wsize = ($hwid / sin(deg2rad($m_arrow_angle)));
    my ($wlatv1,$wlonv1,$whdg,$wlatv2,$wlonv2,$waz1,$tmp,$tmp2);
    my ($wlatv3,$wlonv3,$wlatv4,$wlonv4);

    my $xg = '';
	$tmp = int($whdg1 + 0.5);
	$tmp2 = int($wsize / 1000);
	### $xg .= "# end arrows from $wlat1,$wlon1 to $wlat2,$wlon2, hdg $tmp, size $tmp2 km\n";
	$xg .= "# end arrows from $from to $to, hdg $tmp, size $tmp2 km\n";

    ## $xg .= "color gray\n";
    $xg .= "color $color\n";
    $whdg = $whdg1 + $m_arrow_angle; # was 30
    $whdg -= 360 if ($whdg > 360);
    fg_geo_direct_wgs_84($wlat1,$wlon1, $whdg, $wsize, \$wlatv1, \$wlonv1, \$waz1 );
    fg_geo_direct_wgs_84($wlat2,$wlon2, $whdg, $wsize, \$wlatv2, \$wlonv2, \$waz1 );

    $xg .= "$wlon1 $wlat1\n";
    $xg .= "$wlonv1 $wlatv1\n";
    $xg .= "NEXT\n";

    if ($add_second_end) {
        $xg .= "$wlon2 $wlat2\n";
        $xg .= "$wlonv2 $wlatv2\n";
        $xg .= "NEXT\n";
    }

    if ($add_arrow_sides) {
        $xg .= "$wlonv1 $wlatv1\n";
        $xg .= "$wlonv2 $wlatv2\n";
        $xg .= "NEXT\n";
    }

    $whdg = $whdg1 - $m_arrow_angle; # was 30
    $whdg += 360 if ($whdg < 0);
    fg_geo_direct_wgs_84($wlat1,$wlon1, $whdg, $wsize, \$wlatv3, \$wlonv3, \$waz1 );
    fg_geo_direct_wgs_84($wlat2,$wlon2, $whdg, $wsize, \$wlatv4, \$wlonv4, \$waz1 );

    $xg .= "$wlon1 $wlat1\n";
    $xg .= "$wlonv3 $wlatv3\n";
    $xg .= "NEXT\n";

    if ($add_second_end) {
        $xg .= "$wlon2 $wlat2\n";
        $xg .= "$wlonv4 $wlatv4\n";
        $xg .= "NEXT\n";
    }

    if ($add_arrow_sides) {
        $xg .= "$wlonv3 $wlatv3\n";
        $xg .= "$wlonv4 $wlatv4\n";
        $xg .= "NEXT\n";
    }
    ### prt($xg);
    return $xg;
}

sub get_path_xg($$$$$$$) {
    my ($from,$elat1,$elon1,$to,$elat2,$elon2,$color) = @_;
    my ($az1,$az2,$s,$res);
    my $hwidm = $m_path_widthm; # 300; # was 5000;
    my $xg = '';
    $res = fg_geo_inverse_wgs_84($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
    if ($s < $hwidm) {
        $s = (int($s * 10) / 10);
        return "# Dist too small $from $elat1,$elon1 $to $elat2,$elon2 $s, min $hwidm\n";
    } elsif ($s > $m_max_path ) { # was 100000
        $s = (int($s * 10) / 10);
        $res = $m_max_path / 1000;
        return "# Dist too large $from $elat1,$elon1 $to $elat2,$elon2 $s, GT $res Km\n";
    }
    my $wkm = get_dist_stg_km($hwidm * 2);
    my $lkm = get_dist_stg_km($s);
    $xg .= "# Rect using $elat1,$elon1 $elat2,$elon2 len $lkm, wid $wkm\n";
    # NOTE: Was developed using Wind, so NOTE the reverse track used
    # $xg .= get_arrow_xg($from,$elat1,$elon1,$to,$elat2,$elon2,$az1,$hwidm,$color); # 'orange'
    $xg .= get_arrow_xg($from,$elat1,$elon1,$to,$elat2,$elon2,$az2,$hwidm,$color); # 'orange'
    return $xg;
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
    my (@arr2,$wp,$ra,$color,$plat,$plon,$pcnt,$pwp);
    $lnn = 0;
    my %waypoints = ();
    #my $rfh = search_fix_file("MATIX");
    my $rfa = load_fix_file();
    my $rfh = load_fix_hash($rfa);
	my $rna = load_nav_file();

    my $max_lat = -400;
    my $max_lon = -400;
    my $min_lat = 400;
    my $min_lon = 400;
    my ($clat,$clon);
    $section = '';
    my $wpxg = "# Waypoints found in text\n";
    $pcnt = 0;
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
                    $max_lat = $lat if ($lat > $max_lat);
                    $max_lon = $lon if ($lon > $max_lon);
                    $min_lat = $lat if ($lat < $min_lat);
                    $min_lon = $lon if ($lon < $min_lon);
                    $wpxg .= "anno $lon $lat $name\n";
                    $wpxg .= "$lon $lat\n";
                    $wpxg .= "NEXT\n";
                    $pcnt++;
                } else {
                    prtw("WARNING:$lnn: [$inc] failed regex\n");
                }
            } else {
                pgm_exit(1,"Error: Section [$section] not coded! *** FIX ME ***\n");
            }
        }
    }

    write2file($wpxg,$tmp_xg);
    prt("Written waypoints collected to $tmp_xg\n");

    $clat = ($max_lat + $min_lat) / 2;
    $clon = ($max_lon + $min_lon) / 2;
    @arr = keys %{$rfh};
    $len = 0;
    foreach $name (@arr) {
        $ra = ${$rfh}{$name};
        $lat = ${$ra}[0];
        $lon = ${$ra}[1];
        if (defined $waypoints{$name}) {
            # how to choose
        } else {
            $waypoints{$name} = [$lat,$lon]; # ${$rfh}{$name}; # 
            $len++;
        }
    }
    prt("Added $len fixes to waypoints hash...\n");
    $len = 0;
    my ($res,$az1,$az2,$s,$s2);
    foreach $ra (@{$rna}) {
        $lat = ${$ra}[1];
        $lon = ${$ra}[2];
		$name  = ${$ra}[6];
        # UGH! This id could be a duplicate
        if (defined $waypoints{$name}) {
            $res = fg_geo_inverse_wgs_84($clat,$clon,$lat,$lon,\$az1,\$az2,\$s);
            if ($s < 300000) {
                $wp = $name;
                $ra = $waypoints{$wp};
                $plat = ${$ra}[0];
                $plon = ${$ra}[1];
                $res = fg_geo_inverse_wgs_84($clat,$clon,$plat,$plon,\$az1,\$az2,\$s2);
                if ($s < $s2) {
                    $waypoints{$name} = [$lat,$lon];
                    $len++;
                }
            }
        } else {
            $waypoints{$name} = [$lat,$lon];
            $len++;
        }
	}
    prt("Added $len navaids to waypoints hash...\n");

    $lnn = 0;
    $section = '';
    my %dupes = ();
    my %setwp = ();
    my $xg = "# sid/star/app from $inf\n";
    my ($msg);
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
                $color = $star_color;
                @arr2 = split(/\s+/,$name);
                $name = $arr2[0];
                @arr2 = split("-",$inc);
                $cnt = scalar @arr2;
                for ($i = 0; $i < $cnt; $i++) {
                    $inc = trim_all($arr2[$i]);
                    $arr2[$i] = $inc;
                }
                $msg = "$lnn:star $name = ".join(" ",@arr2)." ($cnt)";
                prt("$msg\n") if (VERB5());
                $xg .= "# $msg\n";
                $pcnt = 0;
                for ($i = 0; $i < $cnt; $i++) {
                    $wp = $arr2[$i];
                    last if ($wp =~ /^\#/);
                    if (defined $waypoints{$wp}) {
                        #if (!find_fix_id($rfa,$wp,\$lat,\$lon)) {
                            $ra = $waypoints{$wp};
                            $lat = ${$ra}[0];
                            $lon = ${$ra}[1];
                        #}
                        $xg .= "color $color\n";
                        if (!defined $setwp{$wp}) {
                            $setwp{$wp} = 1;
                            $xg .= "anno $lon $lat $wp\n";
                        }
                        $xg .= "$lon $lat\n";
                        $xg .= "NEXT\n";
                        if ($pcnt) {
                            $xg .= get_path_xg($pwp,$plat,$plon,$wp,$lat,$lon,$color);

                        }
                        $plat = $lat;
                        $plon = $lon;
                        $pwp  = $wp;
                        $pcnt++;
                    } else {
                        if (! defined $dupes{$wp}) {
                            $dupes{$wp} = 1;
                            prtw("WARNING: star waypoint [$wp] NOT in hash!\n");
                        }
                    }
                }

            } elsif ($section =~ /^SID/) {
                # to do
                $color = $sid_color;
                @arr2 = split(/\s+/,$name);
                $wp = $arr2[0]; # destination of this departure

                @arr2 = split("-",$inc);
                $cnt = scalar @arr2;
                for ($i = 0; $i < $cnt; $i++) {
                    $inc = trim_all($arr2[$i]);
                    $arr2[$i] = $inc;
                }
                prt("$lnn:sid $name = ".join(" ",@arr2)."\n");
                $pcnt = 0;
                if (defined $waypoints{$wp}) {
                    for ($i = 0; $i < $cnt; $i++) {
                        $wp = $arr2[$i];
                        last if ($wp =~ /^\#/);
                        if (defined $waypoints{$wp}) {
                            $ra = $waypoints{$wp};
                            $lat = ${$ra}[0];
                            $lon = ${$ra}[1];
                            $xg .= "color $color\n";
                            if (!defined $setwp{$wp}) {
                                $setwp{$wp} = 1;
                                $xg .= "anno $lon $lat $wp\n";
                            }
                            $xg .= "$lon $lat\n";
                            $xg .= "NEXT\n";
                            if ($pcnt) {
                                $xg .= get_path_xg($pwp,$plat,$plon,$wp,$lat,$lon,$color);

                            }
                            $plat = $lat;
                            $plon = $lon;
                            $pwp  = $wp;
                            $pcnt++;
                        } else {
                            if (! defined $dupes{$wp}) {
                                $dupes{$wp} = 1;
                                prtw("WARNING: app waypoint [$wp] NOT in hash!\n");
                            }
                        }
                    }
                } else {
                    if (! defined $dupes{$wp}) {
                        $dupes{$wp} = 1;
                        prtw("WARNING: app waypoint [$wp] NOT in hash!\n");
                    }
                }
            } elsif ($section =~ /^APP/) {
                $color = $app_color;
                @arr2 = split("-",$inc);
                $cnt = scalar @arr2;
                for ($i = 0; $i < $cnt; $i++) {
                    $inc = trim_all($arr2[$i]);
                    $arr2[$i] = $inc;
                }
                prt("$lnn:app $name = ".join(" ",@arr2)."\n") if (VERB5());
                $wp = $name;
                $pcnt = 0;
                if (defined $waypoints{$wp}) {
                    $ra = $waypoints{$wp};
                    $lat = ${$ra}[0];
                    $lon = ${$ra}[1];
                    $xg .= "color $color\n";
                    if (!defined $setwp{$wp}) {
                        $setwp{$wp} = 1;
                        $xg .= "anno $lon $lat $wp\n";
                    }
                    $xg .= "$lon $lat\n";
                    $xg .= "NEXT\n";
                    $plat = $lat;
                    $plon = $lon;
                    $pwp  = $wp;
                    $pcnt++;
                }
                for ($i = 0; $i < $cnt; $i++) {
                    $wp = $arr2[$i];
                    last if ($wp =~ /^\#/);
                    if (defined $waypoints{$wp}) {
                        $ra = $waypoints{$wp};
                        $lat = ${$ra}[0];
                        $lon = ${$ra}[1];
                        $xg .= "color $color\n";
                        if (!defined $setwp{$wp}) {
                            $setwp{$wp} = 1;
                            $xg .= "anno $lon $lat $wp\n";
                        }
                        $xg .= "$lon $lat\n";
                        $xg .= "NEXT\n";
                        if ($pcnt) {
                            $xg .= get_path_xg($pwp,$plat,$plon,$wp,$lat,$lon,$color);

                        }
                        $plat = $lat;
                        $plon = $lon;
                        $pwp  = $wp;
                        $pcnt++;
                    } else {
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

    if (length($usr_anno)) {
        $xg .= "$usr_anno\n";
        @arr = split(/\s+/,$usr_anno);
        $lon = $arr[1];
        $lat = $arr[2];
        $xg .= "color red\n";
        $xg .= "$lon $lat\n";
        # $xg .= "$clon $clat\n"; # no this is just the center of the wapoints collected
        $xg .= "NEXT\n";
    }

    rename_2_old_bak($out_file);
    write2file($xg,$out_file);
    prt("XG(raph) written to $out_file\n");
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
            } elsif ($sarg =~ /^f/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $fix_file = $sarg;
                prt("Set the fix file to [$fix_file].\n") if ($verb);
				if (! -f $fix_file) {
					pgm_exit(1,"Error: Can NOT locate $fix_file! Check name, location\n");
				}
            } elsif ($sarg =~ /^n/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $nav_file = $sarg;
                prt("Set the nav file to [$nav_file].\n") if ($verb);
				if (! -f $nav_file) {
					pgm_exit(1,"Error: Can NOT locate $nav_file! Check name, location\n");
				}
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
        if (length($usr_anno) == 0) {
            $usr_anno = $def_anno;
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
    my $msg = 'ok';
    if (! -f $fix_file) {
        $msg = '**NF**';
    }
    prt(" --fix <file>  (-f) = Set the fix.dat.gz file. (def=$fix_file $msg)\n");
	$msg = 'NF';
	$msg = 'ok' if (-f $nav_file);
    prt(" --nav <file>  (-n) = Set the nav.dat.gz file. (def=$nav_file $msg)\n");

}

# eof - template.pl
