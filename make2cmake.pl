#!/usr/bin/perl -w
# NAME: make2cmake.pl
# AIM: Given an nmake 'makefile' try to generatet the equivalent cmake CMakeLists.txt
# 03/09/2015 - Copied to the 'scripts' repo for further development
# 02/09/2013 - Given a base directory, follow sub-directories... and load include files
# 27/08/2013 - Only show lines not dealt with once
# 02/07/2013 - Fill in valid SOURCE directories for searching
# 01/05/2013 - Default to 'Console Application' is NO extension - need better way!!!
# 20/03/2013 - Also search for 'default:' like 'all:',and accept either...
# 09/01/2013 - Attempt some improvements
# 03/12/2012 - some improvements and fixes
# 18/07/2012 - Initial cut
use strict;
use warnings;
use File::Basename;  # split path ($name,$dir,$ext) = fileparse($file [, qr/\.[^.]*/] )
use File::Spec; # File::Spec->rel2abs($rel);
use Cwd;
my $os = $^O;
my $cwd = cwd();
my ($pgmname,$perl_dir) = fileparse($0);
my $temp_dir = $perl_dir . "temp";
my $PATH_SEP = '/';
if ($os =~ /win/i) {
    $PATH_SEP = "\\";
}
unshift(@INC, $perl_dir);
require 'lib_utils.pl' or die "Unable to load 'lib_utils.pl' Check paths in \@INC...\n";
require 'lib_params.pl' or die "Unable to load 'lib_params.pl'! Check location and \@INC content.\n";

# log file stuff
our ($LF);
my $outfile = $temp_dir.$PATH_SEP."temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.4 2015-09-03";  # on move to scripts repo
##my $VERS = "0.0.3 2013-09-02";
#my $VERS = "0.0.2 2013-01-09";
#my $VERS = "0.0.1 2012-07-18";
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = '';
my $user_type = '';
my $user_targ_dir = 0;  # user gave a TARGET directory
my $project_version = '';
my $prefix_rel_file = 0;   # try to PRE-fix relative file name - NEEDS MORE WORK

my $ver_major = 1;
my $ver_minor = 2;
my $ver_point = 3;
my $target_ver = 0;
my $user_name = 0;

# APP_TYPE
# $app_console_stg  = 'Console Application'  = get_dsp_head_console
# $app_windows_stg  = 'Application'          = get_dsp_head_app
# $app_dynalib_stg  = 'Dynamic-Link Library' = get_dsp_head_dynalib
# $app_statlib_stg  = 'Static Library'       = get_dsp_head_slib

# debug
my $debug_on = 0;
my $def_targ_dir = 'C:\FG\17\libtomat';
my $def_file = $def_targ_dir.'\makefile.msvc';
my $def_proj_name = 'gmpq';
my $def_out_file = $temp_dir.$PATH_SEP."temp-make2cmake.txt";
my $def_usr_type = 'Static Library';
my $debug_rel_fix = 0;

#my $def_targ_dir = 'C:\Projects\wput-0.6.1';
#my $def_file = $def_targ_dir.'\src\Makefile';
#my $def_proj_name = 'wput';
#my $def_out_file = $temp_dir.$PATH_SEP."temp-make2cmake.txt";
#my $def_usr_type = 'Console Application';

##my $def_file = 'C:\Projects\notepad-plus\scintilla\win32\makefile';
#my $def_file = 'C:\Projects\notepad-plus\scintilla\win32\scintilla.mak';
#my $def_targ_dir = 'C:\Projects\notepad-plus';
my $debug_extra = 0;

### program variables
my @warnings = ();
my %subst = ();
my %subs_not_found = ();
my %targets_deps = ();
my %targets_acts = ();
my %targets_file = ();
my ($rparams);

my @subst_stack = ();
my %dirs_stack = ();
my %valid_source_dirs = ();

my %done_files = ();
my ($root_name,$root_dir);
# shared variables
########################################
### SHARED RESOURCES, VALUES
### ========================
our $fix_relative_sources = 1;
our %g_user_subs = ();    # supplied by USER INPUT
our %g_user_condits = (); # conditionals supplied by the user
# Auto output does the following -
# For libaries
# Debug:  '/out:"lib\barD.lib"'
# Release:'/out:"lib\barD.lib"'
# for programs
# Debug:  '/out:"bin\fooD.exe"'
# Release:'/out:"bin\foo.exe"'
# This also 'adds' missing 'include' files
#Bit:   1: Use 'Debug\$proj_name', and 'Release\$proj_name' for intermediate and out directories
#Bit:   2: Set output to lib, or bin, and names to fooD.lib/foo.lib or barD.exe/bar.exe
#Bit:   4: Set program dependence per library output directories
#Bit:   8: Add 'msvc' to input file directory, if no target directory given
#Bit:  16: Add program library dependencies, if any, to DSW file output.
#Bit:  32: Add all necessary headers to the DSP file. That is scan the sources for #include "foo.h", etc.
#Bit:  64: Write a blank header group even there are no header files for that component.
#Bit: 128: Add defined item of HAVE_CONFIG_H to all DSP files.
#Bit: 256: Exclude projects in SUBDIRS protected by a DEFINITION macro, else include ALL.
#Bit: 512: Unconditionally add ANY libraries build, and NOT excluded to the last application
#Bit:1024: If NO users conditional, do sustitution, if at all possible, regardless of TRUE or FALSE
#Bit:2048: Add User -L dependent libraries to each application
#Bit: These can be given as an integer, or the form 2+8, etc. Note using -1 sets ALL bits on.
#Bit: Bit 32 really slows down the DSP creation, since it involves scanning every line of the sources.
my $auto_max_bit = 512;
our $auto_on_flag = -1; #Bit: ALL ON by default = ${$rparams}{'CURR_AUTO_ON_FLAG'}
sub get_curr_auto_flag() { return $auto_on_flag; }
#my ($g_in_name, $g_in_dir);
#my ($root_file, $root_folder);
#sub get_root_dir() { return $root_folder; }
our $exit_value = 0;
# But SOME Makefile.am will use specific 'paths' so the above can FAIL to find
# a file, so the following two 'try harder' options, will do a full 'root'
# directory SCAN, and search for the file of that name in the scanned files
our $try_harder = 1;
our $try_much_harder = 1;
# ==============================================================================
our $process_subdir = 0;
our $warn_on_plus = 0;
# ==============================================================================
# NOTE: Usually a Makefile.am contains SOURCE file names 'relative' to itself,
# which is usually without any path. This options ADDS the path to the
# Makefile.am, and then substracts the 'root' path, to get a SOURCE file
# relative to the 'root' configure.ac, which is what is needed if the DSP
# is to be placed in a $target_dir, and we want the file relative to that
our $add_rel_sources = 1;
our $target_dir = '';
# ==============================================================================
our $ignore_EXTRA_DIST = 0;
our $added_in_init = '';
our $supp_make_in = 0; # Support Makefile.in scanning
our $project_name = ''; # a name to override any ac scanned name of the project

my $dsp_files_skipped = 0;

### =============================
# offsets into REF_LIB_LIST array
our $RLO_MSG = 0;
our $RLO_PRJ = 1;
our $RLO_VAL = 2;
our $RLO_NAM = 3;
our $RLO_EXC = 4;
### =============================

my $write_dsp = 0;
sub get_write_dsp_files() { return $write_dsp; }

sub ac_do_dir_scan($$$) { return; }

sub VERB1() { return $verbosity >= 1; }
sub VERB2() { return $verbosity >= 2; }
sub VERB5() { return $verbosity >= 5; }
sub VERB9() { return $verbosity >= 9; }

my $final_msg = '';

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
    prt($final_msg) if (length($final_msg));
    close_log($outfile,$load_log);
    exit($val);
}


sub prtw($) {
   my ($tx) = shift;
   $tx =~ s/\n$//;
   prt("$tx\n");
   push(@warnings,$tx);
}

sub process_in_file($);
sub sort_target_deps();

sub add_to_valid_source_dirs($) {
    my $ff = shift;
    my ($n,$dir) = fileparse($ff);
    $valid_source_dirs{$dir} = 1;
}

sub fill_valid_source_dirs($$);
sub fill_valid_source_dirs($$) {
    my ($dir,$dep) = @_;
    if (!opendir(DIR,$dir)) {
        prtw("WARNING: Unable to open directory $dir!\n");
        return;
    }
    my @files = readdir(DIR);
    closedir(DIR);

    my @dirs = ();
    my ($ff,$file);
    ut_fix_directory(\$dir);
    foreach $file (@files) {
        next if ($file eq '.');
        next if ($file eq '..');
        $ff = $dir.$file;
        if (-d $ff) {
            push(@dirs,$ff);
        } elsif (-f $ff) {
            add_to_valid_source_dirs($ff) if (is_c_source($file));
        } else {
            prtw("WARNING: WHAT IS THIS? [$ff] [$file]\n");
        }
    }
    foreach $dir (@dirs) {
        fill_valid_source_dirs($dir,$dep+1);
    }
    if ($dep == 0) {
        $ff = scalar keys %valid_source_dirs;
        prt("From target directory, added $ff valid source dirs\n");
    }
}

sub do_substitutions($$);

