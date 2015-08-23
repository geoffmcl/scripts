#!/usr/bin/perl -w
# NAME: apt2xg.pl
# AIM: Given an airport ICAO, write an XG(raph) file, using CSV inputs
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
# log file stuff
our ($LF);
my $outfile = $temp_dir.$PATH_SEP."temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_icao = '';
my $verbosity = 0;
my $out_file = $temp_dir.$PATH_SEP."tempapt.xg";
my $add_ils_point = 0;  # add the start point with anno of an ILS
my $ils_sep_degs = 3;

my $apts_csv = $perl_dir.'circuits'.$PATH_SEP.'airports2.csv';
my $rwys_csv = $perl_dir.'circuits'.$PATH_SEP.'runways.csv';
my $ils_csv = $perl_dir.'circuits'.$PATH_SEP.'ils.csv';

# ### DEBUG ###
my $debug_on = 1;
my $def_icao = 'LFPO';

### program variables
my @warnings = ();
my ($apt_icao,$in_lat,$in_lon);
my $apt_xg = '';
my %runwayhash = ();
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
        prtw("WARNING: can NOT locate csv $inf\n");
    }
}

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
    prt("Processing $lncnt lines, from [$inf]...\n");   # if (VERB9());
    my ($line,$inc,$lnn,@arr,$txt,$elat1,$elon1,$name);
    my ($elat2,$elon2,$wid,$sign,$key);
    my ($az1,$az2,$s,$res,$az3,$az4,$az5);
    my $rwycnt = 0;
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
            $rwycnt++;
        }
    }
    prt("Found $rwycnt runways using icao $icao\n");
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

sub process_in_icao($) {
    my $icao = shift;
    find_apt($icao);
	my $rwy_xg = process_runway_file($rwys_csv,$icao);    # draw the runways and label
    my $ils_xg = process_ils_csv($ils_csv,$icao);
    my $xg = $apt_xg;
    $xg .= $rwy_xg;
    $xg .= $ils_xg;

    rename_2_old_bak($out_file);
    write2file($xg,$out_file);
    prt("Written xg for $icao to $out_file\n");

}

#########################################
### MAIN ###
parse_args(@ARGV);
process_in_icao($in_icao);
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
            $in_icao = $arg;
            prt("Set input to [$in_icao]\n") if ($verb);
        }
        shift @av;
    }

    if ($debug_on) {
        prtw("WARNING: DEBUG is ON!\n");
        if (length($in_icao) ==  0) {
            $in_icao = $def_icao;
            prt("Set DEFAULT input to [$in_icao]\n");
        }
    }
    if (length($in_icao) ==  0) {
        pgm_exit(1,"ERROR: No input ICAO found in command!\n");
    }
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-icaoe\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>  (-o) = Write output to this file.\n");
}

# eof - template.pl
