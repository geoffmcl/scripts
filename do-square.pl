#!/usr/bin/perl -w
# NAME: do-square.pl
# AIM: Connect to fgfs through telnet, and fly a circuit...
# Circuit is extracted from an .xg file, with certain 'attributes' present to convey info...
# This could also be written/loaded as an xml file...
# 05/07/2015 geoff mclane http://geoffair.net/mperl
#!/usr/bin/perl -w
# NAME: fg_square.pl
# AIM: Through a TELNET connection, fly the aircraft on a course
# 08/07/2015 - Flies a reasonable course, sometimes does a large turns, > 100 degs
# If information known, also align with the runway after turn final... 
# drop engine rpm, slow to flaps speed, lower flaps, commence decent...
#
# 30/06/2015 - Much more refinement
# 03/04/2012 - More changes
# 16/07/2011 - Try to add flying a course around YGIL, using the autopilot
# 15/02/2011 (c) Geoff R. McLane http://geoffair.net/mperl - GNU GPL v2 (or +)
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use IO::Socket;
use Term::ReadKey;
use Time::HiRes qw( usleep gettimeofday tv_interval );
use Math::Trig;
my $cwd = cwd();
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "/temp";
# unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl'! Check location and \@INC content.\n";
require 'lib_fgio.pl' or die "Unable to load 'lib_fgio.pl'! Check location and \@INC content.\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";
require "Bucket2.pm" or die "Unable to load Bucket2.pm ...\n";

# log file stuff
my $outfile = $temp_dir."/temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.5 2015-07-06";
my $load_log = 0;
my $in_file = 'ygil-L.xg';
my $tmp_xg_out = $temp_dir."/temp.$pgmname.xg";
my $verbosity = 0;
my $out_file = '';
# my $HOST = "localhost";
my ($fgfs_io,$HOST,$PORT,$CONMSG,$TIMEOUT,$DELAY);
my $connect_win7 = 1;
if (defined $ENV{'COMPUTERNAME'}) {
    if (!$connect_win7 && $ENV{'COMPUTERNAME'} eq 'WIN7-PC') {
        # connect to Ubuntu in DELL02
        $HOST = "192.168.1.34"; # DELL02 machine
        $PORT = 5556;
        $CONMSG = "Assumed in WIN7-PC connection to Ubuntu DELL02 ";
    } else {
        # assumed in DELL01 - connect to WIN7-PC
        $HOST = "192.168.1.33"; # WIN7-PC machine
        $PORT = 5557;
        $CONMSG = "Assumed in DELL01 connection to WIN7-PC ";
    }
} else {
    # assumed in Ubuntu - connect to DELL01
    $HOST = "192.168.1.11"; # DELL01
    $PORT = 5551;
    $CONMSG = "Assumed in Ubuntu DELL02 connection to DELL01 ";
}
$TIMEOUT = 2;
$DELAY = 5;
my $engine_count = 1;
my $min_eng_rpm = 0; #400;
my $wait_alt_hold = 1;

my $circuit_mode = 0;
my $circuit_flag = 0;
my $chk_turn_done = 0;

my $active_key = 'YGIL';
my $active_runway = '33';

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'def_file';

### program variables
my @warnings = ();
my $SG_NM_TO_METER = 1852;
my $SG_METER_TO_NM = 0.0005399568034557235;

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
    fgfs_disconnect();
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

sub prtt($) {
    my $txt = shift;
    if ($txt =~ /^\n/) {
        $txt =~ s/^\n//;
        prt("\n".lu_get_hhmmss_UTC(time()).": $txt");
    } else {
        prt(lu_get_hhmmss_UTC(time()).": $txt");
    }
}

my $icao = 'YGIL';
my $circuit = '33';
# rough Gil circuit - will be replaced by CALCULATED values
my $tl_lat = -31.684063;
my $tl_lon = 148.614120;
my $bl_lat = -31.723495;
my $bl_lon = 148.633003;
my $br_lat = -31.716778;
my $br_lon = 148.666992;
my $tr_lat = -31.672960;
my $tr_lon = 148.649139;


my $a_gil_lat = -31.697287500;
my $a_gil_lon = 148.636942500;
my $a_dub_lat = -32.2174865;
my $a_dub_lon = 148.57727;

###################################################################
# RUNWAY ARRAY OFFSETS
my $RW_LEN = 0;
my $RW_HDG = 1;
my $RW_REV = 2;
my $RW_TT1 = 3;
my $RW_TT2 = 4;
my $RW_CLAT = 5;
my $RW_CLON = 6;
my $RW_LLAT = 7;
my $RW_LLON = 8;
my $RW_RLAT = 9;
my $RW_RLON = 10;
my $RW_DONE = 11;
#                 Len    Hdg   Rev  Title  RTit Ctr Lat    Ctr Lon
#                 0      1     2    3     4     5          6           7  8  9  10 11
my @gil_patt = ();
### my @gil_rwys = ( [4204,  162.0, 0, '15', '33', -31.696928, 148.636404, 0, 0, 0, 0, 0 ] );
my @gil_rwys = ( [3984,  162.22, 0, '15', '33', -31.69656323, 148.6363057, 0, 0, 0, 0, 0 ] );
#my @gil_navs = ( ["", 0 ] );
my @gil_navs = ();
#my @gil_rwys = ( [162.0, 4204], [93.0, 1902] );
my @dub_patt = ( [ ] );
my @dub_rwys = ( [5600, 53.61, 0, '05', '23', -32.218265, 148.576145, 0, 0, 0, 0, 0 ] );
my @dub_navs = ( ["VOR", 114.4], ["NDB", 251] );

