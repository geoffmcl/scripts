#!/usr/bin/perl -w
# NAME: findawy.pl
# AIM: Given an airport ICAO, or a lat,lon, find all airways, hi and low within a given radius
# 16/08/2015 geoff mclane http://geoffair.net/mperl
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
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
###require 'logfile.pl' or die "Error: Unable to locate logfile.pl ...\n";
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
# log file stuff
our ($LF);
my $outfile = $temp_dir.$PATH_SEP."temp.$pgmname.txt";
open_log($outfile);
# Europe - Airways are corridors 10 nautical miles (19 km) wide of controlled airspace 
# with a defined lower base, usually FL070–FL100, extending to FL195.

# user variables
my $VERS = "0.0.5 2015-08-16";
my $load_log = 0;
my $in_icao = '';
my $in_lat = 400;
my $in_lon = 400;
my $search_rad_km = 100;	# was 200;
# but read this reduces closer to target, so try 10
my $airway_width_km = 10;	# was 19; # or 10 nautical miles
my $add_center_line = 0;
my $add_end_lines = 0;
my $max_count = 20;
my $add_second_end = 1;
my $add_arrow_centre = 0;
my $use_half_arrow = 1;
my $m_arrow_angle = 30;

my $verbosity = 0;
my $out_file = $temp_dir.$PATH_SEP."tempapts.csv";
my $xg_out   = $temp_dir.$PATH_SEP."tempawys.xg";

my $apt_file = $CDATROOT.$PATH_SEP.'Airports'.$PATH_SEP.'apt.dat.gz';
my $awy_file = $CDATROOT.$PATH_SEP.'Navaids'.$PATH_SEP.'awy.dat.gz';

my $apts_csv = $perl_dir.'circuits'.$PATH_SEP.'airports2.csv';

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'YGIL';

### program variables
my @warnings = ();

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