# * ? + [ ] ( ) { } ^ $ | \
sub my_escape($) {
    my $txt = shift;
    my $len = length($txt);
    my $ntxt = '';
    my ($i,$ch);
    for ($i = 0; $i < $len; $i++) {
        $ch = substr($txt,$i,1);
        $ntxt .= "\\" if ($ch eq '*');
        $ntxt .= "\\" if ($ch eq '?');
        $ntxt .= "\\" if ($ch eq '[');
        $ntxt .= "\\" if ($ch eq ']');
        $ntxt .= "\\" if ($ch eq '(');
        $ntxt .= "\\" if ($ch eq ')');
        $ntxt .= "\\" if ($ch eq '{');
        $ntxt .= "\\" if ($ch eq '}');
        $ntxt .= "\\" if ($ch eq '^');
        $ntxt .= "\\" if ($ch eq '$');
        $ntxt .= "\\" if ($ch eq '|');
        $ntxt .= "\\" if ($ch eq "\\");
        $ntxt .= $ch;
    }
    return $ntxt;
}

# this is OK, but FAILS when there are 2 or more substations in a line
# Failed on $(NAME)$(DIR_O)
sub do_substitutions($$) {
    my ($ival,$lnn) = @_;
    my $val = $ival;
    my $rh = \%subst;
    my @arr = space_split($val);
    my $cnt = scalar @arr;
    my ($i,$fnd,$rcs,$nval);
    for ($i = 0; $i < $cnt; $i++) {
        $val = $arr[$i];
        if ($val =~ /\$\((.+)\).*\$?/) {
            my $tmp = $1;
            if (defined ${$rh}{$tmp}) {
                $nval = ${$rh}{$tmp};
                ### $nval = my_escape($nval);
                $val =~ s/\$\($tmp\)/$nval/;
                $arr[$i] = $val; # insert the SUBST value
            } else {
                $fnd = 0;
                if (defined ${$rparams}{'CURR_COMMON_SUBS'}) {
                    $rcs = ${$rparams}{'CURR_COMMON_SUBS'};
                    if (defined ${$rcs}{$tmp}) {
                        $nval = ${$rcs}{$tmp};
                        $val =~ s/\$\($tmp\)/$nval/;
                        $arr[$i] = $val;
                        $fnd = 1;
                    }
                }
                if (!$fnd) {
                    if (!defined $subs_not_found{$tmp}) {
                        prtw("WARNING:$lnn: No sub of [$tmp] in [$val]\nLine [$ival]\n");
                        $subs_not_found{$tmp} = 1;
                    }
                }
            }
        }
    }
    return join(" ",@arr);
}

sub do_substitutions2_NOT_USED($) {
    my $val = shift;
    my $rh = \%subst;
    my @arr = space_split($val);
    my $cnt = scalar @arr;
    my ($i,@arr2,$val2,$nval,$tmp,$sval);
    for ($i = 0; $i < $cnt; $i++) {
        $val = $arr[$i];
        @arr2 = split('$',$val);    # isolate EACH sub
        $sval = '';
        foreach $val2 (@arr2) {
            if ($val2 =~ /\((.+)\)/) {
                $tmp = $1;
                if (defined ${$rh}{$tmp}) {
                    $nval = ${$rh}{$tmp};
                    #### $nval = my_escape($nval);
                    $val2 =~ s/\$\($tmp\)/$nval/;
                    ###$arr[$i] = $val;
                } else {
                    if (!defined $subs_not_found{$tmp}) {
                        prtw("WARNING: No sub of [$tmp] in [$val]\n");
                        $subs_not_found{$tmp} = 1;
                    }
                    $val2 = '$'.$val2;
                }
                $sval .= $val2;
            } else {
                $sval .= $val2;
            }
        }
    }
    return join(" ",@arr);
}

sub is_target_line($$$) {
    my ($line,$rtarg,$ract) = @_;
    if ($line =~ /^(.+):/) {
        my $len = length($line);
        my $targ = '';
        my $act = '';
        my ($i,$ch);
        for ($i = 0; $i < $len; $i++) {
            $ch = substr($line,$i,1);
            last if ($ch eq ':');
            $targ .= $ch;
        }
        $i++;
        for (; $i < $len; $i++) {
            $ch = substr($line,$i,1);
            next if ($ch eq ':');
            $act .= $ch;
        }
        $targ = trim_all($targ);
        $act = trim_all($act);
        ${$rtarg} = $targ;
        ${$ract}  = $act;
        return 1 if (length($targ));
    }
    return 0;
}

sub curr_dep_incs_prev($$) {
    my ($prev,$curr) = @_; # $targets_deps{$targ},$deps
    my @arr1 = space_split($prev);
    my @arr2 = space_split($curr);
    # make sure each item in $prev, is also in $curr
    my ($itm1,$itm2,$fnd);
    foreach $itm1 (@arr1) {
        $itm1 = path_d2u($itm1);
        $fnd = 0;
        foreach $itm2 (@arr2) {
            $itm2 = path_d2u($itm2);
            # path seps are the same - do they compare
            if ($itm1 eq $itm2) {
                $fnd = 1;
                last;
            }
        }
        return 0 if (!$fnd);
    }
    return 1; # all previous found in current = no problem with overwrite
}

# BAD IDEA - SCRAPPED
sub merge_refs($$) {
    my ($rh1,$rh2) = @_;
    my ($key,$val,$val1);
    prt("Started with...\n");
    foreach $key (keys %{$rh2}) {
        $val = ${$rh2}{$key};
        prt("$key = $val\n");
    }
    prt("Now have...\n");
    foreach $key (keys %{$rh1}) {
        $val = ${$rh1}{$key};
        if (defined ${$rh2}{$key}) {
            $val1 = ${$rh2}{$key};
            prt("$key = $val1 - retored from $val\n");
            ${$rh1}{$key} = $val1;
        } else {
            prt("$key = $val\n");
        }
    }
    prt("TEMP EXIT");
    close_log($outfile,$load_log);
    exit(1);
    ###pgm_exit(1,"TEMP EXIT");
}

# really IF the $act looks like 'cd port | nmake /nologo /f makefile.vc | cd ..'
# then SHOULD load an process the /f <file>
sub looks_like_cd_nmake($$$) {
    my ($act,$dir,$rtmp) = @_;
    my @arr = split(/\|/,$act);
    my $cnt = scalar @arr;
    my ($i,$a,$cd,$i2,$ff,@arr2,$cnt2,$i3);
    if (VERB9()) {
        prt("In dir [$dir], actions count $cnt - ");
        for ($i = 0; $i < $cnt; $i++) {
            $a = trim_all($arr[$i]);
            prt("[$a] ");
        }
        prt("\n");
    }
    for ($i = 0; $i < $cnt; $i++) {
        $a = trim_all($arr[$i]);
        if ($a =~ /^cd\s+(\S+)$/i) {
            $cd = $1;
            next if ($cd eq '..');
            $ff = $dir.$cd;
            if (-d $ff) {
                ut_fix_directory(\$ff);
                prt("Found directory [$ff]\n") if (VERB9());
                $i2 = $i + 1;
                for (; $i2 < $cnt; $i2++) {
                    $a = trim_all($arr[$i2]);
                    @arr2 = split(/\s+/,$a);
                    $cnt2 = scalar @arr2;
                    if (VERB9()) {
                        prt("$i2: split $cnt2 ");
                        for ($i3 = 0; $i3 < $cnt2; $i3++) {
                            prt("$i3 [".$arr2[$i3]."] ");
                        }
                        prt("\n");
                    }
                    if ($cnt2 >= 3) {
                        if (($arr2[1] eq '/f')&&($arr2[2] =~ /makefile/i)) {
                            $ff = $ff.$arr2[2];
                            if (-f $ff) {
                                ${$rtmp} = $ff;
                                return 1;
                            }
                        }
                        if ($cnt2 > 3) {
                            if (($arr2[2] eq '/f')&&($arr2[3] =~ /makefile/i)) {
                                $ff = $ff.$arr2[3];
                                if (-f $ff) {
                                    ${$rtmp} = $ff;
                                    return 1;
                                }
                            }
                        }
                    }
                }
            } else {
                prt("Could NOT find dir [$ff]\n") if (VERB9());
            }
        } elsif ($i == 0) {
            prt("Regex for cd failed on [$a]\n") if (VERB9());
        }
    }
    prt("ACTION: [$act] FAILED to look like cd dir | nmake /f makefile\n") if (VERB9());
    return 0;
}