my $OL_LAT = 0;
my $OL_LON = 1;
my $OL_NAV = 2;
my $OL_RWY = 3;
my $OL_PAT = 4;
my %apt_locations = (
    # ICAO       Center LAT, LON       NAVAIDS      RUNWAYS
    'YGIL' => [$a_gil_lat, $a_gil_lon, \@gil_navs, \@gil_rwys, \@gil_patt ],
    'YSDU' => [$a_dub_lat, $a_dub_lon, \@dub_navs, \@dub_rwys, \@dub_patt ]
    );

sub get_locations() { return \%apt_locations; }

###################################################################

sub get_type($) {
    my $color = shift;
    my $type = 'Unknown!';
    if ($color eq 'gray') {
        $type = 'bbox';
    } elsif ($color eq 'white') {
        $type = 'circuit';
    } elsif ($color eq 'blue') {
        $type = 'center line';
    } elsif ($color = 'red') {
        $type = 'runways';
    }
    return $type;
}

my ($mreh_circuithash,$ref_circuit_hash);
sub show_ref_circuit_hash() {
    if (!defined $mreh_circuithash) {
        return undef;
    }
    my $rch = $mreh_circuithash;
    my @arr = keys %{$rch};
    prt("Keys ".join(" ",@arr)."\n");
    my ($key,$rpa,$cnt,$i,$rpa2,$cnt2,$rpa3,$lat,$lon,$msg,$type);
    my ($elat1,$elon1,$elat2,$elon2);
    my $tot_pts = 0;
    foreach $key (@arr) {
        $type = get_type($key);
        $rpa = ${$rch}{$key};
        $cnt = scalar @{$rpa};
        $tot_pts = 0;
        $msg = '';
        for ($i = 0; $i < $cnt; $i++) {
            $rpa2 = ${$rpa}[$i];
            $cnt2 = scalar @{$rpa2};
            $tot_pts += $cnt2;
            foreach $rpa3 (@{$rpa2}) {
                $lat = ${$rpa3}[0];
                $lon = ${$rpa3}[1];
                $msg .= "$lon,$lat ";
            }
        }
        prt("Color $type ($key) - $cnt sets, $tot_pts points\n");
        prt("$msg\n");
    }
    return $rch;
}

## XG generation
sub get_circuit_xg() {
    my $xg = "annon $a_gil_lon $a_gil_lat ICAO $icao, circuit $circuit\n";
    $xg .= "color white\n";
    $xg .= "anno $tr_lon $tr_lat TR\n";
    $xg .= "$tr_lon $tr_lat\n";
    $xg .= "anno $tl_lon $tl_lat TL\n";
    $xg .= "$tl_lon $tl_lat\n";
    $xg .= "anno $bl_lon $bl_lat BL\n";
    $xg .= "$bl_lon $bl_lat\n";
    $xg .= "anno $br_lon $br_lat BR\n";
    $xg .= "$br_lon $br_lat\n";
    $xg .= "$tr_lon $tr_lat\n";
    $xg .= "NEXT\n";
    return $xg;
}

sub write_circuit_xg($) {
    my $file = shift;
    my $xg = get_circuit_xg();
    write2file($xg,$file);
    prt("Circuit XG written to '$file'\n");
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
    my ($line,$inc,$lnn,$type,@arr,$cnt,$ra,$lat,$lon,$text);
    my (@arr2);
    my $tmpxg = $tmp_xg_out;
    $lnn = 0;
    my $color = '';
    my @points = ();
    my %h = ();
    my $circ_cnt = 0;
    ###write_circuit_xg($tmpxg);
    foreach $line (@lines) {
        chomp $line;
        $lnn++;
        if ($line =~ /^\s*\#/) {
            prt("$lnn: $line\n") if (VERB9());
        } elsif ($line =~ /^\s*color\s+(.+)$/) {
            $color = $1;
            $type = 'Unknown!';
            if ($color eq 'gray') {
                $type = 'bbox';
            } elsif ($color eq 'white') {
                $type = 'circuit';
                $circ_cnt = 0;
            } elsif ($color eq 'blue') {
                $type = 'center line';
            } elsif ($color = 'red') {
                $type = 'runways';
            }
            prt("$lnn: color $color $type\n");
        } elsif ($line =~ /^\s*NEXT/i) {
            $cnt = scalar @points;
            if ($cnt) {
                $h{$color} = [] if (! defined $h{$color});
                $ra = $h{$color};
                my @a = @points;
                push(@{$ra},\@a);
                prt("NEXT: Added $cnt pts to $color\n");
            }
            @points = ();   # clear accumulated pointes
        } elsif ($line =~ /^\s*anno\s+/) {
            @arr = split(/\s+/,$line);
            $cnt = scalar @arr;
            # 0    1   2   3
            # anno lon lat text
            if ($cnt > 3) {
                $lon = $arr[1];
                $lat = $arr[2];
                $text = join(' ', splice(@arr,3));
                @arr2 = split(/\s+/,$text);
                if (scalar @arr2 == 4) {
                    $icao = $arr2[0];
                    $circuit = $arr2[3];
                    $a_gil_lat = $lat;
                    $a_gil_lon = $lon;
                    prt("CIRCUIT $a_gil_lat,$a_gil_lon ICAO $icao, circuit $circuit\n");
                } else {
                    prt("Annotation $lat,$lon '$text'\n");
                }
            }
        } else {
            @arr = split(/\s+/,$line);
            $cnt = scalar @arr;
            if ($cnt >= 2) {
                $lon = $arr[0];
                $lat = $arr[1];
                push(@points,[$lat,$lon]);
            }
            if ( $type eq 'circuit') {
                # get the CIRCUIT described in the .xg
                if ($circ_cnt == 0) {
                    $tr_lat = $lat;
                    $tr_lon = $lon;
                } elsif ($circ_cnt == 1) {
                    $tl_lat = $lat;
                    $tl_lon = $lon;
                } elsif ($circ_cnt == 2) {
                    $bl_lat = $lat;
                    $bl_lon = $lon;
                } elsif ($circ_cnt == 3) {
                    $br_lat = $lat;
                    $br_lon = $lon;
                }
                $circ_cnt++;
            }

        }
    }
    $mreh_circuithash = \%h;
    show_ref_circuit_hash();
    write_circuit_xg($tmpxg);
    $ref_circuit_hash = get_circuit_hash();
    ##pgm_exit(1,"TEMP EXIT\n");
}

