#!/usr/bin/perl -w
# NAME: cfcsvlogs.pl, cfjsonlogs.pl (was: jsonfeeds.pl)
# AIM: Annalyse logs written by cfjsonlog.pl, in a target directory.
# Log file name will change each day, in the form - $out_dir/'flights-YYYY-MM-DD.csv'
# 2016-07-27 - Add the tide of usage - times at min/max usage... ie fliers(cs) on line
# 16/07/2016 - Beginning to mature the HTML output - more jumps...
# 12/07/2016 - Begin to add HTML output
# 2016-07-09 - Initial cut
######################################

use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use File::Spec; # File::Spec->rel2abs($rel); # get ABSOLUTE from REALTIVE get_full_path
use File::stat;
use Date::Parse;
use LWP::Simple;
use JSON;
use Data::Dumper;
use Cwd;
use Time::HiRes qw(gettimeofday tv_interval);       # provide more accurate timings

my $begin_app = [ gettimeofday ];
my $os = $^O;
my $PATH_SEP = '/';
$PATH_SEP = "\\" if ($os =~ /win/i);
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
my $VERS = "0.0.9 2016-07-27";
##my $VERS = "0.0.8 2016-07-16";
##my $VERS = "0.0.7 2016-07-07";
##my $VERS = "0.0.6 2016-07-06";
##my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';
my $out_dir = $temp_dir.$PATH_SEP."temp-flights";
my $only_one_feed = 0;
my $show_each_flt = 0;
my $max_show_cs = 1000;
my $max_table_lines = 25;
my $min_table_lines =  8;
my $add_table_captions = 1;

my $add_csv_header = 0; # add CSV header, to each **new** file
my $out_html = $temp_dir."/temphtml2.htm";  # DEFAULT out HTML

############################################################# 
# crossfeed json feed - never fetch faster than 1 Hz!
my $feed1 = "http://crossfeed.freeflightsim.org/flights.json";
#############################################################

# ### DEBUG ###
my $debug_on = 0;
##my $def_file = 'C:\GTools\perl\scripts\temp\temp-flights\cflogs';
##my $def_file = 'C:\GTools\perl\scripts\temp\temp-flights\flights-2016-07-10.csv';
##my $def_file = 'C:\GTools\perl\scripts\temp\temp-flights\flights-2016-07-09.csv';
##my $def_file = 'C:\GTools\perl\scripts\temp\temp-flights\flights-2016-07-07.csv';
my $def_file = 'F:\FGx\crossfeed-dailies\flights-2016-07-30.csv';

### program variables
my @warnings = ();
my $cwd = cwd();
my $MPS2KT = 1.94384;   # meters per second to knots
my $SG_EPSILON = 0.000001;
my $last_ymd = '';
my $g_log_period = "N/A";
my $g_min_flts = 999999;
my $g_max_flts = 0;
my $g_min_upd = 'N/A';
my $g_max_upd = 'N/A';
my $g_tot_files = 0;
my $g_tot_records = 0;

my @g_files = ();

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

sub prt_ran_for() {
    my $end_app = [ gettimeofday ];
    my $elap = tv_interval( $begin_app, $end_app );
    my $tm = get_time_stg($elap);
    prt("Ran for $tm ...\n");
}

sub pgm_exit($$) {
    my ($val,$msg) = @_;
    if (length($msg)) {
        $msg .= "\n" if (!($msg =~ /\n$/));
        prt($msg);
    }
    show_warnings($val);
    prt_ran_for();
    close_log($outfile,$load_log);
    exit($val);
}


sub prtw($) {
   my ($tx) = shift;
   $tx =~ s/\n$//;
   prt("$tx\n");
   push(@warnings,$tx);
}

sub fetch_url($) {	# see gettaf01.pl
	my ($url) = shift;
	prt( "Fetching: $url\n" ) if (VERB9());
	my $txt = get($url);
    my ($len);
	if ($txt && length($txt)) {
        $len = length($txt);
        if (VERB9()) {
            prt("Got $len chars...\n");
            prt("$txt\n");
        }
	} else {
  		prt( "No text available from $url!\n" ) if (VERB5());
	}
    return $txt;
}

