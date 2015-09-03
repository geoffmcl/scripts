#!/usr/bin/perl -w

##########################################
### PARAM INIT ###
our ($try_much_harder, $try_harder, $exit_value, $warn_on_plus, $ignore_EXTRA_DIST,
    $add_rel_sources, $process_subdir, $auto_on_flag, $added_in_init, $fix_relative_sources,
    $target_dir, $supp_make_in, $project_name,
    %g_user_subs, %g_user_condits );

my %g_params_hash = ();
sub get_ref_params() { return \%g_params_hash; }

my %g_defs_not_found = ();
my %g_subs_not_found = ();

my %g_global_hash = (
    'base_LIBS'  => "",
    'opengl_LIBS' => "",
    'network_LIBS' => "",
    'joystick_LIBS' => "",
    'thread_LIBS' => "",
    'openal_LIBS' => "",
    'RELOCATABLE_LDFLAGS' => "",
    'LIBTOOL' => "lib",
    'BISON_LOCALEDIR' => "",
    'AM_LIBTOOLFLAGS' => "",
    'AM_CFLAGS' => "",
    'OPENMP_CFLAGS' => "",
    'gl_LIBOBJS' => "glu32.lib"
);

# some exception warnings suppressed
my %g_sources_exceptions = (
  'DOXSOURCES' => 1
  );

my @common_set = qw( LIBS LDFLAGS CPPFLAGS CXXFLAGS CPPFLAGS CXXLDFLAGS CFLAGS CFLAGS_FOR_BUILD X_CFLAGS AR_FLAGS );
my @common_dir_set = qw( top_srcdir bindir BASE_DIR BUILD_DIR DATA_DIR datadir DESTDIR dir DIRNAME 
 docdir INCLUDE_DIR  includedir libdir libdocdir localedir mandir objdir pkgdatadir srcdir tardir top_builddir top_srcdir
 X_EXTRA_LIBS x_includes x_libraries X_LIBS X_PRE_LIBS X11_LIB );

my $curr_prefix = ".\\";
my %known_set = (
 'AM_CFLAGS' => '',
 'AR' => 'ar',
 'AWK' => 'awk',
 'BUILD_EXEEXT' => 'exe',
 'BUILD_OBJEXT' => 'obj',
 'CC' => 'cl',
 'CCC' => 'cl',
 'CC_FOR_BUILD' => 'cl',
 'CXX' => 'cl',
 'CXX_FOR_BUILD' => 'cl',
 'CPP' => 'cl',
 'ECHO' => 'echo',
 'EXEEXT' => 'exe',
 'GCC' => 'gcc',
 'OBJEXT' => 'obj',
 'ac_default_prefix' => $curr_prefix,
 'exec_prefix' => $curr_prefix,
 'host' => 'WIN32',
 'host_cpu' => 'X86',
 'host_os' => 'Windows',
 'host_vendor' => 'MS',
 'LIB_TOOL' => 'link',
 'LIBTOOL' => 'link',
 'LINK' => 'link',
 'MAKE' => 'nmake',
 'NEWLINE' => "\n",
 'NULL' => "",
 'POSIX_SHELL' => 'sh',
 'prefix' => $curr_prefix,
 'PATH_SEPARATOR' => "\\",
 'PERL' => 'perl',
 'PYTHON' => 'python',
 'RM' => 'del',
 'SHELL' => 'sh',
 'SED' => 'sed',
 'YASM' => 'yasm',
 'RC' => 'rc'       # add 20150903
 );

my @others_maybe = qw( enableval );

###my $added_in_init = '';

