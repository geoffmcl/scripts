#!/usr/bin/perl -w
# NAME: xg2kml.pl
# AIM: Convet an xg, or csv, to a kml fil.. input must be one continuous stream,
# from the start of the journey to the end, giving at least lat,lon,alt_ft
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
use XML::Simple;
use Data::Dumper;
use Math::Trig;
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'fg_wsg84.pl' or die "Unable to load fg_wsg84.pl ...\n";

# log file stuff
our ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
$outfile = ($os =~ /win/i) ? path_u2d($outfile) : path_d2u($outfile);
open_log($outfile);

# user variables
my $VERS = "0.0.6 2016-04-21";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = $temp_dir."/tempxg2kml.kml";
my $out_csv = '';
my $wpt_htz = 1;
my $wpt_set = 10;   # only add each 10th wpt
my $add_placemarks = 1;
my $open_wpts = 0;

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'F:\FGx\fgx.github.io\sandbox\flightpath\LEIG-L1500-cooked-01.csv';

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

sub is_decimal($) {
    my $num = shift;
    return 1 if ($num =~ /^[-+]?[0-9]*\.?[0-9]+$/);
    return 0;
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

sub sample_placemark_kml() {
    my $txt = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Placemark>
    <name>Simple placemark</name>
    <description>Attached to the ground. Intelligently places itself 
       at the height of the underlying terrain.</description>
    <Point>
      <coordinates>-122.0822035425683,37.42228990140251,0</coordinates>
    </Point>
  </Placemark>
</kml>
EOF
    return $txt;
}

sub sample_fgracker_kml() {
    my $txt = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
	<name>FGFS Flight #6588208</name>
	<open>1</open>
	<Style id="Arrival">
      <IconStyle>
        <Icon>
          <href>http://maps.google.com/mapfiles/kml/paddle/A.png</href>
        </Icon>
      </IconStyle>
    </Style>
	<Style id="Departure">
		<IconStyle>
			<Icon>
				<href>http://maps.google.com/mapfiles/kml/paddle/D.png</href>
			</Icon>
		</IconStyle>
    </Style>
	<Style id="Waypoints">
		<IconStyle>
			<Icon>
				<href>http://mpserver15.flightgear.org/modules/fgtracker/icons/reddot.png</href>
			</Icon>
	</IconStyle>
    </Style>
	<Folder>
		<name>Waypoints</name>
		<open>1</open>

		<Placemark>
			<name>#0:2016-04-08 01:25:46+08</name>
			<description>
			Coordinate: 2.217136,41.392792
			Altitude: 1090.81ft
			Speed: - knots</description>
			<styleUrl>#Waypoints</styleUrl>
			<TimeStamp>
				<when>2016-04-08T01:25:46+08</when>
			</TimeStamp>
			<Point>
				<coordinates>2.217136,41.392792,332.48</coordinates>
			</Point>
		</Placemark>
		<Placemark>
			<name>#1:2016-04-08 01:25:56+08</name>
			<description>
			Coordinate: 2.22055,41.396891
			Altitude: 1090.82ft
			Speed: 105 knots</description>
			<styleUrl>#Waypoints</styleUrl>
			<TimeStamp>
				<when>2016-04-08T01:25:56+08</when>
			</TimeStamp>
			<Point>
				<coordinates>2.22055,41.396891,332.48</coordinates>
			</Point>
		</Placemark>
	</Folder>
	<Placemark>
		<name>Migration path</name>
		<Style>
			<LineStyle>
			<color>ff0000ff</color>
			<width>2</width>
			</LineStyle>
		</Style>
		<LineString>
			<tessellate>1</tessellate>
			<altitudeMode>absolute</altitudeMode>
			<coordinates>
			2.217136,41.392792,332.48 2.22055,41.396891,332.48 2.223958,41.400983,332.48 ...
			</coordinates>
		</LineString>
	</Placemark>
  	<Placemark> 
		<name>Departure</name> 
		<styleUrl>#Departure</styleUrl>
		<Point>
		  <coordinates>2.217136,41.392792,332.48</coordinates>
		</Point> 
	</Placemark>
	<Placemark> 
		<name>Arrival</name> 
		<styleUrl>#Arrival</styleUrl>
		<Point>
		  <coordinates>1.652598,41.58608,336.01</coordinates>
		</Point> 
	</Placemark>
</Document>
</kml>
EOF
    return $txt;
}

sub get_kml_head() {
    my $txt = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
EOF
    return $txt;
}

sub get_kml_tail() {
    my $txt = <<EOF;
</kml>
EOF
    return $txt;
}

sub get_fgt_head() {
    my $txt = <<EOF;
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
<Document>
	<name>FGFS Flight #6588208</name>
	<open>1</open>
	<Style id="Arrival">
      <IconStyle>
        <Icon>
          <href>http://maps.google.com/mapfiles/kml/paddle/A.png</href>
        </Icon>
      </IconStyle>
    </Style>
	<Style id="Departure">
		<IconStyle>
			<Icon>
				<href>http://maps.google.com/mapfiles/kml/paddle/D.png</href>
			</Icon>
		</IconStyle>
    </Style>
	<Style id="Waypoints">
		<IconStyle>
			<Icon>
				<href>http://mpserver15.flightgear.org/modules/fgtracker/icons/reddot.png</href>
			</Icon>
	</IconStyle>
    </Style>
	<Folder>
		<name>Waypoints</name>
		<open>$open_wpts</open>

EOF
    return $txt;
}

sub get_fgt_tail() {
    my $txt = <<EOF;
	</Folder>
</Document>
</kml>
EOF
    return $txt;
}

sub get_fgt_tail2($$$$$$$) {
    my ($list,$lon1,$lat1,$alt1,$lon2,$lat2,$alt2) = @_;
    my $txt = <<EOF;
	</Folder>
	<Placemark>
		<name>Migration path</name>
		<Style>
			<LineStyle>
			<color>ff0000ff</color>
			<width>2</width>
			</LineStyle>
		</Style>
		<LineString>
			<tessellate>1</tessellate>
			<altitudeMode>absolute</altitudeMode>
			<coordinates>
			$list
			</coordinates>
		</LineString>
	</Placemark>
  	<Placemark> 
		<name>Departure</name> 
		<styleUrl>#Departure</styleUrl>
		<Point>
		  <coordinates>$lon1,$lat1,$alt1</coordinates>
		</Point> 
	</Placemark>
	<Placemark> 
		<name>Arrival</name> 
		<styleUrl>#Arrival</styleUrl>
		<Point>
		  <coordinates>$lon2,$lat2,$alt2</coordinates>
		</Point> 
	</Placemark>
</Document>
</kml>
EOF
    return $txt;
}


sub get_placemark($$$$$) {
    my ($lon,$lat,$alt,$nm,$desc) = @_;
    my $pm = <<EOF;
		<Placemark>
            <name>$nm</name>
            <description>$desc</description>
			<styleUrl>#Waypoints</styleUrl>
            <Point>
                <coordinates>$lon,$lat,$alt</coordinates>
            </Point>
        </Placemark>
EOF
    return $pm;
}

# Speed: 105 knots</description>
sub get_description($$$) {
    my ($lon,$lat,$alt) = @_;
    my $desc = <<EOF;

			Coordinate: $lon,$lat
			Altitude: $alt ft
EOF
    return $desc;
}

sub process_waypoints($) {
    my $rwpts = shift;
    my $len = scalar @{$rwpts};
    if ($len < 3) {
        prt("Found only $len waypoints...\n");
        return;
    }
    my ($ra,$lat1,$lon1,$lat2,$lon2,$res,$s,$dist,$time,$az1,$az2);
    my ($alt1,$alt2,$altm,$nm,$desc);
    my $diff = 1 / $wpt_htz;
    $len = 0;
    $dist = 0;

    $time = 0;
    foreach $ra (@{$rwpts}) {
        $lon2 = ${$ra}[0];
        $lat2 = ${$ra}[1];
        if ($len > 0) {
            $res = fg_geo_inverse_wgs_84($lat1, $lon1, $lat2, $lon2, \$az1, \$az2, \$s);
            $dist += $s;
            $time += $diff;
        }
        $len++;
        $lon1 = $lon2;
        $lat1 = $lat2;
    }
    my $Nms = meter_2_nm($dist);
    my $ddist = int($Nms)." nm";
    my $dtime = secs_HHMMSS($time);
    prt("Found $len waypoints... dist=$ddist, time=$dtime secs\n");
    my $csv = '';
    my $kml = '';
    my $wpts = '';
    my $list = '';
    my $wrap = 0;   # $wpt_set
    $len = 0;
    foreach $ra (@{$rwpts}) {
        $lon1 = ${$ra}[0];
        $lat1 = ${$ra}[1];
        $alt1 = ${$ra}[2];
        $altm = feet_2_meter($alt1);
        $csv .= "$lon1,$lat1,$alt1\n";

        if ($wrap == 0) {
            $len++;
            $nm = "#$len:";
            $desc = get_description($lon1,$lat1,$alt1);
            chomp $desc;
            $wpts .= get_placemark($lon1,$lat1,$altm,$nm,$desc);
            $list .= "$lon1,$lat1,$altm ";
        }

        if ($wpt_set > 0) {
            $wrap++;
            if ($wrap > $wpt_set) {
                $wrap = 0;
            }
        }

    }
    # get beginning
    $ra = ${$rwpts}[0];
    $lon1 = ${$ra}[0];
    $lat1 = ${$ra}[1];
    $alt1 = feet_2_meter(${$ra}[2]);
    # get ending
    $ra = ${$rwpts}[-1];
    $lon2 = ${$ra}[0];
    $lat2 = ${$ra}[1];
    $alt2 = feet_2_meter(${$ra}[2]);
    if ($wrap) {
        $len++;
        $nm = "#$len:";
        $desc = get_description($lon2,$lat2,$alt2);
        chomp $desc;
        $wpts .= get_placemark($lon2,$lat2,$alt2,$nm,$desc);
        $list .= "$lon2,$lat2,$alt2 ";
    }

    if (length($out_file)) {
        #$kml = get_kml_head().$kml.get_kml_tail();
        #$kml = get_fgt_head().$kml.get_fgt_tail();
        if ($add_placemarks) {
            $kml = get_fgt_head().$wpts.get_fgt_tail2($list,$lon1,$lat1,$alt1,$lon2,$lat2,$alt2);
        } else {
            $kml = get_fgt_head().get_fgt_tail2($list,$lon1,$lat1,$alt1,$lon2,$lat2,$alt2);
        }
        write2file($kml,$out_file);
        prt("KML output written to '$out_file'\n");
    } else {
        prt("No -o output file name given...\n");
    }
    if (length($out_csv)) {
        write2file($csv,$out_csv);
        prt("CSV output written to '$out_csv'\n");
    } else {
        #prt($csv);
        prt("No -o cvs output file name given...\n");
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
    my ($i,$line,$ra,$lnn,$len,@arr,$cnt,$lat,$lon,$alt);
    $lnn = 0;
    my @wpts = ();
    for ($i = 0; $i < $lncnt; $i++) {
        $lnn = $i + 1;
        $line = $lines[$i];
        chomp $line;
        $line = trim_all($line);
        $len = length($line);
        next if ($len == 0);
        $line =~ s/,/ /g;
        @arr = space_split($line);
        $cnt = scalar @arr;
        if (($cnt >= 3) && is_decimal($arr[0]) && is_decimal($arr[1]) && is_decimal($arr[2])) {
            $lon = $arr[0];
            $lat = $arr[1];
            $alt = $arr[2]; # this could be feet
            if (m_in_world_range($lat,$lon)) {
                push(@wpts, [$lon,$lat,$alt]);
            } else {
                prtw("WARNING:$lnn: lat/lon $lat $lon NOT in WORLD!\n");
            }
        } elsif ($line =~ /^\#/) {
            # comment line
        } elsif ($line =~ /^color/i ) {
            # color line
        } elsif ($line =~ /^anno/i ) {
            # annotation line
        } elsif ($line =~ /^NEXT/i ) {
            # end of segment
        } else {
            if ($i) {
                pgm_exit(1,"$lnn: Unknown line [$line]! *** FIX ME ***\n");
            } else {
                # if csv, skip first line
            }
        }
    }

    process_waypoints(\@wpts);
}

sub process_in_file_text($) {
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
                prt("Set KML out file to [$out_file].\n") if ($verb);
            } elsif ($sarg =~ /^c/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_csv = $sarg;
                prt("Set CSV out file to [$out_csv].\n") if ($verb);
            } elsif ($sarg =~ /^f/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if ($sarg =~ /^\d+$/) {
                    $wpt_set = $sarg;
                    prt("Set wpt set to [$wpt_set].\n") if ($verb);
                } else {
                    pgm_exit(1,"ERROR: Expected an integer to follow -f! Got $sarg?\n");
                }
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
        pgm_exit(1,"ERROR: No input files found in command!\n");
    }
    if (! -f $in_file) {
        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
    }
}

sub give_help {
    prt("\n");
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-file\n");
    prt("\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. (def=$verbosity)\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>  (-o) = Write output to this file. (def=$out_file)\n");
    prt(" --freq int    (-f) = Sample the input csv/xg at this interval. 0=all. (def=$wpt_set)\n");
    prt(" --csv <file>  (-c) = Also output a CSV files. (def=none)\n");
    prt("\n");
    prt(" Given a suitable csv/xg input file write a Google Earth KML file. Here suitable\n");
    prt(" really means only one list of continuous points given, with at least lon,lat,alt-ft.\n");
    prt("\n");
}

# eof - xg2kml.pl