##############################################################
###########
sub check_keyboard() {
    my ($char,$val,$pmsg);
    if (got_keyboard(\$char)) {
        $val = ord($char);
        $pmsg = sprintf( "%02X", $val );
        if ($val == 27) {
            prtt("ESC key... Exiting loop...\n");
            return 1;
        } elsif ($char eq '+') {
            $DELAY++;
            prtt("Increase delay to $DELAY seconds...\n");
        } elsif ($char eq '-') {
            $DELAY-- if ($DELAY);
            prtt("Decrease delay to $DELAY seconds...\n");
        } else {
            prt("Got keyboard input hex[$pmsg]...\n");
        }
    }
    return 0;
}




sub wait_fgio_avail() {
    # sub fgfs_connect($$$) 
    prt("$CONMSG at IP $HOST, port $PORT\n");
    # get the TELENET connection
    $fgfs_io = fgfs_connect($HOST, $PORT, $TIMEOUT) ||
        pgm_exit(1,"ERROR: can't open socket!\n".
        "Is FG running on IP $HOST, with TELNET enabled on port $PORT?\n");

    ReadMode('cbreak'); # not sure this is required, or what it does exactly

	fgfs_send("data");  # switch exchange to data mode

}


######################################################################
my $sp_prev_msg = '';
my $sp_msg_skipped = 0;
my $sp_msg_show = 10;
my $sp_msg_cnt = 0;

my $have_target = 0;
my $min_fly_speed = 30; # Knots
my $min_agl_height = 500;   # 4500;  # was just 500
my $alt_msg_chg = 0;
my $ind_alt_ft = 0; # YGIL = 881.7 feet
my $set_in_hg = 0;  # 29.92 STP inches of mercury
my $ind_off_degs = 0;   # -52.8.. what is this?
my $altimeter_msg = '';
my $ind_hdg_degs = 0;
my $dbg_roll = 0;
my $m_stable_cnt = 0;   # less than 2 degrees between previous ind hdg
my $got_alt_hold = 0;

sub get_hdg_in_range($) {
    my $r = shift;
    if (${$r} < 0) {
        ${$r} += 360;
    } elsif (${$r} > 360) {
        ${$r} -= 360;
    }
}

sub get_mag_hdg_from_true($) {
    my $hdg = shift;
    $hdg -= get_mag_deviation();
    get_hdg_in_range(\$hdg);
    return $hdg;
}

# this is changing fast in a TURN
sub update_hdg_ind() {
    fgfs_get_hdg_ind(\$ind_hdg_degs);
}

# sub fgfs_get_altimeter()
sub get_altimeter_stg() {
    my ($ai,$hg,$off,$ind);
    fgfs_get_alt_ind(\$ai);
    fgfs_get_alt_inhg(\$hg);
    # "/instrumentation/heading-indicator/offset-deg"
    fgfs_get_hdg_off(\$off);
    fgfs_get_hdg_ind(\$ind);
    $ind_alt_ft = $ai;
    $set_in_hg  = $hg;
    $ind_off_degs = $off;
    $ind_hdg_degs = $ind;

    set_decimal1_stg(\$ai);
    set_decimal1_stg(\$hg);

    my $msg = "QNH $hg, IndFt $ai, ";
    if ($altimeter_msg ne $msg) {
        $altimeter_msg = $msg;
        $alt_msg_chg++;
    }
}

