#!/usr/bin/perl -w
# NAME: xml2xg.pl
# AIM: Given a SID/STAR xml procedure file, render as an xg 2D graph
# 05/08/2015 geoff mclane http://geoffair.net/mperl
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use XML::Simple;
use Data::Dumper;
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";

# log file stuff
our ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
$outfile = path_u2d($outfile) if ($os =~ /win/i);
open_log($outfile);

# user variables
my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';
my $apts_csv = $perl_dir."circuits/airports.csv";
my $rwys_csv = $perl_dir."circuits/runways.csv";

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'circuits\EHAM.procedures.xml';
my $def_xg = $temp_dir."/tempsidstar.xg";

### program variables
my @warnings = ();
my $cwd = cwd();

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

sub process_in_file2($) {
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

##??    'HASH(0x319fd98)' => 1,
my %waypointkeys = (
    'Altitude' => 1,
    'AltitudeRestriction' => 1,
    'Hld_Rad_or_Inbd' => 1,
    'Hld_Rad_value' => 1,
    'Hld_Time_or_Dist' => 1,
    'Hld_Turn' => 1,
    'Hld_td_value' => 1,
    'ID' => 1,
    'Latitude' => 1,
    'Longitude' => 1,
    'Name' => 1,
    'Speed' => 1,
    'Type' => 1
);

my %wpminkeys = (
    'ID' => 1,
    'Latitude' => 1,
    'Longitude' => 1,
    'Name' => 1,
    'Type' => 1
);

sub is_valid_wp($) {
    my $wp = shift;
    my ($key);
    foreach $key (keys %wpminkeys) {
        return 0 if (!defined ${$wp}{$key});
    }
    return 1;
}
sub get_wp_info($) {
    my $wp = shift;
    return ${$wp}{'Name'},${$wp}{'ID'},${$wp}{'Latitude'},${$wp}{'Longitude'},${$wp}{'Type'};
}

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

sub get_path_xg($$$$) {
    my ($elat1,$elon1,$elat2,$elon2) = @_;
    my ($az1,$az2,$s,$az3,$az4,$az5);
    my ($lat1,$lon1,$lat2,$lon2,$lat3,$lon3,$lat4,$lon4);
    my $hwidm = 300;   # was 5000;   
    #################################################
    my $res = fg_geo_inverse_wgs_84($elat1,$elon1,$elat2,$elon2,\$az1,\$az2,\$s);
    ## $res = fg_geo_direct_wgs_84($elat1,$elon1, $az1, ($s / 2), \$clat, \$clon, \$az5);
    if ($s < $hwidm) {
        return "# Dist too small $s\n";
    } elsif ($s > 100000) {
        $s = (int($s * 10) / 10);
        return "# Dist GT 100Km $elat1,$elon1 $elat2,$elon2 $s\n";
    }
    #################################################
    $az3 = $az1 + 90;
    $az3 -= 360 if ($az3 >= 360);
    $az4 = $az1 - 90;
    $az4 += 360 if ($az4 < 0);
    my $wkm = get_dist_stg_km($hwidm * 2);
    my $lkm = get_dist_stg_km($s);
    my $xg = "# Rect using $elat1,$elon1 $elat2,$elon2 len $lkm, wid $wkm\n";
    $xg .= "color gray\n";
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
    return $xg;
}

my $add_star_wps = 1;
my $add_sid_wps = 1;
my $add_app_wps = 1;
# 0    1        2         3...
# icao,latitude,longitude,name
# VHXX,22.32753500,114.19287600,[X] CLOSED Kai Tak
# E46,29.87489694,-103.69712667,02 Ranch
sub process_airports_file($$) {
    my ($inf,$icao) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($line,$inc,$lnn,@arr,$txt,$lat,$lon,$name);
    $lnn = 0;
    my $xg = '';
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        next if ($lnn == 1);
        @arr = split(",",$line);
        $txt = $arr[0];
        if ($txt eq $icao) {
            $lat = $arr[1];
            $lon = $arr[2];
            $name = join(',', splice(@arr,3)); # Name
            $xg = "anno $lon $lat $icao $name\n";
            last;
        }
    }
    return $xg;
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
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($line,$inc,$lnn,@arr,$txt,$elat1,$elon1,$name);
    my ($elat2,$elon2,$wid,$sign);
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

            $xg .= "color blue\n";
            $xg .= "anno $elon1 $elat1 $name\n";
            $xg .= "$elon1 $elat1\n";
            $xg .= "$elon2 $elat2\n";
            $xg .= "NEXT\n";
            my ($lat1,$lon1,$lat2,$lon2,$lat3,$lon3,$lat4,$lon4);
            my $hwidm = $wid / 2;
            $xg .= "color red\n";
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
        }
    }
    return $xg;
}

