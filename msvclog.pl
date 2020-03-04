#!/usr/bin/perl -w
# NAME: msvclog.pl
# AIM: Read a MSVC build log output, and report success and failed projects
# 2020-03-04 - Accept 'CPack: ...' messages...
# 2018-06-22 - Accept cmake out message(STATUS "messages...") better, before 'Configuring done' 
# 2018-05-21 - Add show of 'error' lines
# 2018-04-12 - Show 'begin' line if date or time...
# 2018-02-28 - Skip ComputeCustomBuildOutput:
# 2018-01-24 - Skip some MSVC15 2017 output
# 2017-12-09 - Always collect and show compile warnings DISABLED
# 2017-10-13 - Show compile and link flags
# 2017-10-02 - Cover some more 'exceptions'
# 2016-11-04 - Quieten the output, unless -v(\n+)
# 2016-10-20 - Deal with CMake policy warnings
# 2016-10-18 - Try to pickup on Debug or Release or ---
# 07/05/2016 - Show project name with warning/error
# 13/01/2016 - Show each warning count, to add to CMakeLists.txt...
# 01/01/2016 - Add a clean build message
# 20/10/2015 - Deal with fatal error on link line
# 21/09/2015 - Reduce, simplify output
# 24/09/2014 - default to defacto standard log, bldlog-1.txt, if it exists
# 21/07/2014 - Skip ZERO_CHECK and ALL_BUILD projects.
# 20/07/2013 geoff mclane http://geoffair.net/mperl
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use Cwd;
my $os = $^O;
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "/temp";
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
# log file stuff
our ($LF);
my $outfile = $temp_dir."/temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.1.1 2018-06-22";  # move to 'scripts'...
##my $VERS = "0.1.0 2018-05-21";
##my $VERS = "0.0.9 2018-01-24";
##my $VERS = "0.0.8 2017-10-13";
##my $VERS = "0.0.7 2017-10-02";
##my $VERS = "0.0.6 2016-11-04";
##my $VERS = "0.0.5 2016-05-07";
##my $VERS = "0.0.4 2016-01-01";
##my $VERS = "0.0.3 2015-09-21";
##my $VERS = "0.0.2 2014-07-21";
##my $VERS = "0.0.1 2013-07-20";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';
my $skip_zero_all = 0;
my $show_warnings = 1;
my $show_errors = 1;
my $show_fatal = 1;
my $show_duplicate_projects = 0;
my $show_cmake_mess = 0;
my $show_compile_flags = 0;

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'F:\Projects\mozjs-24.2.0\js\src\msvc\bldlog-1.txt';
###my $def_file = 'C:\FG\18\build-sdl2\bldlog-1.txt';

### program variables
my @warnings = ();
my $cwd = cwd();
my $skipped_cmake_mess = 0;
my $curr_proj = 'N/A';
my $curr_conf = 'N/A';
my $curr_out = '';
# /wd4244 /wd4305 /wd4477 /wd4996 /wd4005 /wd4273 /wd4267 /wd4474
my %warn_disabled = ();
my %flags_seen = ();
my $had_end_cmake = 0;

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

# file lines - cmake header

#-- Configuring done
#-- Generating done
#-- Build files have been written to: C:/FG/18/build-sdl2
#
#Microsoft (R) Visual Studio Version 10.0.40219.1.
#Copyright (C) Microsoft Corp. All rights reserved.
#------ Build started: Project: ZERO_CHECK, Configuration: Debug Win32 ------
#Build started 20/07/2013 16:00:33.
#InitializeBuildStatus:
#  Creating "Win32\Debug\ZERO_CHECK\ZERO_CHECK.unsuccessfulbuild" because "AlwaysCreate" was specified.
#FinalizeBuildStatus:
#  Deleting file "Win32\Debug\ZERO_CHECK\ZERO_CHECK.unsuccessfulbuild".
#  Touching "Win32\Debug\ZERO_CHECK\ZERO_CHECK.lastbuildstate".
#
#Build succeeded.
#
#Time Elapsed 00:00:00.06

#Time Elapsed 00:00:00.39
#------ Build started: Project: ALL_BUILD, Configuration: Debug Win32 ------
#Build started 20/07/2013 16:01:02.
#InitializeBuildStatus:
#  Creating "Win32\Debug\ALL_BUILD\ALL_BUILD.unsuccessfulbuild" because "AlwaysCreate" was specified.
#CustomBuild:
#  Build all projects
#FinalizeBuildStatus:
#  Deleting file "Win32\Debug\ALL_BUILD\ALL_BUILD.unsuccessfulbuild".
#  Touching "Win32\Debug\ALL_BUILD\ALL_BUILD.lastbuildstate".
#
#Build succeeded.
#
#Time Elapsed 00:00:00.26
#========== Build: 47 succeeded, 21 failed, 0 up-to-date, 0 skipped ==========
my $act_file = '';
my $act_include = '';

sub trim_leading_path($) {
    my $line = shift;
    my $len = length($line);
    my ($i,$ch,$hadsp);
    $hadsp = 0;
    my $nline = '';
    my $file = '';

    for ($i = 0; $i < $len; $i++) {
        $ch = substr($line,$i,1);
        if (!$hadsp) {
            $file .= $ch;
            # if ($ch =~ /\s/) {
            if (($ch eq ':')&&($i > 1)) {
                $hadsp = 1;
            } else {
                if (($ch eq '/')||($ch eq '\\')) {
                    $nline = '';
                    $ch = '';
                }
            }
        }
        $nline .= $ch;
    }
    $file =~ s/\(\d+\):$//;
    $act_file = $file;
    # Cannot open include file: 'idn/res.h':
    $act_include = '';
    if ($nline =~ /Cannot open include file: '(.+)': /) {
        $act_include = $1;
    }
    return $nline;
}


sub strip_trailing_vcxproj($) {
    my $line = shift;
    my $len = length($line);
    my ($ch,$i);
    my $open = 0;
    my $close = 0;
    for ($i = 0; $i < $len; $i++) {
        $ch = substr($line,$i,1);
        if ($ch eq ']') {
            $close = $i + 1;
        } elsif ($ch eq '[') {
            $open = $i;
        }
    }
    if (($open && $close)&&($open < $close)) {
        $line = substr($line,0,$open);
    }
    return $line;
}

sub get_trim_fatal($) {
    my $line = shift;
    $line = strip_trailing_vcxproj($line);
    $line = trim_leading_path($line);
    #$line =~ s/\s+\(\?.+\)\s*$//;
    return $line;
}