sub show_position($) {
    my ($rp) = @_;
    return if (!defined ${$rp}{'time'});
    my $ctm = lu_get_hhmmss_UTC(${$rp}{'time'});
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$cpos,$tmp);
    my ($rch,$targ_lat,$targ_lon,$targ_hdg,$targ_dist,$targ_pset,$prev_pset);
    my $msg = '';
    my $eta = '';
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    $hdg  = ${$rp}{'hdg'};
    $agl  = ${$rp}{'agl'};
    $hb   = ${$rp}{'bug'};
    $mag  = ${$rp}{'mag'};  # is this really magnetic - # /orientation/heading-magnetic-deg

    $aspd = ${$rp}{'aspd'}; # Knots
    $gspd = ${$rp}{'gspd'}; # Knots

    my $re = fgfs_get_engines();
    my $run = ${$re}{'running'};
    my $rpm = ${$re}{'rpm'};
    my $thr = ${$re}{'throttle'};
    my $magn = ${$re}{'magn'}; # int 3=BOTH 2=LEFT 1=RIGHT 0=OFF
    my $mixt = ${$re}{'mix'}; # $ctl_eng_mix_prop = "/control/engines/engine/mixture";  # double 0=0% FULL Lean, 1=100% FULL Rich

    $thr = (int($thr * 100) / 10);
    $rpm = int($rpm + 0.5);
    # =================================================================
    # display stuff - note destroys values - local now only for display
    # =================================================================
    set_hdg_stg(\$hdg);
    set_hdg_stg(\$mag);
    # had some trouble with this BUG - seems not initialized!!! until you move it...
    if ($hb && ($hb =~ /^-*(\d|\.)+$/)) {
        set_hdg_stg(\$hb);
    } elsif ((defined $hb) && length($hb)) {
        $hb = "?$hb?!";
    } else {
        fgfs_set_hdg_bug($mag);
    }
    set_int_stg(\$alt);
    set_lat_stg(\$lat);
    set_lon_stg(\$lon);
    $cpos = "$lat,$lon,$alt";
    if ($aspd < $min_fly_speed) {
        # ON GROUND has different concerns that say position
        get_altimeter_stg();
        $agl = "OG ";
        if ($alt_msg_chg) {
            $alt_msg_chg = 0;
            $agl .= "$altimeter_msg ";
        } else {
            if ($sp_msg_cnt < 5) {
                $agl .= "$altimeter_msg ";
            } else {
                $agl .= "$cpos";
            }
        }
    } elsif (!$got_alt_hold) {
        if ($agl > $min_agl_height) {
            $agl = '';
        } elsif ($have_target) {
            $agl = '';
        } else {
            $agl = int($agl + 0.5)."Ft";
        }
    } else {
        $agl = '';
    }
    $aspd = int($aspd + 0.5);
    $gspd = int($gspd + 0.5);
    #$msg .= " $aspd/${gspd}Kt";
    #$msg .= " R=".get_curr_roll() if ($dbg_roll);
    if (!$have_target) {
        if ($got_alt_hold) {
            # what to add here
        } else {
            $msg .= " E($rpm/$thr\%)";
            $msg .= " B(".get_curr_brake_stg().")";
        }
    }
    my $prev_hdg = $ind_hdg_degs;
    update_hdg_ind(); # this is changing fast in a TURN
    my $diff = $prev_hdg - $ind_hdg_degs;
    my $turn = 's';
    if (($diff < -1.0)||($diff > 1.0)) {
        $turn = 'InTurn';
        $m_stable_cnt = 0;
    } else {
        $m_stable_cnt++;
    }
    $msg .= " d=$turn";

    $tmp = $ind_hdg_degs;
    ### set_decimal1_stg(\$tmp);
    set_hdg_stg(\$tmp);

    my $show_msg = 0;
    if ($msg eq $sp_prev_msg) {
        # decide to show or not
        $sp_msg_skipped++;
        if ($sp_msg_skipped > $sp_msg_show) {
            $sp_msg_skipped = 0;
            $show_msg = 1;
            $sp_msg_cnt++;          # count of messages actually output
        }
    } else {
        $show_msg = 1;
        $sp_msg_cnt++;          # count of messages atually output
    }
    if ($show_msg) {
        my $rch = $ref_circuit_hash;
        if (defined ${$rch}{'target_eta'}) {
            if ($turn eq 's') {
                # in stable level flight - check for course change
                $eta = ${$rch}{'target_eta'};
                my $tlat = ${$rch}{'target_lat'};   # $targ_lat;
                my $tlon = ${$rch}{'target_lon'};   # $targ_lon;
                my ($az1,$az2,$distm);
                fg_geo_inverse_wgs_84 ($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$distm);
                ${$rch}{'suggest_hdg'} = $az1;
                if (defined ${$rch}{'target_hdg'}) {
                    $az2 = ${$rch}{'target_hdg'};
                    set_hdg_stg(\$az1);
                    my $distnm = get_dist_stg_nm($distm);
                    my $distkm = get_dist_stg_km($distm);
                    $eta .= " h=$az1, d $distnm $distkm ";
                    if (abs($az1 - $az2) > 1) {
                        if (${$rch}{'suggest_chg'}) {
                            ${$rch}{'suggest_chg'}++;
                            $eta .= " Waiting ".${$rch}{'suggest_chg'};
                        } else {
                            ${$rch}{'suggest_chg'} = 1;
                            $eta .= " Suggest change...";
                        }
                    }
                }
            }
        }
        $hdg  = ${$rp}{'hdg'};
        # $agl  = ${$rp}{'agl'};
        # $hb   = ${$rp}{'bug'};
        $mag  = ${$rp}{'mag'};  # is this really magnetic - # /orientation/heading-magnetic-deg
        set_hdg_stg(\$hdg);
        set_hdg_stg(\$mag);
        prt("$ctm: $agl hdg=".$hdg."t/".$mag."m/${tmp}i,b=$hb $msg $eta\n");
    }

    $sp_prev_msg = $msg;    # save last message
    
}


#######################################################################
########### WAIT for engine start ####### need motor for flight #######
#######################################################################
sub wait_for_engine() {
    my ($ok,$btm,$ntm,$dtm,$ctm);
    my ($running,$rpm);
    my ($run2,$rpm2);
    my ($throt,$thpc,$throt2,$thpc2);
    my ($magn,$cmag,$mixt);
    prtt("Checking $engine_count engine(s) running...\n");
    $btm = time();
    $ctm = 0;
    $ok = 0;
    show_flight(fgfs_get_flight());
    while (!$ok) {
        my $re = fgfs_get_engines();
        $running = ${$re}{'running'};
        $rpm     = ${$re}{'rpm'};
        $throt   = ${$re}{'throttle'};
        $magn    = ${$re}{'magn'};
        $mixt    = ${$re}{'mix'};
        $cmag = 'BOTH';
        if ($magn == 0) {
            $cmag = 'NONE';
        } elsif ($magn == 1) {
            $cmag = 'LEFT';
        } elsif ($magn == 2) {
            $cmag = 'RIGHT';
        }
        $mixt = int($mixt * 100);
        # prt("run = [$running] rpm = [$rpm]\n");
        if ($engine_count == 2) {
            # TWO engines
            $run2   = ${$re}{'running2'};
            $rpm2   = ${$re}{'rpm2'};
            $throt2 = ${$re}{'throttle2'};
            if (($running eq 'true') && ($run2 eq 'true') &&
                ($rpm > $min_eng_rpm) && ($rpm2 > $min_eng_rpm)) {
                $thpc = (int($throt * 100) / 10);
                $rpm = int($rpm + 0.5);
                $thpc2 = (int($throt2 * 100) / 10);
                $rpm2 = int($rpm2 + 0.5);
                prtt("Run1=$running, rpm=$rpm, throt=$thpc\%, mags $cmag, mix $mixt ...\n");
                prtt("Run2=$run2, rpm=$rpm2, throt=$thpc2\% ...\n");
                $ok = 1;
                last;
            }
        } else {
            # ONE engine
            if (($running eq 'true') && ($rpm > $min_eng_rpm)) {
                $thpc = (int($throt * 100) / 10);
                $rpm = int($rpm + 0.5);
                prtt("Run=$running, rpm=$rpm, throt=$thpc\%, mags $cmag, mix $mixt ...\n");
                $ok = 1;
                last;
            }
        }
        if (check_keyboard()) {
            return 1;
        }
        $ntm = time();
        $dtm = $ntm - $btm;
        if ($dtm > $DELAY) {
            $ctm += $dtm;
            # show_flight(get_curr_flight());
            show_flight(fgfs_get_flight());
            if ($engine_count == 2) {
                prtt("Waiting for $engine_count engines to start... $ctm secs (run1=$running rpm1=$rpm, run2=$run2 rpm2=$rpm2)\n");
            } else {
                prtt("Waiting for $engine_count engine to start... $ctm secs (run=$running rpm=$rpm)\n");
            }
            $btm = $ntm;
        }
    }
    my $rp = fgfs_get_position();
    prtt("Position on got engine...\n");
    show_position($rp);
    return 0;
}