sub eliminate_dupes($) {
    my $txt = shift;
    my $len = length($txt);
    my %dupes = ();
    my @arr = ();
    my ($i,$ch,$bgn,$item,$ntxt);
    $ntxt = '';
    for ($i = 0; $i < $len; $i++) {
        $ch = substr($txt,$i,1);
        if (($ch eq '/') || ($ch eq '-')) {
            $bgn = $ch;
            $i++;
            if ($i < $len) {
                $ch = substr($txt,$i,1);
                $bgn .= $ch;
                $i++;
                $ch = '';
                for (; $i < $len; $i++) {
                    $ch = substr($txt,$i,1);
                    last if ($ch =~ /\S/);
                }
                $item = '';
                for (; $i < $len; $i++) {
                    $ch = substr($txt,$i,1);
                    last if ($ch =~ /\s/);
                    $item .= $ch;
                }
                if (length($item)) {
                    if ( ! defined $dupes{$item}) {
                        $dupes{$item} = $bgn;
                        push(@arr,$item);
                    } 
                }
                $ch = '';
            }
        } else {
            $ntxt .= $ch;
        }
    }
    $ntxt = trim_all($ntxt);
    # foreach $item (keys %dupes) but this loses the order, so use
    foreach $item (@arr) {
        $bgn = $dupes{$item};
        $ntxt .= ' ' if (length($ntxt));
        $ntxt .= "$bgn $item";
    }
    return $ntxt;
}

# some common things - used often, so set to a blank
# set some to current in_file directory,
# and some to known values...

sub add_key_2_added($) {
    my $key = shift;
    $added_in_init .= " " if (length($added_in_init));
    $added_in_init .= $key;
}

sub init_common_subs2($$) {
    my ($rh,$add) = @_;  # = \%common_subs
    my ($key,$rd,$val);
    $rd = get_root_dir();
    # prt("Init using common directory [$rd]\n");
    # like 'srcdir'
    foreach $key (@common_dir_set) {
        if (!defined ${$rh}{$key}) {
            ${$rh}{$key} = $rd;
            add_key_2_added($key) if ($add);
        }
    }
    foreach $key (@common_set) {
        if (!defined ${$rh}{$key}) {
            ${$rh}{$key} = '';
            add_key_2_added($key) if ($add);
        }
    }
    # like 'CC', 'EXEEXT', ...
    foreach $key (keys %known_set) {
        if (!defined ${$rh}{$key}) {
            $val = $known_set{$key};
            ${$rh}{$key} = $val;
            add_key_2_added($key) if ($add);
        }
    }
}

sub gen_param_check($) {
    my ($rparams) = @_;
    my ($key,$msg,$line);
    $msg = '';
    $line = ' ';
    foreach $key (keys %{$rparams}) {
        $line .= "$key ";
        if (length($line) > 80) {
            $msg .= $line."\n";
            $line = ' ';
        }
    }
    if (length($line)) {
       $msg .= $line."\n";
    }
    $msg = "my \@par_list = qw(\n$msg\n );\n";
    write2file($msg,'templist.txt');
    exit(1);
}

sub validate_ref_param($) {
    my ($rparam) = @_;
    my @par_list = qw(
 REF_EXIT_VALUE TRY_MUCH_HARDER REF_SRC_EXCEPT CURR_AC_MAC CURR_FILE_DIR REF_AMS_DONE 
 CURR_FILE_NAME ROOT_FOLDER REF_DEF_CONDITIONS CURR_USER_LIBS CURR_MAKE_INP_LIST 
 PROCESS_SUBDIR CURR_DIR_SCAN TARGET_DIR REF_DEFS_NOT_FOUND REF_PROG_HASH FIX_REL_SOURCE 
 IGNORE_EXTRA_DIST CURR_USER_SUBS CURR_FILE ADD_REL_SOURCE CURR_DEBUG_FLAG REF_GLOBAL_HASH 
 VALUE_WARN_ON_PLUS REF_LIBS_HASH CURR_COMMON_SUBS REF_PROGRAMS CURR_SUBS_NOT_FOUND 
 REF_LIBRARIES CURR_DONE_SCAN CURR_HASH TRY_HARDER CURR_AUTO_ON_FLAG
 );
    my ($key);
    foreach $key (@par_list) {
        if (! defined ${$rparam}{$key}) {
            prt("INTERNAL ERROR: key [$key] NOT defined in ref params!\n");
            exit(1);
        }
    }
}

