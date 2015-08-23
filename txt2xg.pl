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
my $in_icao = '';
my $usr_line = '';

my $add_star_wps = 1;
my $add_sid_wps = 1;
my $add_app_wps = 1;

my $m_max_path = 300000;    # was 100000
my $m_path_widthm = 500; # was 300; # was 5000;   
my $m_arrow_angle = 30;
my $add_second_end = 1;
my $add_arrow_sides = 1;

my $add_ils_point = 0;  # add the start point with anno of an ILS
my $ils_sep_degs = 3;

# ### DEBUG ###
my $debug_on = 1;
#my $def_file = 'C:\Users\user\Documents\FG\LFPO.procedures.txt';
my $def_file = $perl_dir.'circuits'.$PATH_SEP.'LFPO.procedures.txt';
my $def_anno = "anno 2.308119 48.75584 Rue Pernoud, Antony";
my $def_line = "color gray\n".
"2.306127,48.756332\n".
"2.308844,48.755655\n".
"NEXT\n";

my $def_icao = 'LFPO';

### program variables
my @warnings = ();
my $tmp_xg = $temp_dir.$PATH_SEP."temptemp.xg";
my $apt_icao = '';
my ($in_lat,$in_lon);
my $apt_xg = '';
my $METER2NM = 0.000539957;
my $NM2METER = 1852;

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
my $ils_csv = $perl_dir.'circuits'.$PATH_SEP.'ils.csv';

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

###################################################################
### APT XG

sub get_opposite_rwy($) {
	my $rwy = shift;
	my $rwy2 = '';
	if ($rwy =~ /^(\d+)(R|L|C)*$/) {
		$rwy2 = ($1 > 18) ? $1 - 18 : $1 + 18;
		$rwy2 = '0'.$rwy2 if ($rwy2 < 10);
        if (defined $2) {
			$rwy2 .= 'L' if ($2 eq 'R');
            $rwy2 .= 'R' if ($2 eq 'L');
            $rwy2 .= 'C' if ($2 eq 'C');
        }
	}
	return $rwy2;
}

my %runwayhash = ();

# 0    1    2    3    4    5     6
# icao,lat1,lon1,lat2,lon2,width,sign
# VHXX,22.32526300,114.19222700,22.30395000,114.21587400,54.86,13
# E46,29.88083567,-103.70108085,29.86895821,-103.69317249,30.48,15
sub process_runway_file($$) {
    my ($inf,$icao) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n") if (VERB9());
    my ($line,$inc,$lnn,@arr,$txt,$elat1,$elon1,$name);
    my ($elat2,$elon2,$wid,$sign,$key);
    my ($az1,$az2,$s,$res,$az3,$az4,$az5);
    $lnn = 0;
    my $xg = '';
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        next if ($lnn == 1);
        @arr = split(",",$line);
        $txt = $arr[0];
        if ($txt eq $icao) {
            $elat1 = $arr[1];
            $elon1 = $arr[2];
            $elat2 = $arr[3];
            $elon2 = $arr[4];
            $wid  = $arr[5];
            $name = $arr[6];
            $res = fg_geo_inverse_wgs_84($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
			# mark ENDS, and center line
            $xg .= "color blue\n";
            $xg .= "anno $elon1 $elat1 $name\n";
            $xg .= "$elon1 $elat1\n";
            $xg .= "$elon2 $elat2\n";
            $xg .= "NEXT\n";
            my ($lat1,$lon1,$lat2,$lon2,$lat3,$lon3,$lat4,$lon4,$rwy2);

            $key = "RWY".$name;
            $runwayhash{$key} = [$elat1,$elon1];
			$rwy2 = get_opposite_rwy($name);
            if (length($rwy2)) {
                $xg .= "anno $elon2 $elat2 $rwy2\n";
                $key = "RWY".$rwy2;
                $runwayhash{$key} = [$elat2,$elon2];
            }

			# draw runway rectangles
            my $hwidm = $wid / 2;
            $xg .= "color red\n";
            $az3 = $az1 + 90;
            $az3 -= 360 if ($az3 >= 360);
            $az4 = $az1 - 90;
            $az4 += 360 if ($az4 < 0);
            $res = fg_geo_direct_wgs_84($elat1,$elon1, $az3, $hwidm, \$lat1, \$lon1, \$az5);
            $res = fg_geo_direct_wgs_84($elat1,$elon1, $az4, $hwidm, \$lat2, \$lon2, \$az5);
            $res = fg_geo_direct_wgs_84($elat2,$elon2, $az4, $hwidm, \$lat3, \$lon3, \$az5);
            $res = fg_geo_direct_wgs_84($elat2,$elon2, $az3, $hwidm, \$lat4, \$lon4, \$az5);
            $xg .= "$lon1 $lat1\n";
            $xg .= "$lon2 $lat2\n";
            $xg .= "$lon3 $lat3\n";
            $xg .= "$lon4 $lat4\n";
            $xg .= "$lon1 $lat1\n";
            $xg .= "NEXT\n";
        }
    }
    return $xg;
}