sub get_trim_error($) {
    my $line = shift;
    $line = strip_trailing_vcxproj($line);
    $line = trim_leading_path($line);
    my ($ch);
    $ch = index($line," referenced in ");
    if ($ch > 0) {
        $line = substr($line,0,$ch);
    }
    $line =~ s/\s+\(\?.+\)\s*$//;
    return $line;
}

sub get_trim_warn($) {
    my $line = shift;
    $line = strip_trailing_vcxproj($line);
    $line = trim_leading_path($line);
    return $line;
}

sub mycmp_decend_n0 {
   return 1 if (${$a}[0] < ${$b}[0]);
   return -1 if (${$a}[0] > ${$b}[0]);
   return 0;
}

# /wd4244 /wd4305 /wd4477 /wd4996 /wd4005 /wd4273 /wd4267 /wd4474
# my %warn_disabled = ();
sub get_wd_flags($) {
    my ($txt) = @_;
    my @arr = space_split($txt);
    my $len = scalar @arr;
    my ($i,$tmp,$val);
    for ($i = 0; $i < $len; $i++) {
        $tmp = $arr[$i];
        if ($tmp =~ /^\/wd(\d+)$/) {
            $val = $1;
            if (defined $warn_disabled{$val}) {
                $warn_disabled{$val}++;
            } else {
                $warn_disabled{$val} = 1;
            }
        }
    }
}

sub show_flags($$) {
    my ($txt,$tool) = @_;
    my @arr = space_split($txt);
    my $msg = '';
    my $max_len = 100;
    my ($tmp,$len,$i,$len2,$lenm,$flag);
    $len = scalar @arr;
    prt("\n$tool Flags - $len items... Proj $curr_proj... Conf $curr_conf\n") if ($len);
    for ($i = 0; $i < $len; $i++) {
        $tmp = $arr[$i];
        if ($tmp eq '/D') {
            $i++;
            if ($i < $len) {
                $flag = $arr[$i];
                $tmp .= " $flag";
            } 
        }
        if (defined $flags_seen{$tmp}) {
            $flags_seen{$tmp}++;
        } else {
            $flags_seen{$tmp} = 1;
        }
        $lenm = length($msg);
        $len2 = length($tmp);
        if ($lenm) {
            if (($lenm + $len2) > $max_len) {
                prt("$msg\n");
                $msg = '';
            }
        }
        $msg .= ' ' if (length($msg));
        $msg .= $tmp;
    }
    prt("$msg\n") if (length($msg));
}

sub get_proj_conf($) {
    my $txt = shift;
    my @arr = space_split($txt);
    my $np = '';
    my $nc = '';
    $txt = strip_double_quotes($arr[0]);
    @arr = split(/(\\|\/)/,$txt);
    my ($tmp);
    foreach $tmp (@arr) {
        if ($tmp =~ /^Debug$/i) {
            $nc = "Debug";
        } elsif ($tmp =~ /^Release$/i) {
            $nc = "Release";
        } elsif ($tmp =~ /^RelWithDebInfo$/i) {
            $nc = "RelWithDebInfo";
        } elsif ($tmp =~ /^MinSizeRel$/i) {
            $nc = "MinSizeRel";
        } elsif ($tmp =~ /^(.+)\.tlog$/) {
            $np = $1;
        }
    }
    return ($np,$nc);
}