sub add_airport_xg($) {
    my $icao = shift;
    my $xg = "";
    if (-f $apts_csv) {    # def = $perl_dir."circuits/airports.csv";
        $xg .= process_airports_file($apts_csv,$icao);
    }
    if (-f $rwys_csv) {     # def  = $perl_dir."circuits/runways.csv";
        $xg .= process_runway_file($rwys_csv,$icao);
    }
    return $xg;
}

sub process_in_file($) {
    my ($inf) = @_;
    my $xref = XMLin($inf);
    #prt(Dumper($xref));
    if (! defined ${$xref}{'Airport'}) {
        pgm_ext(1,"File $inf does not have 'Airport'\n");
    }
    my $aref = ${$xref}{'Airport'};
    #prt(Dumper($aref));
    #$load_log = 1;
    # expect something like Star Approach ICAOcode Sid
    my @arr = keys %{$aref};
    my $cnt = scalar @arr;
    my ($key,$icao,$wprh,$name,$wpra,$wpcnt,$wp);
    my (@arr2,$msg,$wpvcnt);
    my ($nm,$id,$lat,$lon,$typ);
    my ($plat,$plon,$pxg,$wpxg);
    my %wpkeys = {};
    $key = 'ICAOcode';
    my $xg = "# icao found\n";
    if (defined ${$aref}{$key}) {
        $icao = ${$aref}{$key};
        prt("Have Airport $icao...\n");
        $xg = "# Airport $icao\n";
        $xg .= add_airport_xg($icao);
    }

    prt("Have $cnt keys: ".join(" ",@arr)."\n");
    $key = 'Star';
    if (defined ${$aref}{$key}) {
        my $starra = ${$aref}{$key};
        $cnt = scalar @{$starra};
        prt("$key with $cnt points...\n");
        foreach $wprh (@{$starra}) {
            $name = 'Unknown';
            if (defined ${$wprh}{'Name'}) {
                $name = ${$wprh}{'Name'};
            }
            $wpcnt = 0;
            $wpra = [];
            if (defined ${$wprh}{'Star_Waypoint'}) {
                $wpra = ${$wprh}{'Star_Waypoint'};
                $wpcnt = scalar @{$wpra};
            }
            $wpvcnt = 0;
            foreach $wp (@{$wpra}) {
                if (is_valid_wp($wp)) {
                    $wpvcnt++;
                }
            }

            prt("  $name - with $wpcnt ($wpvcnt) wps\n");
            $xg .= "# Star $name $wpvcnt wps\n";
            if ($wpvcnt && $add_star_wps) {
                $wpxg = "color green\n";
                $pxg = '';
                $wpvcnt = 0;
                foreach $wp (@{$wpra}) {
                    if (is_valid_wp($wp)) {
                        ($nm,$id,$lat,$lon,$typ) = get_wp_info($wp);
                        prt ("     $nm, $id, $lat, $lon, $typ\n") if (VERB9());
                        $typ = '' if ($typ eq 'Normal');
                        $id = '' if ($id != 1);
                        $wpxg .= "anno $lon $lat $nm $typ $id\n";
                        if ($wpvcnt) {
                            $pxg .= get_path_xg($plat,$plon,$lat,$lon);
                        } else {
                        }
                        $wpxg .= "$lon $lat # $nm, $id, $typ\n";
                        $plat = $lat;
                        $plon = $lon;
                        $wpvcnt++;
                    }
                }
                $wpxg .= "NEXT\n";
                $xg .= $pxg;
                $xg .= $wpxg;
            }
        }
    }
    $key = 'Sid';
    if (defined ${$aref}{$key}) {
        my $starra = ${$aref}{$key};
        $cnt = scalar @{$starra};
        prt("$key with $cnt points...\n");
        foreach $wprh (@{$starra}) {
            $name = 'Unknown';
            if (defined ${$wprh}{'Name'}) {
                $name = ${$wprh}{'Name'};
            }
            $wpcnt = 0;
            $wpra = [];
            if (defined ${$wprh}{'Sid_Waypoint'}) {
                $wpra = ${$wprh}{'Sid_Waypoint'};
                $wpcnt = scalar @{$wpra};
            }
            $wpvcnt = 0;
            foreach $wp (@{$wpra}) {
                if (is_valid_wp($wp)) {
                    $wpvcnt++;
                }
            }

            prt("  $name - with $wpcnt ($wpvcnt) wps\n");
            $xg .= "# Sid $name $wpvcnt wps\n";
            if ($wpvcnt && $add_sid_wps) {
                $pxg = '';
                $wpvcnt = 0;
                $wpxg = "color blue\n";
                foreach $wp (@{$wpra}) {
                    if (is_valid_wp($wp)) {
                        ($nm,$id,$lat,$lon,$typ) = get_wp_info($wp);
                        prt ("     $nm, $id, $lat, $lon, $typ\n") if (VERB9());
                        $typ = '' if ($typ eq 'Normal');
                        $id = '' if ($id != 1);
                        $wpxg .= "anno $lon $lat $nm $typ $id\n";
                        if ($wpvcnt) {
                            $pxg .= get_path_xg($plat,$plon,$lat,$lon);
                        } else {
                        }
                        $wpxg .= "$lon $lat # $nm, $id, $typ\n";
                        $plat = $lat;
                        $plon = $lon;
                        $wpvcnt++;
                    }
                }
                $wpxg .= "NEXT\n";
                $xg .= $pxg;
                $xg .= $wpxg;
            }
        }
    }
    $key = 'Approach';
    if (defined ${$aref}{$key}) {
        my $starra = ${$aref}{$key};
        $cnt = scalar @{$starra};
        prt("$key with $cnt points...\n");
        foreach $wprh (@{$starra}) {
            $name = 'Unknown';
            if (defined ${$wprh}{'Name'}) {
                $name = ${$wprh}{'Name'};
            }
            $wpcnt = 0;
            $wpra = [];
            if (defined ${$wprh}{'App_Waypoint'}) {
                $wpra = ${$wprh}{'App_Waypoint'};
                $wpcnt = scalar @{$wpra};
            }
            $wpvcnt = 0;
            foreach $wp (@{$wpra}) {
                if (is_valid_wp($wp)) {
                    $wpvcnt++;
                }
            }

            prt("  $name - with $wpcnt ($wpvcnt) wps\n");
            $xg .= "# App $name $wpvcnt wps\n";
            if ($wpvcnt && $add_app_wps) {
                $pxg = '';
                $wpvcnt = 0;
                $wpxg = "color white\n";
                foreach $wp (@{$wpra}) {
                    if (is_valid_wp($wp)) {
                        ($nm,$id,$lat,$lon,$typ) = get_wp_info($wp);
                        prt ("     $nm, $id, $lat, $lon, $typ\n") if (VERB9());
                        $typ = '' if ($typ eq 'Normal');
                        $id = '' if ($id != 1);
                        $wpxg .= "anno $lon $lat $nm $typ $id\n";
                        if ($wpvcnt) {
                            $pxg .= get_path_xg($plat,$plon,$lat,$lon);
                        } else {
                        }
                        $wpxg .= "$lon $lat # $nm, $id, $typ\n";
                        $plat = $lat;
                        $plon = $lon;
                        $wpvcnt++;
                    }
                }
                $wpxg .= "NEXT\n";
                $xg .= $pxg;
                $xg .= $wpxg;
            }
        }
    }
    if (length($out_file) == 0) {
        $out_file = $def_xg;
    }
    $out_file = path_u2d($out_file) if ($os =~ /win/i);
    ###prt("Writting Xgraph out to $out_file\n");
    write2file($xg,$out_file);
    prt("Xgraph out written to $out_file\n");

    # $load_log = 1;
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
    }
    if (length($in_file) ==  0) {
		give_help();
		if ( -f $def_file ) {
			prt("Try: $pgmname $def_file\n");
        }
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
	prt(" Read an xml sid/star procedure file, and generate a 2D graph of the\n");
	prt(" flight waypoints found.\n");
	
}

# eof - template.pl