sub find_apt_gz($) {
    my $ficao = shift;
    my ($cnt,$msg);
    my $aptdat = $apt_file;
    #### pgm_exit(1,"TEMP EXIT\n");
    prt("[v9] Loading $aptdat file ... moment..\n"); # if (VERB9());
    mydie("ERROR: Can NOT locate $aptdat ...$!...\n") if ( !( -f $aptdat) );
    ###open IF, "<$aptdat" or mydie("OOPS, failed to open [$aptdat] ... check name and location ...\n");
    open IF, "gzip -d -c $aptdat|" or mydie( "ERROR: CAN NOT OPEN $aptdat...$!...\n" );
    my @lines = <IF>;
    close IF;
    $cnt = scalar @lines;
    prt("[v9] Got $cnt lines to scan for ICAO $ficao...\n"); # if (VERB9());
    my ($line,$len,$type,@arr);
    my $g_version = 0;
    foreach $line (@lines) {
        chomp $line;
        $line = trim_all($line);
        if ($line =~ /\s+Version\s+/i) {
            @arr = split(/\s+/,$line);
            $g_version = $arr[0];
            $msg .= "Version $g_version";
            last;
        }
    }
    prt("$msg\n") if (VERB1());
    my $lnn = 0;
    my ($rlat,$rlon,$glat,$glon,$rwyt,$rwycnt,$got_twr,$alat,$alon);
    my ($rlat1,$rlon1,$rlat2,$rlon2,$wwcnt,$helicnt,$aptln);
    my ($aalt,$actl,$abld,$icao,$name,@arr2);
    #my $acsv = "icao,latitude,longitude,name\n";
    $glat = 0;
    $glon = 0;
    $rwycnt = 0;
    $wwcnt = 0;
    $helicnt = 0;
    $got_twr = 0;
    $aptln = '';
    my $csv = "lat,lon,altft,type,rwys,icao,name\n";
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        $line = trim_all($line);
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
        @arr = split(/ /,$line);
        $type = $arr[0];
        ###if ($line =~ /^1\s+/) {	# start with '1'
        # if 1=Airport, 16=SeaPlane, 17=Heliport
        if ($type == 99) {
        ### } elsif ($line =~ /^$lastln\s?/) {	# 99, followed by space, count 0 or more ...
            prt( "[v9] Reached END OF FILE ... \n" ) if (VERB9());
            last;
        }
        if (($type == 1)||($type == 16)||($type == 17)) {	# start with 1, 16, 17
            #prt("$lnn: $line\n");
            $rwycnt += $wwcnt;
            $rwycnt += $helicnt;
            if (length($aptln)) {
                if ($rwycnt > 0) {
                    if (!$got_twr) {
                        $alat = $glat / $rwycnt;
                        $alon = $glon / $rwycnt;
                    }
                    @arr2 = split(/\s+/,$aptln);
                    $aalt = $arr2[1]; # Airport (general) ALTITUDE AMSL
                    $actl = $arr2[2]; # control tower
                    $abld = $arr2[3]; # buildings
                    $icao = $arr2[4]; # ICAO
                    $name = join(' ', splice(@arr2,5)); # Name
                    $csv .= "$alat,$alon,$aalt,$type,$rwycnt,$icao,$name\n";
                    if ($ficao eq $icao) {
                        prt("Found $alat,$alon,$aalt,$type,$rwycnt,$icao,$name\n");
                        $apt_icao = $icao;
                        $in_lat = $alat;
                        $in_lon = $alon;
                        $apt_xg = "anno $in_lon $in_lat $icao $name";
                    }
                } else {
                    prtw("WARNING: apt no runways!!! $aptln\n");
                }
            }
            $aptln = $line;
            $glat = 0;
            $glon = 0;
            $rwycnt = 0;
            $got_twr = 0;
            $wwcnt = 0;
            $helicnt = 0;
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
                ###my @ar3 = @arr;
                ###push(@runways, \@ar3);
                prt("$lnn: $line\n");
            }
        } elsif (($type >= 50)&&($type <= 56)) {
            # frequencies
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
            $rwycnt++;
            ##my @a2 = @arr;
            ##push(@runways, \@a2);
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
            if (!m_in_world_range($rlat,$rlon)) {
                prtw( "WARNING: $.: $line [$rlat, $rlon] NOT IN WORLD\n" );
                next;
            }
            $glat += $rlat;
            $glon += $rlon;
            ##my @a2 = @arr;
            ##push(@waterways, \@a2);
            $wwcnt++;
        } elsif ($type == 102) {	# Heliport
            # my $heli =   '102'; # Helipad
            # 0   1  2           3            4      5     6     7 8 9 10   11
            # 102 H2 52.48160046 013.39580674 355.00 18.90 18.90 2 0 0 0.00 0
            # 102 H3 52.48071507 013.39937648 2.64   13.11 13.11 1 0 0 0.00 0
            # prt("$.: $line\n");
            $rlat = sprintf("%.8f",$arr[2]);
            $rlon = sprintf("%.8f",$arr[3]);
            if (!m_in_world_range($rlat,$rlon)) {
                prtw( "WARNING: $.: $line [$rlat, $rlon] NOT IN WORLD\n" );
                next;
            }
            $glat += $rlat;
            $glon += $rlon;
            #my @a2 = @arr;
            #push(@heliways, \@a2);
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
        } else {
            pgm_exit(1,"Uncase line $line\n");
        }
    }
    ################################
    # process LAST airport
    $rwycnt += $wwcnt;
    $rwycnt += $helicnt;
    if (length($aptln)) {
        if ($rwycnt > 0) {
            if (!$got_twr) {
                $alat = $glat / $rwycnt;
                $alon = $glon / $rwycnt;
            }
            @arr2 = split(/\s+/,$aptln);
            $aalt = $arr2[1]; # Airport (general) ALTITUDE AMSL
            $actl = $arr2[2]; # control tower
            $abld = $arr2[3]; # buildings
            $icao = $arr2[4]; # ICAO
            $name = join(' ', splice(@arr2,5)); # Name
            $csv .= "$alat,$alon,$aalt,$type,$rwycnt,$icao,$name\n";
            if ($ficao eq $icao) {
                prt("Found $alat,$alon,$aalt,$type,$rwycnt,$icao,$name\n");
                $apt_icao = $icao;
                $in_lat = $alat;
                $in_lon = $alon;
                $apt_xg = "anno $in_lon $in_lat $aalt $icao $name\n";
				$apt_xg .= "color red\n";
		        $apt_xg .= "$in_lon $in_lat\n";
				$apt_xg .= "NEXT\n";
            }
        } else {
            prtw("WARNING: apt no runways!!! $aptln\n");
        }
    }
    rename_2_old_bak($apts_csv);
    write2file($csv,$apts_csv);
    prt("Scanned $lnn lines... written csv to $apts_csv\n");
}