# stay HERE until AUTOPILOT kicks in...
sub wait_for_alt_hold() {
    my ($ok,$btm,$ntm,$dtm,$ctm);
    my ($ah,$rp);
    if ($wait_alt_hold) {
        prtt("Checking for altitude hold...\n");
    } else {
        fgfs_get_K_ah(\$ah);
        if ($ah eq 'true') {
            prtt("Got altitude hold ($ah)...\n");
        }
        return 0;
    }
    $btm = time();
    $ctm = 0;
    $ok = 0;
    while ( !$ok && $wait_alt_hold ) {
        fgfs_get_K_ah(\$ah);
        if ($ah eq 'true') {
            prtt("Got altitude hold ($ah)...\n");
            $rp = fgfs_get_position();
            prtt("Position on acquiring altitude hold...\n");
            show_position($rp);
            $ok = 1;
            $got_alt_hold = 1;
        } else {
            if (check_keyboard()) {
                return 1;
            }
        }
        $ntm = time();
        $dtm = $ntm - $btm;
        if ($dtm > $DELAY) {
            $ctm += $dtm;
            $rp = fgfs_get_position();
            show_position($rp);
            prtt("Cycle waiting for altitude hold... $ctm secs\n") if (!$ok);
            $btm = $ntm;
        }
    }
    return 0;
}

