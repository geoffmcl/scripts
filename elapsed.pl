#!/perl -w
# NAME: elapsed.pl
# AIM: Take two time parameters, like 14:21:03.48 14:23:36.65,
# and display the difference ...
# 13/08/2015 - Add to scripts repo...
# 17/11/2009 - If negative, assume next day. Not accurate, but better
# 15/05/2007 - geoff mclane - http://geoffmclane.com/mperl.index.htm
use strict;
use warnings;

my $tm_start = '14:21:03.48';
my $tm_end   = '14:23:36.65';

parse_args( @ARGV );

my $bgn_secs = get_seconds( $tm_start );
my $end_secs = get_seconds( $tm_end   );
# 17/11/2009 - if negative, assume 1 day has passed.
# Not necessarily accurate, but better
if ($bgn_secs > $end_secs) {
   $end_secs += (24 * 60 * 60);
   print "Assumed the next day...\n";
}
my $hms = secs2hms($end_secs - $bgn_secs);
my $secs = int((($end_secs - $bgn_secs) + 0.005) * 100) / 100;

print( "Difference $secs seconds, or $hms ...\n" );

exit(0);

sub parse_args {
	my (@av) = @_;
	my $acnt = 0;
	while (@av) {
		if ($acnt == 0) {
			$tm_start = $av[0];
			$acnt++;
		} elsif ($acnt == 1) {
			$tm_end = $av[0];
			$acnt++;
		} else {
			die( "ERROR: Too many arguments ...\n" );
		}
		shift @av;
	}
	if ($acnt != 2) {
		die( "Useage: Begin-Time End-Time, in hh:mm:ss form ...\n" );
	}
}

sub get_seconds {
	my ($tm) = shift;
	my @arr = split(':', $tm);
	my $rsecs = 0;
	if (scalar @arr == 3) {
		$rsecs = $arr[0] * 60 * 60;
		$rsecs += $arr[1] * 60;
		$rsecs += $arr[2];
	} else {
		print( "ERROR: TIme did NOT split correctly ...Expect hh:mm:secs ... got [$tm] ...\n" );
	}
	return $rsecs;
}

sub secs2hms {
	my ($s) = shift;
	my $h = int($s / (60 * 60));
	$s -= $h * 60 * 60;
	my $m = int($s / 60);
	$s -= $m * 60;
	my $ret = '';
	if ($h < 10) {
		$ret = "0$h";
	} else {
		$ret = "$h";
	}
	$ret .= ':';
	if ($m < 10) {
		$ret .= "0$m";
	} else {
		$ret .= "$m";
	}
	$ret .= ':';
	$s = int(($s + 0.005) * 100) / 100;
	if ($s < 10) {
		$ret .= "0$s";
	} else {
		$ret .= "$s";
	}
	return $ret;
}

# eof - elapsed.pl