my $max_model = 14; # beech99-model
# "Aircraft/777/Models/777-200ER.xml
sub get_model($) {
    my $mod = shift;
    my @arr = split(/\//,$mod);
    $mod = $arr[-1];
    $mod =~ s/\.xml$//;
    $mod =~ s/-model$//;
    return $mod;
}

sub get_ll_double($) {
    my $deg = shift;
    my $dbl = sprintf("%12.6f",$deg);
    return $dbl;
}

sub get_alt_stg($) {
    my $alt = shift;
    if ($alt > 10000) {
        $alt = 'FL'.int($alt / 100);
        #$alt = sprintf("%6d",$alt);
    } else {
        $alt = sprintf("%8d",$alt);
    }
    return $alt;
}

sub get_decimal_stg($$$) {
    my ($dec,$il,$dl) = @_;
    my (@arr);
    if ($dec =~ /\./) {
        @arr = split(/\./,$dec);
        if (scalar @arr == 2) {
            $arr[0] = " ".$arr[0] while (length($arr[0]) < $il);
            $dec = $arr[0];
            if ($dl > 0) {
                $dec .= ".";
                $arr[1] = substr($arr[1],0,$dl) if (length($arr[1]) > $dl);
                $dec .= $arr[1];
            }
        }
    } else {
        $dec = " $dec" while (length($dec) < $il);
        if ($dl) {
            $dec .= ".";
            while ($dl--) {
                $dec .= "0";
            }
        }
    }
    return $dec;
}

sub get_sg_dist_stg($) {
    my ($sg_dist) = @_;
    my $sg_km = $sg_dist / 1000;
    my $sg_im = int($sg_dist);
    my $sg_ikm = int($sg_km + 0.5);
    my $dlen = 5;
    # if (abs($sg_pdist) < $CP_EPSILON)
    my $sg_dist_stg = "";
    if (abs($sg_km) > $SG_EPSILON) { # = 0.0000001; # EQUALS SG_EPSILON 20101121
        if ($sg_ikm && ($sg_km >= 1)) {
            $sg_km = int(($sg_km * 10) + 0.05) / 10;
            #$sg_dist_stg .= get_decimal_stg($sg_km,5,1)." km";
            $sg_dist_stg .= get_decimal_stg($sg_km,($dlen - 2),1)." km";
        } else {
            #$sg_dist_stg .= "$sg_im m, <1km";
            #$sg_dist_stg .= get_decimal_stg($sg_im,7,0)." m.";
            $sg_dist_stg .= get_decimal_stg($sg_im,$dlen,0)." m.";
        }
    } else {
        #$sg_dist_stg .= "0 m";
        #$sg_dist_stg .= get_decimal_stg('0',7,0)." m.";
        $sg_dist_stg .= get_decimal_stg('0',$dlen,0)." m.";
    }
    return $sg_dist_stg;
}


sub display_flight($$$$$$$$$) {
    my ($callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$type) = @_;
    $callsign .= ' ' while (length($callsign) < 8);
    $lat = get_ll_double($lat);
    $lon = get_ll_double($lon);
    $alt_ft = get_alt_stg($alt_ft);
    $alt_ft = ' '.$alt_ft while (length($alt_ft) < 8);
    $model = ' '.$model while (length($model) < $max_model);
    $spd_kts = ' '.$spd_kts while (length($spd_kts) < 7);
    $hdg = ' '.$hdg while (length($hdg) < 4);
    $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
    my $line = "$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm - $type\n";
    prt($line);
    #return $line;
}

my $iocnt = 0;
my $csv_headers = "fid,callsign,lat,lon,alt_ft,model,spd_kts,hdg,dist_nm,update,tot_secs\n";

sub record_flight($$$$$$$$$$$) {
    my ($fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$tot_secs,$upd1) = @_;
    my $epoch = time();
    my $line = "$fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$upd1,$tot_secs\n";
    if (length($out_dir) && (-d $out_dir)) {
        my $ymd = get_YYYYMMDD($epoch);
        $ymd =~ s/\//-/g;   # conver to a path compatible name
        my $file = $out_dir.$PATH_SEP."flights-$ymd.csv";
        if (-f $file) {
            $last_ymd = $ymd if (length($last_ymd) == 0);
            if ($ymd eq $last_ymd) {
                prt("Appended to file $file...\n") if ($iocnt == 0);
                append2file($line,$file);
                $iocnt++;
            } else {
                $last_ymd = $ymd;
                $line = $csv_headers.$line if ($add_csv_header);
                write2file($line,$file);
                prt("Created new file $file...\n");
                $iocnt = 1;
            }
        } else {
            $last_ymd = $ymd;
            $line = $csv_headers.$line if ($add_csv_header);
            write2file($line,$file);
            prt("Created new file $file...\n");
            $iocnt = 1;
        }
    } elsif ($iocnt == 0) {
        if (length($out_dir)) {
            $line = File::Spec->rel2abs($out_dir);
            my ($n,$d) = fileparse($line);
            prt("\nInfo: Can find dir '$d', but missing '$n'!\n") if (-d $d);
            pgm_exit(1,"ERROR: Can NOT 'stat' output dir '$line'!\n".
                "This directory MUST exist. Create and re-run...\n\n");
        } else {
            pgm_exit(1,"\nERROR: No valid output directory given!\n\n");
        }
        $iocnt++;
    }
}

# crossfeed
# {"success":true,"source":"cf-client","last_updated":"2015-01-22 17:35:42","flights":[
# {"fid":1421695466000,"callsign":"Charlie","lat":45.360490,"lon":5.335270,"alt_ft":1288,"model":"Aircraft/777/Models/777-200ER.xml","spd_kts":0,"hdg":324,"dist_nm":379},
# {"fid":1421826354000,"callsign":"saphir","lat":51.242089,"lon":-0.834174,"alt_ft":3113,"model":"Aircraft/777/Models/777-200LR.xml","spd_kts":187,"hdg":146,"dist_nm":16384},
# fid callsign lat lon alt_ft model spd_kts hdg dist_nm 


# php feed
# {"pilots":[
# {"callsign":"Charlie","aircraft":"777-200ER","latitude":"45.360490","longitude":"5.335270","altitude":"1287.707060","heading":323.8147125058},
# {"callsign":"saphir","aircraft":"777-200LR","latitude":"51.240209","longitude":"-0.832257","altitude":"3109.778402","heading":145.73179151024},
# {"callsign":"EGXU_TW","aircraft":"OpenRadar","latitude":"54.045074","longitude":"-1.250728","altitude":"53.001620","heading":0},
# callsign aircraft latitude longitude altitude heading
sub repeat_feeds() {
    my $repeat = 1;
    my $secs = 5;
    my $header = '';
    my $upd1 = "Unknown";
    my ($fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm);
    my ($ra1,$cnt1,$i,$rh2,$line,$msg,$show,$rh3);
    my ($lat2,$lon2,$alt_ft2,$model2,$spd_kts2,$hdg2,$dist_nm2,$type);
    my ($res,$az1,$az2,$dist,$mps,$tsecs);
    my $min_mps = 5; 
    my %hash = ();
    $callsign = 'callsign';
    $lat = 'latitude';
    $lon = 'longitude';
    $alt_ft = 'altitude';
    $model = 'model';
    $spd_kts = 'spd kts';
    $hdg = 'hdg';
    $dist_nm = 'dist nm';
    # display header
    $callsign .= ' ' while (length($callsign) < 8);
    $lat = ' '.$lat while (length($lat) < 12);
    $lon = ' '.$lon while (length($lon) < 12);
    $alt_ft = ' '.$alt_ft while (length($alt_ft) < 8);
    $model = ' '.$model while (length($model) < $max_model);
    $spd_kts = ' '.$spd_kts while (length($spd_kts) < 7);
    $hdg = ' '.$hdg while (length($hdg) < 4);
    $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
    $msg = "$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm\n";
    $header = $msg;
    my $tot_secs = 0;
    while ($repeat) {
        my $txt1 = fetch_url($feed1); # "http://crossfeed.freeflightsim.org/flights.json";
        my $json = JSON->new->allow_nonref;
        my $rh1 = $json->decode( $txt1 );
        ###prt(Dumper($rh1));

        my $upd1 = "Unknown";
        my ($fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm);
        my ($ra1,$cnt1,$i,$rh2,$line,$msg);
        if (defined ${$rh1}{last_updated}) {
            $upd1 = ${$rh1}{last_updated};
        }
        if (defined ${$rh1}{flights}) {
            $ra1 = ${$rh1}{flights};
            $cnt1 = scalar @{$ra1};
            # get all current FIDS in current hash
            my @fids = keys %hash;
            my $cnt2 = scalar @fids;    # get COUNT in current db
            my %hfids = ();
            foreach $fid (@fids) {
                $hfids{$fid} = 1;
            }
            # pre-process current cnt1, for missing FIDs
            for ($i = 0; $i < $cnt1; $i++) {
                $rh2 = ${$ra1}[$i]; # extract the hash
                $fid = ${$rh2}{fid};    # get FID
                if (defined $hfids{$fid}) {
                    delete $hfids{$fid}; # REMOVVE from list
                }
            }
            # any remaining in FIDS need to DIE, have LEFT, no more
            @fids = keys %hfids;
            if (@fids) {
                foreach $fid (@fids) {
                    $rh3 = $hash{$fid};
                    $callsign = ${$rh3}[0];
                    $lat      = ${$rh3}[1];
                    $lon      = ${$rh3}[2];
                    $alt_ft   = ${$rh3}[3];
                    $model    = ${$rh3}[4];
                    $spd_kts  = ${$rh3}[5];
                    $hdg      = ${$rh3}[6];
                    $dist_nm  = ${$rh3}[7];
                    $dist     = ${$rh3}[8];
                    $tsecs    = ${$rh3}[9];
                    my $active = secs_HHMMSS($tsecs);
                    $type = "LEFT ".get_sg_dist_stg($dist).", after $active";
                    display_flight($callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$type);
                    delete $hash{$fid}; # remove it
                }
            }
            @fids = keys %hash;
            my $cnt3 = scalar @fids;
            prt("Updated: $upd1, flights $cnt1... db $cnt2/$cnt3\n");
            # now process THIS set of json flights
            for ($i = 0; $i < $cnt1; $i++) {
                $rh2 = ${$ra1}[$i]; # extract the hash
                $fid = ${$rh2}{fid};
                $callsign = ${$rh2}{callsign};
                $lat = ${$rh2}{lat};
                $lon = ${$rh2}{lon};
                $alt_ft = ${$rh2}{alt_ft};
                $model = get_model(${$rh2}{model});
                $spd_kts = ${$rh2}{spd_kts};
                $hdg = ${$rh2}{hdg};
                $dist_nm = ${$rh2}{dist_nm};
                record_flight($fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$tot_secs,$upd1);
                ###prt("$fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm\n");
                if (defined $hash{$fid}) {
                    $show = 0;
                    $rh3 = $hash{$fid};
                    $lat2 = ${$rh3}[1];
                    $lon2 = ${$rh3}[2];
                    $type = 'SAME';
                    if (($lat != $lat2) || ($lon != $lon2)) {
                        $res = fg_geo_inverse_wgs_84($lat2,$lon2,$lat,$lon,\$az1,\$az2,\$dist);
                        $mps = $dist / $secs;
                        if ($mps > $min_mps) {
                            $type = "moved ".get_sg_dist_stg($dist);
                            $show = 1;
                            ${$rh3}[1] = $lat;
                            ${$rh3}[2] = $lon;
                            ${$rh3}[8] += $dist;
                        }
                    }
                    ${$rh3}[9] += $secs;    # accumulate rough seconds - better based on update string
                } else {
                    #              0         1    2    3       4      5        6    7        8 9 10
                    $hash{$fid} = [$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,0,0,$upd1];
                    $show = 1;
                    $type = 'NEW';
                }
                if ($show) {
                    display_flight($callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$type);
                    #$msg .= $line;
                }
            }
            #if (length($out_file)) {
            #    write2file($msg,$out_file);
            #    prt("JSON crossfeed flight list written to $out_file\n");
            #}
        } else {
            prt("'flights' is NOT defined in hash 1!\n");
        }
        prt("Sleep for $secs second...\n");
        sleep $secs;
        $tot_secs += $secs;
    }
}

sub get_one_feed() {
    my $txt1 = fetch_url($feed1); # "http://crossfeed.freeflightsim.org/flights.json";
    my $json = JSON->new->allow_nonref;
    my $rh1 = $json->decode( $txt1 );
    ###prt(Dumper($rh1));
    my $csv = '';

    my $upd1 = "Unknown";
    my ($fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm);
    my ($ra1,$cnt1,$i,$rh2,$line,$msg);
    if (defined ${$rh1}{last_updated}) {
        $upd1 = ${$rh1}{last_updated};
    }
    if (defined ${$rh1}{flights}) {
        $ra1 = ${$rh1}{flights};
        $cnt1 = scalar @{$ra1};
        prt("Updated: $upd1, flights $cnt1...\n");
        $callsign = 'callsign';
        $lat = 'latitude';
        $lon = 'longitude';
        $alt_ft = 'altitude';
        $model = 'model';
        $spd_kts = 'spd kts';
        $hdg = 'hdg';
        $dist_nm = 'dist nm';
        $csv .= "$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,update\n";

        # display header
        $callsign .= ' ' while (length($callsign) < 8);
        $lat = ' '.$lat while (length($lat) < 12);
        $lon = ' '.$lon while (length($lon) < 12);
        $alt_ft = ' '.$alt_ft while (length($alt_ft) < 8);
        $model = ' '.$model while (length($model) < $max_model);
        $spd_kts = ' '.$spd_kts while (length($spd_kts) < 7);
        $hdg = ' '.$hdg while (length($hdg) < 4);
        $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
        $msg = "$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm\n";
        prt($msg);

        for ($i = 0; $i < $cnt1; $i++) {
            $rh2 = ${$ra1}[$i]; # extract the hash
            $fid = ${$rh2}{fid};
            $callsign = ${$rh2}{callsign};
            $lat = ${$rh2}{lat};
            $lon = ${$rh2}{lon};
            $alt_ft = ${$rh2}{alt_ft};
            $model = get_model(${$rh2}{model});
            $spd_kts = ${$rh2}{spd_kts};
            $hdg = ${$rh2}{hdg};
            $dist_nm = ${$rh2}{dist_nm};
            ###prt("$fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm\n");
            $csv .= "$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$upd1\n";

            ###################################
            # display - for spaced display only
            $callsign .= ' ' while (length($callsign) < 8);
            $lat = get_ll_double($lat);
            $lon = get_ll_double($lon);
            $alt_ft = get_alt_stg($alt_ft);
            $alt_ft = ' '.$alt_ft while (length($alt_ft) < 8);
            $model = ' '.$model while (length($model) < $max_model);
            $spd_kts = ' '.$spd_kts while (length($spd_kts) < 7);
            $hdg = ' '.$hdg while (length($hdg) < 4);
            $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
            $line = "$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm\n";
            prt($line);
            $msg .= $line;
            ###################################
        }
        if (length($out_file)) {
            ### No, do not output the spaced display lines
            ### write2file($msg,$out_file);
            ### Write instead the compact CSV collected as well
            rename_2_old_bak($out_file);
            write2file($csv,$out_file);
            prt("JSON crossfeed CSV flight list written to $out_file\n");
        } else {
            prt("Compact CSV discarded. No -o out-file.csv given...\n");
        }
    } else {
        prt("'flights' is NOT defined in hash 1!\n");
    }

    ## $load_log = 1;

}

my $def_min_secs = 60;
my $def_min_dist = 2;   # ignore a flight that does not move...

my %flt_fids = ();
my $htm = '';

my $href_txt = "<a href=\"#models\"><b>models</b></a>:\n".
    "sorted (<a href=\"#mod.alpha\">alpha</a>, <a href=\"#mod.dist\">dist</a>, <a href=\"#mod.time\">time</a>)\n".
    "<a href=\"#callsign\"><b>callsigns</b></a>:\n".
    "sorted (<a href=\"#stat.alpha\">alpha</a>, <a href=\"#stat.dist\">dist</a>, <a href=\"#stat.time\">time</a>)\n".
    "<a href=\"#stats\">stats</a>\n".
    "page: <a href=\"#top\">top</a> <a href=\"#end\">end</a>\n";

sub get_warn_txt() {
    my $txt = <<EOF;

<p><b>WARNING</b>: The times and distance flown can be greatly influenced by sim time warping, 
and sim time speed up and slow down, so are always <b>only estimates</b>! And this is only the 
results of one particular, specific crossfeed. That is, no prizes will be awarded on
these results. ;=)) And as such should not be taken as an general indication of 
<a target="_blank" href="http://www.flightgear.org/">FlightGear</a> usage, and just a 
sub-set of MultiPlayer usage.
</p>