sub set_circuit_values($$) {
    my ($rch,$show) = @_;
    my ($az1,$az2,$dist);
    my ($dwd,$dwa,$bsd,$bsa,$rwd,$rwa,$crd,$cra);
    my ($tllat,$tllon,$bllat,$bllon,$brlat,$brlon,$trlat,$trlon);
    my ($elat1,$elon1);  # nearest end

    fg_geo_inverse_wgs_84 (${$rch}{'tl_lat'},${$rch}{'tl_lon'},${$rch}{'bl_lat'},${$rch}{'bl_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'tl_az1'} = $az1;
    ${$rch}{'tl_az2'} = $az2;
    ${$rch}{'tl_dist'} = $dist;
    ${$rch}{'TL'} = [$az1,$az2,$dist];

    fg_geo_inverse_wgs_84 (${$rch}{'bl_lat'},${$rch}{'bl_lon'},${$rch}{'br_lat'},${$rch}{'br_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'bl_az1'} = $az1;
    ${$rch}{'bl_az2'} = $az2;
    ${$rch}{'bl_dist'} = $dist;
    ${$rch}{'BL'} = [$az1,$az2,$dist];

    fg_geo_inverse_wgs_84 (${$rch}{'br_lat'},${$rch}{'br_lon'},${$rch}{'tr_lat'},${$rch}{'tr_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'br_az1'} = $az1;
    ${$rch}{'br_az2'} = $az2;
    ${$rch}{'br_dist'} = $dist;
    ${$rch}{'BR'} = [$az1,$az2,$dist];

    fg_geo_inverse_wgs_84 (${$rch}{'tr_lat'},${$rch}{'tr_lon'},${$rch}{'tl_lat'},${$rch}{'tl_lon'},\$az1,\$az2,\$dist);
    ${$rch}{'tr_az1'} = $az1;
    ${$rch}{'tr_az2'} = $az2;
    ${$rch}{'tr_dist'} = $dist;
    ${$rch}{'TR'} = [$az1,$az2,$dist];

    ### ${$rch}{'rwy_ref'} = $active_ref_rwys;
    #### ${$rch}{'rwy_off'} = $active_off_rwys;

    # ================================================
    $tllat = ${$rch}{'tl_lat'};
    $tllon = ${$rch}{'tl_lon'};
    $bllat = ${$rch}{'bl_lat'};
    $bllon = ${$rch}{'bl_lon'};
    $brlat = ${$rch}{'br_lat'};
    $brlon = ${$rch}{'br_lon'};
    $trlat = ${$rch}{'tr_lat'};
    $trlon = ${$rch}{'tr_lon'};
    # ================================================

    if ($show) {
        ### my ($elat2,$elon2);
        ### my ($az11,$az21,$dist1);

        $tllat = ${$rch}{'tl_lat'};
        $tllon = ${$rch}{'tl_lon'};
        $bllat = ${$rch}{'bl_lat'};
        $bllon = ${$rch}{'bl_lon'};
        $brlat = ${$rch}{'br_lat'};
        $brlon = ${$rch}{'br_lon'};
        $trlat = ${$rch}{'tr_lat'};
        $trlon = ${$rch}{'tr_lon'};

        # extract values
        # downwind TL to BL
        $dwa = ${$rch}{'tl_az1'};
        $dwd = ${$rch}{'tl_dist'};
        # base BL to BR
        $bsd = ${$rch}{'bl_dist'};
        $bsa = ${$rch}{'bl_az1'};
        # turn final BR to TR
        $rwd = ${$rch}{'br_dist'};
        $rwa = ${$rch}{'br_az1'};
        # cross TR to TL
        $crd = ${$rch}{'tr_dist'};
        $cra = ${$rch}{'tr_az1'};

        # get NEAREST runway END
        # $elat1 = ${$active_ref_rwys}[$active_off_rwys][$RW_LLAT];
        # $elon1 = ${$active_ref_rwys}[$active_off_rwys][$RW_LLON];
        ### fg_geo_inverse_wgs_84 (${$rch}{'br_lat'},${$rch}{'br_lon'},$elat1,$elon1,\$az1,\$az2,\$dist);
        fg_geo_inverse_wgs_84 ($tl_lat,$tl_lon,$bl_lat,$bl_lon,\$az1,\$az2,\$dist);


        # set for display - values DESTROYED for calculations
        # ===================================================

        set_dist_stg(\$dist);
        set_int_stg(\$az1);
        ### set_dist_stg(\$dist1);

        set_lat_stg(\$tllat);
        set_lat_stg(\$bllat);
        set_lat_stg(\$brlat);
        set_lat_stg(\$trlat);
        set_lon_stg(\$tllon);
        set_lon_stg(\$bllon);
        set_lon_stg(\$brlon);
        set_lon_stg(\$trlon);

        prt("Set, show circuit...\nTL $tllat,$tllon\nBL ".
            "$bllat,$bllon\nBR ".
            "$brlat,$brlon\nTR ".
            "$trlat,$trlon\n");

        set_int_dist_stg5(\$dwd);
        set_hdg_stg3(\$dwa);
        set_int_dist_stg5(\$bsd);
        set_hdg_stg3(\$bsa);
        set_int_dist_stg5(\$rwd);
        set_hdg_stg3(\$rwa);
        set_int_dist_stg5(\$crd);
        set_hdg_stg3(\$cra);

        prt("l1 $dwd m, on $dwa (tl2bl) - downwind, turn $bsa to base\n");
        prt("l2 $bsd m, on $bsa (bl2br) - base,     turn $rwa to final $active_key $active_runway $dist on $az1\n");
        prt("l3 $rwd m, on $rwa (br2tr) - runway,   turn $cra to cross\n");
        prt("l4 $crd m, on $cra (tr2tl) - cross,    turn $dwa to downwind\n");

    }
}


sub get_circuit_hash() {
    my %h = ();
    $h{'tl_lat'} = $tl_lat;
    $h{'tl_lon'} = $tl_lon;
    $h{'bl_lat'} = $bl_lat;
    $h{'bl_lon'} = $bl_lon;
    $h{'br_lat'} = $br_lat;
    $h{'br_lon'} = $br_lon;
    $h{'tr_lat'} = $tr_lat;
    $h{'tr_lon'} = $tr_lon;
    set_circuit_values(\%h,1);
    $h{'suggest_hdg'} = 0;
    $h{'suggest_chg'} = 0;
    $h{'target_secs'} = 0;
    $h{'targ_first'}  = 0;
    return \%h;
}

sub get_nxt_ps($) {
    my $ps = shift;
    my $nxps = 'none';
    if ($ps eq 'TL') {
        $nxps = 'BL';
    } elsif ($ps eq 'BL') {
        $nxps = 'BR';
    } elsif ($ps eq 'BR') {
        $nxps = 'TR';
    } elsif ($ps eq 'TR') {
        $nxps = 'TL';
    } else {
        prtw("WARNING: point [$ps] set NOT one of 'TL', 'BR', 'TR', or 'TL'!");
    }
    return $nxps;
}

sub get_next_pointset($$$$$) {
    my ($rh,$ptset,$rlat,$rlon,$show) = @_;
    my $nxps = 'none';
    my ($nlat,$nlon);
    if ($ptset eq 'TL') {
        $nxps = 'BL';
        $nlat = ${$rh}{'bl_lat'};
        $nlon = ${$rh}{'bl_lon'};
    } elsif ($ptset eq 'BL') {
        $nxps = 'BR';
        $nlat = ${$rh}{'br_lat'};
        $nlon = ${$rh}{'br_lon'};
    } elsif ($ptset eq 'BR') {
        $nxps = 'TR';
        $nlat = ${$rh}{'tr_lat'};
        $nlon = ${$rh}{'tr_lon'};
    } elsif ($ptset eq 'TR') {
        $nxps = 'TL';
        $nlat = ${$rh}{'tl_lat'};
        $nlon = ${$rh}{'tl_lon'};
    } else {
        prtw("WARNING: point [$ptset] set NOT one of 'TL', 'BR', 'TR', or 'TL'!");
    }
    ${$rlat} = $nlat;
    ${$rlon} = $nlon;
    prtt("get_next_pointset: from $ptset to $nxps\n") if ($show);
    return $nxps;
}

#######################################################################################
# A good attempt at choosing a circuit target
#######################################################################################
sub get_closest_ptset($$$$$$) {
    my ($rch,$slat,$slon,$rpt,$rlat,$rlon) = @_;
    ### set_distances_bearings($rch,$slat,$slon,"Initial position");
    my $pt = "TL";
    my $dist = ${$rch}{'tl_dist'};  # distance to top-left
    my $tlat = ${$rch}{'tl_lat'};
    my $tlon = ${$rch}{'tl_lon'};
    if (${$rch}{'bl_dist'} < $dist) {  # distance to bottom left
        # BOTTOM LEFT
        $dist = ${$rch}{'bl_dist'};
        $pt = "BL";
        $tlat = ${$rch}{'bl_lat'};
        $tlon = ${$rch}{'bl_lon'};
    }
    if (${$rch}{'br_dist'} < $dist) {  # distance to bottom right
        # BOTTOM RIGHT
        $dist = ${$rch}{'br_dist'};
        $pt = "BR";
        $tlat = ${$rch}{'br_lat'};
        $tlon = ${$rch}{'br_lon'};
    }
    if (${$rch}{'tr_dist'} < $dist) {  # distance to top right
        # TOP RIGHT
        $dist = ${$rch}{'tr_dist'};
        $pt = "TR";
        $tlat = ${$rch}{'tr_lat'};
        $tlon = ${$rch}{'tr_lon'};
    }
    ${$rpt} = $pt;
    ${$rlat} = $tlat;
    ${$rlon} = $tlon;
}

#####################################################
##### SET A TARGET TO ONE OF APEX OF THE CIRCUIT ####
#####################################################
# This will return the next target when joining a circuit from in or out of current circuit
sub set_next_in_circuit_targ($$$$) {
    my ($rch,$slat,$slon,$pt) = @_;
    my ($nlat,$nlon,$nxps);
    ## get next ptset
    $nxps = get_next_pointset($rch,$pt,\$nlat,\$nlon,0);
    ${$rch}{'target_lat'} = $nlat;   # $targ_lat;
    ${$rch}{'target_lon'} = $nlon;   # $targ_lon;

    ### This seems the BEST ;=))
    ### my ($clat,$clon);
    ### $clat = ($tlat + $nlat) / 2;
    ### $clon = ($tlon + $nlon) / 2;
    ### $next_targ_lat = $clat;
    ### $next_targ_lon = $clon;
    ## prt("Set target lat, lon $clat,$clon\n");
    my ($distm,$az1,$az2);
    # get info, from HERE to TARGET
    fg_geo_inverse_wgs_84 ($slat,$slon,$nlat,$nlon,\$az1,\$az2,\$distm);

    ${$rch}{'user_lat'} = $slat;
    ${$rch}{'user_lon'} = $slon;
    # ${$rch}{'target_lat'} = $clat;   # $targ_lat;
    # ${$rch}{'target_lon'} = $clon;   # $targ_lon;
    ${$rch}{'target_hdg'} = $az1;
    ${$rch}{'target_dist'} = $distm;
    ${$rch}{'targ_ptset'} = $nxps;   # current chosen point = TARGET point
    ${$rch}{'prev_ptset'} = $pt;   # previous to get TARGET TRACK

    #    Suggest HEAD for
    # prt("Suggest head for $clat,$clon, on $az1, $distnm, prev $pt, next $nxps\n");
    my $distnm = get_dist_stg_nm($distm);
    my $distkm = get_dist_stg_km($distm);

    ##set_hdg_stg(\$az1);
    set_decimal1_stg(\$az1);
    set_lat_stg(\$nlat);
    set_lon_stg(\$nlon);
    my $targ = 'NEXT';
    my $prev = "prev $pt";

    # ${$rch}{'targ_first'} = 1;
    if (defined ${$rch}{'targ_first'}) {
        if (${$rch}{'targ_first'} <= 1) {
            $targ = 'First';
            ${$rch}{'targ_first'} = 1;
            $prev = "prev usr pt";
        } else {
            $targ = 'Next';
        }
        ${$rch}{'targ_first'}++;
    } else {
        $targ = "????";
    }

    ### TODO add ETA...
    ###prtt("\n$targ target $nlat,$nlon, on $az1, $distnm $distkm, prev $pt, next $nxps\n");
    prtt("\n$targ target $nxps, on $az1, $distnm $distkm, $prev\n");

}

sub get_next_in_circuit_targ($$$) {
    my ($rch,$slat,$slon) = @_;
    ### my $rch = $ref_circuit_hash;
    # get_closest_ptset($$$$$$)
    my ($pt,$tlat,$tlon);
    get_closest_ptset($rch,$slat,$slon,\$pt,\$tlat,\$tlon);
    set_next_in_circuit_targ($rch,$slat,$slon,$pt);
}

sub choose_first_target($$) {
    my ($rch,$rp) = @_;
    my ($lat,$lon,$alt);
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    ${$rch}{'targ_first'} = 1;
    get_next_in_circuit_targ($rch,$lat,$lon);
}


sub GetHeadingError($$) {
    my ($initial,$final) = @_;
    if ($initial > 360 || $initial < 0 || $final > 360 || $final < 0) {
        pgm_exit(1,"Internal ERROR: GetHeadingError invalid params $initial $final\n");
    }

    my $diff = $final - $initial;
    my $absDiff = abs($diff);
    if ($absDiff <= 180) {
        # Edit 1:27pm
        return $absDiff == 180 ? $absDiff : $diff;
    } elsif ($final > $initial) {
        return $absDiff - 360;
    }
    return 360 - $absDiff;
}

sub get_hdg_diff($$) {
    my ($chdg,$nhdg) = @_;
    return GetHeadingError($chdg,$nhdg);
}



sub set_suggested_hdg($$) {
    my ($rch,$rp) = @_;
    my $chdg = ${$rch}{'target_hdg'};
    my $shdg = ${$rch}{'suggest_hdg'};
    my $ct = time();
    ${$rch}{'target_hdg'} = $shdg;
    ${$rch}{'suggest_chg'} = 0;
    fgfs_set_hdg_bug(${$rch}{'target_hdg'});
    $circuit_flag |= 2;
    $m_stable_cnt = 0;
    ### set_hdg_bug_force($az2);
    ${$rch}{'target_heading_t'} = $shdg;
    ${$rch}{'target_heading_m'} = get_mag_hdg_from_true($shdg);
    ${$rch}{'target_start'} = $ct;
    ${$rch}{'begin_time'} = $ct;
    ${$rch}{'last_time'} = $ct;
    my $dist = ${$rch}{'target_dist'};
    ${$rch}{'last_dist'} = $dist;    # initially how far to go

    my $lon  = ${$rp}{'lon'};
    my $lat  = ${$rp}{'lat'};
    my $tlat  = ${$rch}{'target_lat'};
    my $tlon  = ${$rch}{'target_lon'};
    my ($az1,$az2);
    fg_geo_inverse_wgs_84($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
    # display a turn commencing
    my $gspd = ${$rp}{'gspd'}; # Knots
    my $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
    ${$rch}{'change_oount'} = 0;    # no change direction yet
    # display stuff
    # $ptset = ${$rch}{'targ_ptset'}; # get active point set
    my $eta = " ETA:".secs_HHMMSS2($secs); # display as hh:mm:ss
    my $diff = get_hdg_diff($chdg,$shdg);
    set_decimal1_stg(\$diff);
    set_hdg_stg(\$chdg);
    set_hdg_stg(\$shdg);
    prtt("TURN from $chdg to $shdg ($diff) degs, to targ... $eta\n");
}

# $circuit_mode is ON
# $mag_deviation = ($curr_hdg - $curr_mag);
# ref position hash
sub process_circuit($) {
    my ($rp) = @_;
    my $rch = $ref_circuit_hash;
    return if (!defined ${$rp}{'time'});
    my $ctm = lu_get_hhmmss_UTC(${$rp}{'time'});
    my $bgn_turn = 500; # meters BEFORE target, commence turn - should be a function of degrees to turn to next
    my $secs = -1;
    my $eta = '';
    my ($lon,$lat,$alt,$hdg,$agl,$hb,$mag,$aspd,$gspd,$cpos,$msg);
    my ($az1,$az2,$dist);
    my $ptset = ${$rch}{'targ_ptset'};   # current chosen point TR,BR,BL,TL
    if (!defined $ptset) {
        $ptset = 'none';
    }
    # extract current POSIIION values
    $lon  = ${$rp}{'lon'};
    $lat  = ${$rp}{'lat'};
    $alt  = ${$rp}{'alt'};
    $hdg  = ${$rp}{'hdg'};
    $agl  = ${$rp}{'agl'};
    $hb   = ${$rp}{'bug'};
    $mag  = ${$rp}{'mag'};  # /orientation/heading-magnetic-deg
    $aspd = ${$rp}{'aspd'}; # Knots
    $gspd = ${$rp}{'gspd'}; # Knots
    if ($circuit_mode && $circuit_flag) {
        if (!defined ${$rch}{'target_lat'} || !defined ${$rch}{'target_lon'}) {
            pgm_exit(1,"ERROR: target_lat, lon NOT defined?\n");
        }
        my $tlat  = ${$rch}{'target_lat'};
        my $tlon  = ${$rch}{'target_lon'};
        fg_geo_inverse_wgs_84($lat,$lon,$tlat,$tlon,\$az1,\$az2,\$dist);
        $secs = int(( $dist / (($gspd * $SG_NM_TO_METER) / 3600)) + 0.5);
        my $psecs = ${$rch}{'target_secs'};
        ${$rch}{'target_secs'} = $secs;
        my $trend = '=';
        if ($secs < $psecs) {
            $trend = '-';
        } elsif ($psecs > $secs) {
            $trend = "++";
        }
        ${$rch}{'target_eta'} = "ETA:".secs_HHMMSS2($secs).$trend; # display as hh:mm:ss
    }

    if ($circuit_flag == 0) {
        choose_first_target($rch,$rp);
        $circuit_flag = 1;
        # set intital course to target
        fgfs_set_hdg_bug(${$rch}{'target_hdg'});
    }

    if ($circuit_flag) {
        if ($m_stable_cnt > 1) {  # less than 2 degrees between previous ind hdg
            if (${$rch}{'suggest_chg'}) {
                if (${$rch}{'target_secs'} < 20) {
                    # only 20 secs to target - choose next target
                    my ($ntlat,$ntlon);
                    my $ptset = ${$rch}{'targ_ptset'};  # passing this target, head for next
                    ##my $nxt_ps = get_next_pointset($rch,$ptset,\$ntlat,\$ntlon,0);
                    set_next_in_circuit_targ($rch,$lat,$lon,$ptset);
                    fgfs_set_hdg_bug(${$rch}{'target_hdg'});

                } else {
                    set_suggested_hdg($rch,$rp);
                    return;
                }
            }
        }
    }

}


sub main_loop() {

    prtt("Get 'sim' information...\n");
    show_sim_info(fgfs_get_sim_info());
    prtt("Get Fuel - comsumables...\n");
    show_consumables(fgfs_get_consumables());
    prtt("Getting current environment...\n");
    show_environ(fgfs_get_environ());
    prtt("Getting current COMMS...\n");
    show_comms(fgfs_get_comms());

    # ### FOREVER - NOTHING happens without an ENGINE ###
    if ( wait_for_engine() ) {
       return 1;
    }

    # we have ENGINES!!!
    if ( wait_for_alt_hold() ) {
        return 1;
    }
    my $ok = 1;
    my ($char,$val,$rp);
    while ($ok) {
        $rp = fgfs_get_position();
        show_position($rp);
        if ( got_keyboard(\$char) ) {
            $val = ord($char);
            if (($val == 27)||($char eq 'q')) {
                prtt("Quit key... Exiting...\n");
                $ok = 0;
                return 0;
            } elsif ($char eq 'c') {
                prtt("Set CIRCUIT mode\n");
                $circuit_mode = 1;
                $circuit_flag = 0;
                $chk_turn_done = 0;
                process_circuit($rp);
            } elsif ($char eq 'C') {
                prtt("Clear CIRCUIT mode\n");
                $circuit_mode = 0;
                $circuit_flag = 0;
                $chk_turn_done = 0;
            }
        }
        process_circuit($rp) if ($circuit_mode);
    }
}

#########################################
### MAIN ###
parse_args(@ARGV);
process_in_file($in_file);
wait_fgio_avail();
main_loop();
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
}

# eof - template.pl