sub m_in_world_range($$) {
    my ($lat,$lon) = @_;
    if (($lat < -90) ||
        ($lat >  90) ||
        ($lon < -180) ||
        ($lon > 180) ) {
        return 0;
    }
    return 1;
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
                        $in_lat = $alat;
                        $in_lon = $alon;
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
            }
        } else {
            prtw("WARNING: apt no runways!!! $aptln\n");
        }
    }
    rename_2_old_bak($out_file);
    write2file($csv,$out_file);
    prt("Scanned $lnn lines... written csv to $out_file\n");
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
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        @arr = split(',',$line);
        $alat = $arr[0];
        $alon = $arr[1];
        $aalt = $arr[2];
        $type = $arr[3];
        $rwycnt = $arr[4];
        $icao = $arr[5];
        $name = join(' ', splice(@arr,6)); # Name
        if ($icao eq $ficao) {
            prt("Found $alat,$alon,$aalt,$type,$rwycnt,$icao,$name\n");
            $in_lat = $alat;
            $in_lon = $alon;
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

sub load_gzip_file($) {
    my ($fil) = shift;
	prt("[v2] Loading [$fil] file... moment...\n"); # if (VERB2());
	mydie("ERROR: Can NOT locate [$fil]!\n") if ( !( -f $fil) );
	open NIF, "gzip -d -c $fil|" or mydie( "ERROR: CAN NOT OPEN $fil...$!...\n" );
	my @arr = <NIF>;
	close NIF;
    prt("[v9] Got ".scalar @arr." lines to scan...\n") if (VERB9());
    return \@arr;
}

sub mycmp_decend_n0 {
   return -1 if (${$a}[0] < ${$b}[0]);
   return  1 if (${$a}[0] > ${$b}[0]);
   return 0;
}
sub mycmp_ascend_n0 {
   return  1 if (${$a}[0] < ${$b}[0]);
   return -1 if (${$a}[0] > ${$b}[0]);
   return 0;
}
sub set_lat_lon($) {
	my $rv = shift;
	${$rv} = sprintf("%.6f", ${$rv});
}

sub get_arrow_xg($$$$$$$$) {
    my ($from,$wlat1,$wlon1,$to,$wlat2,$wlon2,$whdg1,$wsize) = @_;
    my $xg = '';
    my ($wlatv1,$wlonv1,$whdg,$wlatv2,$wlonv2,$waz1,$tmp,$tmp2);

	$tmp = int($whdg1 + 0.5);
	$tmp2 = int($wsize / 1000);
	### $xg .= "# end arrows from $wlat1,$wlon1 to $wlat2,$wlon2, hdg $tmp, size $tmp2 km\n";
	$xg .= "# end arrows from $from to $to, hdg $tmp, size $tmp2 km\n";

    ## $xg .= "color gray\n";
    $xg .= "color orange\n";
    $whdg = $whdg1 + $m_arrow_angle; # was 30
    $whdg -= 360 if ($whdg > 360);
    fg_geo_direct_wgs_84($wlat1,$wlon1, $whdg, $wsize, \$wlatv1, \$wlonv1, \$waz1 );
    $xg .= "$wlon1 $wlat1\n";
    $xg .= "$wlonv1 $wlatv1\n";
    $xg .= "NEXT\n";

    if ($add_second_end) {
        fg_geo_direct_wgs_84($wlat2,$wlon2, $whdg, $wsize, \$wlatv2, \$wlonv2, \$waz1 );
        $xg .= "$wlon2 $wlat2\n";
        $xg .= "$wlonv2 $wlatv2\n";
        $xg .= "NEXT\n";
    }
    if ($add_arrow_centre) {
        ## $xg .= "$wlonv1 $wlatv1\n";
        ## $xg .= "$wlonv2 $wlatv2\n";
        ## $xg .= "NEXT\n";
    }

    $whdg = $whdg1 - $m_arrow_angle; # was 30
    $whdg += 360 if ($whdg < 0);
    fg_geo_direct_wgs_84($wlat1,$wlon1, $whdg, $wsize, \$wlatv1, \$wlonv1, \$waz1 );
    $xg .= "$wlon1 $wlat1\n";
    $xg .= "$wlonv1 $wlatv1\n";
    $xg .= "NEXT\n";

    if ($add_second_end) {
        fg_geo_direct_wgs_84($wlat2,$wlon2, $whdg, $wsize, \$wlatv2, \$wlonv2, \$waz1 );
        $xg .= "$wlon2 $wlat2\n";
        $xg .= "$wlonv2 $wlatv2\n";
        $xg .= "NEXT\n";
    }

    ## $xg .= "$wlonv1 $wlatv1\n";
    ## $xg .= "$wlonv2 $wlatv2\n";
    ## $xg .= "NEXT\n";
    return $xg;
}

sub get_airway_strip($$$$$$) {
    my ($from,$elat1,$elon1,$to,$elat2,$elon2) = @_;
    my $widm = $airway_width_km * 1000;
    my $hwidm = $widm / 2;
    my ($az1,$az2,$s,$az3,$az4,$az5);
    my ($lon1,$lon2,$lon3,$lon4,$lat1,$lat2,$lat3,$lat4);
    my ($clat,$clon);
    my $xg = '';
    #################################################
    my $res = fg_geo_inverse_wgs_84($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
    $res = fg_geo_direct_wgs_84($elat1,$elon1, $az1, ($s / 2), \$clat, \$clon, \$az5);

    ### my ($wlat1,$wlon1,$wlat2,$wlon2,$whdg1,$wsize) = @_;
	my $wsize = $use_half_arrow ? $hwidm : $widm;
    $xg .= get_arrow_xg($from,$elat1,$elon1,$to,$elat2,$elon2,$az1,$wsize);

    # outline of airway, with width
    $az3 = $az1 + 90;
    $az3 -= 360 if ($az3 >= 360);
    $az4 = $az1 - 90;
    $az4 += 360 if ($az4 < 0);

    $res = fg_geo_direct_wgs_84($elat1,$elon1, $az3, $hwidm, \$lat1, \$lon1, \$az5);
    $res = fg_geo_direct_wgs_84($elat1,$elon1, $az4, $hwidm, \$lat2, \$lon2, \$az5);
    $res = fg_geo_direct_wgs_84($elat2,$elon2, $az4, $hwidm, \$lat3, \$lon3, \$az5);
    $res = fg_geo_direct_wgs_84($elat2,$elon2, $az3, $hwidm, \$lat4, \$lon4, \$az5);

	# XG output
	$xg .= "# airway strip from $from to $to - add-end=$add_end_lines\n";
    $xg .= "color gray\n";
    if ($add_end_lines) {
        # make it a closed box
        $xg .= "$lon1 $lat1\n";
        $xg .= "$lon2 $lat2\n";
        $xg .= "$lon3 $lat3\n";
        $xg .= "$lon4 $lat4\n";
        $xg .= "$lon1 $lat1\n";
        $xg .= "NEXT\n";
    } else {
        # just draw the sides
        $xg .= "$lon1 $lat1\n";
        $xg .= "$lon4 $lat4\n";
        $xg .= "NEXT\n";
        $xg .= "$lon2 $lat2\n";
        $xg .= "$lon3 $lat3\n";
        $xg .= "NEXT\n";
    }
    return $xg;
}


sub search_awys_near($$$) {
    my ($raa,$lat,$lon) = @_;
    my $max = scalar @{$raa};
    my ($line,$len,@arr,$cnt,$typ,$flat,$flon,$fname,$name,$key);
    my ($tlat,$tlon,$from,$to,$hadver);
    my ($cat,$bfl,$efl,$ra,$lnn,$res);
    my ($az1,$az2,$dist);
    my ($dist1,$dist2,$ccnt);
    my $max_dist = $search_rad_km * 1000; # was 200000
    my %h = ();
    $lnn = 0;
    $hadver = 0;
    my @narr = ();
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
            $res = fg_geo_inverse_wgs_84($lat,$lon,$flat,$flon,\$az1,\$az2,\$dist1);
            $res = fg_geo_inverse_wgs_84($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist2);
            $dist = $dist1;
            $dist = $dist2 if ($dist2 < $dist1);

            ## $h{$from} = [ ] if (!defined $h{$from});
            ## $ra = $h{$from};
            ## #              0      1      2    3      4      5     6     7     8
            ## push(@{$ra}, [ $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl, $name ]);
            ## $h{$to} = [ ] if (!defined $h{$to});
            ## $ra = $h{$to};
            ## push(@{$ra}, [ $tlat, $tlon, $from, $flat, $flon, $cat, $bfl, $efl, $name ]);
            push(@narr, [$dist, $from, $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl, $name ]);
        }
    }
    # sort by distance
    my @sarr = sort mycmp_decend_n0 @narr;
    $cnt = 0;
	my $xg = "# airways near $lat,$lon\n";
    foreach $ra (@sarr) {
		#              0      1      2      3      4    5      6      7     8     9     10
        # push(@narr, [$dist, $from, $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl, $name ]);
        $dist = ${$ra}[0];
        $from = ${$ra}[1];
        $flat = ${$ra}[2];
        $flon = ${$ra}[3];
        $to   = ${$ra}[4];
        $tlat = ${$ra}[5];
        $tlon = ${$ra}[6];
        $cat  = ${$ra}[7];
        $bfl  = ${$ra}[8];
        $efl  = ${$ra}[9];
        $name = ${$ra}[10];
        last if ($dist > $max_dist);

        $xg .= get_airway_strip( $from, $flat, $flon, $to, $tlat, $tlon );

		$xg .= "anno $flon $flat $from\n";
		$xg .= "anno $tlon $tlat $to\n";
        if ($add_center_line) {
            if ($cat == 1) {
                $xg .= "color blue\n";
            } else {
                $xg .= "color green\n";
            }
            $xg .= "$flon $flat\n";
            $xg .= "$tlon $tlat\n";
            $xg .= "NEXT\n";
        }

		# for display
		$from .= " " while (length($from) < 5);
		$to   .= " " while (length($to) < 5);
        $dist = sprintf("%3d",int(($dist + 0.5) / 1000));
		set_lat_lon(\$flat);
		set_lat_lon(\$flon);
		set_lat_lon(\$tlat);
		set_lat_lon(\$tlon);
		$ccnt = sprintf("%2d",$cnt);
        prt("$ccnt: $dist, $from, $flat, $flon, $to, $tlat, $tlon, $cat, $bfl, $efl, $name\n");

        $cnt++;
        ###last if ($cnt > 10);
		last if ($max_count && ($cnt > $max_count));
    }

	# add the center point
	$xg .= "color red\n";
	$xg .= "$lon $lat\n";
	$xg .= "NEXT\n";
	$xg .= "anno $lon $lat C: ";
	if (length($in_icao)) {
		$xg .= "$in_icao ";
	}
	$xg .= "$lat,$lon\n";

	# write xg file
	rename_2_old_bak($xg_out);
	write2file($xg,$xg_out);
	$line = "Airways near ";
	$line .= "$in_icao " if (length($in_icao));
	$line .= "$lat,$lon ";
	prt("$line, written to $xg_out\n");
}