EOF
    return $txt;
}

sub get_body_html() {
    my $txt = "<body>\n";
    $txt .= "<a id=\"top\" name=\"top\"></a>\n";
    $txt .= "<h1>Multiplayer Crossfeed Flights</h1>\n";
    $txt .= "<p class=\"top\">$href_txt</p>\n";
    $txt .= "<h2>$g_log_period</h2>\n";
    $txt .= get_warn_txt();
    return $txt;
}

sub get_html_head() {
    my $txt = <<EOF;
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Crossfeed Flights</title>
<style>
body { 
    display: block;
    margin: 8px;
}
.vat { 
    vertical-align: top;
    white-space: nowrap;
}
.ran {
    text-align: right;
    vertical-align: top;
}
em {
    color: #204000;
    font-weight: bold;
}
tr:nth-child(even) {background-color: #f2f2f2}
tr:hover {background-color: #ddd;}

h1 { 
background : #efefef;
border-style : solid solid solid solid;
border-color : #d9e2e2;
border-width : 1px;
padding : 2px 2px 2px 2px;
font-size : 300%;
text-align : center;
} 

h2 { 
font-size : 16pt;
font-weight : bold;
background-color : #ccccff;
} 

p.top { 
margin : 0;
border-style : none;
padding : 0;
text-align : center;
}

caption { 
    display: table-caption;
    text-align: center;
    font-weight: bold;
    font-size: 110%;
    background-color: #ffffc0;
}

</style>
</head>
EOF
    $txt .= get_body_html();
    return $txt;
}

sub get_html_end($) {
    my $utc = shift;
    my $tm = "<!-- Generated $utc, by $pgmname -->";
    my $txt = <<EOF;

<p class="top">$href_txt</p>

<a name="end" id="end"></a>
<p align="right">eof <a href="#top">top</a></p>
    $tm
</body>
</html>
EOF
    return $txt;
}

sub get_file_table() {
    my $h = "<p class=\"top\">$href_txt</p>\n";
    my $cnt = scalar @g_files;

    $h .= "<table border='1' width='100%'>\n";
    $h .= "<caption>Display of $cnt files scanned.</caption>\n"; # if ($add_table_captions);
    #              0    1   2      3            4           5         6         7
    #ush(@g_files,[$inf,$sz,$lncnt,$first_upd,$last_upd,$min_flts,$max_flts,$tm]);
    my ($ff,$inf,$dir,$sz,$lncnt,$first_upd,$last_upd,$min_flts,$max_flts,$tm,$ra);
    $h .= "<tr>\n";
    $h .= "<th>file name</th>\n";
    $h .= "<th>size</th>\n";
    $h .= "<th>lines</th>\n";
    $h .= "<th>begin</th>\n";
    $h .= "<th>end</th>\n";
    $h .= "<th>min</th>\n";
    $h .= "<th>max</th>\n";
    $h .= "<th>date</th>\n";
    $h .= "</tr>\n";
    foreach $ra (@g_files) {
        $ff = ${$ra}[0];
        $sz = ${$ra}[1];
        $lncnt = ${$ra}[2];
        $first_upd = ${$ra}[3];
        $last_upd = ${$ra}[4];
        $min_flts = ${$ra}[5];
        $max_flts = ${$ra}[6];
        $tm = ${$ra}[7];
        my @lt = localtime($tm);
        my $ctm = sprintf( "%02d/%02d/%04d %02d:%02d", $lt[3], $lt[4]+1, $lt[5]+1900, $lt[2], $lt[1]);
        ($inf,$dir) = fileparse($ff);
        $h .= "<tr>\n";
        $h .= "<td>$inf</td>\n";
        $h .= "<td align='right'>".get_nn($sz)."</td>\n";
        $h .= "<td align='right'>".get_nn($lncnt)."</td>\n";
        $h .= "<td>$first_upd</td>\n";
        $h .= "<td>$last_upd</td>\n";
        # json groups $g_min_flts to $g_max_flts
        if ($g_min_flts == $min_flts) {
            $h .= "<td align='right'><b>$min_flts</b></td>\n";
        } else {
            $h .= "<td align='right'>$min_flts</td>\n";
        }
        if ($g_max_flts == $max_flts) {
            $h .= "<td align='right'><b>$max_flts</b></td>\n";
        } else {
            $h .= "<td align='right'>$max_flts</td>\n";
        }
        $h .= "<td>$ctm</td>\n";
        $h .= "</tr>\n";
    }

    $h .= "</table>\n";
    return $h;
}

sub get_html_tail() {
    my $utc = lu_get_YYYYMMDD_hhmmss_UTC(time());
    my $rc = get_nn($g_tot_records);
    my $end_app = [ gettimeofday ];
    my $elap = tv_interval( $begin_app, $end_app );
    my $pt = get_time_stg($elap);

    my $txt = <<EOF;

<p><b>$utc UTC</b>: Information extracted from <b>crossfeed</b> json, connected to <b>mpserver14</b>, sampled every 5 seconds, over the perod of time
$g_log_period, collected into to a CSV file, by this <a target="_blank" href="https://github.com/geoffmcl/scripts/blob/master/cfjsonlog.pl">cfjsonlog.pl</a> script,
then analysed by the <a target="_blank" href="https://github.com/geoffmcl/scripts/blob/master/cfcsvlogs.pl">cfcsvlogs.pl</a> script.
This was from $g_tot_files file(s), $rc records, processed in $pt. json groups $g_min_flts to $g_max_flts.</p>

<p>The min <b>multiplayer/crossfeed</b> count $g_min_flts, first encountered on $g_min_upd, 
and max $g_max_flts on $g_max_upd, <b>BUT</b> this is only one crossfeed sample... be assured, 
the FGFS free sim has been flown <b>many</b> more times than shown here, without an mp connection... 
rendering these stats totally invalid as <b>any</b> indication of true FGFS usage...
</p>

EOF
    $txt .= get_warn_txt();
    $txt .= get_file_table();
    $txt .= get_html_end($utc);

    return $txt;
}


sub prth($$) {
    my ($txt,$flag) = @_;
    prt($txt);
    #$txt =~ s/\n$//;
    $txt = trim_all($txt);
    if ($flag & 8) {
        $htm .= "<h3>$txt</h3>\n";
    } elsif ($flag & 1) {
        if ($flag & 2) {
            $htm .= "<tr><td>$txt</td></tr>\n";
        } else {
            $htm .= "<td>$txt</td>\n";
        }
    } else {
        $htm .= "<p>$txt</p>\n";
    }
}

sub get_time_stg($) {
    my $elap = shift;
    my $negative = 0;
    my $units = '';
    if ($elap < 0) {
        $negative = 1;
        $elap = -$elap;
    }
    if ( !($elap > 0.0) ) {
        return "0.0 s";
    }
    if ($elap < 1e-21) {
        #// yocto - 10^-24
        $elap *= 1e+21;
        $units = "ys";
    } elsif ($elap < 1e-18) {
        #// zepto - 10^-21
        $elap *= 1e+18;
        $units = "zs";
    } elsif ($elap < 1e-15) {
        #// atto - 10^-18
        $elap *= 1e+15;
        $units = "as";
    } elsif ($elap < 1e-12) {
        #// femto - 10^-15
        $elap *= 1e+12;
        $units = "fs";
    } elsif ($elap < 1e-9) {
        #// pico - 10^-12
        $elap *= 1e+9;
        $units = "ps";
    } elsif ($elap < 1e-6) {
        #// nanosecond - one thousand millionth (10?9) of a second
        $elap *= 1e+6;
        $units = "ns";
    } elsif ($elap < 1e-3) {
        #// microsecond - one millionth (10?6) of a second
        $elap *= 1e+3;
        $units = "us";
    } elsif ($elap < 1.0) {
        #// millisecond
        $elap *= 1000.0;
        $units = "ms";
    } elsif ($elap < 60.0) {
        $units = "s";
    } else {
        my $secs = int($elap + 0.5);
        my $mins = int($secs / 60);
        $secs = ($secs % 60);
        if ($mins >= 60) {
            my $hrs = int($mins / 60);
            $mins = $mins % 60;
            if ($hrs >= 24) {
                my $days = int($hrs / 24);
                $hrs = $hrs % 24;
                return sprintf("%d days %2d:%02d:%02d hh:mm:ss", $days, $hrs, $mins, $secs);
            } else {
                return sprintf("%2d:%02d:%02d hh:mm:ss", $hrs, $mins, $secs);
            }
        } else {
            return sprintf("%2d:%02d mm:ss", $mins, $secs);
        }
    }
    my $res = '';
    if ($negative) {
        $res = '-';
    }
    $res .= "$elap $units";
    return $res;
}

sub mycmp_decend_n0 {
   return  1 if (${$a}[0] < ${$b}[0]);
   return -1 if (${$a}[0] > ${$b}[0]);
   return  0;
}
sub mycmp_decend_n2 {
   return  1 if (${$a}[2] < ${$b}[2]);
   return -1 if (${$a}[2] > ${$b}[2]);
   return  0;
}

sub mycmp_ascend {
   return -1 if ($a > $b);
   return  1 if ($a < $b);
   return  0;
}

sub mycmp_decend {
   return -1 if ($a < $b);
   return  1 if ($a > $b);
   return  0;
}

sub mycmp_nc_sort {
   return -1 if (lc($a) lt lc($b));
   return 1 if (lc($a) gt lc($b));
   return 0;
}


# SHOW the collected set of flights, and 
# TODO: Update a database, and gen html page
sub show_flt_fids() {

    my @arr = sort keys %flt_fids;
    my $max = scalar @arr;
    prt("Have $max flights to analyse...\n");
    my ($fid,$ra,$rma);
    my ($callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$tsecs,$upd,$upd2,$be,$ee,$elap,$tm,$cnt,$rcsa);
    my ($i,$stt,$end,$msg,$lncnt);
    my $skipped = 0;
    my %models = ();
    my %callsigns = ();
    my $flt_cnt = 0;
    my $first_ep = time();
    my $last_ep = 0;
    my $first_upd = '';
    my $last_upd = '';
    my $tot_secs = 0;
    my $tot_dist = 0;
    my ($nmph,$wrap,$tcols);
    my $cols = 3;
    my $tab_cnt = 0;    # start TABLE counter

    $stt = [ gettimeofday ];
    # collection of information, by FID (unique)
    foreach $fid (@arr) {
        $ra = $flt_fids{$fid};
        $callsign = ${$ra}[0];
        $lat = ${$ra}[1];
        $lon = ${$ra}[2];
        $alt_ft = ${$ra}[3];
        $model = ${$ra}[4];
        $spd_kts = ${$ra}[5];
        $hdg = ${$ra}[6];
        $dist_nm = ${$ra}[7];
        $tsecs = ${$ra}[8];
        $upd = ${$ra}[10];
        $upd2 = ${$ra}[11];
        $be = str2time($upd);
        $ee = str2time($upd2);
        $elap = $ee - $be;
        $tm = get_time_stg($elap);
        ### $tm .= " (".get_time_stg($tsecs).")";

        ########################################
        #### Eliminate flights that -
        #### Are NOT alive for very long
        if ($elap < $def_min_secs) {
            $skipped++;
            next;
        }
        #### Did not move the min distance
        if ($dist_nm < $def_min_dist) {
            $skipped++;
            next;
        }

        $flt_cnt++; # count this FLIGHT

        # get the PERIOD, but if over multiple files???
        if ($be < $first_ep) {
            $first_ep = $be;
            $first_upd = $upd;
        }
        if ($ee > $last_ep) {
            $last_ep = $ee;
            $last_upd = $upd2;
        }

        $tot_secs += $elap;
        $tot_dist += $dist_nm;

        # store by MODEL
        $models{$model} = [] if (! defined $models{$model});
        $rma = $models{$model};
        push(@{$rma},[$callsign,$dist_nm,$elap]);

        # store by CALLSIGN
        $callsigns{$callsign} = [] if (! defined $callsigns{$callsign});
        $rcsa = $callsigns{$callsign};
        #              model, dist,    elap
        #              0      1        2    
        push(@{$rcsa},[$model,$dist_nm,$elap]);

        ##################################################
        ### DISPLAY
        if (VERB2()) {
            $callsign .= ' ' while (length($callsign) < 8);
            # $lat = get_ll_double($lat);
            # $lon = get_ll_double($lon);
            # $alt_ft = get_alt_stg($alt_ft);
            # $alt_ft = ' '.$alt_ft while (length($alt_ft) < 8);
            $model = ' '.$model while (length($model) < $max_model);
            # $spd_kts = ' '.$spd_kts while (length($spd_kts) < 7);
            # $hdg = ' '.$hdg while (length($hdg) < 4);
            $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
            ###prt("$callsign $model $dist_nm frm: $upd to: $upd2 $tm\n");
            prt("$callsign $model $dist_nm $tm\n");
        }
    }

    $end = [ gettimeofday ];
    $elap = tv_interval( $stt, $end );
    $tm = get_time_stg($elap);
    prt("Collected $flt_cnt flights from the csv... in $tm\n");
    if ($skipped) {
        prt("Skipped $skipped with time LTT $def_min_secs secs, or dist_nm LTT $def_min_dist...\n");
    }

    $tm = get_time_stg($last_ep - $first_ep);
    $g_log_period = "From: $first_upd, To: $last_upd - $tm";
    prt("$g_log_period\n");

    @arr = sort keys %models;
    my $modcnt = scalar @arr;
    @arr = sort keys %callsigns;
    my $cscnt = scalar @arr;
    my $tm_ts = get_time_stg($tot_secs);
    prth("Sampled ".get_nn($flt_cnt)." flights, ".get_nn($tot_dist)." nm., ".
        get_nn($modcnt)." models, ".get_nn($cscnt)." callsigns, est.time $tm_ts...\n",8);

    ########################################################
    # Show extracted MODEL usage information
    @arr = sort mycmp_nc_sort keys(%models);
    # OOPS, need to collect into CALLSIGNS
    # to avoid repeated models...
    # ok, go through the list, 1 by 1
    my %cs = ();
    my %mods = ();
    my ($rcsh2,$ra3,$tlines,$dnlines);
    $cnt = scalar @arr;
    # set, and add a JUMP
    $htm .= "<a id=\"models\" id=\"models\"></a>\n";
    $htm .= "<a id=\"mod.alpha\" id=\"mod.alpha\"></a>\n";
    prt("\n") if (VERB1());
    prt("Display of $cnt MODELS, sorted alpha, with CALLSIGNS\n");
    $htm .= "<p>Display of $cnt MODELS, sorted alpha, <a href=\"#mod.dist\">dist</a>, <a href=\"#mod.time\">time</a></p>\n";
    ########################################################################################
    $tab_cnt++; # table 1
    $htm .= "<a name=\"tab$tab_cnt.top\" id=\"tab$tab_cnt.top\"></a>\n";
    $htm .= "<table>\n";
    $htm .= "<caption>Display of $cnt MODELS, sorted alpha, with CALLSIGN list</caption>\n" if ($add_table_captions);
    $lncnt = scalar @arr;
    foreach $model (@arr) {
        $ra = $models{$model};
        $cnt = scalar @{$ra};
        prt("Model: $model, flown by $cnt -\n") if ($show_each_flt);
        $tsecs = 0;
        $spd_kts = 0;
        foreach $rma (@{$ra}) {
            $callsign = ${$rma}[0];
            $dist_nm = ${$rma}[1];
            $elap = ${$rma}[2];
            $tsecs += $elap;
            $spd_kts += $dist_nm;
            # Models into callsign usage - totals
            # per MODEL basis
            if (defined $cs{$model}) {
                $rcsh2 = $cs{$model};
                if (defined ${$rcsh2}{$callsign}) {
                    $ra3 = ${$rcsh2}{$callsign};
                    ${$ra3}[0] += $dist_nm;
                    ${$ra3}[1] += $elap;
                    ${$ra3}[2] ++;
                } else {
                    ${$rcsh2}{$callsign} = [$dist_nm,$elap,1];
                }
            } else {
                $cs{$model} = {};
                $rcsh2 = $cs{$model};
                ${$rcsh2}{$callsign} = [$dist_nm,$elap,1];
            }

            # display
            $callsign .= ' ' while (length($callsign) < 8);
            $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
            $tm = get_time_stg($elap);
            prt("  $callsign $dist_nm $tm\n")if ($show_each_flt);
        }
        if ($cnt > 1) {
            $tm = get_time_stg($tsecs);
            $dist_nm = $spd_kts;
            $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
            prt("     Total $dist_nm $tm\n") if ($show_each_flt);
        }
        if (defined $mods{$model}) {
            $ra = $mods{$model};
            ${$ra}[0] += $spd_kts;
            ${$ra}[1] += $tsecs;
        } else {
            $mods{$model} = [$spd_kts,$tsecs];
        }
    }

    if (!$show_each_flt) {
        @arr = sort mycmp_nc_sort keys(%cs);
        $lncnt = scalar @arr;
        $tlines = 0;
        $dnlines = 0;
        $htm .= "<tr>\n";
        $htm .= "<th>model</th>\n";
        $htm .= "<th>#</th>\n";
        $htm .= "<th>'callsign dist time (flts)' list...</th>\n";
        $htm .= "</tr>\n";
        $tcols = 3;
        foreach $model (@arr) {
            $rcsh2 = $cs{$model};
            my @a3 = sort mycmp_nc_sort keys( %{$rcsh2} );
            $lon = scalar @a3;
            prt("Model: $model, flown by $lon -\n") if (VERB1());
            $htm .= "<tr>\n";
            $htm .= "<td class=\"vat\"><b>$model</b></td>\n";
            $htm .= "<td class=\"ran\">$lon</td>\n";
            $htm .= "<td>";
            $tsecs = 0;
            $spd_kts = 0;
            $alt_ft = 0;
            foreach $callsign (@a3) {
                $ra3 = ${$rcsh2}{$callsign};
                $dist_nm = ${$ra3}[0];
                $elap = ${$ra3}[1];
                $lat = ${$ra3}[2];

                $alt_ft += $lat;    # accumulate total flight by this callsign, for this model

                $tsecs += $elap;
                $spd_kts += $dist_nm;

                # display
                $callsign .= ' ' while (length($callsign) < 8);
                $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
                $tm = get_time_stg($elap);
                prt("  $callsign $dist_nm $tm ($lat)\n") if (VERB2());
                ##$htm .= "  $callsign $dist_nm $tm ($lat)\n";
                $htm .= "<em>$callsign</em> $dist_nm $tm ($lat)\n";
            }
            if ($lon > 1) {
                $tm = get_time_stg($tsecs);
                $dist_nm = $spd_kts;
                $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
                prt("     Total $dist_nm $tm\n") if (VERB2());
                $htm .= "<i>Total $dist_nm $tm ($alt_ft)</i>\n";
            }
            $htm .= "</td></tr>\n";
            $tlines++;
            $dnlines++;
            if ($max_table_lines && ($tlines >= $max_table_lines) && (($lncnt - $dnlines) > $min_table_lines )) {
                $tlines = 0;
                $htm .= "<tr><td align=\"center\" colspan=\"$tcols\">\n";
                $htm .= "Table $tab_cnt: <a href=\"#tab$tab_cnt.top\">top</a> <a href=\"#tab$tab_cnt.end\">end</a>\n";
                $htm .= "File: <a href=\"#top\">top</a> <a href=\"#end\">end</a>\n";
                $htm .= "</td></tr>\n"; 
            }
        }
    }   # for each MODEL
    $htm .= "</table>\n";
    $htm .= "<a name=\"tab$tab_cnt.end\" id=\"tab$tab_cnt.end\"></a>\n";
    ########################################################################################
    $htm .= "<p class=\"top\">$href_txt</p>\n";
    ########################################################################################
    @arr = sort keys(%mods);
    $cnt = scalar @arr;
    my @modarr = ();
    foreach $model (@arr) {
        $ra = $mods{$model};
        $dist_nm = ${$ra}[0];
        $tsecs = ${$ra}[1];
        push(@modarr,[$dist_nm,$model,$tsecs]);
    }
    $htm .= "<a name=\"mod.dist\" id=\"mod.dist\"></a>\n";
    prt("\n") if (VERB1());
    prt("Display of $cnt MODELS, sorted by distance flown...\n");
    $htm .= "<p>Display of $cnt MODELS, sorted by distance flown... <a href=\"#mod.alpha\">alpha</a>, <a href=\"#mod.time\">time</a></p>\n";
    @arr = sort mycmp_decend_n0 @modarr;
    $lncnt = scalar @arr;
    $lncnt = int($lncnt / $cols);
    $lncnt++ if ($lncnt % $cols);
    $tab_cnt++; # table 2
    $htm .= "<a name=\"tab$tab_cnt.top\" id=\"tab$tab_cnt.top\"></a>\n";
    $htm .= "<table width=\"100%\">\n";
    $htm .= "<caption>Display of $cnt MODELS, sorted by dist flown</caption>\n" if ($add_table_captions);
    $wrap = 0;
    $cnt = 0;
    $htm .= "<tr>\n";
    $tcols = 0;
    for ($i = 0; $i < $cols; $i++) {
        $htm .= "<th>#</th>\n";
        $htm .= "<th>model</th>\n";
        $htm .= "<th>dist.nm</th>\n";
        $htm .= "<th>time</th>\n";
        if (($i + 1) < $cols) {
            $htm .= "<th>|</th>\n";
            $tcols += 5;
        } else {
            $tcols += 4;
        }
    }
    $htm .= "</tr>\n";
    $wrap = 0;
    $tlines = 0;
    $dnlines = 0;
    foreach $ra (@arr) {
        $dist_nm = ${$ra}[0];
        $model = ${$ra}[1];
        $tsecs = ${$ra}[2];
        $tm = get_time_stg($tsecs);
        $cnt++;

        $htm .= "<tr>\n" if ($wrap == 0);
        $htm .= "<td class=\"ran\">$cnt</td>\n";
        $htm .= "<td class=\"vat\"><b>$model</b></td>\n";
        $htm .= "<td class=\"ran\">".get_nn($dist_nm)."</td>\n";
        $htm .= "<td>$tm</td>\n";
        $wrap++;
        if ($wrap == $cols) {
            $wrap = 0;
            $htm .= "</tr>\n";
            $dnlines++;
            $tlines++;
            if ($max_table_lines && ($tlines >= $max_table_lines) && (($lncnt - $dnlines) > $min_table_lines )) {
                $tlines = 0;
                $htm .= "<tr><td align=\"center\" colspan=\"$tcols\">\n";
                $htm .= "Table $tab_cnt: <a href=\"#tab$tab_cnt.top\">top</a> <a href=\"#tab$tab_cnt.end\">end</a>\n";
                $htm .= "File: <a href=\"#top\">top</a> <a href=\"#end\">end</a>\n";
                $htm .= "</td></tr>\n"; 
            }
        } else {
            $htm .= "<td>|</td>\n";
        }
    }
    if ($wrap) {
        while ($wrap < $cols) {
            $htm .= "<td>&nbsp;</td>\n";
            $htm .= "<td>&nbsp;</td>\n";
            $htm .= "<td>&nbsp;</td>\n";
            $htm .= "<td>&nbsp;</td>\n";
            $wrap++;
            if ($wrap < $cols) {
                $htm .= "<td>|</td>\n";
            }
        }
        $htm .= "</tr>\n";
    }
    $htm .= "</table>\n";
    $htm .= "<a name=\"tab$tab_cnt.end\" id=\"tab$tab_cnt.end\"></a>\n";
    ########################################################################################
    $htm .= "<p class=\"top\">$href_txt</p>\n";
    ########################################################################################
    $htm .= "<a name=\"mod.time\" id=\"mod.time\"></a>\n";
    prt("\n") if (VERB1());
    prt("Display of $cnt MODELS, sorted est. time flown...\n");
    $htm .= "<p>Display of $cnt MODELS, sorted est. time flown... <a href=\"#mod.alpha\">alpha</a>, <a href=\"#mod.dist\">dist</a></p>\n";
    @arr = sort mycmp_decend_n2 @modarr;
    $lncnt = scalar @arr;
    $lncnt = int($lncnt / $cols);
    $lncnt++ if ($lncnt % $cols);
    $tab_cnt++; # table 3
    $htm .= "<a name=\"tab$tab_cnt.top\" id=\"tab$tab_cnt.top\"></a>\n";
    $htm .= "<table width=\"100%\">\n";
    $htm .= "<caption>Display of $cnt MODELS, sorted by est. time flown</caption>\n" if ($add_table_captions);
    $wrap = 0;
    $cnt = 0;
    $htm .= "<tr>\n";
    $tcols = 0;
    for ($i = 0; $i < $cols; $i++) {
        $htm .= "<th>#</th>\n";
        $htm .= "<th>model</th>\n";
        $htm .= "<th>time</th>\n";
        $htm .= "<th>dist.nm</th>\n";
        if (($i + 1) < $cols) {
            $htm .= "<th>|</th>\n";
            $tcols += 5;
        } else {
            $tcols += 4;
        }
    }
    $htm .= "</tr>\n";
    $wrap = 0;
    $tlines = 0;
    $dnlines = 0;
    foreach $ra (@arr) {
        $dist_nm = ${$ra}[0];
        $model = ${$ra}[1];
        $tsecs = ${$ra}[2];
        $tm = get_time_stg($tsecs);
        $cnt++;

        $htm .= "<tr>\n" if ($wrap == 0);
        $htm .= "<td class=\"ran\">$cnt</td>\n";
        $htm .= "<td class=\"vat\"><b>$model</b></td>\n";
        $htm .= "<td>$tm</td>\n";
        $htm .= "<td class=\"ran\">".get_nn($dist_nm)."</td>\n";
        $wrap++;
        if ($wrap == $cols) {
            $wrap = 0;
            $htm .= "</tr>\n";
            $dnlines++;
            $tlines++;
            if ($max_table_lines && ($tlines >= $max_table_lines) && (($lncnt - $dnlines) > $min_table_lines )) {
                $tlines = 0;
                $htm .= "<tr><td align=\"center\" colspan=\"$tcols\">\n";
                $htm .= "Table $tab_cnt: <a href=\"#tab$tab_cnt.top\">top</a> <a href=\"#tab$tab_cnt.end\">end</a>\n";
                $htm .= "File: <a href=\"#top\">top</a> <a href=\"#end\">end</a>\n";
                $htm .= "</td></tr>\n"; 
            }
        } else {
            $htm .= "<td>|</td>\n";
        }
    }
    if ($wrap) {
        while ($wrap < $cols) {
            $htm .= "<td>&nbsp;</td>\n";
            $htm .= "<td>&nbsp;</td>\n";
            $htm .= "<td>&nbsp;</td>\n";
            $htm .= "<td>&nbsp;</td>\n";
            $wrap++;
            if ($wrap < $cols) {
                $htm .= "<td>|</td>\n";
            }
        }
        $htm .= "</tr>\n";
    }
    $htm .= "</table>\n";
    $htm .= "<a name=\"tab$tab_cnt.end\" id=\"tab$tab_cnt.end\"></a>\n";

    ## $load_log = 1;
    #pgm_exit(1,"TEMPEXIT\n");

    ########################################################################################
    $htm .= "<p class=\"top\">$href_txt</p>\n";
    ########################################################################################

    $htm .= "Models by: <a href=\"#mod.alpha\">alpha</a>, <a href=\"#mod.dist\">dist</a>, <a href=\"#mod.time\">time</a>\n";
    $htm .= "</p>\n";

    ########################################################
    #Show extracted CALLSIGN usage information
    @arr = sort mycmp_nc_sort keys(%callsigns);
    $cnt = scalar @arr;
    # set, and add a JUMP
    $htm .= "<a id=\"callsign\" id=\"callsign\"></a>\n";
    $htm .= "<a id=\"stat.alpha\" id=\"stat.alpha\"></a>\n";
    prt("\n") if (VERB5());
    prth("Display of $cnt CALLSIGNS, alpha sorted...\n",0);

    my $max_mod_cnt = 0;
    my $cs_most_mods = '';
    my $max_sec_cnt = 0;
    my $cs_most_secs = '';
    my $max_dist_nm = 0;
    my $cs_most_dist = '';
    my %disth = ();
    my %modsh = ();
    my %timeh = ();
    $tab_cnt++; # table 4
    $htm .= "<a name=\"tab$tab_cnt.top\" id=\"tab$tab_cnt.top\"></a>\n";
    $htm .= "<table>\n";
    $htm .= "<caption>Display of $cnt CALLSIGNS, alpha sorted, with MODELS used</caption>\n" if ($add_table_captions);
    $lncnt = scalar @arr;
    $tlines = 0;
    $dnlines = 0;
    foreach $callsign (@arr) {
        $ra = $callsigns{$callsign};
        $cnt = scalar @{$ra};
        $msg = "Callsign: $callsign, flew $cnt flights";
        $tsecs = 0;     # total secs, for this CALLSIGN
        $spd_kts = 0;   # total dist, for this CALLSIGN
        #                0      1        2
        # push(@{$rcsa},[$model,$dist_nm,$elap]);
        # OOPS, need to collect into MODELS
        if ($show_each_flt) {
            prt("$msg\n");  # close line...
            foreach $rcsa (@{$ra}) {
                $model = ${$rcsa}[0];
                $dist_nm = ${$rcsa}[1];
                $elap = ${$rcsa}[2];
                $tsecs += $elap;        # accumulate TIME
                $spd_kts += $dist_nm;   # and distance

                # display 
                $model = ' '.$model while (length($model) < $max_model);
                $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
                $tm = get_time_stg($elap);
                prt("  $model $dist_nm $tm\n");
            }
            if ($cnt > 1) {
                $tm = get_time_stg($tsecs);
                $dist_nm = $spd_kts;
                $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
                $model = "Total";
                $model = ' '.$model while (length($model) < $max_model);
                prt("  $model $dist_nm $tm\n");
            }
        } else {
            ##################################################
            # For this CALLSIGN
            # collect flights into model usage
            my %m = ();     # start a by MODEL hash
            my ($rma2,$fcnt);
            $fcnt = scalar @{$ra};
            foreach $rcsa (@{$ra}) {
                $model = ${$rcsa}[0];
                $dist_nm = ${$rcsa}[1];
                $elap = ${$rcsa}[2];
                $tsecs += $elap;        # accumulate TIME
                $spd_kts += $dist_nm;   # and distance
                if (defined $m{$model}) {
                    # just update model usage stats
                    $rma2 = $m{$model};
                    ${$rma2}[0] += $dist_nm;
                    ${$rma2}[1] += $elap;
                    ${$rma2}[2] ++; # bump usage count
                } else {
                    $m{$model} = [$dist_nm,$elap,1];
                }
            }
            # now show results for this CALLSIGN, by MODELS flown
            my @rma2 = sort mycmp_nc_sort keys(%m);
            $cnt = scalar @rma2;
            $tm = get_time_stg($tsecs);
            $msg .= ", used $cnt models, flew $spd_kts nm., in $tm";
            prt("$msg\n") if (VERB5());
            $htm .= "<tr><td class=\"vat\"><b>$callsign</b></td>\n";
            $htm .= "<td class=\"ran\">$cnt</td>\n";
            $htm .= "<td>";

            if ($tsecs > $max_sec_cnt) {
                $max_sec_cnt = $tsecs;
                $cs_most_secs = $callsign;
            }
            if ($cnt >= $max_mod_cnt) {
                $max_mod_cnt = $cnt;
                $cs_most_mods = $callsign;
            }
            if ($spd_kts > $max_dist_nm) {
                $max_dist_nm = $spd_kts;
                $cs_most_dist = $callsign;
            }

            #######################################################
            ### store in hashes, to get ORDER
            while (defined $disth{$spd_kts}) {
                $spd_kts++;
            }
            $disth{$spd_kts} = [$callsign,$tsecs,$spd_kts,$cnt];
            while (defined $timeh{$tsecs}) {
                $tsecs++;
            }
            $timeh{$tsecs} = [$callsign,$tsecs,$spd_kts,$cnt];
            # this will override the last
            $modsh{$cnt} = [$callsign,$tsecs,$spd_kts,$cnt];
            #######################################################

            foreach $model (@rma2) {
                $rma2 = $m{$model};
                $dist_nm = ${$rma2}[0];
                $elap = ${$rma2}[1];
                $lat = ${$rma2}[2]; # count for this MODEL

                # display 
                $model = ' '.$model while (length($model) < $max_model);
                $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
                $tm = get_time_stg($elap);
                prt("  $model $dist_nm $tm ($lat)\n") if (VERB5());
                $htm .= "<em>$model</em> $dist_nm $tm ($lat)\n";
            }
            if ($cnt > 1) {
                $tm = get_time_stg($tsecs);
                $dist_nm = $spd_kts;
                $dist_nm = ' '.$dist_nm while (length($dist_nm) < 7);
                $model = "Total";
                $model = ' '.$model while (length($model) < $max_model);
                prt("  $model $dist_nm $tm $fcnt\n") if (VERB5());
                $htm .= "<i>Total $dist_nm $tm $fcnt</i>\n";
            }
            #$htm .= "</table></tr></td>\n";
            $htm .= "</td></tr>\n";
            $tlines++;
            $dnlines++;
            if ($max_table_lines && ($tlines >= $max_table_lines) && (($lncnt - $dnlines) > $min_table_lines )) {
                $tlines = 0;
                $htm .= "<tr><td align=\"center\" colspan=\"3\">\n";
                $htm .= "Table $tab_cnt: <a href=\"#tab$tab_cnt.top\">top</a> <a href=\"#tab$tab_cnt.end\">end</a>\n";
                $htm .= "File: <a href=\"#top\">top</a> <a href=\"#end\">end</a>\n";
                $htm .= "</td></tr>\n"; 
            }
        }   # display 1-by-1, or GROUPED per model
    }   # for each CALLSIGN

    $htm .= "</table>\n";
    $htm .= "<a name=\"tab$tab_cnt.end\" id=\"tab$tab_cnt.end\"></a>\n";

    ########################################################################################
    $htm .= "<p class=\"top\">$href_txt</p>\n";
    ########################################################################################

    ####################################################################
    ### SUMMARY OUTPUT...
    ### if (length($cs_most_secs)) {
        prt("\n") if (VERB1());
        prt("Some 'stats' gathered...\n");
        $htm .= "<a id=\"stats\" id=\"stats\"></a>\n";
        # $href_txt .= " <a href=\"#stats\">stats</a>";
        $htm .= "<h2>Some 'stats' gathered...</h2>\n";

        $htm .= "<p>CALLSIGN by <a href=\"#stat.time\">time</a> <a href=\"#stat.dist\">dist</a></p>\n";

        # models used... is this useful?
        prth("CS: $cs_most_mods flew the most models - $max_mod_cnt\n",0);

        ######################################################################
        # Arranged by TIME
        $tm = get_time_stg($max_sec_cnt);
        @arr = sort mycmp_ascend keys(%timeh);
        $max = scalar @arr;
        $i = $max;
        if ($max_show_cs > 0) { # note 0=all
            $max = $max_show_cs if ($max > $max_show_cs);
        }
        $htm .= "<a id=\"stat.time\" id=\"stat.time\"></a>\n";
        prt("CS: $cs_most_secs flew the most time - $tm - list of top $max of $i\n");
        $htm .= "<p>CS: <b>$cs_most_secs</b> flew the most time - $tm - list of top $max of $i</p>\n";
        $tab_cnt++; # table 5
        $htm .= "<a name=\"tab$tab_cnt.top\" id=\"tab$tab_cnt.top\"></a>\n";
        $lncnt = int($max / $cols);
        $lncnt++ if ($max % $cols);
        $tlines = 0;
        $dnlines = 0;
        $htm .= "<table width=\"100%\">\n";
        $htm .= "<caption>Display of $max CALLSIGNS, sorted est. time flown</caption>\n" if ($add_table_captions);
        # header line
        $htm .= "<tr>\n";
        $tcols = 0;
        for ($i = 0; $i < $cols; $i++) {
            $htm .= "<th>#</th>\n";
            $htm .= "<th>callsign</th>\n";
            $htm .= "<th>time</th>\n";
            $htm .= "<th>dist nm.</th>\n";
            $htm .= "<th>av.kt.</th>\n";
            $htm .= "<th>flts</th>\n";
            if (($i + 1) < $cols) {
                $htm .= "<th>|</th>\n";
                $tcols += 7;
            } else {
                $tcols += 6;
            }
        }
        $htm .= "</tr>\n";
        $wrap = 0;
        for ($i = 0; $i < $max; $i++) {
            $tsecs = $arr[$i];
            $ra = $timeh{$tsecs};
            $callsign = ${$ra}[0];
            ### $tsecs = ${$ra}[1];
            $dist_nm = ${$ra}[2];
            $cnt = ${$ra}[3];

            $tm = get_time_stg($tsecs);
            $nmph = ($dist_nm / $tsecs) * 60 * 60;
            $nmph = int($nmph + 0.5);

            $htm .= "<tr>\n" if ($wrap == 0);

            $htm .= "<td class=\"ran\">".($i+1)."</td>\n";
            $htm .= "<td class=\"vat\"><b>$callsign</b></td>\n";
            #$htm .= "<td>for $tm, $dist_nm nm. av. $nmph kt.</td>\n";
            $htm .= "<td>$tm</td>\n";
            $htm .= "<td class=\"ran\">".get_nn($dist_nm)."</td>\n";
            $htm .= "<td class=\"ran\">".get_nn($nmph)."</td>\n";
            $htm .= "<td class=\"ran\">$cnt</td>\n";
            $wrap++;
            if ($wrap == $cols) {
                $htm .= "</tr>\n";
                $wrap = 0;
                $dnlines++;
                $tlines++;
                if ($max_table_lines && ($tlines >= $max_table_lines) && (($lncnt - $dnlines) > $min_table_lines )) {
                    $tlines = 0;
                    $htm .= "<tr><td align=\"center\" colspan=\"$tcols\">\n";
                    $htm .= "Table $tab_cnt: <a href=\"#tab$tab_cnt.top\">top</a> <a href=\"#tab$tab_cnt.end\">end</a>\n";
                    $htm .= "File: <a href=\"#top\">top</a> <a href=\"#end\">end</a>\n";
                    $htm .= "</td></tr>\n"; 
                }
            } else {
                $htm .= "<td>|</td>\n";
            }

            # display
            $callsign .= ' ' while (length($callsign) < 8);
            my $clnn = sprintf("%3d",($i+1));
            prt(" $clnn: $callsign flew for $tm, $dist_nm nm. av. $nmph kt. mods $cnt\n") if (VERB9());
        }
        if ($wrap) {
            while ($wrap < $cols) {
                $wrap++;
                $htm .= "<td class=\"ran\">&nbsp;</td>\n";
                $htm .= "<td class=\"vat\">&nbsp;</td>\n";
                $htm .= "<td>&nbsp;</td>\n";
                $htm .= "<td class=\"ran\">&nbsp;</td>\n";
                $htm .= "<td class=\"ran\">&nbsp;</td>\n";
                $htm .= "<td class=\"ran\">&nbsp;</td>\n";
                $htm .= "<td>|</td>\n" if ($wrap < $cols);
            }
            $htm .= "</tr>\n";
        }

        $htm .= "</table>\n";
        $htm .= "<a name=\"tab$tab_cnt.end\" id=\"tab$tab_cnt.end\"></a>\n";

        ########################################################################################
        $htm .= "<p class=\"top\">$href_txt</p>\n";
        ########################################################################################

        ######################################################################
        # Arrange by DISTANCE flown
        @arr = sort mycmp_ascend keys(%disth);
        $max = scalar @arr;
        $i = $max;
        if ($max_show_cs > 0) {
            $max = $max_show_cs if ($max > $max_show_cs);
        }
        $htm .= "<a id=\"stat.dist\" id=\"stat.dist\"></a>\n";
        prt("CS: $cs_most_dist flew the most dist - $max_dist_nm nm. - list of top $max on $i\n");
        $htm .= "CS: <b>$cs_most_dist</b> flew the most dist - $max_dist_nm nm. - list of top $max on $i</p>\n";
        $tab_cnt++;
        $htm .= "<a name=\"tab$tab_cnt.top\" id=\"tab$tab_cnt.top\"></a>\n";
        $htm .= "<table width=\"100%\">\n";
        $htm .= "<caption>Display of $max CALLSIGNS, sorted est. dist flown</caption>\n" if ($add_table_captions);
        # header line
        $htm .= "<tr>\n";
        $tcols = 0;
        for ($i = 0; $i < $cols; $i++) {
            $htm .= "<th>#</th>\n";
            $htm .= "<th>callsign</th>\n";
            $htm .= "<th>time</th>\n";
            $htm .= "<th>dist nm.</th>\n";
            $htm .= "<th>av.kt.</th>\n";
            $htm .= "<th>flts</th>\n";
            if (($i + 1) < $cols) {
                $htm .= "<th>|</th>\n";
                $tcols += 7;
            } else {
                $tcols += 6;
            }
        }
        $htm .= "</tr>\n";
        $wrap = 0;
        $dnlines = 0;
        $tlines = 0;
        $lncnt = int($max / $cols);
        $lncnt++ if ($max % $cols);
        for ($i = 0; $i < $max; $i++) {
            $dist_nm = $arr[$i];
            $ra = $disth{$dist_nm};
            $callsign = ${$ra}[0];
            $tsecs = ${$ra}[1];
            ### $dist_nm = ${$ra}[2];
            $cnt = ${$ra}[3];
            $tm = get_time_stg($tsecs);

            $nmph = ($dist_nm / $tsecs) * 60 * 60;
            $nmph = int($nmph + 0.5);

            $htm .= "<tr>\n" if ($wrap == 0);
            ;
            $htm .= "<td class=\"ran\">".($i+1)."</td>\n";
            $htm .= "<td class=\"vat\"><b>$callsign</b></td>\n";
            $htm .= "<td>$tm</td>\n";
            #$htm .= "<td>for $tm, $dist_nm nm. av. $nmph kt.</td>\n";
            $htm .= "<td class=\"ran\">".get_nn($dist_nm)."</td>\n";
            $htm .= "<td class=\"ran\">".get_nn($nmph)."</td>\n";
            $htm .= "<td class=\"ran\">$cnt</td>\n";
            $wrap++;
            if ($wrap == $cols) {
                $htm .= "</tr>\n";
                $wrap = 0;
                $dnlines++;
                $tlines++;
                if ($max_table_lines && ($tlines >= $max_table_lines) && (($lncnt - $dnlines) > $min_table_lines )) {
                    $tlines = 0;
                    $htm .= "<tr><td align=\"center\" colspan=\"$tcols\">\n";
                    $htm .= "Table $tab_cnt: <a href=\"#tab$tab_cnt.top\">top</a> <a href=\"#tab$tab_cnt.end\">end</a>\n";
                    $htm .= "File: <a href=\"#top\">top</a> <a href=\"#end\">end</a>\n";
                    $htm .= "</td></tr>\n"; 
                }
            } else {
                $htm .= "<td>|</td>\n";
            }

            # display
            $callsign .= ' ' while (length($callsign) < 8);
            my $clnn = sprintf("%3d",($i+1));
            prt(" $clnn: $callsign flew for $dist_nm nm. in $tm. av. $nmph kt. mods $cnt\n") if (VERB9());
        }

        if ($wrap) {
            while ($wrap < $cols) {
                $wrap++;
                $htm .= "<td class=\"ran\">&nbsp;</td>\n";
                $htm .= "<td class=\"vat\">&nbsp;</td>\n";
                $htm .= "<td>&nbsp;</td>\n";
                $htm .= "<td class=\"ran\">&nbsp;</td>\n";
                $htm .= "<td class=\"ran\">&nbsp;</td>\n";
                $htm .= "<td class=\"ran\">&nbsp;</td>\n";
                $htm .= "<td>|</td>\n" if ($wrap < $cols);
            }
            $htm .= "</tr>\n";
        }
        $htm .= "</table>\n";
        $htm .= "<a name=\"tab$tab_cnt.end\" id=\"tab$tab_cnt.end\"></a>\n";

        ########################################################################################
        $htm .= "<p class=\"top\">$href_txt</p>\n";
        ########################################################################################
    ### }
    if (length($out_html) && length($htm)) {
        if ($os =~ /win/i) {
            $out_html = path_u2d($out_html);
        } else {
            $out_html = path_d2u($out_html);
        }
        $htm = get_html_head().$htm.get_html_tail();
        rename_2_old_bak($out_html);
        write2file($htm,$out_html);
        prt("Written HTML to '$out_html'\n");
        if ($only_one_feed) {
            system("$out_html\n");
        }
    }
}

sub add_csv_flight($$) {
    my ($fid,$ra) = @_;
    #               0         1    2    3       4      5        6    7        8      9 10
    #$hash{$fid} = [$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$tsecs,0,$upd];
    my $callsign = ${$ra}[0];
    my $lat = ${$ra}[1];
    my $lon = ${$ra}[2];
    my $alt_ft = ${$ra}[3];
    my $model = ${$ra}[4];
    my $spd_kts = ${$ra}[5];
    my $hdg = ${$ra}[6];
    my $dist_nm = ${$ra}[7];
    my $tsecs = ${$ra}[8];
    my $upd = ${$ra}[10];
    if (defined $flt_fids{$fid}) {
        # update flight
        my $ra2 = $flt_fids{$fid};
        ${$ra2}[7] = $dist_nm;
        ${$ra2}[8] = $tsecs;
        ${$ra2}[11] = $upd;
    } else {
        # add new FID
        $flt_fids{$fid} = [$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$tsecs,0,$upd,$upd];
    }
}

# 0             1      2         3        4   5         6 7   8    9                   10
# 1467204782000,AF2222,45.724327,5.082578,799,777-200ER,0,180,8539,2016-07-07 16:49:25,0
# my $line = 
# "$fid,        $callsign,$lat,$lon,$alt_ft,  $model,   $spd_kts,$hdg,$dist_nm, $upd1,$tot_secs\n";

sub process_in_file($) {
    my ($rfile) = @_;
    my $inf = ${$rfile}[0];
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n");
    my ($line,$cnt,$lnn,@arr,$i);
    my ($fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$upd,$dist_nm,$epock,$diff,$diff2,$tsecs);
    my ($stt,$end,$elap,$tm);
    $lnn = 0;
    my $first_upd = 'N/A';
    my $last_upd = 'N/A';

    my $bgn_epock = 0;
    my $last_epock = 0;
    my $last_diff = 0;
    my $cnt_recs = 0;
    my $tot_recs = 0;
    my $flt_cnt = 0;
    my %hash = ();
    my @fids = ();  # keys %hash;
    my ($ra,$fid2,$cnt2);
    my $min_flts = 999999;
    my $max_flts = 0;
    my $max_upd = '';
    my $min_upd = '';
    $stt = [ gettimeofday ];
    for ($i = 0; $i < $lncnt; $i++) {
        $line = $lines[$i];
        chomp $line;
        $lnn = $i + 1;
        @arr = split(/,/,$line);
        $cnt = scalar @arr;
        if ($cnt < 11) {
            prtw("W:$lnn: BAD $line\n");
            next;
        }
        prt("$line\n") if (VERB9());
        #             0    1         2    3    4       5      6        7    8        9     10
        # my $line = "$fid,$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$upd1,$tot_secs\n";
        $fid = $arr[0];
        $callsign = $arr[1];
        $lat = $arr[2];
        $lon = $arr[3];
        $alt_ft = $arr[4];
        $model = $arr[5];
        $spd_kts = $arr[6];
        $hdg = $arr[7];
        $dist_nm = $arr[8];
        $upd = $arr[9];
        $tsecs = $arr[10];

        next if ($fid eq 'fid');

        $epock = str2time($upd);
        $bgn_epock = $epock if ($bgn_epock == 0);
        $last_epock = $epock;
        $diff = $epock - $bgn_epock;
        #prt("$cnt columns... $upd, epoch $epock, diff $diff.\n");
        prt("$lnn: $upd, epoch $epock, diff $diff.\n") if (VERB5());
        $i++;
        $last_diff = $diff;
        $cnt_recs = 1;
        $tot_recs = 1;
        $flt_cnt = 1;
        #              0         1    2    3       4      5        6    7        8      9 10
        $hash{$fid} = [$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$tsecs,0,$upd];
        #$show = 1;
        #$type = 'NEW';
        last;
    }
    $first_upd = $upd;
    my $curr_upd = $upd;
    for (; $i < $lncnt; $i++) {
        $line = $lines[$i];
        chomp $line;
        $lnn = $i + 1;
        @arr = split(/,/,$line);
        $cnt = scalar @arr;
        if ($cnt < 11) {
            prtw("W:$lnn: BAD $line\n");
            next;
        }
        prt("$line\n") if (VERB9());
        $fid = $arr[0];
        $callsign = $arr[1];
        $lat = $arr[2];
        $lon = $arr[3];
        $alt_ft = $arr[4];
        $model = $arr[5];
        $spd_kts = $arr[6];
        $hdg = $arr[7];
        $dist_nm = $arr[8];
        $upd = $arr[9];
        $tsecs = $arr[10];
        
        #next if ($fid eq 'fid');
        $tot_recs++;
        $cnt_recs++;
        $epock = str2time($upd);
        $diff = $epock - $bgn_epock;
        $diff2 = $epock - $last_epock;
        #prt("$cnt columns... $upd, epoch $epock, diff $diff.\n");
        if ($upd ne $curr_upd) {
            ####################################################################
            # have a set of crossfeed records, ie for each json feed - $flt_cnt
            @fids = keys %hash;
            $cnt2 = scalar @fids;
            # prt("Process $cnt2 flights...\n");
            if ($cnt2) {
                if ($cnt2 < $min_flts) {
                    $min_flts = $cnt2;
                    $min_upd  = $upd;
                }
                if ($cnt2 > $max_flts) {
                    $max_flts = $cnt2;
                    $max_upd = $upd;
                }
            }
            foreach $fid2 (@fids) {
                $ra = $hash{$fid2};
                add_csv_flight($fid2,$ra);
            }
            ####################################################################
            if ($diff2 > 60) {
                $cnt_recs--;
                prt("$lnn: $upd, new $epock, diff2 $diff2. recs $cnt_recs on $tot_recs\n") if (VERB5());
                $bgn_epock = $epock;
                $cnt_recs = 1;
            } else {
                prt("$lnn: $upd, epoch $epock, diff $diff. flts $flt_cnt, recs $cnt_recs\n") if (VERB5());
            }
            $curr_upd = $upd;
            $flt_cnt = 1;
            %hash = ();     # clear hash
            #              0         1    2    3       4      5        6    7        8      9 10
            $hash{$fid} = [$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$tsecs,0,$upd];
        } else {
            $flt_cnt++;
            #              0         1    2    3       4      5        6    7        8      9 10
            $hash{$fid} = [$callsign,$lat,$lon,$alt_ft,$model,$spd_kts,$hdg,$dist_nm,$tsecs,0,$upd];
        }
        $last_epock = $epock;
        if (($lnn % 100000) == 0) {
            my $pct = int(($lnn / $lncnt) * 100);
            my $rem = $lncnt - $i;
            $end = [ gettimeofday ];
            $elap = tv_interval( $stt, $end );
            $tm = get_time_stg($elap);
            #  $msd_elap += $elap;
            # prt("ELAP: Inserted $cnt records in $elap secs ...\n");
            prt("Done $lnn of $lncnt lines... $pct% in $tm...\n");
        }
        $last_upd = $upd;
    }

    # update totals
    $g_tot_files++;
    $g_tot_records += $lncnt;

    $end = [ gettimeofday ];
    $elap = tv_interval( $stt, $end );
    $tm = get_time_stg($elap);
    prt("Done $lnn of $lncnt lines... 100% in $tm...\n");
    ####################################################################
    # have a set of crossfeed records, ie for each json feed - $flt_cnt
    @fids = keys %hash;
    $cnt2 = scalar @fids;
    # prt("Process $cnt2 flights...\n");
    if ($cnt2) {
        $min_flts = $cnt2 if ($cnt2 < $min_flts);
        $max_flts = $cnt2 if ($cnt2 > $max_flts);
        if ($min_flts && ($min_flts < $g_min_flts)) {
            $g_min_flts = $min_flts;
            $g_min_upd  = $min_upd;
        }
        if ($max_flts > $g_max_flts) {
            $g_max_flts = $max_flts;
            $g_max_upd  = $max_upd;
        }
    }
    foreach $fid2 (@fids) {
        $ra = $hash{$fid2};
        add_csv_flight($fid2,$ra);
    }
    ####################################################################
    $ra = $rfile;
    # $inf == $ff = ${$ra}[0];
    # just file name - $file = ${$ra}[1];
    $tm = ${$ra}[2];    # file time
    my $sz = ${$ra}[3];
    # my @lt = localtime($tm);
    #              0    1   2      3            4       5         6         7
    push(@g_files,[$inf,$sz,$lncnt,$first_upd,$last_upd,$min_flts,$max_flts,$tm]);
    prt("Processed $tot_recs - json groups $min_flts to $max_flts ($g_min_flts/$g_max_flts)\n");
}

sub process_in_dir($) {
    my $dir = shift;
    if (! opendir( DIR, $dir) ) {
        pgm_exit(1,"ERROR: Unable to open dir [$dir]\n"); 
    }
    my @files = readdir(DIR);
    closedir(DIR);
    my ($file,$ff,$sb,$tm,$sz,$max,$i,$ra,$i2,$msg,$ci,$pct,$elap,$tend,$est);
    ut_fix_directory(\$dir);
    my @csv = ();
    my $tot_size = 0;
    my $tot_done = 0;
    my $tbgn = [ gettimeofday ];
    foreach $file (@files) {
        next if ($file eq '.');
        next if ($file eq '..');
        $ff = $dir.$file;
        my ($n,$d,$e) = fileparse($ff, qr/\.[^.]*/ );
        if ($e =~ /^\.csv$/i) {
            if ($sb = stat($ff)) {
                $tm = $sb->mtime;
                $sz = $sb->size;
                push(@csv,[$ff,$file,$tm,$sz]);
                $tot_size += $sz;
            } else {
                prtw("WARNING: Failed to 'stat' $ff - SKIPPED\n");
            }
            #process_in_file($ff);
        }
    }
    $max = scalar @csv;
    prt("Found $max csv files to process... ".get_nn($tot_size)." bytes...\n");
    for ($i = 0; $i < $max; $i++) {
        $i2 = $i + 1;
        $ra = $csv[$i];
        $ff = ${$ra}[0];
        $file = ${$ra}[1];
        $tm = ${$ra}[2];
        $sz = ${$ra}[3];
        my @lt = localtime($tm);
        $msg = sprintf( "%02d/%02d/%04d %02d:%02d %12s %s", $lt[3], $lt[4]+1, $lt[5]+1900,
                $lt[2], $lt[1], get_nn($sz), $ff );
        $ci = sprintf("%2d",$i2);
        prt("$ci of $max: $msg\n");
        process_in_file($ra);
        $tot_done += $sz;
        $pct = ($tot_done * 100) / $tot_size;
        $tend = [ gettimeofday ];
        $elap = tv_interval( $tbgn, $tend );
        $msg = 'N/A';
        if ($pct > 0) {
            $est = (100 / $pct) * $elap;
            $msg = "est.rem ".get_time_stg($est - $elap)." est.tot ".get_time_stg($est);
        }
        $pct = int($pct * 10) / 10;
        $tm = get_time_stg($elap);
        prt("Done $pct%... in $tm... $msg\n");

    }
    ### pgm_exit(1,"TEMP EXIT!\n");
}

sub process_a_file($) {
    my $file = shift;
    my ($sb,$tm,$sz,$ff,$ra);
    $ff = $file;
    if ($sb = stat($ff)) {
        $tm = $sb->mtime;
        $sz = $sb->size;
        $ra = [$ff,$file,$tm,$sz];
        process_in_file($ra);
    } else {
        prtw("WARNING: Failed to 'stat' $ff - SKIPPED\n");
    }
}

#########################################
### MAIN ###
parse_args(@ARGV);
if (-d $in_file) {
    process_in_dir($in_file);
} else {
    process_a_file($in_file);
}
show_flt_fids();

#if ($only_one_feed) {
#    get_one_feed();
#} else {
#    repeat_feeds();
#}
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
            } elsif ($sarg =~ /^d/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_dir = $sarg;
                prt("Set out DIR to [$out_dir].\n") if ($verb);
            } elsif ($sarg =~ /^o/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_html = $sarg;
                prt("Set out html file to [$out_html].\n") if ($verb);
            } elsif ($sarg =~ /^L/) {
                $only_one_feed = 1;
                prt("Pass html to system at end.\n") if ($verb);
            } elsif ($sarg =~ /^a/) {
                $add_csv_header = 1;
                prt("Add CSV header to 'new' files.t\n") if ($verb);
            } elsif ($sarg =~ /^m/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if ($sarg =~ /^\d+$/) {
                    $max_show_cs = $sarg;
                    prt("Set max. callsign stats to show [$sarg]. 0=all\n") if ($verb);
                } else {
                    pgm_exit(1,"ERROR: Argument [$arg] must be followed by an integer 0-999999...! But $sarg?\n");
                }
            } elsif ($sarg =~ /^n/) {
                $add_table_captions = 0;
                prt("No table captions added.\n") if ($verb);
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
            #$load_log = 1;
            prt("Set DEFAULT input to [$in_file]\n");
        }
    }
    if (length($in_file) ==  0) {
        pgm_exit(1,"ERROR: No input files found in command!\n");
    }

    # if not a file or directory
    if ((! -f $in_file) && (! -d $in_file)) {
        pgm_exit(1,"ERROR: Unable to find in file, or dir [$in_file]! Check name, location...\n");
    }
}

sub give_help {
    prt("\n");
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-file/in_dir\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --out <file>  (-o) = Write html output to this file. (def=$out_html)\n");
    prt(" --LOADHTML    (-L) = Pass html to system at end.\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --max <num>   (-m) = Set maximum callsigns to output in stats. 0=all. (def=$max_show_cs)\n");
    prt(" --nocaptions  (-n) = Do not add a caption to each table generated. (def=$add_table_captions)\n");
    prt("\n");
    prt(" Read a json csv log, created by cfjsonlog.pl, and generate some html\n");
    prt(" table information of models and callsigns used, over the period of the log.\n");
    prt(" Accepts a directory input, where all '.csv' files found are assumed to be cf\n");
    prt(" csv logs, and each will be processed, and the totals put in the tables.\n");
    prt("\n");
}

# eof - cfcsvlogs.pl