###################################################################
# process the Makefile
###################################################################
sub process_in_file($) {
    my ($minf) = @_;
    if (defined $done_files{$minf}) {
        prt("Avoiding repeating file [$minf]\n") if (VERB9());
        return;
    }
    $done_files{$minf} = 1;
    if (! open INF, "<$minf") {
        pgm_exit(1,"ERROR: Unable to open file [$minf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    my $rh = \%subst;
    prt("Processing $lncnt lines, from [$minf]...\n");

    my ($line,$inc,$lnn,$i,$tline,$len,$i2,$tmp,$blnn,$elnn,$ff);
    my ($key,$val,$targ,$act,$tmp2,$deps,$sline,@arr,$inc_file);
    my ($name,$dir) = fileparse($minf);
    ut_fix_directory(\$dir);
    if (!defined $dirs_stack{$dir}) {
        $dirs_stack{$dir} = 1;
        prt("Stored [$dir] in directories stack...\n");
    }
    $lnn = 0;
    my $inif = 0;
    my @ifstack = ();
    my $defines_locked = 0;
    my %skipping = ();
    my $rd = get_root_dir();
    ut_fix_directory(\$rd);
    my $rd2 = $root_dir;
    ut_fix_directory(\$rd2);
    my $skip_count = 0;
    for ($i = 0; $i < $lncnt; $i++) {
        $line = $lines[$i];
        chomp $line;
        $lnn = $i + 1;
        $i2 = $i + 1;
        $tline = trim_all($line);
        $len = length($tline);
        next if ($len == 0);
        next if ($tline =~ /^\#/);
        $blnn = $lnn;
        while (($i2 < $lncnt) && ($tline =~ /\\$/)) {
            $tline =~ s/\\$//;  # remove trailing '\'
            $i++;
            $tmp = $lines[$i];  # get next
            chomp $tmp;
            $lnn++;
            $i2 = $i + 1;
            $tline .= ' '.trim_all($tmp);
        }
        $elnn = $lnn;
        $tline = trim_all($tline);
        $len = length($tline);
        prt("$blnn-$elnn: $len [$tline]\n") if (VERB9());
        $sline = do_substitutions($tline,$blnn);
        if ($sline ne $tline) {
            $tline = $sline;
            prt("$blnn-$elnn: $len [$tline] after SUBS\n") if (VERB9());
        }
        next if ($tline =~ /^=====(.+)=$/); # skip these lines
        # Lines beginning '!...'
        #############################################################
        if ($tline =~ /^!/) {
            # Handle like...
            # [!INCLUDE ../boostregex/nppSpecifics.mak]
            if ($tline =~ /^!INCLUDE\s+(.+)$/i) {
                $inc = $1;
                prt("$blnn-$elnn: INCLUDE file [$dir].[$inc] in [$minf]\n") if (VERB9());
                $ff = File::Spec->rel2abs($dir.$inc);
                if (! -f $ff) {
                    #prt("Failed to find [$ff] [$dir.$inc] [$inc]\n");
                    foreach $tmp (keys %dirs_stack) {
                        $tmp2 = File::Spec->rel2abs("$tmp$inc");
                        #prt("Trying [$tmp2] [$tmp".$inc."] [$inc]\n");
                        if (-f $tmp2) {
                            $ff = $tmp2;
                            last;
                        }
                        #$tmp2 = fix_rel_path("$tmp$inc");
                        #prt("Trying [$tmp2] [$tmp".$inc."] [$inc]\n");
                        #if (-f $tmp2) {
                        #    $ff = $tmp2;
                        #    last;
                        #}
                    }
                }
                if (-f $ff) {
                    push(@subst_stack, { %{$rh} }); # store current value
                    #prt("\nProcessing INCLUDE $ff\n");
                    process_in_file($ff);
                    #prt("Done INCLUDE $ff\n\n");
                    my $rh2 = pop @subst_stack; # recover value before INCLUDE
                    ### merge_refs($rh,$rh2); # HMMM, turned out to be a BAD idea
                } else {
                    prtw("WARNING: Unable to find INCLUDE [$ff] [$inc]!\n");
                }
            } elsif ($tline =~ /^!IF\s+(.+)$/i) {
                $inc = $1;
                push(@ifstack,"\@".$inc."_TRUE\@");
                $inif++;
            } elsif ($tline =~ /^!IFDEF\s(.+)$/i) {
                $inc = $1;
        		###if (! $configure_cond{$1});
	            ###push (@conditional_stack, "\@" . $1 . "_TRUE\@");
                push(@ifstack,"\@".$inc."_TRUE\@");
                $inif++;
            } elsif ($tline =~ /^!IFNDEF\s(.+)$/i) {
                $inc = $1;
        		###if (! $configure_cond{$1});
	            ###push (@conditional_stack, "\@" . $1 . "_TRUE\@");
                push(@ifstack,"\@".$inc."_TRUE\@");
                $inif++;
                ###my $rh = \%subst;
                if (defined ${$rh}{$inc}) {
                    # this IS defined, so eat until ELSE or ENDIF
                    $defines_locked++;
                    prt("Found [$inc] defined. Locking the DEFINES until ELSE or ENDIF\n") if (VERB9());
                }
             } elsif ($tline =~ /^!ELSE\b/i) {
                if (@ifstack) {
                    $inc = $ifstack[$#ifstack]; # get last
                    if ($inc =~ /_FALSE\@$/) {
                        prtw("WARNING:$blnn-$elnn: ELSE after ELSE! [$inc] [$tline]\n file [$minf]\n");
                    } else {
                        $inc =~  s/_TRUE\@$/_FALSE\@/;
                        $ifstack[$#ifstack] = $inc;
                    }

                } else {
                    prtw("WARNING:$blnn-$elnn: ELSE with NO IF! [$tline]\n file [$minf]\n");
                }
                $defines_locked-- if ($defines_locked);
            } elsif ($tline =~ /^!ENDIF\b/i) {
                if (@ifstack) {
                    pop @ifstack;
                } else {
                    prtw("WARNING:$blnn-$elnn: ENDIF with NO IF! [$tline]\n file [$minf]\n");
                }
                $inif-- if ($inif);
                $defines_locked-- if ($defines_locked);
            } elsif ($tline =~ /^!MESSAGE\b(.*)$/i) {
            } elsif ($tline =~ /^!ERROR\s+(.+)$/i) {
            } else {
                prtw("WARNING:$blnn-$elnn: Uncased ! command [$tline] FIX ME!\n file [$minf]\n");
            }
        #############################################################
        } else {
        #############################################################
            ###if ($tline =~ /^(\w+)\s*=\s*(.+)$/) - can be a blank
            ######################################
            if ($tline =~ /^(\w+)\s*=\s*(.*)$/) {
                $key = $1;
                $tmp = $2;
                $val = do_substitutions($tmp,$blnn);
                if (defined ${$rh}{$key} ) {
                    $tmp = ${$rh}{$key};
                    if ($defines_locked) {
                        prt("$blnn-$elnn: Defines LOCKED key [$key] = value [$tmp], not changed to [$val]\n") if (VERB5());
                    } else {
                        ${$rh}{$key} = $val;
                        prt("$blnn-$elnn: RESet key [$key] = value [$val], from [$tmp]\n") if (VERB5());
                    }
                } else {
                    ${$rh}{$key} = $val;
                    prt("$blnn-$elnn: Set key [$key] = value [$val]\n") if (VERB5());
                }
            ######################################
            } elsif ($tline =~ /^(\w+)\s*:/) {
            ######################################
                $targ = $1;
                $act = '';
                $deps = '';
                if ($tline =~ /^\w+\s*:\s*(.+)$/) {
                    $deps = $1;
                }
                # must collect following actions
                while ($i2 < $lncnt) {
                    $i++;
                    $i2 = $i + 1;
                    $tmp = $lines[$i];
                    next if ($tmp =~ /^\#/);
                    if ($tmp =~ /^\S/) {    # should commence with TAB - here just non-space
                        $i--;   # back up to process this line later
                        last;
                    }
                    $lnn++;
                    chomp $tmp;
                    $tmp = trim_all($tmp);
                    $len = length($tmp);
                    last if ($len == 0);    # no need to back up - is a blank line - skip it
                    while (($i2 < $lncnt) && ($tmp =~ /\\$/)) {
                        $tmp =~ s/\\$//;  # remove trailing '\'
                        $i++;
                        $tmp2 = $lines[$i];  # get next
                        chomp $tmp2;
                        $lnn++;
                        $i2 = $i + 1;
                        $tmp .= ' '.trim_all($tmp2);
                    }
                    $act .= ' | ' if (length($act));
                    $act .= $tmp;
                }
                $elnn = $lnn;
                $act = do_substitutions($act,$blnn);
                $deps = do_substitutions($deps,$blnn);
                prt("$blnn-$elnn: TARGET [$targ] deps [$deps]\n actions [$act]\n") if (VERB5());
                if ((defined $targets_deps{$targ}) && ($targets_deps{$targ} ne $deps)){
                    prtw("WARNING: TARGET [$targ] deps [".$targets_deps{$targ}."] being over written\n by [$deps]\n");
                }
                ##################################################################################
                $targets_deps{$targ} = $deps;
                $targets_acts{$targ} = $act;
                $targets_file{$targ} = $minf;   # Makefile sources - needed for relative dir fixes
                ##################################################################################
                # really IF the $act looks like 'cd port | nmake /nologo /f makefile.vc | cd ..'
                # then SHOULD load an process the /f <file>
                # DIDN'T WORK !!!! loads file ok, but fails to create a project even though it gets
                # a LONG list of .obj files... 
                if (!($targ =~ /clean/)) {
                    if (looks_like_cd_nmake($act,$dir,\$tmp)) {
                        prt("\nProcess in file [$tmp]\n");
                        process_in_file($tmp);
                        sort_target_deps();
                    }
                }
            ######################################
            } elsif ($tline =~ /^\.SUFFIXES\s*:\s*(.+)$/) {
            ######################################
                # [.SUFFIXES: cxx]
            ######################################
            } else {
            ######################################
                $line = do_substitutions($tline,$blnn);
                $act = '';
                $deps = '';
                if (is_target_line($line,\$targ,\$deps)) {
                   # must collect following actions
                    while ($i2 < $lncnt) {
                        $i++;
                        $i2 = $i + 1;
                        $tmp = $lines[$i];
                        next if ($tmp =~ /^\#/);
                        if ($tmp =~ /^\S/) {   # line does NOT commence with tab (here a non-space)
                            $i--; # back up to process this line
                            last;
                        }
                        chomp $tmp;
                        $lnn++;
                        $tmp = trim_all($tmp);
                        $len = length($tmp);
                        last if ($len == 0);
                        while (($i2 < $lncnt) && ($tmp =~ /\\$/)) {
                            $tmp =~ s/\\$//;  # remove trailing '\'
                            $i++;
                            $tmp2 = $lines[$i];  # get next
                            chomp $tmp2;
                            $lnn++;
                            $i2 = $i + 1;
                            $tmp .= ' '.trim_all($tmp2);
                        }
                        $act .= ' | ' if (length($act));
                        $act .= $tmp;
                    }
                    $elnn = $lnn;
                    $act = do_substitutions($act,$blnn);
                    $deps = do_substitutions($deps,$blnn);
                    prt("$blnn-$elnn: Target [$targ] deps [$deps]\n actions [$act]\n") if (VERB5());
                    if ((defined $targets_deps{$targ}) && ($targets_deps{$targ} ne $deps) && !curr_dep_incs_prev($targets_deps{$targ},$deps)){
                        prtw("WARNING: Target [$targ] deps [".$targets_deps{$targ}."] being over written\nwith [$deps]") if (VERB2());
                    }
                    $targets_deps{$targ} = $deps;
                    $targets_acts{$targ} = $act;
                    $targets_file{$targ} = $minf;   # Makefile src - for rel dir fixes
                } elsif ($tline =~ /^-*include\s+(.+)$/) {
                    # include a file, like -
                    $tmp2 = $1;
                    $tmp = $tmp2;
                    if (! -f $tmp) {
                        prt("Failed to find [$tmp]\n") if (VERB9());
                        $tmp = fix_rel_path($rd2.$tmp2);
                        if (! -f $tmp) {
                            prt("Failed to find [$tmp]\n") if (VERB9());
                            $tmp = fix_rel_path($rd.$tmp2);
                            if (! -f $tmp) {
                                prt("Failed to find [$tmp]\n") if (VERB9());
                                $tmp = fix_rel_path($dir.$tmp2);
                                if (! -f $tmp) {
                                    prt("Failed to find [$tmp]\n") if (VERB9());
                                }
                            }
                        }
                    }
                    $inc_file = File::Spec->rel2abs($tmp);
                    if (-f $inc_file) {
                        prt("\n$blnn-$elnn: Processing 'include' file [$inc_file]\n") if (VERB5());
                        process_in_file($inc_file);
                    } else {
                        prtw("WARNING: $blnn-$elnn: Can NOT locate 'include' file [$inc_file]\n");
                        ###pgm_exit(1,"TEMP EXIT");
                    }

                } else {
                    $skip_count++;
                    @arr = split(/\s+/,$line);
                    $tmp = $arr[0];
                    if ( defined $skipping{$tmp} ) {
                        $skipping{$tmp}++;
                    } else {
                        $skipping{$tmp} = 1;
                        if (VERB5()) {
                            prtw("WARNING:$blnn-$elnn: Line NOT dealt with [$line]\n file [$minf]\n");
                        } elsif (VERB2()) {
                            prtw("WARNING:$blnn-$elnn: Line NOT dealt with [$line]\n");
                        }
                    }
                }
            ######################################
            }
        #############################################################
        }
    }
    prt("Done $lncnt lines, from [$minf]... skipped $skip_count (-v2+ to view)...\n");
    if (@ifstack) {
        $tmp = scalar @ifstack;
        $inc = join(" ",@ifstack);
        prtw("WARNING: Exit file with $tmp items on IF-STACK!\n $inc\n");
    }
}

my %dhashes = ();

sub get_directory_hash($) {
    my $dir = shift;
    if (defined $dhashes{$dir}) {
        return $dhashes{$dir};
    }
    my %h = ();
    if (! opendir(DIR, $dir)) {
        return \%h;
    }
    my @files = readdir(DIR);
    closedir(DIR);
    my ($file,$n,$d,$e,$ra);
    foreach $file (@files) {
        next if ($file eq '.');
        next if ($file eq '..');
        ($n,$d,$e) = fileparse($file, qr/\.[^.]*/);
        $h{$n} = [] if (!defined $h{$n});
        $ra = $h{$n};
        push(@{$ra},$e);
    }
    $dhashes{$dir} = \%h;
    return \%h;
}

#                    $ff = File::Spec->rel2abs($fdir.$fil);
#                    ($n,$d,$e) = fileparse($ff, qr/\.[^.]*/);
#                    $rdh = get_directory_hash($d);
#                    if (defined ${$rdh}{$n}) {
#                        $ext = '.???';
#                        $ok = "NF";
#                        $ra = ${$rdh}{$n}; # get array of extensions
#                        $ecnt = scalar @{$ra};
#                        if ($ecnt == 1) {
#                            # only ONE choice - choose it
#                            $ext = ${$ra}[0];
#                        } else {
#                            # multiple choices - choose extended c source
#                            $ext = '';
#                            foreach $e (@{$ra}) {
#                                $ff = $n.$e;
#                                if (is_c_source_extended($ff)) {
#                                    $ext = $e;
#                                    last;
#                                }
#                            }
#                        }
#                        $ff = $d.$n.$ext;
#                        $ok = 'ok' if (-f $ff);
#                        prt(" $cnt2: $ff $ok\n");
#                    } else {
#                        prt(" $cnt2: [$fil] [$ff] NOT FOUND\n");
#                    }

# 50-51: TARGET [ALL] deps [..\bin\Scintilla.dll ..\bin\SciLexer.dll Lexers.lib .\ScintillaWinS.obj]
# my $app_console_stg  = 'Console Application';
# my $app_windows_stg  = 'Application';
# my $app_dynalib_stg  = 'Dynamic-Link Library';
# my $app_statlib_stg  = 'Static Library';
# my $app_utility_stg  = 'Utility';
sub get_type_from_key($$) {
    my ($key,$rtype) = @_;
    my $type = "Unknown";
    if ($key =~ /\.dll$/i) {
        $type = 'Dynamic-Link Library';
    } elsif ($key =~ /\.so$/i) {
        $type = 'Dynamic-Link Library';
    } elsif ($key =~ /\.lib$/i) {
        $type = 'Static Library';
    } elsif ($key =~ /\.a$/i) {
        $type = 'Static Library';
    } elsif ($key =~ /\.obj$/i) {
        $type = 'Static Library';   # not sure about this
    } elsif ($key =~ /\.exe$/i) {
        $type = 'Application';  # how to know if this or 'Console Application'
    } elsif ( !($key =~ /\./) ) {
        $type = 'Console Application'; # FIX20130501 - choose it is a linux console app
        prtw("WARNING: Choosing a 'Console Application' for key [$key]! CHECK ME!\n");
    } else {
        #pgm_exit(1,"ERROR: Key [$key] NOT TYPED! FIX ME!\n");
        prtw("WARNING: Key [$key] NOT TYPED! FIX ME!\n");
        return 0;
    }
    ${$rtype} = $type;
    return 1;
}

sub get_anon_proj_hash() {
    my %project = ();
    return \%project;
}

my $last_good_find = '';
my $fix_rel_path = 0;   # maybe not a good idea if done here
sub check_c_extensions($$) {
    my ($base,$rsrc) = @_; # $dir.$name,\$src
    my ($ff);
    my $src = $base.".cxx";
    if (-f $src) {
        $ff = $src;
        $ff = File::Spec->rel2abs($src) if ($fix_rel_path);
        ${$rsrc} = $ff;
        $last_good_find = $base;
        prt(" found [$ff] [$src]\n");
        return 1;
    }
    prt(" failed [$src]\n");
    $src = $base.".cpp";
    if (-f $src) {
        $ff = $src;
        $ff = File::Spec->rel2abs($src) if ($fix_rel_path);
        ${$rsrc} = $ff;
        $last_good_find = $base;
        prt(" found [$ff] [$src]\n");
        return 1;
    }
    prt(" failed [$src]\n");
    $src = $base.".cc";
    if (-f $src) {
        $ff = $src;
        $ff = File::Spec->rel2abs($src) if ($fix_rel_path);
        ${$rsrc} = $ff;
        $last_good_find = $base;
        prt(" found [$ff] [$src]\n");
        return 1;
    }
    prt(" failed [$src]\n");
    $src = $base.".c";
    if (-f $src) {
        $ff = $src;
        $ff = File::Spec->rel2abs($src) if ($fix_rel_path);
        ${$rsrc} = $ff;
        $last_good_find = $base;
        prt(" found [$ff] [$src]\n");
        return 1;
    }
    prt(" failed [$src]\n");
    return 0;
}

sub check_h_extensions($$) {
    my ($base,$rsrc) = @_; # $dir.$name,\$src
    my $src = $base.".h";
    my ($ff);
    if (-f $src) {
        $ff = $src;
        $ff = File::Spec->rel2abs($src) if ($fix_rel_path);
        ${$rsrc} = $ff;
        prt(" found [$ff] [$src]\n");
        return 1;
    }
    prt(" failed [$src]\n");
    $src = $base.".hpp";
    if (-f $src) {
        $ff = $src;
        $ff = File::Spec->rel2abs($src) if ($fix_rel_path);
        ${$rsrc} = $ff;
        prt(" found [$ff] [$src]\n");
        return 1;
    }
    prt(" failed [$src]\n");
    $src = $base.".hxx";
    if (-f $src) {
        $ff = $src;
        $ff = File::Spec->rel2abs($src) if ($fix_rel_path);
        ${$rsrc} = $ff;
        prt(" found [$ff] [$src]\n");
        return 1;
    }
    prt(" failed [$src]\n");
    #$src = $base.".c";
    #if (-f $src) {
    #    ${$rsrc} = $src;
    #    $last_good_find = $base;
    #    prt(" found [$src]\n");
    #    return 1;
    #}
    #prt(" failed [$src]\n");
    return 0;
}

sub can_find_source_for_obj($$$) {
    my ($ff,$rsrc,$rhdr) = @_;
    prt("Trying to find source for [$ff]\n");
    my ($name,$dir,$ext) = fileparse($ff, qr/\.[^.]*/);
    my ($src,$hdr);
    if (check_c_extensions($dir.$name,\$src)) {
        ${$rsrc} = $src;
        if (check_h_extensions($dir.$name,\$hdr)) {
            ${$rhdr} = $hdr;
            return 2;
        }
        return 1;
    }
    foreach $dir (keys %valid_source_dirs) {
        if (check_c_extensions($dir.$name,\$src)) {
            ${$rsrc} = $src;
            if (check_h_extensions($dir.$name,\$hdr)) {
                ${$rhdr} = $hdr;
                return 2;
            }
            return 1;
        }
    }
    prt("JUST NOT TO BE FOUND [$name][$ext][$dir]\n");
    return 0;
}


##################################################################################
### stored values
# $targets_deps{$targ} = $deps;
# $targets_acts{$targ} = $act;
# $targets_file{$targ} = $minf;   # Makefile sources - needed for relative dir fixes
##################################################################################
sub sort_target_deps() {
    my $rh  = \%targets_deps;
    my $rhf = \%targets_file;

    my @arr = keys(%{$rh}); # get the TARGET keys
    my $cnt = scalar @arr;
    my ($key,$val,$fil);
    my ($fname,$fdir,$rdh);
    my ($n,$d,$e);
    my ($ff,@arr2,$cnt2,$ra,$ecnt,$ext);
    my ($ok,$rnfa);
    my ($val2,$fil2);
    my ($fil3,@arr3,$cnt3);
    my ($type,$rp,$proj_name);
    my ($res,$hdr2,$tcs,$tch,$minf);
    my $all_key = '';
    my $all_dep = '';
    foreach $key (@arr) {
        $val = ${$rh}{$key};
        if ($key =~ /^all$/i) {
            $all_key = $key;
            $all_dep = $val;
        } elsif ($key =~ /^default$/i) {
            $all_key = $key;
            $all_dep = $val;
        }
    }
    my %not_found = ();
    my %key_not_found = ();
    my %my_src_hash = ();
    my $rsh = \%my_src_hash;
    my %projects_hash = ();
    my $rph = \%projects_hash;
    my ($rsrcs,$rsrch);
    my %done_projects = ();
    my ($tmp1,$tmp2);
    if (length($all_key)) {
        # 50-51: TARGET [ALL] deps [..\bin\Scintilla.dll ..\bin\SciLexer.dll Lexers.lib .\ScintillaWinS.obj]
        prt("\nIn $cnt targets, found 'all:' with deps [$all_dep]\n");
        @arr = space_split($all_dep);   # all: dependency list - ie targets to process
        $cnt = 0;
        # 1: [..\bin\Scintilla.dll] deps [.\AutoComplete.obj .\CallTip.obj .\CellBuffer.obj .\CharacterSet.obj .\CharClassify.obj .\ContractionState.obj .\Decoration.obj .\Document.obj .\Editor.obj .\Indicator.obj .\KeyMap.obj .\LineMarker.obj .\PerLine.obj .\PlatWin.obj .\PositionCache.obj .\PropSetSimple.obj .\RESearch.obj .\RunStyles.obj .\ScintillaBase.obj .\ScintillaWin.obj .\Selection.obj .\Style.obj .\UniConversion.obj .\ViewStyle.obj .\XPM.obj .\AutoComplete.obj .\CallTip.obj .\CellBuffer.obj .\CharacterSet.obj .\CharClassify.obj .\ContractionState.obj .\Decoration.obj .\Document.obj .\Editor.obj .\Indicator.obj .\KeyMap.obj .\LineMarker.obj .\PerLine.obj .\PlatWin.obj .\PositionCache.obj .\PropSetSimple.obj .\RESearch.obj .\RunStyles.obj .\ScintillaBase.obj .\ScintillaWin.obj .\Selection.obj .\Style.obj .\UniConversion.obj .\ViewStyle.obj .\XPM.obj .\BoostRegexSearch.obj .\UTF8DocumentIterator.obj .\ScintRes.res]
        #   1: [.\AutoComplete.obj] [C:\Projects\notepad-plus\scintilla\win32\AutoComplete.obj] NOT FOUND
        foreach $key (@arr) {
            $cnt++;
            if (length($user_type)) {
                $type = $user_type;
            } else {
                next if (!get_type_from_key($key,\$type));
            }
            $rp = get_anon_proj_hash();
            ($proj_name,$d,$e) = fileparse($key, qr/\.[^.]*/);
            $tmp1 = $proj_name;
            $tmp2 = 0;
            while (defined $done_projects{$proj_name}) {
                $tmp2++;
                $proj_name = $tmp1.$tmp2;
            }
            $done_projects{$proj_name} = 1;
            ${$rp}{'PROJECT_TYPE'} = $type;
    		${$rp}{'PROJECT_KEY'} = $key;
            ${$rp}{'PROJECT_NAME'} = $proj_name; # != $key
            $val = "Target NOT FOUND";
            my %dupes = ();
            my @c_files = ();
            my @h_files = ();
            my @srcs = ();
            ${$rp}{'PROJECT_SOURCES'} = \@srcs;  # source
            ${$rp}{'PROJECT_C_SRCS'} = \@c_files;
            ${$rp}{'PROJECT_H_SRCS'} = \@h_files;
            ${$rp}{'MAKEFILE_INPUT'} = $minf;
            ${$rph}{$proj_name} = $rp;  # STORE PROJECT
            ${$rsh}{$proj_name} = \@srcs;
            if (defined ${$rh}{$key}) {
                $val  = ${$rh}{$key};
                $minf = ${$rhf}{$key};   # get the Makefile source, for rel dir fixes
                ($fname,$fdir) = fileparse($minf);  # get its directory
                $ff = File::Spec->rel2abs($fdir.$key);
                @arr2 = space_split($val);
                $cnt2 = scalar @arr2;
                prt("$cnt: [$key] deps $cnt2 [$val]\n") if (VERB2());
                # 251-252: Target [.\AutoComplete.obj] deps [../src/AutoComplete.cxx ../include/Platform.h ../src/AutoComplete.h]
                # 241-243: Target [.\ScintillaWinS.obj] deps [ScintillaWin.cxx]
                $cnt2 = 0;
                #######################################################
                # process the SOURCES
                #######################################################
                foreach $fil (@arr2) {
                    $cnt2++;
                    $ff = File::Spec->rel2abs($fdir.$fil);
                    $ok = "TARGET NOT FOUND!";
                    if (defined ${$rh}{$fil}) {
                        $val2 = ${$rh}{$fil}; # this could/should be the sources for this target
                        $fil2 = ${$rhf}{$fil}; # and the source makefile it was in...
                        ($fname,$fdir) = fileparse($fil2);
                        @arr3 = space_split($val2);
                        $cnt3 = 0;
                        foreach $fil3 (@arr3) {
                            $cnt3++;
                            $ff = File::Spec->rel2abs($fdir.$fil3);
                            $ok = "NF";
                            ### $ok = (-f $ff) ? "ok" : "NF";
                            if (-f $ff) {
                                $ok = "ok";
                                # NO - this adds header directories as well
                                # add_to_valid_source_dirs($ff);
                            }
                            prt(" $cnt2:$cnt3: targ [$fil] source $ff $ok ($fil3)\n") if (VERB2());
                            if (defined $dupes{$ff}) {
                                if (is_c_source($fil3)) {
                                    prtw("WARNING:$proj_name: Duplicate SOURCE of [$ff] avoided!\n");
                                } elsif (is_h_source($fil3)) {
                                    prt("$proj_name: Duplicate HEADER of [$ff] avoided!\n") if (VERB9() && $debug_extra);
                                    ###prtw("WARNING:$proj_name: Duplicate HEADER of [$ff] avoided!\n") if (VERB9());
                                }
                            } else {
                                if (is_c_source($fil3)) {
                                    if ($prefix_rel_file) {
                                        push(@c_files,$fil3);
                                    } else {
                                        push(@c_files,$ff);
                                    }
                                    add_to_valid_source_dirs($ff) if ($ok eq 'ok');
                                } elsif (is_h_source($fil3)) {
                                    if ($prefix_rel_file) {
                                        push(@h_files,$fil3);
                                    } else {
                                        push(@h_files,$ff);
                                    }
                                }
                                if ($prefix_rel_file) {
                                    push(@srcs,$fil3);
                                } else {
                                    push(@srcs,$ff);
                                }
                                $dupes{$ff} = 1;
                            }
                        }
                    } elsif (is_c_source_extended($fil) && (-f $ff)) {
                        # this is the SOURCE
                        prt(" $cnt2:$cnt3: C/C++ src [$fil] [$ff] OK\n") if (VERB5());
                        if (defined $dupes{$ff}) {
                            prtw("WARNING:$proj_name: Duplicate source name of [$ff] avoided!\n");
                        } else {
                            if ($prefix_rel_file) {
                                push(@c_files,$fil);
                                push(@srcs,$fil);
                            } else {
                                push(@c_files,$ff);
                                push(@srcs,$ff);
                            }
                            $dupes{$ff} = 1;
                        }
                    } elsif (is_h_source($fil) && (-f $ff)) {
                        prt(" $cnt2:$cnt3: HEADER file [$fil] [$ff] OK\n") if (VERB5());
                        if (defined $dupes{$ff}) {
                            prtw("WARNING:$proj_name: Duplicate header of [$ff] avoided!\n") if (VERB9());
                        } else {
                            if ($prefix_rel_file) {
                                push(@h_files,$fil);
                                push(@srcs,$fil);
                            } else {
                                push(@h_files,$ff);
                                push(@srcs,$ff);
                            }
                            $dupes{$ff} = 1;
                        }
                    } elsif (($fil =~ /\.rc$/i) && (-f $ff)) {
                        prt(" $cnt2:$cnt3: RES file [$fil] [$ff] OK\n");
                        if (defined $dupes{$ff}) {
                            prtw("WARNING:$proj_name: Duplicate RES of [$ff] avoided!\n");
                        } else {
                            if ($prefix_rel_file) {
                                push(@c_files,$fil);
                                push(@srcs,$fil);
                            } else {
                                push(@c_files,$ff);
                                push(@srcs,$ff);
                            }
                            $dupes{$ff} = 1;
                        }
                    } elsif (-f $ff) {
                        prt(" $cnt2:$cnt3: OTHER file [$fil] [$ff] OK\n");
                        if (defined $dupes{$ff}) {
                            prtw("WARNING:$proj_name: Duplicate OTHER of [$ff] avoided!\n");
                        } else {
                            if ($prefix_rel_file) {
                                push(@srcs,$fil);
                            } else {
                                push(@srcs,$ff);
                            }
                            $dupes{$ff} = 1;
                        }
                    } else {
                        if ($ff =~ /\$/) {
                            $res = 0;
                        } else {
                            $res = can_find_source_for_obj($ff,\$fil2,\$hdr2);
                        }
                        if ($res) {
                            if (defined $dupes{$fil2}) {
                                prtw("WARNING:$proj_name: Duplicate source name of [$fil2] avoided!\n");
                            } else {
                                push(@c_files,$fil2);
                                push(@srcs,$fil2);
                                $dupes{$fil2} = 1;
                                $tcs = scalar @c_files;
                                if ($res == 2) {
                                    if (defined $dupes{$hdr2}) {
                                        prtw("WARNING:$proj_name: Duplicate header of [$hdr2] avoided!\n") if (VERB9());
                                    } else {
                                        push(@h_files,$hdr2);
                                        $tch = scalar @h_files;
                                        push(@srcs,$hdr2);
                                        $dupes{$hdr2} = 1;
                                        prt("$proj_name: Added src [$fil2]$tcs hdr [$hdr2]$tch\n");
                                    }
                                } else {
                                    prt("$proj_name: Added src [$fil2]$tcs\n");
                                }
                            }
                        } else {
                             if ( !($ff =~ /\$/) ) {
                                   $not_found{$fil} = [] if (!defined $not_found{$fil});
                                $rnfa = $not_found{$fil};
                                # save a NOT found file, for later searching
                                push(@{$rnfa},[$proj_name,$ff,$rp,$cnt2,$cnt3,$fdir,\%dupes]);
                             }
                        }
                    }
                }
                $tcs = scalar @c_files;
                # $rsrch = ${$rp}{'PROJECT_H_SRCS'}; # = \@h_files;
                $tch = scalar @h_files;
                prt("PROJ:1: $proj_name: SRCS $tcs HDRS $tch\n");
                ${$rp}{'PROJECT_SOURCES'} = \@srcs;  # source
                ${$rp}{'PROJECT_C_SRCS'}  = \@c_files;
                ${$rp}{'PROJECT_H_SRCS'}  = \@h_files;
                ${$rp}{'MAKEFILE_INPUT'}  = $minf;  # Makefile source, for rel dir fixes
                ${$rph}{$proj_name}    = $rp;   # STORE THE PROJECT
            } else {
                if (!defined $not_found{$key}) {
                    $key_not_found{$key} = 1;
                    prtw("WARNING:$cnt: [$key] deps [$val]\n");
                }
            }
        }

        # see if we can FIND missing source
        foreach $fil (keys %not_found) {
            $rnfa = $not_found{$fil};
            $cnt = scalar @{$rnfa};
            my ($i,$rdups);
            #push(@{$rnfa},[$proj_name,$ff,$rp,$cnt2,$cnt3,$fdir,\%dupes]);
            #               0          1   2   3     4     5     6
            for ($i = 0; $i < $cnt; $i++) {
                $proj_name = ${$rnfa}[$i][0];
                $ff        = ${$rnfa}[$i][1];
                $rp        = ${$rnfa}[$i][2];
                $cnt2      = ${$rnfa}[$i][3];
                $cnt3      = ${$rnfa}[$i][4];
                $fdir      = ${$rnfa}[$i][5];
                $rdups     = ${$rnfa}[$i][6];
                $res = can_find_source_for_obj($ff,\$fil2,\$hdr2);
                if ($res) {
                    if (defined ${$rdups}{$fil2}) {
                        prt(" $cnt2:$cnt3: $proj_name for targ [$fil] FOUND source [$fil2] but DUPLICATE\n"); # if (VERB2());
                    } else {
                        # now need to ADD source to appropriate arrays - only check for C/C++ sources, and H, so...
                        ${$rdups}{$fil2} = 1;
                        $rsrcs = ${$rp}{'PROJECT_SOURCES'};  # source
                        push(@{$rsrcs},$fil2);
                        $rsrcs = ${$rp}{'PROJECT_C_SRCS'}; # = \@c_files;
                        push(@{$rsrcs},$fil2);
                        $tcs = scalar @{$rsrcs};
                        if ($res == 2) {
                            $rsrch = ${$rp}{'PROJECT_H_SRCS'}; # = \@h_files;
                            push(@{$rsrch},$hdr2);
                            $tch = scalar @{$rsrch};
                            prt(" $cnt2:$cnt3: $proj_name for targ [$fil] FOUND sce [$fil2]$tcs hdr [$hdr2]$tch ok\n"); # if (VERB2());
                        } else {
                            prt(" $cnt2:$cnt3: $proj_name for targ [$fil] FOUND source [$fil2]$tcs ok\n"); # if (VERB2());
                        }
                    }
                } else {
                    prtw("WARNING:$cnt2: proj $proj_name targ [$fil] ff [$ff] TARGET NOT FOUND!\n");
                }
            }
        }
        #if ((!defined ${$rh}{$fil}) && ($ff =~ /\.obj$/i) && can_find_source_for_obj($ff,\$fil2)) {
        #    my ($n2,$d2) = fileparse($fil2);
        #    ${$rh}{$fil} = $n2;
        #    ${$rhf}{$fil} = $d2."dummy";
        #    prt(" $cnt2:$cnt3: for targ [$fil] FOUND source [$fil2] ok\n") if (VERB2());
        #}

    } else {
        prt("In $cnt targets, NO find of 'all:'!\n");
    }

    ${$rparams}{'REF_SOURCES_HASH'}  = $rsh; # store sources/proj_name hash
    ${$rparams}{'REF_PROJECTS_HASH'} = $rph; # store projects/proj_name hash
    $tmp1 = 0;
    foreach $proj_name (keys %{$rph}) {
        $tmp1++;
        $rp = ${$rph}{$proj_name};
        $rsrcs = ${$rp}{'PROJECT_C_SRCS'}; # = \@c_files;
        $tcs = scalar @{$rsrcs};
        $rsrch = ${$rp}{'PROJECT_H_SRCS'}; # = \@h_files;
        $tch = scalar @{$rsrch};
        prt("$tmp1: PROJ:2: $proj_name: SRCS $tcs HDRS $tch\n");
    }
}

#########################################################
### sub_targ_dir() - started out as just subtracting the target,
### but that only works if the makefile is in the target.
###
### The source in a makefile is relative to that makefile
### So you have F:\Projects\scintilla\win32\scintilla.mak
### SOURCES can be local files, like 'ScintRes.rc'
### Or relative files, like '..\src\ScintillaBase.cxx'
###
### The user has given a TARGET directory, or one was 'assumed'...
### like say '-t ..', which is (now) converted to absolute path,
### like F:\Projects\scintilla
###
### The trick is to MOVE say -
### 'ScintRes.rc' to 'Win32\ScintRes.rc', and
### '..\src\ScintillaBase.cxx' to 'src\ScintillaBase.cxx'
###
### my $prefix_rel_file = 0;   # try to PRE-fix rel file name - BUT NEEDS MORE WORK
###
##########################################################
sub sub_targ_dir($$) {
    my ($src,$minf) = @_;
    my ($inf,$idir) = fileparse($minf);
    my $ff = $src;
    if ($prefix_rel_file) {
        $ff = $idir.$src;
        $ff = fix_rel_path($ff) if ($src =~ /\.\./);
    }
    my ($name,$curr_dir) = fileparse($ff);
    # what I need is a relative path for $curr_dir to $target_dir
    my $rel_dir = get_relative_path($curr_dir,$target_dir);
    my $res = $rel_dir.$name;
    if ($debug_rel_fix) {
        if ($prefix_rel_file) {
            prt("For src '$src', ff $ff, targ $target_dir, got rel '$res'\n");
        } else {
            prt("For src '$src', targ $target_dir, got rel '$res'\n");
        }
    }
    return $res;
}

sub sub_targ_dir_TOO_SIMPLE($) {
    my $src = shift;
    my $len = length($target_dir);
    return substr($src,$len+1);
}

sub accumulate_incs($$) {
    my ($rh,$fil) = @_;
    my ($n,$d) = fileparse($fil);
    $d =~ s/(\\|\/)$//;
    ${$rh}{$d} = 1;
}

sub get_def_block {
    my $txt = <<EOF;

if(CMAKE_COMPILER_IS_GNUCXX)
    set( WARNING_FLAGS -Wall )
endif(CMAKE_COMPILER_IS_GNUCXX)

if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang") 
   set( WARNING_FLAGS "-Wall -Wno-overloaded-virtual" )
endif() 

if(WIN32)
    if(MSVC)
        # turn off various warnings
        set(WARNING_FLAGS "\${WARNING_FLAGS} /wd4996")
        # foreach(warning 4244 4251 4267 4275 4290 4786 4305)
        #     set(WARNING_FLAGS "\${WARNING_FLAGS} /wd\${warning}")
        # endforeach(warning)

        set( MSVC_FLAGS "-DNOMINMAX -D_USE_MATH_DEFINES -D_CRT_SECURE_NO_WARNINGS -D_SCL_SECURE_NO_WARNINGS -D__CRT_NONSTDC_NO_WARNINGS" )
        # if (\${MSVC_VERSION} EQUAL 1600)
        #    set( MSVC_LD_FLAGS "/FORCE:MULTIPLE" )
        # endif (\${MSVC_VERSION} EQUAL 1600)
        # distinguish between debug and release libraries
        set( CMAKE_DEBUG_POSTFIX "d" )
    endif(MSVC)
    set( NOMINMAX 1 )
endif(WIN32)

set( CMAKE_C_FLAGS "\${CMAKE_C_FLAGS} \${WARNING_FLAGS} \${MSVC_FLAGS} -D_REENTRANT" )
set( CMAKE_CXX_FLAGS "\${CMAKE_CXX_FLAGS} \${WARNING_FLAGS} \${MSVC_FLAGS} -D_REENTRANT" )
set( CMAKE_EXE_LINKER_FLAGS "\${CMAKE_EXE_LINKER_FLAGS} \${MSVC_LD_FLAGS}" )

add_definitions( -DHAVE_CONFIG_H )

if(BUILD_SHARED_LIB)
   set(LIB_TYPE SHARED)
   message(STATUS "*** Building DLL library \${LIB_TYPE}")
else(BUILD_SHARED_LIB)
   message(STATUS "*** Building static library \${LIB_TYPE}")
endif(BUILD_SHARED_LIB)

EOF
    return $txt;
}

sub add_opt_block($) {
    my $type = shift;
    my $txt = <<EOF;

# Allow developer to select is Dynamic or static library built
set( LIB_TYPE STATIC )  # set default static
option( BUILD_SHARED_LIB "Build Shared Library" $type )

EOF
    return $txt;
}


sub enumerate_project_hashes() {
    my $rsh = ${$rparams}{'REF_SOURCES_HASH'}; # store sources/proj_name hash
    my $rph = ${$rparams}{'REF_PROJECTS_HASH'}; # store projects/proj_name hash
    my ($pn,$rsa,$cnt,$rp,$type,$rca,$rha,$ccnt,$hcnt,$ocnt);
    my ($src,$var1,$var2,@arr,$mod,$tmp,$minf);
    $cnt = scalar keys(%{$rph});
    my $proj_name = $project_name;
    prt("Enumeration of $cnt projects... target dir $target_dir\n");
    my $cmake = '';
    my %inc_dirs = ();
    my @libs = ();
    my @bins = ();
    my $hdrlist = '';
    my $ind = '   ';

    # pass one - ADD LIBRARIES
    # ========================
    foreach $pn (keys %{$rph}) {
        $rp  = ${$rph}{$pn};
        $type = ${$rp}{'PROJECT_TYPE'};
        if ( !(($type eq 'Dynamic-Link Library') || ($type eq 'Static Library')) ) {
            next;
        }
        $rsa = ${$rsh}{$pn};
        $cnt = scalar @{$rsa};
        $rca = ${$rp}{'PROJECT_C_SRCS'};    # = \@c_files;
        $rha = ${$rp}{'PROJECT_H_SRCS'};    # = \@h_files;
        $minf = ${$rp}{'MAKEFILE_INPUT'};
        $ccnt = scalar @{$rca};
        $hcnt = scalar @{$rha};
        $ocnt = $cnt - ($ccnt + $hcnt);
        prt("Project: [$pn], type $type, with $cnt sources, $ccnt C/C++, $hcnt Hdrs, $ocnt O.\n");
        $cmake .= "\n# Project: [$pn], type $type, with $cnt sources, $ccnt C/C++, $hcnt Hdrs, $ocnt O.\n";
        #if ($type eq 'Dynamic-Link Library') {
        #} elsif ($type eq 'Static Library') {
        #} elsif ($type eq 'Application') {
        #} else {
        #    prtw("WARNING: Project [$pn] has type [$type] NOT HANDLED!\n");
        #    next;
        #}
        $var1 = '';
        $var2 = '';
        if ($ccnt) {
            $var1 = $pn."_SRCS";
            $cmake .= "set( $var1\n";
            foreach $src (sort @{$rca}) {
                $src = sub_targ_dir($src,$minf);
                $src = path_d2u($src);
                $cmake .= "   $src\n";
            }
            $cmake =~ s/\n$//;
            $cmake .= " )\n";
            if ($hcnt) {
                $var2 = $pn."_HDRS";
                $cmake .= "set( $var2\n";
                foreach $src (sort @{$rha}) {
                    $src = sub_targ_dir($src,$minf);
                    $src = path_d2u($src);
                    $cmake .= "   $src\n";
                    accumulate_incs(\%inc_dirs,$src);
                    $hdrlist .= " $src";
                }
                $cmake =~ s/\n$//;
                $cmake .= " )\n";
                $cmake .= "list (APPEND inst_HDRS \${$var2})\n";
            }

        } else {
            prtw("WARNING: Project [$pn] NO SOURCES!\n");
            next;
        }
        $cmake .= "add_library( $pn ";
        #if ($type eq 'Dynamic-Link Library') {
        #    $cmake .= 'SHARED';
        #} else {
        #    $cmake .= 'STATIC';
        #}
        $cmake .= "\${LIB_TYPE}";
        $cmake .= "\n";
        $cmake .= "      \${$var1}\n";
        if (length($var2)) {
            $cmake .= "      \${$var2}\n";
        }
        $cmake =~ s/\n$//;
        $cmake .= " )\n";
        $cmake .= "list (APPEND add_LIBS $pn )\n";
        $cmake .= "list (APPEND inst_LIBS $pn )\n";
        push(@libs,$pn);
    }

    # pass two - Add EXECUTABLES
    # ==========================
    foreach $pn (keys %{$rph}) {
        $rp  = ${$rph}{$pn};
        $type = ${$rp}{'PROJECT_TYPE'};
        if (($type eq 'Dynamic-Link Library') || ($type eq 'Static Library')) {
            next;
        }
        $rsa = ${$rsh}{$pn};
        $cnt = scalar @{$rsa};
        $rca = ${$rp}{'PROJECT_C_SRCS'};    # = \@c_files;
        $rha = ${$rp}{'PROJECT_H_SRCS'};    # = \@h_files;
        $minf = ${$rp}{'MAKEFILE_INPUT'};
        $ccnt = scalar @{$rca};
        $hcnt = scalar @{$rha};
        $ocnt = $cnt - ($ccnt + $hcnt);
        prt("Project: [$pn], type $type, with $cnt sources, $ccnt C/C++, $hcnt Hdrs, $ocnt O.\n");
        $cmake .= "\n# Project: [$pn], type $type, with $cnt sources, $ccnt C/C++, $hcnt Hdrs, $ocnt O.\n";
        if ($type eq 'Console Application') {
            $mod = '';
        } elsif ($type eq 'Application') {
            $mod = 'WIN32'
        } else {
            prtw("WARNING: Project [$pn] has type [$type] NOT HANDLED!\n");
            next;
        }
        $var1 = '';
        $var2 = '';
        if ($ccnt) {
            $var1 = $pn."_SRCS";
            $cmake .= "set( $var1\n";
            foreach $src (sort @{$rca}) {
                $src = sub_targ_dir($src,$minf);
                $src = path_d2u($src);
                $cmake .= "   $src\n";
            }
            $cmake =~ s/\n$//;
            $cmake .= " )\n";
            if ($hcnt) {
                $var2 = $pn."_HDRS";
                $cmake .= "set( $var2\n";
                foreach $src (sort @{$rha}) {
                    $src = sub_targ_dir($src,$minf);
                    $src = path_d2u($src);
                    $cmake .= "   $src\n";
                    accumulate_incs(\%inc_dirs,$src);
                }
                $cmake =~ s/\n$//;
                $cmake .= " )\n";
            }
        } else {
            prtw("WARNING: Project [$pn] NO SOURCES!\n");
            next;
        }
        $cmake .= "add_executable( $pn $mod\n";
        $cmake .= "      \${$var1}\n";
        if (length($var2)) {
            $cmake .= "      \${$var2}\n";
        }
        $cmake =~ s/\n$//;
        $cmake .= " )\n";
        $cmake .= "if (WIN32)\n";
        $cmake .= "    set_target_properties( $pn PROPERTIES DEBUG_POSTFIX d )\n";
        $cmake .= "endif (WIN32)\n";
        if (@libs) {
            $cmake .= "target_link_libraries ( $pn \${add_LIBS} )\n";
        }
        $cmake .= "list (APPEND inst_BINS $pn)\n";
        push(@bins,$pn);
    }

    # INSTALLATION
    $cmake .= "\n# deal with INSTALL\n";
    $cmake .= "# install(TARGETS \${inst_LIBS} DESTINATION lib)\n" if (@libs);
    $cmake .= "# install(FILES \${inst_HDRS} DESTINATION include)\n" if (length($hdrlist));
    $cmake .= "# install(TARGETS \${inst_BINS} DESTINATION bin)\n" if (@bins);

    @arr = sort keys %inc_dirs;
    if (@arr) {
        ###$var1 = "include_directories( SYSTEM ".join(" ",@arr)." )\n\n";
        $var1 = "include_directories( ".join(" ",@arr)." )\n\n";
        $cmake = $var1.$cmake;
    }
    $var1 = "# CMakeLists.txt generated ".lu_get_YYYYMMDD_hhmmss(time())."\n";
    $var1 .= "# by $pgmname from $in_file\n\n";
    $var1 .= "cmake_minimum_required (VERSION 2.8.8)\n\n";
    $var1 .= "project ($proj_name)\n\n";
    $ind = '';
    if (length($project_version)) {
        $var1 .= "# ### NOTE: *** CHECK ME ***\n";
        @arr = split(/\./,$project_version);
        $tmp = scalar @arr;
        $ver_major = $arr[0];
        $ver_minor = (($tmp > 1) ? $arr[1] : 0);
        $ver_point = (($tmp > 2) ? $arr[2] : 0);
    } else {
        $var1 .= "# ### NOTE: *** FIX ME ***\n";
        $ind = '#';
    }
    $var1 .= $ind."set( ${proj_name}_VERSION_MAJOR $ver_major )\n";
    $var1 .= $ind."set( ${proj_name}_VERSION_MINOR $ver_minor )\n";
    $var1 .= $ind."set( ${proj_name}_VERSION_POINT $ver_point )\n\n";
    if (($user_name == 1) && ($target_ver == 1)) {
        $var1 .= "# add_definitions( -DVERSION=\"\${${proj_name}_VERSION_MAJOR}.\${${proj_name}_VERSION_MINOR}.\${${proj_name}_VERSION_POINT}\")\n";
    }
    $var1 .= add_opt_block("OFF");
    $var1 .= get_def_block();

    $cmake = $var1.$cmake."\n# eof\n";
    if (length($out_file) == 0) {
        $out_file = $def_out_file;
        prt("Set DEFAULT out file to [$out_file]. Use -o file to set output.\n");
    }

    rename_2_old_bak($out_file) if (-f $out_file);
    write2file($cmake,$out_file);
    $final_msg .= "cmake output written to [$out_file]\n"; 
    prt("cmake output written to [$out_file]\n");

}

#########################################
### MAIN ###
parse_args(@ARGV);
process_in_file($in_file);
sort_target_deps();
enumerate_project_hashes();
###write_project_cmake_files($rparams);
pgm_exit(0,"");
########################################

sub need_arg {
    my ($arg,@av) = @_;
    pgm_exit(1,"ERROR: [$arg] must have a following argument!\n") if (!@av);
}

sub parse_args {
    my (@av) = @_;
    my ($arg,$sarg);
    my $got_par = 0;
    while (@av) {
        $arg = $av[0];
        if ($arg =~ /^-/) {
            $sarg = substr($arg,1);
            $sarg = substr($sarg,1) while ($sarg =~ /^-/);
            if (($sarg =~ /^h/i)||($sarg eq '?')) {
                give_help();
                pgm_exit(0,"Help exit(0)");
            } elsif ($sarg =~ /^a/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                if ($sarg eq 'C') {
                    $user_type = 'Console Application';
                } elsif ($sarg eq 'A') {
                    $user_type = 'Application';
                } elsif ($sarg eq 'D') {
                    $user_type = 'Dynamic-Link Library';
                } elsif ($sarg = 'S') {
                    $user_type = 'Static Library';
                } else {
                    pgm_exit(1,"ERROR: $arg can only be followed by C|A|D|S, NOT $sarg!\n");
                }
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
            } elsif ($sarg =~ /^V/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                #set_project_version($sarg);
                $project_version = $sarg;
            } elsif ($sarg =~ /^l/) {
                if ($sarg =~ /^ll/) {
                    $load_log = 2;
                } else {
                    $load_log = 1;
                }
                prt("Set to load log at end. ($load_log)\n") if (VERB1());
            } elsif ($sarg =~ /^n/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $project_name = $sarg;
                prt("Set project name to [$project_name].\n") if (VERB1());
                $user_name = 1;
            } elsif ($sarg =~ /^o/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_file = $sarg;
                prt("Set out file to [$out_file].\n") if (VERB1());
            } elsif ($sarg =~ /^t/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                #$target_dir = $sarg;
                $target_dir = File::Spec->rel2abs($sarg);
                pgm_exit(1,"ERROR: Target directory [$target_dir] DOES NOT EXIST!\n") if ( ! -d $target_dir);
                prt("Set user target directory to [$target_dir].\n") if (VERB1());
                if ($target_dir =~ /(\d+)\.(\d+)\.(\d+)/) {
                    $ver_major = $1;
                    $ver_minor = $2;
                    $ver_point = $3;
                    $target_ver = 1;
                }
                $user_targ_dir = 1;
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            $in_file = File::Spec->rel2abs($arg);
            prt("Set input to [$in_file]\n") if (VERB1());

        }
        shift @av;
    }

    if ($debug_on) {
        prtw("WARNING: DEBUG is ON!\n");
        if (length($in_file) ==  0) {
            $in_file = File::Spec->rel2abs($def_file);
            prt("DBG: Set DEFAULT input to [$in_file]\n");
            $load_log = 2;
            $verbosity = 9;
        }
        if ((length($target_dir) == 0) && length($def_targ_dir)) {
            $target_dir = $def_targ_dir;
            prt("DBG: Set DEFAULT target directory to [$target_dir]\n");
        }

        if ((length($out_file) == 0) && length($def_out_file)) {
            $out_file = $def_out_file;
            prt("DBG: Set DEFAULT out file to [$out_file]\n");
        }
        if ((length($project_name) == 0) && length($def_proj_name)) {
            $project_name = $def_proj_name;
            prt("DBG: Set DEFAULT project name to [$project_name]\n");
        }
        if ((length($user_type) == 0) && length($def_usr_type)) {
            $user_type = $def_usr_type;
            prt("DBG: Set DEFAULT project type to [$user_type]\n");
        }
    }

    if (length($in_file) ==  0) {
        give_help();
        pgm_exit(1,"\nERROR: No input files found in command!\n");
    }
    if (! -f $in_file) {
        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
    }
    ($root_name,$root_dir) = fileparse($in_file);
    $rparams = init_common_subs($in_file) if (!$got_par); # note: sets ROOT_FOLDER - where a CMakeLists.txt could be written

    if (length($project_name) == 0) {
        ($project_name,$arg,$sarg) = fileparse($in_file, qr/\.[^.]*/ );
        prt("Set project name [$project_name] from input file.\n");
    }

    if (length($target_dir) == 0) {
        $target_dir = $cwd;
        prt("Set 'target' directory to CWD [$target_dir]\n");
    }

    fill_valid_source_dirs($target_dir,0) if ($user_targ_dir);

    ut_fix_directory(\$target_dir);
    if (length($target_dir)) {
        ${$rparams}{'ROOT_FOLDER'} = $target_dir;   # store the TARGET DIRECTORY, to fix rel dir
    } else {
        $target_dir = ${$rparams}{'ROOT_FOLDER'};
    }
    
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-file\n");
    prt("Options:\n");
    prt(" --help  (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]     (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --VER <num>   (-V) = Set Version number. Use form n[.n[.n]]\n");
    prt(" --app [CADS]  (-a) = Set app type Console, Application, DLL, Static library.\n");
    prt(" --load        (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>  (-o) = Write output to this file.\n");
    prt(" --name <name> (-n) = Set project name.\n");
    prt(" --targ <dir>  (-t) = Target directory for CMakeLists.txt file. Default to CWD\n");
    prt("\n");
    prt(" Given an nmake 'makefile' try to generatet the equivalent cmake CMakeLists.txt\n");
    prt(" Note, not given a target directory the current $cwd will be assumed.\n");
}

# eof - make2cmake.pl