sub process_lat_lon() {
    my $lat = $in_lat;
    my $lon = $in_lon;
    if (!m_in_world_range($lat,$lon)) {
        pgm_exit(1,"lat/lon $lat,$lon NOT in world!\n");
    }
    my $rla = load_gzip_file($awy_file);
    my $lncnt = scalar @{$rla};
    prt("Got $lncnt lines to process from $awy_file...\n");
    search_awys_near($rla,$lat,$lon);
    prt("Done...\n");
}

#########################################
### MAIN ###
parse_args(@ARGV);
process_lat_lon();
pgm_exit(0,"");
########################################

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg);
	my $cnt = 0;
    my $verb = VERB2();
    while (@av) {
		$cnt++;
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
            } elsif ($sarg =~ /^a/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $awy_file = $sarg;
                prt("Set awy file to [$awy_file].\n") if ($verb);
				if (! -f $awy_file) {
					pgm_exit(1,"Error: can NOT locate $awy_file!\n");
				}
            } elsif ($sarg =~ /^A/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $apt_file = $sarg;
                prt("Set apt file to [$apt_file].\n") if ($verb);
				if (! -f $apt_file) {
					pgm_exit(1,"Error: can NOT locate $apt_file!\n");
				}
            } else {
                pgm_exit(1,"ERROR:$cnt: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            $in_icao = $arg;
            prt("Set input to [$in_icao]\n") if ($verb);
        }
        shift @av;
    }

    if ($debug_on) {
        prtw("WARNING: DEBUG is ON!\n");
        if (length($in_icao) ==  0) {
            $in_icao = $def_file;
            prt("Set DEFAULT input to [$in_icao]\n");
        }
    }
    if (length($in_icao)) {
        find_apt($in_icao);
        if (($in_lat == 400) || ($in_lon == 400)) {
            pgm_exit(1,"ERROR: input ICAO $in_icao NOT found!\n");
        }
    }
    if ((length($in_icao) ==  0) && (($in_lat == 400) || ($in_lon == 400)) ) {
        give_help();
        pgm_exit(1,"ERROR: No input found in command!\n");
    }
}

sub give_help {
    my ($msg);
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] icao or lat,lon\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>  (-o) = Write output to this file.\n");
    $msg = 'ok';
    if (! -f $awy_file) {
        $msg = '**NF**';
    }
    prt(" --awy <file>  (-a) = Set the awy.dat.gz file. (def=$awy_file $msg)\n");
    $msg = 'ok';
    if (! -f $apt_file) {
        $msg = '**NF**';
    }
    prt(" --Apt <file>  (-A) = Set the apt.dat.gz file. (def=$apt_file $msg)\n");
}

# eof - template.pl
