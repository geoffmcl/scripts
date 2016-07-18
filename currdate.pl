#!/usr/bin/perl
#< currdate.pl - 20160718
use strict;
use warnings;

# output YYYYMMDD string... nothing more...
sub get_YYYYMMDD($) {
    my ($t) = shift;
    my @f = (localtime($t))[0..5];
    my $m = sprintf( "%04d%02d%02d",
        $f[5] + 1900, $f[4] + 1, $f[3]);
    return $m;
}

print get_YYYYMMDD(time())."\n";

# eof