sub find_apt_csv($$) {
    my ($ficao,$inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($line,$inc,$lnn,@arr);
    $lnn = 0;
    my ($alat,$alon,$aalt,$type,$rwycnt,$icao,$name);
	# $apt_xg = # seek airport $ficao\n";
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        @arr = split(',',$line);
        $icao = $arr[5];
        if ($icao eq $ficao) {
			$alat = $arr[0];
			$alon = $arr[1];
			$aalt = $arr[2];
			$type = $arr[3];
			$rwycnt = $arr[4];
			$name = join(' ', splice(@arr,6)); # Name
            prt("Found $alat,$alon,$aalt,$type,$rwycnt,$icao,$name\n");
            $apt_icao = $icao;
            $in_lat = $alat;
            $in_lon = $alon;
			$apt_xg .= "color red\n";
            $apt_xg .= "$in_lon $in_lat\n";
			$apt_xg .= "NEXT\n";
            $apt_xg .= "anno $in_lon $in_lat $aalt $icao $name\n";
            last;
        }
    }
}

sub find_apt($) {
    my $ficao = shift;
    my $inf = $apts_csv;
    if (-f $inf) {
        find_apt_csv($ficao,$inf);
    } else {
        find_apt_gz($ficao);
    }
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

# type,lat,lon,alt,frq,rng,frq2,id,icao,rwy,name
# 0 1           2             3   4     5  6       7    8   9  10
# 4,39.98091100,-075.87781400,660,10850,18,281.662,IMQS,40N,29,ILS-cat-I
# 4,-09.45892200,147.23122500,128,11010,18,148.638,IWG,AYPY,14L,ILS-cat-I
sub process_ils_csv($$) {
    my ($inf,$icao) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");   # if (VERB9());
    my ($line,@arr,$cnt,$freq);
    my ($res,$az1,$az2,$dist,$lat1,$lon1,$rhdg,$lat2,$lon2,$elat1,$elon1);
    my $lnn = 0;
    my $ilscnt = 0;
    my $xg = '';
    #   0    1    2    3    4    5    6    7   8     9    10
    my ($typ,$lat,$lon,$alt,$frq,$rng,$hdg,$id,$ica,$rwy,$nam);
    my @rwys = ();
    my $hdegs = $ils_sep_degs / 2;
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        next if ($lnn < 2); # skip first line
        @arr = split(",",$line);
        $cnt = scalar @arr;
        if ($cnt < 11) {
            pgm_exit(1,"Error: bad csv line! split $cnt, expected 11\n");
        }
        $typ = $arr[0];
        $ica = $arr[8];
        if (($icao eq $ica)&&($typ == 4)) {
            ### $typ = $arr[0];
            $lat = $arr[1];
            $lon = $arr[2];
            $alt = $arr[3];
            $frq = $arr[4];
            $rng = $arr[5];
            $hdg = $arr[6];
            $id  = $arr[7];
            ### $ica = $arr[8];
            $rwy = $arr[9];
            $nam = $arr[10];
            if ($nam =~ /^ILS/) {
                $ilscnt++;
                push(@rwys,$rwy);
                $freq = $frq / 100;
                $dist = $rng * $NM2METER;
                $rhdg = $hdg + 180;
                $rhdg -= 360 if ($rhdg >= 360);
                
                if ($add_ils_point) {
                    $xg .= "color yellow\n";
                    $xg .= "$lon $lat\n";
                    $xg .= "NEXT\n";
                    $xg .= "anno $lon $lat ILS RWY $rwy $freq\n";
                }
                # get the center line end on the reve ILS heading, for the range minus 1.5 km
                $res = fg_geo_direct_wgs_84($lat,$lon,$rhdg,($dist - 1500),\$elat1,\$elon1,\$az2);
                # get plus half the degree sep/spead
                $az1 = $rhdg + $hdegs;
                $az1 -= 360 if ($az1 >= 360);
                $res = fg_geo_direct_wgs_84($lat,$lon,$az1,$dist,\$lat1,\$lon1,\$az2);
                # get plus half the degree sep/spead
                $az1 = $rhdg - $hdegs;
                $az1 += 360 if ($az1 < 0);
                $res = fg_geo_direct_wgs_84($lat,$lon,$az1,$dist,\$lat2,\$lon2,\$az2);

                # join the dots
                $xg .= "color gray\n";
                $xg .= "$lon $lat\n";
                $xg .= "$lon1 $lat1\n";
                $xg .= "NEXT\n";
                $xg .= "$lon $lat\n";
                $xg .= "$lon2 $lat2\n";
                $xg .= "NEXT\n";
                # arrow lines
                $xg .= "$elon1 $elat1\n";
                $xg .= "$lon1 $lat1\n";
                $xg .= "NEXT\n";
                $xg .= "$elon1 $elat1\n";
                $xg .= "$lon2 $lat2\n";
                $xg .= "NEXT\n";
                $xg .= "anno $elon1 $elat1 ILS RWY $rwy $freq\n";

            }
        }

    }
    prt("Found $ilscnt ILS for $icao, rwys ".join(" ",@rwys)."\n");
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

	if (length($apt_icao)) {    # given an airport ICAO, load info
		find_apt($apt_icao);    # find airport in csv, or apt.dat.gz file - gen $apt_xg if found...
	    if (length($apt_xg)) {
			if (-f $rwys_csv) {     # def  = $perl_dir."circuits/runways.csv";
				$apt_xg .= process_runway_file($rwys_csv,$apt_icao);    # draw the runways and label
			}
			if (-f $ils_csv) {
				$apt_xg .= process_ils_csv($ils_csv,$apt_icao);
			}
		}
	}

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

    rename_2_old_bak($tmp_xg);
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

    my ($msg);
    $lnn = 0;
    $section = '';
    my %dupes = ();
    my %setwp = ();
    $msg = "sid/star/app from $inf opts: star=$add_star_wps, sid=$add_sid_wps, app=$add_app_wps";
    my $xg = "# $msg\n";
	prt("$msg\n");
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
				next if (!$add_star_wps);
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
                $color = $sid_color;
				next if (!$add_sid_wps);
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
				next if (!$add_app_wps);
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

    if (length($apt_xg)) {
	    $xg .= "$apt_xg";   # add the airport anno to the output...
	}
    if (length($usr_anno)) {
		$xg .= "# User annon\n";
        $xg .= "$usr_anno\n";
        @arr = split(/\s+/,$usr_anno);
        $lon = $arr[1];
        $lat = $arr[2];
        $xg .= "color red\n";
        $xg .= "$lon $lat\n";
        # $xg .= "$clon $clat\n"; # no this is just the center of the wapoints collected
        $xg .= "NEXT\n";
    }

    if (length($usr_line)) {
		$xg .= "# User line\n";
		$xg .= $usr_line;
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
		#$add_star_wps = 0;
		#$add_app_wps  = 0;
		$apt_icao = $def_icao;
		$usr_line = $def_line;
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