sub set_params_ref($) {
    my ($inf) = @_;
    my ($name,$dir) = fileparse($inf);
    $dir = $cwd if ($dir =~ /^\.(\\|\/)$/);
    $dir .= "\\" if (!($dir =~ /(\\|\/)$/));
    $dir = path_u2d($dir);

    #my $debug_flag = -1;   # this will set them _ALL_ on
    my $debug_flag = 0;   # this should set none
    #my $debug_flag = 1 << (13 - 1);   # this will set #13 ON
    # ======================================================
    # SETUP for a call using a 'parameters' HASH
    my $rparams = get_ref_params();
    ${$rparams}{'CURR_BEGIN_TIME'} = time();

    my %hash = ();
    my $rh = \%hash;
    ${$rparams}{'CURR_HASH'} = $rh; # Establish REF HASH
    my @mk_inp_list = ();
    my $ramil = \@mk_inp_list;

    ${$rparams}{'CURR_FILE'} = $inf;
    ${$rparams}{'CURR_FILE_NAME'} = $name;
    ${$rparams}{'CURR_FILE_DIR'} = $dir;

    my %common_subs = ();
    my $rcs = \%common_subs;
    ${$rparams}{'CURR_COMMON_SUBS'} = $rcs;
    my $rus = \%g_user_subs;    # supplied by USER INPUT
    ${$rparams}{'CURR_USER_SUBS'} = $rus; # supplied by USER INPUT

    my %conf_ac_mac = ();
    my $racmacs = \%conf_ac_mac;
    ${$rparams}{'CURR_AC_MAC'} = $racmacs;
    my $rsnf = \%g_subs_not_found;
    ${$rparams}{'CURR_SUBS_NOT_FOUND'} = $rsnf;
    ${$rparams}{'CURR_MAKE_INP_LIST'} = $ramil; # array reference
    ${$rparams}{'CURR_DEBUG_FLAG'} = $debug_flag;
    # ======================================================
    # and for AM files processing
    my %programs = ();
    my %libraries = ();
    my %projects = ();
    my $r_progs = \%programs;
    ${$rparams}{'REF_PROGRAMS'} = $r_progs;
    my $r_libs = \%libraries;
    ${$rparams}{'REF_LIBRARIES'} = $r_libs;
    my $r_projs = \%projects;
    ${$rparams}{'REF_PROJECTS'} = $r_projs;

    # to keep the original has reference of the Makefile.am
    # scan, kept under the project name key, as in the above
    my %prog_hash = ();
    my %libs_hash = ();
    my %lib_dupes = ();
    my %lib_lists = (); # list of SL/DLL, and whether 'eXcluded' or not
    ${$rparams}{'REF_PROG_HASH'} = \%prog_hash;
    ${$rparams}{'REF_LIBS_HASH'} = \%libs_hash;
    ${$rparams}{'REF_LIB_DUPES'} = \%lib_dupes;
    ${$rparams}{'REF_LIB_LISTS'} = \%lib_lists;
    #my %common_subs = ();
    #my $rcomsubs = \%common_subs;
    #${$rparams}{'REF_COMMON_SUBS'} = $rcomsubs;
    my $rglobhash = \%g_global_hash;
    ${$rparams}{'REF_GLOBAL_HASH'} = $rglobhash;
    # my $rsnf = \%g_subs_not_found; - see CURR_SUBS_NOT_FOUND above # ${$rparams}{'REF_SUBS_NOT_FOUND'} = $rsnf;
    my $rdnf = \%g_defs_not_found;
    ${$rparams}{'REF_DEFS_NOT_FOUND'} = $rdnf;

    my $rdef_conds = \%g_user_condits;
    my %missing_conds = ();
    ${$rparams}{'REF_DEF_CONDITIONS'} = $rdef_conds;
    ${$rparams}{'REF_MISSED_CONDITIONS'} = \%missing_conds;

    my %ams_done = ();
    my $ramsdone = \%ams_done;
    ${$rparams}{'REF_AMS_DONE'} = $ramsdone;
    my %hoh_subdirs = ();
    my $rhohsubs = \%hoh_subdirs;
    ${$rparams}{'REF_HOH_SUBS'} = $rhohsubs;

    my $rexcept = \%g_sources_exceptions;
    ${$rparams}{'REF_SRC_EXCEPT'} = $rexcept;

    ${$rparams}{'REF_EXIT_VALUE'} = \$exit_value;
    ${$rparams}{'PROCESS_SUBDIR'} = $process_subdir;
    ${$rparams}{'VALUE_WARN_ON_PLUS'} = $warn_on_plus;
    ### ${$rparams}{'MAX_OF_TYPE'} = $max_of_type;
    ${$rparams}{'ADD_REL_SOURCE'} = $add_rel_sources;
    ${$rparams}{'TRY_HARDER'} = $try_harder;
    ${$rparams}{'TRY_MUCH_HARDER'} = $try_much_harder; 
    ${$rparams}{'IGNORE_EXTRA_DIST'} = $ignore_EXTRA_DIST;
    ${$rparams}{'FIX_REL_SOURCE'} = $fix_relative_sources;
    ${$rparams}{'TARGET_DIR'} = $target_dir;
    ${$rparams}{'CURR_AUTO_ON_FLAG'} = $auto_on_flag;
    ${$rparams}{'SUPP_MAKE_IN'} = $supp_make_in;
    ${$rparams}{'PROJECT_NAME_MASTER'} = $project_name;
    ${$rparams}{'TOTAL_LINE_COUNT'} = 0;

    # function
    my $func = \&get_user_libs;
    bless ($func);
    ${$rparams}{'CURR_USER_LIBS'} = $func; # = \&get_user_libs
    my $func2 = \&get_user_output;
    bless ($func2);
    ${$rparams}{'CURR_USER_OUTS'} = $func2; # = \&get_user_output;


    ${$rparams}{'CURR_DONE_SCAN'} = 0;
    ${$rparams}{'CURR_DIR_SCAN'} = [];

    if (${$rparams}{'TRY_HARDER'} || ${$rparams}{'TRY_MUCH_HARDER'}) {
        ac_do_dir_scan($rparams,$dir,0);
    }

    return $rparams;
}

