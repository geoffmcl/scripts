#!/usr/bin/perl -w
# NAME: cfjsonlog.pl (was: jsonfeeds.pl)
# AIM: Fetch, show, and store a json crossfeed log in a target directory.
# Log file name will change each day, in the form - $out_dir/'flights-YYYY-MM-DD.csv'
# 07/07/2016 - Moved into useful 'scripts' repo, and renamed to cfjsonlog.pl
# The default is to fetch and write a flight record each 5 seconds *** FOREVER *** Ctrl+c to abort...
# Add option -1, to just get one, and write a compact CSV to an -o out-file
# All fetches are from a single server "http://crossfeed.freeflightsim.org/flights.json" = Thanks Pete
# 22/07/2016 - Merge one feed, -1, with repeated feeds...
# 06/07/2016 - Review
# 2015-01-09 - Initial cut
######################################

use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use File::Spec; # File::Spec->rel2abs($rel); # get ABSOLUTE from REALTIVE get_full_path
use LWP::Simple;
use JSON;
use Data::Dumper;
use Cwd;
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
my $VERS = "0.0.8 2016-07-22";
##my $VERS = "0.0.7 2016-07-07";
##my $VERS = "0.0.6 2016-07-06";
##my $VERS = "0.0.5 2015-01-09";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';
my $out_dir = $temp_dir.$PATH_SEP."temp-flights";
my $only_one_feed = 0;
my $add_csv_header = 1;

############################################################# 
# crossfeed json feed - never fetch faster than 1 Hz!
my $feed1 = "http://crossfeed.freeflightsim.org/flights.json";
#############################################################

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'def_file';

### program variables
my @warnings = ();
my $cwd = cwd();
my $MPS2KT = 1.94384;   # meters per second to knots
my $SG_EPSILON = 0.000001;
my $last_ymd = '';

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
        $repeat = 0 if ($only_one_feed);
    }   # while ($repeat)
}

#########################################
### MAIN ###
parse_args(@ARGV);
repeat_feeds();
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
                $out_file = $sarg;
                prt("Set out file to [$out_file].\n") if ($verb);
            } elsif ($sarg =~ /^1/) {
                $only_one_feed = 1;
                prt("Only show one feed and exit\n") if ($verb);
            } elsif ($sarg =~ /^n/) {
                $add_csv_header = 0;
                prt("Disabled adding csv header to new files.\n") if ($verb);
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            $in_file = $arg;
            prt("Set input to [$in_file]\n") if ($verb);
        }
        shift @av;
    }

#    if ($debug_on) {
#        prtw("WARNING: DEBUG is ON!\n");
#        if (length($in_file) ==  0) {
#            $in_file = $def_file;
#            prt("Set DEFAULT input to [$in_file]\n");
#        }
#    }
#    if (length($in_file) ==  0) {
#        pgm_exit(1,"ERROR: No input files found in command!\n");
#    }
#    if (! -f $in_file) {
#        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
#    }
}

sub give_help {
    prt("\n");
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-file\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --dir <dir>   (-d) = Set output DIR. (def=$out_dir)\n");
    prt(" --no-header   (-n) = Disable adding csv header to each new file. (def=$add_csv_header)\n");
    prt("Single shot mode\n");
    prt(" --1           (-1) = Only fetch one feed, and exit. (def=$only_one_feed)\n");
    prt(" --out <file>  (-o) = Write output to this file. (def=$out_file)\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt("\n");
}

# eof - cfjsonlog.pl.pl