sub process_in_file($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    prt("Processing $lncnt lines, from [$inf]...\n") if (VERB9()); # 2016-11-04
    my ($i,$line,$inc,$lnn,$tline,$len,$dncmake,$had_blank);
    my ($hour,$mins,$secs,$tsecs,$time,$csecs,$ok,@arr,$trline,$ra);
    my ($hadprj,$hadtm,$hadbld,$nproj,$nconf,$show,$msg,$cnt,$val,$cmd1,$size);
    $lnn = 0;
    $dncmake = 0;
    $had_blank = 0;
    $csecs = 0;
    $ok = '';
    @arr = ();
    my %h = (); # store ALL in this project
    $hadprj = 0;
    $hadtm = 0;
    $hadbld = 0;
    my @warns = ();
    my @error = ();
    my @fatal = ();
    my @projs = (); # list of projects per configuration
    my @cmwarns = (); # like 'CMake Warning (dev) in CMakeLists.txt:'
    my %projects = ();
    my %warn_lines = ();
    my %error_lines = ();
    my %fatal_lines = ();
    my %warnvalues = ();
    my %errorvalues = ();
    my %fatalvalues = ();
    my %shown_files = ();
    my %linkwarn = ();
    my %linkerror = ();
    my %linkfatal = ();
    my %missing_files = ();
    my %proj_srcs = ();
    my %cmakewarn = ();
    my $fatalcnt = 0;
    my $errorcnt = 0;
    my $warningcnt = 0;
    my $cmakewcnt = 0;
    my $cmakeecnt = 0;
    my @lnarr = ();
    my $comp_file = '';
    my $incomptarg = 0;
    my $projcnt = 0;
    my ($pname1,$pdir,$pext);
    my ($line1,$j,$tmp);
    my $curr_wcnt = 0;
    my $curr_ecnt = 0;
    my $linklin = '';
    # process the file lines...
    for ($i = 0; $i < $lncnt; $i++) {
        $line = $lines[$i];
        chomp $line;
        $lnn = $i + 1;
        $tline = trim_all($line);
        $len = length($tline);
        if ($len == 0) {
            $had_blank = 1;
            next;
        }
        ### prt("$lnn: $line\n");
        # Project "F:\Projects\mozjs-24.2.0\js\src\msvc\ALL_BUILD.vcxproj" on node 1 (default targets).
        # Project "F:\Projects\mozjs-24.2.0\js\src\msvc\ALL_BUILD.vcxproj" (1) is building "F:\Projects\mozjs-24.2.0\js\src\msvc\ZERO_CHECK.vcxproj" (2) on node 1 (default targets).
        # and
        # Done Building Project "F:\Projects\mozjs-24.2.0\js\src\msvc\ZERO_CHECK.vcxproj" (default targets).
        # drop some lines
        if ($line =~ /^The\s+target\s+\"(\w+)\"\s+listed\s+in\s+(a|an)\s+/) {
            next;
        #} elsif ($line =~ /^InitializeBuildStatus:$/) {
        #    next;
        } elsif ($line =~ /^FinalizeBuildStatus:$/) {
            next;
        #} elsif ($line =~ /^CustomBuild:$/) {
        #    next;  # see later
        } elsif ($line =~ /^\s+All\s+outputs\s+are\s+up-to-date.$/) {
            next;
        } elsif ($line =~ /^--\s+/) {
            # End of cmake config and gen phases
            # -- Configuring done
            # -- Generating done
            # -- Build files have been written to: Z:/build-netcdf.x64
            if ($tline =~ /^--\s+Configuring\s+done$/) {
                $had_end_cmake = 1; #near end of cmake conf & gen
            }
            if ($show_cmake_mess) {
                # -- Configuring incomplete, errors occurred!
                prt("$lnn: $line\n");
            } else {
                $skipped_cmake_mess++;
            }
            # cmake status outputs, like 
            # 6: UNPARSED '-- *** Option BUILD_SHARED_LIB is OFF STATIC'
            # 7: UNPARSED '-- === Set language bindings to C;CXX;HL;TOOLS'
            next;
        } elsif ($line =~ /^Microsoft\s+\(R\)\s+/) {
            # 279: UNPARSED 'Microsoft (R) Build Engine version 14.0.25420.1'
            next;
        } elsif ($line =~ /^Copyright\s+\(C\)/ ) {
            # 280: UNPARSED 'Copyright (C) Microsoft Corporation. All rights reserved.'
            next
        } elsif ($line =~ /^\[Microsoft\s+/) {
            # '[Microsoft .NET Framework, version 4.0.30319.34209]'
            next;
        } elsif ($line =~ /^\s+Compiling\.\.\.$/) {
            # '  Compiling...'
            next;
        } elsif ($line =~ /^\s*CPack:/) {
            # like '32:WARNING: UNPARSED '  CPack: Create package using ZIP''
            next;
        }
        @lnarr = space_split($tline);
        $size = scalar @lnarr;
        $cmd1 = $lnarr[0];
        if ($cmd1 eq 'Project') {
            # Project "F:\Projects\gshhg\build\ALL_BUILD.vcxproj" on node 1 (default targets).
            # Project "F:\Projects\gshhg\build\ALL_BUILD.vcxproj" (1) is building "F:\Projects\gshhg\build\ZERO_CHECK.vcxproj" (2) on node 1 (default targets).
            if ($size > 1) {
                $nproj = strip_double_quotes($lnarr[1]);
                ($pname1,$pdir,$pext) = fileparse($nproj, qr/\.[^.]*/ );
                ### next if ($pname1 eq 'INSTALL');
            }
            if ($tline =~ /\s+is\s+building\s+\"(.+)\"/) {
                $nproj = $1;
                my ($n,$d,$e) = fileparse($nproj, qr/\.[^.]*/ );
                # pgm_exit(1,"TEMP EXIT '$nproj'\n");
                my $proj = $n;
                if (($proj ne 'ZERO_CHECK')&&($proj ne 'ALL_BUILD')) {
                    if (defined $projects{$proj}) {
                        if ($show_duplicate_projects) {
                            my $flnn = $projects{$proj};
                            $line1 = $lines[$flnn];
                            $flnn++;
                            prtw("WARNING: Repeated project name $proj\n".
                                "$lnn: $tline\n".
                                "First:$flnn $line1\n");
                        }
                    } else {
                        $projects{$proj} = $lnn - 1;
                    }
                    prt("$lnn: Project: $proj $curr_conf\n") if (VERB1());
                    $projcnt++;
                    push(@projs,$proj);
                }
            }
            next;
        } elsif ($cmd1 eq 'Done') {
            next;
        } elsif ($cmd1 eq 'Link:') {
            # process a LINK block for project - need includes, and libraries linked
            $linklin = '';
            $tmp = $line;
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ($tmp =~ /^\w/);
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
                if ($tmp =~ /^(.+)link\.exe\s+/) {
                    if ($show_compile_flags) {
                        $tmp =~ s/^(.+)link\.exe\s+//;
                        # prt("Compile:$j: $tmp\n");
                        show_flags($tmp,"Link");
                    }
                }
            }
            #pgm_exit(1,"$lnn: $line\n$linklin\nTEMP EXIT\n");
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'Lib:') {
            # process a LINK block for project - need includes, and libraries linked
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            #pgm_exit(1,"$lnn: $line\n$linklin\nTEMP EXIT\n");
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'PreBuildEvent:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'ManifestResourceCompile:') {
            # 'ManifestResourceCompile:'
            next;
        } elsif ($cmd1 eq 'Manifest:') {
            # 'Manifest:'
            next;
        } elsif ($cmd1 eq 'LinkEmbedManifest:') {
            # 'LinkEmbedManifest:'
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ($tmp =~ /^\w/);
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($line =~ /Configuring\s+incomplete/) {
            # -- Configuring incomplete, errors occurred!
            prt("$lnn: $line\n");
        } elsif ($cmd1 eq 'CMake') {
            # Deal with 'CMake Error...
            if ($line =~ /^CMake\s+Error\s+/) {
                $cmakeecnt++;
                prt("$lnn: $line\n");
            }
            # Deal with CMake policy (dev) warnings
            # CMake Warning (dev) in CMakeLists.txt:
            #  Policy CMP0020 is not set: Automatically link Qt executables to qtmain
            #  target on Windows.  Run "cmake --help-policy CMP0020" for policy details.
            #  Use the cmake_policy command to set the policy and suppress this warning.
            # This warning is for project developers.  Use -Wno-dev to suppress it.
            # 20161115: But his can be preceeded by
            # Call Stack (most recent call first):
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                if ($tmp =~ /^\w/) {
                    if ( !($tmp =~ /^Call\s+Stack\s/) ) {
                        last;
                    }
                }
                $tmp =~ s/^\s+//;
                if ($tmp =~ /Policy\s+CMP(\d+)\s+/) {
                    $val = $1;
                    if (defined $cmakewarn{$val}) {
                        $cmakewarn{$val}++;
                    } else {
                        $cmakewarn{$val} = 1;
                        push(@cmwarns,$trline);
                    }
                    $cmakewcnt++;
                } elsif ($tmp =~ /Configuring\s+incomplete/) {
                    # -- Configuring incomplete, errors occurred!
                    prt("$j: $line\n");
                }
                $linklin .= " $tmp";
            }
            $j--;
            # This warning is for project developers.  Use -Wno-dev to suppress it.
            if ($tmp =~ /^This\s+warning\s+is\s+/) {
                $linklin .= " $tmp";
                $j++;   # and skip this
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j;    # update position
            next;
        ### The following are emitted by MSVC10
        } elsif ($cmd1 eq 'InitializeBuildStatus:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
                # 2017-10-13
                if ($tmp =~ /^Creating\s+/) {
                    $tmp =~ s/^Creating\s+//;
                    $nproj = '';
                    $nconf = '';
                    ($nproj,$nconf) = get_proj_conf($tmp);
                    if (length($nproj) && length($nconf)) {
                        $curr_proj = $nproj;
                        $curr_conf = $nconf;
                    }
                }
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'FinalizeBuildStatus:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                chomp $tmp;
                last if ($tmp =~ /^\w/);
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
                # 2017-10-13
                if ($tmp =~ /^Deleting\s+file\s+/) {
                    $tmp =~ s/^Deleting\s+file\s+//;
                    $nproj = '';
                    $nconf = '';
                    ($nproj,$nconf) = get_proj_conf($tmp);
                    if (length($nproj) && length($nconf)) {
                        $curr_proj = "N/A";
                        $curr_conf = "N/A";
                    }
                }
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'ComputeCustomBuildOutput:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                chomp $tmp;
                last if ($tmp =~ /^\w/);
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'ClCompile:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            %proj_srcs = ();
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                chomp $tmp;
                last if ($tmp =~ /^\w/);
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
                if ($j > $lnn) {
                    if (is_c_source($tmp)) {
                        $proj_srcs{$tmp} = 1;
                    }
                }
                if ($tmp =~ /^(.+)CL\.exe\s+/) {
                    $tmp =~ s/^(.+)CL\.exe\s+//;
                    get_wd_flags($tmp);
                    if ($show_compile_flags) {
                        # prt("Compile:$j: $tmp\n");
                        show_flags($tmp,"Compile");
                    }
                }
            }
            @arr = keys %proj_srcs;
            if (VERB9()) {
                prt("$lnn:$line\n$linklin\n");  # if (VERB9());
                prt("$lnn: Sources: ".join(" ",@arr)."\n") if (@arr);
            } elsif (VERB5()) {
                prt("$lnn: Sources: ".join(" ",@arr)."\n") if (@arr);
            }
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'CustomBuild:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'MakeDirsForCl:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'ResourceCompile:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'PrepareForBuild:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'PostBuildEvent:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            my $had_conf = 0;
            my $uptodate = 0;
            my $installed = 0;
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
                # '  -- Install configuration: "Debug"'
                # '  -- Up-to-date: X:/install/msvc140-64/SimGear/include/simgear/simgear_config.h
                # '  -- Installing: X:/install/msvc140-64/SimGear/lib/cmake/SimGear/SimGearTargets-debug.cmake
                if ($tmp =~ /--\s+Install\s+configuration:\s+/) {
                    prt("$lnn: $tmp\n");
                    $had_conf = 1;
                } elsif ($tmp =~ /--\s+Up-to-date:\s+/) {
                    $uptodate++;
                } elsif ($tmp =~ /--\s+Installing:\s+/) {
                    $installed++;
                }
            }
            if ($had_conf && ($uptodate || $installed)) {
                prt("$lnn: Installed $installed, Up-to-date $uptodate\n");
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        } elsif ($cmd1 eq 'MakeDirsForLink:') {
            # just skip over these command
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
            next;
        }

        if ( ($size == 1) && is_c_source($cmd1) ) {
            $comp_file = $cmd1;
            prt("$lnn: Compile $comp_file\n") if (VERB9());
            next;
        }
        if ($incomptarg) {
            if ($line =~ /^\s*(\d+)\s+Warning\(s\)/) {
                $incomptarg = 0;
                prt("$lnn: Exit ClCompile target\n") if (VERB9());
            } else {
                # 9860 Error(s)
                # Time Elapsed 00:02:11.24
                next;
            }
        } elsif ($line =~ /^\"(.+)\.vcxproj\"\s+\(default\s+target\)/) {
            # could gather some info from the likes of -
            # "F:\Projects\gshhg\build\ALL_BUILD.vcxproj" (default target) (1) ->
            # "F:\Projects\gshhg\build\bmp-1bit.vcxproj" (default target) (7) ->
            # could skip until the next line
            next;
        } elsif ($line =~ /\(ClCompile target\) ->/) {
            $incomptarg = 1;
            prt("$lnn: Entered ClCompile target\n") if (VERB9());
            next;
        } elsif ($line =~ /\(Link target\)\s+->/) {
            next;
        } elsif ($line =~ /\(Lib target\)\s+->/) {
            next;
        } elsif ($line =~ /^Build\s+succeeded\./) {
            next;
        }

        #------ Build started: Project: ZERO_CHECK, Configuration: Debug Win32 ------
        # Oops this ouput has CHANGED - See new stuff above...
        if ($line =~ /------\s+Build\s+started:\s+Project:\s+(.+),\s+Configuration:\s+(.+)\s+------/) {
            $nproj = $1;    # reached the NEXT project
            $nconf = $2;
            if ($hadprj && $hadbld && $hadtm) {
                # time to store the RESULTS
                my %ph = ();
                $ph{'name'} = $curr_proj;
                $ph{'conf'} = $curr_conf;
                $ph{'time'} = $time;
                $ph{'res'}  = $ok;
                $ph{'lines'} = [ @arr ];
                $h{$curr_proj.':'.$curr_conf} = \%ph;
            }
            prt("Proj: $nproj Conf: $nconf\n") if (VERB9());
            $curr_proj = $nproj;
            $curr_conf = $nconf;
            $dncmake = 1;
            @arr = ();
            if (($curr_proj eq 'ZERO_CHECK')||($curr_proj eq 'ALL_BUILD')) {
                $hadprj = 0;
            } else {
                $hadprj = 1;
            }
        } elsif ($line =~ /Time\s+Elapsed\s+(.+)$/) {
            ###########################################
            #### TERMINATION OF 1 OR MORE PROJECTS ####
            ###########################################
            $tmp = scalar @projs;
            if (VERB9()) {
                $tmp = join(", ",@projs);
            }
            prt("$lnn: Conf: $curr_conf $line\n") if (VERB5());
            $time = $1;
            if ($time =~ /(\d{2}):(\d{2}):(\d{2})\.(\d{2})/) {
                $hour  = $1;
                $mins  = $2;
                $secs  = $3;
                $tsecs = $4;
                $time = sprintf("Elapsed %02d:%02d:%02d.%02d", $hour, $mins, $secs, $tsecs);
                $csecs += ($hour * 60 * 60);
                $csecs += ($mins * 60);
                $csecs += $secs;
                $csecs += $tsecs / 100;
                $hadtm = 1;
            } else {
                $time .= " (CHECK)"
            }
            # This is a LAST LINE of a PROJECT:configuration
            # prt("$time Cum $csecs secs\n");
            $show = 1;
            #if ($skip_zero_all) {
            #    $show = 0 if (($proj eq 'ZERO_CHECK')||($proj eq 'ALL_BUILD'));
            #}
            if ($show) {
                $msg = "Proj(s): $tmp Conf: $curr_conf $time Cum $csecs secs $ok";
                if ($show_warnings && @warns) {
                    prt("\n$msg\n") if (length($msg));
                    $msg = '';
                    prt("\n".join("\n",@warns)."\n");
                }
                if ($show_errors && @error) {
                    prt("\n$msg\n") if (length($msg));
                    $msg = '';
                    prt("\n".join("\n",@error)."\n");
                }
                if ($show_fatal && @fatal) {
                    prt("\n$msg\n") if (length($msg));
                    $msg = '';
                    prt("\n".join("\n",@fatal)."\n");
                }
                prt("\n$msg\n") if (length($msg) && VERB1());  # 2016-11-04
            }
            @warns = ();
            @error = ();
            @fatal = ();
            @projs = ();
            ######################################################
        } elsif ($line =~ /==========\s+Build:\s+(\d+)\s+succeeded,\s+(\d+)\s+failed,\s+(\d+)\s+up-to-date,\s+(\d+)\s+skipped\s+==========/) {
        ###    # this is the LAST line of a configuration
        ###    prt("$line\n"); # 2016-10-18 with msvc140 2015 and cmake v.3.5.2 appears NOT emitted
        ############ fatal error #################
        } elsif ($line =~ /:\s+fatal\s+error\s+/) {
            if (! defined $fatal_lines{$line}) {
                $fatalcnt++;
                $fatal_lines{$line} = 1;
                $trline = get_trim_fatal($line);
                prt("$lnn: $trline\n") if (VERB1());
                if ($trline =~ /:\s+fatal\s+error\s+C(\d+):/) {
                    # F:\Projects\bind-9.10.3-P2\lib\isc\win32\include\isc/net.h(81): fatal error C1083: Cannot open include file: 'isc/platform.h': No such file or directory [F:\Projects\bind-9.10.3-P2\build\a_11.vcxproj]
                    $val = $1;
                    if (!defined $fatalvalues{$val}) {
                        $fatalvalues{$val} = 1;
                        if (!defined $shown_files{$act_file}) {
                            $shown_files{$act_file} = 1;
                            push(@fatal,$trline);
                            # push(@fatal,"$act_file $trline");
                        }
                    }
                    if ($val == 1083) {
                        prt("$lnn: $act_file $act_include\n") if (VERB9());
                        $missing_files{$act_include} = [] if (!defined $missing_files{$act_include});
                        $ra = $missing_files{$act_include};
                        push(@{$ra},$act_file);
                        ###prt("$lnn: $trline\n");
                    }
                } elsif ($trline =~ /:\s+fatal\s+error\s+LNK(\d+):/) {
                    $val = $1;
                    if (!defined $linkfatal{$val}) {
                        $linkfatal{$val} = 1;
                        push(@fatal,$trline);
                    }

                } else {
                    pgm_exit(1,"ERROR:$lnn: fatal regex failed [$trline]! ** FIX ME **\nLine:$lnn: '$line'\n");
                    push(@fatal,$trline);
                }
            }
        } elsif ($line =~ /^See\s+also\s+/) {
            # 
        } elsif ($line =~ /:\s+error\s+/) {
            if (! defined $error_lines{$line}) {
                $errorcnt++;
                $error_lines{$line} = 1;
                $trline = get_trim_error($line);
                if ($trline =~ /:\s+error\s+C(\d+):/) {
                    $val = $1;
                    if (!defined $errorvalues{$val}) {
                        $errorvalues{$val} = 1;
                        push(@fatal,$trline);
                        if (!defined $shown_files{$act_file}) {
                            $shown_files{$act_file} = 1;
                            # push(@fatal,"$act_file $trline");
                        }
                    }
                } elsif ($trline =~ /:\s+error\s+LNK(\d+):/) {
                    $val = $1;
                    if (!defined $linkerror{$val}) {
                        $linkerror{$val} = 1;
                        if (VERB1()) {
                            push(@error,"$lnn:$curr_conf: $trline");
                        } else {
                            push(@error,$trline);
                        }
                    }
                } else {
                    pgm_exit(1,"ERROR:$lnn: error regex failed [$trline]! ** FIX ME **\nLine:$lnn: '$line'\n");
                    push(@error,$trline);
                }
            }
            # Deal with multiple lines
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ( !($tmp =~ /^\s/) );
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            #pgm_exit(1,"$lnn: $line\n$linklin\nTEMP EXIT\n");
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
        } elsif ($line =~ /:\s+warning\s+/) {
            if (! defined $warn_lines{$line}) {
                $warningcnt++;
                $warn_lines{$line} = 1;
                $trline = get_trim_warn($line);
                if ($trline =~ /:\s+warning\s+C(\d+):/) {
                    $val = $1;
                    if (defined $warnvalues{$val}) {
                        $warnvalues{$val}++;
                    } else {
                        $warnvalues{$val} = 1;
                        # if (!defined $shown_files{$act_file}) {
                            $shown_files{$act_file} = 1;
                            push(@warns,$trline);
                            # push(@fatal,"$act_file $trline");
                        #}
                    }
                } elsif ($trline =~ /:\s+warning\s+LNK(\d+):/) {
                    $val = $1;
                    if (defined $linkwarn{$val}) {
                        $linkwarn{$val}++;
                    } else {
                        $linkwarn{$val} = 1;
                        push(@warns,$trline);
                    }
                } elsif ($trline =~/^CUSTOMBUILD\s*:\s+warning\s+/) {
                    push(@warns,$trline);
                } else {
                    pgm_exit(1,"ERROR:$lnn: warning regex failed [$trline]! ** FIX ME **\nLine:$lnn: '$line'\n");
                    push(@warns,$tline);
                }
            }
            # Deal with multiple lines
            $linklin = '';
            $tmp = $line;
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ($tmp =~ /^\w/);
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            #pgm_exit(1,"$lnn: $line\n$linklin\nTEMP EXIT\n");
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
        } elsif ($line =~ /\s+warning\s+D(\d+):\s+/) {
            # 432:WARNING: UNPARSED 
            # cl : Command line warning D9002: ignoring unknown option '-fno-fast-math' [X:\build-fg\3rdparty\sqlite3\fgsqlite3.vcxproj]' *** FIX ME **
            $val = "D$1";
            if (defined $warnvalues{$val}) {
                $warnvalues{$val}++;
            } else {
                $warnvalues{$val} = 1;
                if (!defined $shown_files{$act_file}) {
                    $shown_files{$act_file} = 1;
                    push(@warns,$trline);
                }
            }
        } elsif ($line =~ /^error:\s+/) {
            #pgm_exit(1,"$lnn: $line\n");
            if (! defined $error_lines{$line}) {
                $errorcnt++;
                $error_lines{$line} = 1;
                $trline = get_trim_error($line);
                push(@error,$trline);
            }
            # Deal with multiple lines
            $linklin = '';
            # start at NEXT line
            for ($j = $lnn; $j < $lncnt; $j++) {
                $tmp = $lines[$j];
                last if ($tmp =~ /^\w/);
                $tmp =~ s/^\s+//;
                $linklin .= " $tmp";
            }
            #pgm_exit(1,"$lnn: $line\n$linklin\nTEMP EXIT\n");
            prt("$lnn:$line:\n$linklin\n") if (VERB9());
            $i = $j - 1;    # update position
        } else {
            if ($line =~ /^ClCompile:$/) {
                # could collect compile lines
            } elsif ($line =~ /^\s+C:\\Program\s+Files\s+/) {
                # 99:WARNING: UNPARSED '  C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\bin\CL.exe 
                # /c /IF:\Projects\software\include /IF:\Projects\gshhg\src\utils /IF:\Projects\gshhg\src\bmp 
                # /IF:\Projects\gshhg\src\png /Zi /nologo /W3 /WX- /Od /Ob0 /Oy- /D WIN32 /D _WINDOWS 
                # /D NOMINMAX /D _USE_MATH_DEFINES /D _CRT_SECURE_NO_WARNINGS /D _SCL_SECURE_NO_WARNINGS 
                # /D __CRT_NONSTDC_NO_WARNINGS /D _REENTRANT /D _DEBUG /D USE_PNG_LIB /D "CMAKE_INTDIR=\"Debug\"" 
                # /D _MBCS /Gm- /EHsc /RTC1 /MDd /GS /fp:precise /Zc:wchar_t /Zc:forScope /Zc:inline /GR 
                # /Fo"bmp_utils.dir\Debug\\" /Fd"bmp_utils.dir\Debug\bmp_utils.pdb" /Gd /TC /wd4996 
                # /analyze- /errorReport:queue F:\Projects\gshhg\src\bmp\readbmp.c 
                # F:\Projects\gshhg\src\bmp\endianness.c' *** FIX ME **
                # LOTS of information to EXTRACT, if desired

            } elsif ($line =~ /^\s+(.+)\s+note:\s+placeholders\s+/) {
                # 198:WARNING: UNPARSED '  F:\Projects\gshhg\src\bmp\bmp-1bit.cxx(159): note: placeholders and their parameters expect 0 variadic arguments, but 1 were provided' *** FIX ME **
            } elsif ($line =~ /^\s+(.+)\s+note:\s+see\s+declaration\s+of\s+/) {
                # 401:WARNING: UNPARSED '  X:\terragear-fork\src\Lib\terragear/tg_polygon.hxx(242): 
                # note: see declaration of 'tgPolygon'' *** FIX ME **
            } elsif ($line =~ /^\s+(.+)\s+note:\s+type\s+is\s+/) {
                # 257:WARNING: UNPARSED '  X:\terragear-fork\src\Prep\GSHHS\main.cxx(133): 
                # note: type is 'unknown-type'' *** FIX ME **
            } elsif ($line =~ /^\s+Checking\s+Build\s+System$/) {
                # 74:WARNING: UNPARSED '  Checking Build System' *** FIX ME **
            # } elsif ($line =~ /^Lib:$/) {
                # could collect link lines - DONE ABOVE
            } elsif ($line =~ /^\s+Deleting\s+file\s+\"(.+)\".$/) {
                # Deleting file "write-bmp2.dir\Release\write-bmp2.tlog\unsuccessfulbuild".'
            } elsif ($line =~ /^\s+Touching\s+\"(.+)\".$/) {
                #   Touching "write-bmp2.dir\Release\write-bmp2.tlog\write-bmp2.lastbuildstate".
            } elsif ($line =~ /^\s+Creating\s+\"(.+)\"\s+because\s+/) {
                #   Creating "Win32\Release\ALL_BUILD\ALL_BUILD.tlog\unsuccessfulbuild" because "AlwaysCreate" was specifie
            } elsif ($line =~ /^PrepareForBuild:$/) {
                # PrepareForBuild:
            } elsif ($line =~ /^\s+Generating\s+Code\.\.\.$/) {
                # Generating Code...
            } elsif ($line =~ /^\s+Creating\s+directory\s+\"(.+)\".$/) {
                #   Creating directory "Win32\Debug\ZERO_CHECK\".
            } elsif ($line =~ /^\s+Building\s+Custom\s+Rule\s+(.+)$/) {
                # 96:WARNING: UNPARSED '  Building Custom Rule F:/Projects/gshhg/CMakeLists.txt' *** FIX ME **
            } elsif ($line =~ /^\s+CMake\s+does\s+not\s+need\s+to\s+re-run\s+because\s+/) {
                # 97:WARNING: UNPARSED '  CMake does not need to re-run because F:\Projects\gshhg\build\CMakeFiles\generate.stamp is up-to-date.' *** FIX ME **
            } elsif ($line =~ /^\s+(\w+)\.vcxproj\s+->\s+(.+)$/) {
                # 66: UNPARSED '  bmp_utils.vcxproj -> F:\Projects\gshhg\build\Debug\bmp_utilsd.lib'
                # 84: UNPARSED '  png_utils.vcxproj -> F:\Projects\gshhg\build\Debug\png_utilsd.lib'
                # 102: UNPARSED '  utils.vcxproj -> F:\Projects\gshhg\build\Debug\utilsd.lib'
                $curr_proj = $1;
                $curr_out  = $2;
                $curr_conf = "N/A";
                if ($curr_out =~ /(\\|\/)Debug(\\|\/)/i) {
                    $curr_conf = "Debug";
                } elsif ($curr_out =~ /(\\|\/)Release(\\|\/)/i) {
                    $curr_conf = "Release";
                } elsif ($curr_out =~ /(\\|\/)RelWithDebInfo(\\|\/)/i) {
                    $curr_conf = "RelWithDebInfo";
                }
            } elsif ($line =~ /^Build\s+succeeded.$/) {
                # is usually followed by the follwowing lines...
            } elsif ($line =~ /^\s+(\d+)\s+Warning\(s\)$/) {
                $curr_wcnt = $1;
            } elsif ($line =~ /^\s+(\d+)\s+Error\(s\)$/) {
                $curr_ecnt = $1;
            } else {
                #############################################################################
                ### UGH: Some rather random output line from the build-me.bat
                # 1: UNPARSED 'Building gshhg begin 17:31:06.63 '
                # 2: UNPARSED 'Doing 'cmake .. -DCMAKE_INSTALL_PREFIX=F:\Projects\software' '
                # 24: UNPARSED 'Doing 'cmake --build . --config Debug'  '
                # 28: UNPARSED 'Build started 2016-10-18 17:31:07.'
                # 278: UNPARSED 'Doing: 'cmake --build . --config Release'  '
                # 282: UNPARSED 'Build started 2016-10-18 17:31:08.'
                if ($line =~ /^Building\s+/) {
                    # Building terragear begin 2016-11-02  2:35:53.43 
                    # standard entry
                    if ($line =~ /(\d{4}-\d{2}-\d{2})/) {
                        $tmp = $1;
                        # 'Begin 2016-10-16 19:22:23.88 '
                        prt("$lnn: $line\n");
                    } elsif ($line =~ /\d{2}:\d{2}:\d{2}/) {
                        # Building tidy-test begin 19:49:38.58
                        # has only the time
                        prt("$lnn: $line\n");
                    } else {
                        prt("$lnn: $line\n") if (VERB1());
                    }
                } elsif ($line =~ /^Build\s+of\s+/) {
                    # standard entry
                    if ($line =~ /(\d{4}-\d{2}-\d{2})/) {
                        $tmp = $1;
                        # 'Begin 2016-10-16 19:22:23.88 '
                        prt("$lnn: $line\n");
                    } elsif ($line =~ /\d{2}:\d{2}:\d{2}/) {
                        # Building tidy-test begin 19:49:38.58
                        # has only the time
                        prt("$lnn: $line\n");
                    } else {
                        prt("$lnn: $line\n") if (VERB1());
                    }
                } elsif ($line =~ /^Doing(:*)\s+/) {
                    if ($line =~ /\s+--config\s+Debug/i) {
                        $curr_conf = 'Debug';
                    } elsif ($line =~ /\s+--config\s+Release/i) {
                        $curr_conf = 'Release';
                    } elsif ($line =~ /\s+--config\s+(\w+)\s*/) {
                        $curr_conf = $1;
                    }
                } elsif ($line =~ /^Build\s+started\s(.+)$/) {
                    # ...
                } elsif ($line =~ /^ERROR:\s+cmake\s+build\s+Debug/i) {
                    # 791:UNPARSED 'ERROR: cmake build Debug ' *** FIX ME **
                } elsif ($line =~ /Build\s+FAILED/) {
                    # 639:UNPARSED 'Build FAILED.' *** FIX ME **
                } elsif ($line =~ /^Setup\s+Qt/) {
                    # 'Setup Qt 5 64-bits D:\Qt5.6.1\5.6\msvc2015_64 '
                ###} elsif ($line =~ /^Begin\s+(\d{4}-\d{2}-\d{2})/) {
                } elsif ($line =~ /^Begin\s+/) {
                    if ($line =~ /(\d{4}-\d{2}-\d{2})/) {
                        $tmp = $1;
                        # 'Begin 2016-10-16 19:22:23.88 '
                        prt("$lnn: $line\n");
                    } elsif ($line =~ /(\d{2}\/\d{2}\/\d{4})/) {
                        $tmp = $1;
                        # Begin 17/06/2016 14:18:43.90 
                        prt("$lnn: $line\n");
                    }
                } elsif ($line =~ /^Build\s+/) {
                    if ($line =~ /(\d{4}-\d{2}-\d{2})/) {
                        $tmp = $1;
                        # 'Begin 2016-10-16 19:22:23.88 '
                        prt("$lnn: $line\n");
                    } elsif ($line =~ /(\d{2}\/\d{2}\/\d{4})/) {
                        $tmp = $1;
                        # Begin 17/06/2016 14:18:43.90 
                        prt("$lnn: $line\n");
                    }
                } elsif ($line =~ /^(debug|release)\s+build\s+error/) {
                    # batch error exit
                } elsif ($line =~ /^Setting\s+/) {
                    # Setting environment for using Microsoft Visual Studio 2010 x64 tools.
                } elsif ($line =~ /^Set\s+/) {
                    # Set ENV SIMGEAR_DIR=D:\FG\d-and-c\install\simgear
                    if ($line =~ /\s+(\w+)=(.+)$/) {
                        prt("$lnn: $line\n");
                    }
                } elsif ($line =~ /^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}/) {
                    # just a DIR line
                } elsif ($line =~ /^\s+\d+\s+file/) {
                    #  1 file(s) copied.
                } elsif ($line =~ /^Copying\s+/) {
                    # Copying CMakeLists.txt to
                } elsif ($line =~ /^Appears\s+no\s+change/) {
                    # 'Appears no change in config.
                } elsif ($line =~ /^Appears\s+/) {
                    # Appears a successful build of Example
                    # output from some build-me.bat's
                } elsif ($line =~ /\d{4}.{1}\d{2}.{1}\d{2}/) {
                    # it has what looks like a DATE
                    prt("$lnn: $line\n");
                } elsif ($line =~ /^Added\s+/) {
                # } elsif ($line =~ /^\s*set\s+(\w|)_)+=\.+/i) {
                } elsif ($line =~ /^\s*set\s+.+/i) {
                    # ignore a 'set' statement
                } elsif ($line =~ /Built\s+target\s+/) {
                    # ignore unix 'Built target '...
                } elsif ($line =~ /CMAKE\s+Build\s+type:/) {
                    # ignore 'CMAKE Build type:'
                } elsif ($line =~ /Installing:/) {
                    # ignore 'Installing:'
                } elsif ($line =~ /^\*\*/) {
                    # ignore '** Visual Studio 2017 Developer Command Prompt v15.5.4'
                } elsif ($line =~ /Environment\s+initialized/) {
                    # ignore '[vcvarsall.bat] Environment initialized for: 'x64''
                } elsif ($line =~ /^Compiling\s*/i) {
                    # 'Compiling TerraGear'
                } elsif ($line =~ /^All done/i) {
                    # 'All done!'
                } elsif ($line =~ /^No\s+pause/i) {
                    # 'No pause reqested'
                } else {
                    if ($had_end_cmake) {
                        prtw("$lnn:WARNING: UNPARSED '$line' *** FIX ME **\n");
                    }
                }
                #############################################################################
            }
        }
        if ($had_blank) {
            if ($line =~ /^Build\s+(.+)\./ ) {
                $ok = $1;
                $hadbld = 1;
            }
        }
        if ($hadprj) {
           push(@arr,$line);
        }
        $had_blank = 0;
    }
    prt("\n");
    ####################################################
    ### sumary
    ####################################################
    $cnt = $fatalcnt + $errorcnt + $warningcnt + $cmakewcnt + $cmakeecnt;
    if ($cnt) {
        prt("$projcnt projects: Had $fatalcnt fatal, errors $errorcnt, warnings $warningcnt, cmake e=$cmakeecnt, w=$cmakewcnt, total $cnt\n");
    } else {
        prt("$projcnt projects: Had no errors or warnings... clean build...\n");
    }
    @arr = sort keys %warn_disabled;
    $len = scalar @arr;
    if ($len) {
        prt("Noted $len compiler warnings DISABLED - check these -");
        prt(" ".join(" ",@arr)."\n");
    }
    if ($skipped_cmake_mess) {
        prt("Skipped $skipped_cmake_mess cmake messages beginning with '-- '. Use -c to show.\n");
    }

    @arr = sort keys %fatalvalues;
    $cnt = scalar @arr;
    if ($cnt) {
        prt("Got $cnt fatal values ".join(" ",@arr)."\n");
    }

    @arr = sort keys %errorvalues;
    $cnt = scalar @arr;
    if ($cnt) {
        prt("Got $cnt error values ".join(" ",@arr)."\n");
    }

    @arr = sort keys %warnvalues;
    $cnt = scalar @arr;
    if ($cnt) {
        my $wcnt = $cnt;
        ##prt("Got $cnt warning values ".join(" ",@arr)."\n");
        prt("Got $warningcnt warnings:  $wcnt diff: ");
        my @order = ();
        for ($j = 0; $j < $wcnt; $j++) {
            $tmp = $arr[$j];
            $cnt = $warnvalues{$tmp};
            push(@order,[ $cnt, $tmp ]);
        }
        @order = sort mycmp_decend_n0 @order;
        foreach $ra (@order) {
            $tmp = ${$ra}[1];
            $cnt = $warnvalues{$tmp};
            prt("$tmp ($cnt) ");
        }
        prt("\n");
    }
    @arr = sort keys %linkfatal;
    $cnt = scalar @arr;
    if ($cnt) {
        prt("Got $cnt fatal link ".join(" ",@arr)."\n");
    }
    @arr = sort keys %linkerror;
    $cnt = scalar @arr;
    if ($cnt) {
        prt("Got $cnt error link ".join(" ",@arr)."\n");
    }
    @arr = sort keys %linkwarn;
    $cnt = scalar @arr;
    if ($cnt) {
        prt("Got $cnt warn link ".join(" ",@arr)."\n");
    }
    @arr = sort keys %cmakewarn;
    $cnt = scalar @arr;
    if ($cnt) {
        prt("Got $cnt cmake warnings CMP0".join(" ",@arr)."\n");
    }
    @arr = sort keys %missing_files;
    $cnt = scalar @arr;
    if ($cnt) {
        prt("Got $cnt MISSING FILES! ".join(" ",@arr)."\n");
    }
}