sub init_common_subs($) {
    my ($fil) = shift;
    my ($root_file, $root_folder) = fileparse($fil);
    $root_folder = $cwd if ($root_folder =~ /^\.(\\|\/)$/);
    $root_folder .= "\\" if (!($root_folder =~ /(\\|\/)$/));
    $root_folder = path_u2d($root_folder);
    if (length($target_dir) == 0) {
        $target_dir = $root_folder;
        my $auto_on = $auto_on_flag;
        if ($auto_on & 8) {    # $auto_on
            ###$target_dir .= 'msvc';
            $target_dir .= 'build'; # 20130902 - default to 'build' directory if no target given
        } else {
            $fix_relative_sources = 0;  # no fix needed. since the SAME as 'root'
        }
        $target_dir .= "\\" if (!($target_dir =~ /(\\|\/)$/));
        prt("Set TARGET directory to [$target_dir]\n");
    } else {
        $target_dir .= "\\" if (!($target_dir =~ /(\\|\/)$/));
    }

    my ($key,$rcs);
    if ($target_dir ne $root_folder) {
        $key = get_rel_dos_path($root_folder,$target_dir);
        $key =~ s/(\\|\/)$//;
        $rcs = length($key);
        if ($rcs && ($rcs < length($target_dir)) && ($rcs < length($root_folder))) {
            # add this ONLY if writing DSP files, AND NOT writing cmake
            if ( get_write_dsp_files() && !get_write_cmake_files() ) {
                prt("init_common_subs: Adding 'include' [$key] relative,\n".
                    " from [$fil] input filedir *-2.*\n".
                    " root [$root_folder]\n".
                    " targ [$target_dir]\n");
                add_include_item($key);
            }
        }
    }

    my $rparams = get_ref_params();
    ${$rparams}{'ROOT_FOLDER'} = $root_folder;

    set_params_ref($fil);

    $rcs = ${$rparams}{'CURR_COMMON_SUBS'};

    # === gen_param_check($rparams);
    # =========================================================
    validate_ref_param($rparams);

    init_common_subs2($rcs,1);

    return $rparams;
}

sub get_root_dir() {
    my $rparams = get_ref_params();
    if (! defined ${$rparams}{'ROOT_FOLDER'}) {
        pgm_exit(1,"ERROR: lib_params: sub 'get_root_dir' called before 'ROOT_FOLDER' established.\n");
    }
    my $rd = ${$rparams}{'ROOT_FOLDER'};
    return $rd;
}


1;