sub show_flags_seen() {
    my @arr = sort keys %flags_seen;
    my $cnt = scalar @arr;
    return if (!$cnt);
    prt("Seen $cnt compile and link flags...\n");
    my $msg = '';
    my $max_len = 100;
    my ($i,$tmp,$lenm,$len2);
    for ($i = 0; $i < $cnt; $i++) {
        $tmp = $arr[$i];
        $lenm = length($msg);
        $len2 = length($tmp);
        if ($lenm) {
            if (($lenm + $len2) > $max_len) {
                prt("$msg\n");
                $msg = '';
            }
        }
        $msg .= ' ' if (length($msg));
        $msg .= $tmp;
    }
    prt("$msg\n") if (length($msg));
}



#########################################
### MAIN ###
parse_args(@ARGV);
process_in_file($in_file);
#1show_flags_seen();
pgm_exit(0,"");
########################################

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg);
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
                prt("Verbosity = $verbosity\n") if (VERB1());
            } elsif ($sarg =~ /^l/) {
                if ($sarg =~ /^ll/) {
                    $load_log = 2;
                } else {
                    $load_log = 1;
                }
                prt("Set to load log at end. ($load_log)\n") if (VERB1());
            } elsif ($sarg =~ /^o/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_file = $sarg;
                prt("Set out file to [$out_file].\n") if (VERB1());
            } elsif ($sarg =~ /^f/) {
                $show_fatal = 0;
                prt("Set fatal warnings.\n") if (VERB1());
            } elsif ($sarg =~ /^e/) {
                $show_errors = 0;
                prt("Set skip errors.\n") if (VERB1());
            } elsif ($sarg =~ /^w/) {
                $show_warnings = 0;
                prt("Set skip warnings.\n") if (VERB1());
            } elsif ($sarg =~ /^c/) {
                $show_cmake_mess = 1;
                prt("Set show cmake messages beginning '-- '.\n") if (VERB1());
            } elsif ($sarg =~ /^F/) {
                $show_compile_flags = 1;
                prt("Set show compile flags.\n") if (VERB1());
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            $in_file = $arg;
            prt("Set input to [$in_file]\n") if (VERB1());
        }
        shift @av;
    }

    if ($debug_on) {
        prtw("WARNING: DEBUG is ON!\n");
        if (length($in_file) ==  0) {
            $in_file = $def_file;
            prt("Set DEFAULT input to [$in_file]\n");
        }
        $load_log = 1;
    }
    if (length($in_file) ==  0) {
        if (-f 'bldlog-1.txt') {
            $in_file = 'bldlog-1.txt';
            prt("Set input to [$in_file]\n") if (VERB9());
        } else {
            give_help();
            pgm_exit(1,"\nERROR: No input files found in command!\n");
        }
    }
    if (! -f $in_file) {
        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
    }
}

sub give_help {
    prt("\n");
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] [in-file]\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>  (-o) = Write output to this file.\n");
    prt(" --fatal       (-f) = Skip fatal (def=$show_fatal).\n");
    prt(" --errors      (-e) = Skip fatal (def=$show_errors).\n");
    prt(" --warnings    (-w) = Skip warnings (def=$show_warnings).\n");
    prt(" --cmake       (-c) = Show cmake messages beginning with '--'.\n");
    prt(" --Flags       (-F) = Show CLCompile flags.\n");
    prt("\n");
    prt(" Parse the msvc output build file, (def=bldlog-1.txt)\n");
    prt(" and show summarised results, depending on -vn (0,1,2,5,9)\n");
}

# eof - msvclog.pl
