#!/usr/bin/perl -w
# NAME: Qt2cmake.pl
# AIM: Convert a given Qt project file <project>.pro to a CMakeLists.txt
# 31/08/2015 - moved to scripts repo
# 26/02/2015 - Fix BUG that writes CMakeLists.txt to root
# 07/09/2012 - Tweak for adding QtScript component
# 08/06/2012 - Even if 'qt' NOT found in CONFIG it IS a Qt project
# 05/06/2012 - ADD INSTALL
# 13/05/2012 - Quieten the beast unless -v[n]
# 10/05/2012 - Tidy up for first release
# 08/05/2012 - First cut
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
# log file stuff
our ($LF);
my $outfile = $temp_dir.$PATH_SEP."temp.$pgmname.txt";
open_log($outfile);

# user variables
my $VERS = "0.0.6 2015-08-31";  # move to scripts repo
###my $VERS = "0.0.5 2014-06-30";
###my $VERS = "0.0.4 2012-09-07";
###my $VERS = "0.0.3 2012-05-13";
###my $VERS = "0.0.1 2012-01-06";
my $load_log = 0;
my $in_file = '';
my $usr_targ_dir = '';
my $proj_name = '';
my $verbosity = 0;
# my $tmpcmlist = $temp_dir.$PATH_SEP."temp.cmakelists.txt";
my $max_col_width = 80;
my $add_cmake_debug = 1;
my $load_cmake_list = 0;
my $use_static_lib = 0;
my $put_all_in_moc = 0;
my $add_linux_win = 0;

my @qmake_nouns = qw( TEMPLATE TARGET DEPENDPATH INCLUDEPATH HEADERS SOURCES RESOURCES CONFIG QT );

my %qmake_verbs = (
    'CONFIG' => 'General project configuration options.',
    'DESTDIR' => 'The directory in which the executable or binary file will be placed.',
    'FORMS' => 'A list of UI files to be processed by uic.',
    'HEADERS' => 'A list of filenames of header (.h) files used when building the project.',
    'QT' => 'Qt-specific configuration options.',
    'RESOURCES' => 'A list of resource (.rc) files to be included in the final project.', # See the The Qt Resource System for more information about these files.
    'SOURCES' => 'A list of source code files to be used when building the project.',
    'TEMPLATE' => 'The template to use for the project. This determines whether the output of the build process will be an application, a library, or a plugin.' );

my $debug_on = 0;
my $def_file = 'C:\Projects\fgx\src\fgx.pro';
my $def_targ = 'C:\Projects\fgx';

### program variables
my @warnings = ();
my $out_list_file = '';
my $user_defines = '';

sub get_user_defines($) {
    my $rcm = shift;
    if (length($user_defines)) {
        my @arr = split(";",$user_defines);
        my ($itm,$val,@arr2);
        foreach $itm (@arr) {
            @arr2 = split(":",$itm);
            if (scalar @arr2 == 2) {
                $itm = $arr2[0];
                $val = $arr2[1];
                ${$rcm} .= "add_definitions( -D$itm=\\\"$val\\\" )\n";
            } else {
                ${$rcm} .= "add_definitions( -D$itm )\n";
            }
        }
    }
}

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

# HEADERS - A list of all the header files for the application.
# SOURCES - A list of all the source files for the application.
# FORMS - A list of all the UI files (created using Qt Designer) for the application.
# LEXSOURCES - A list of all the lex source files for the application.
# YACCSOURCES - A list of all the yacc source files for the application.
# TARGET - Name of the executable for the application. This defaults to the name of the project file. (The extension, if any, is added automatically).
# DESTDIR - The directory in which the target executable is placed.
# DEFINES - A list of any additional pre-processor defines needed for the application.
# INCLUDEPATH - A list of any additional include paths needed for the application.
# DEPENDPATH - The dependency search path for the application.
# VPATH - The search path to find supplied files.
# DEF_FILE - Windows only: A .def file to be linked against for the application.
# RC_FILE - Windows only: A resource file for the application.
# RES_FILE - Windows only: A resource file to be linked against for the application

# TODO
# TEMP_SOURCES = $$SOURCES - copy to another variable
# DEST = "Program Files" - white space handling
# win32:INCLUDEPATH += "C:/mylibs/extra headers"
# unix:INCLUDEPATH += "/home/user/extra headers"
# include(other.pro) - include another project in this project
# sort of like an IF structure
# win32 {
#     SOURCES += paintwidget_win.cpp
# }
# or
#win32 {
#     debug {
#         CONFIG += console
#     }
# }
# for parsing
# EXTRAS = handlers tests docs
# for(dir, EXTRAS) {
#     exists($$dir) {
#         SUBDIRS += $$dir
#     }
# }
#
# TARGET
#  CONFIG(debug, debug|release) {
#     TARGET = debug_binary
# } else {
#     TARGET = release_binary
# }
#CONFIG(debug, debug|release) {
#     mac: TARGET = $$join(TARGET,,,_debug)
#     win32: TARGET = $$join(TARGET,,d)
# }
# TEMPLATES
# Template Description of qmake output
my %qmake_templates = (
    'app' => 'Creates a Makefile to build an application.', # the default if NO TEMPLATE given
    'lib' => 'Creates a Makefile to build a library.',
    'subdirs' => 'Creates a Makefile containing rules for the subdirectories specified using the SUBDIRS variable. Each subdirectory must contain its own project file.',
    'vcapp' => 'Creates a Visual Studio Project file to build an application.',
    'vclib' => 'Creates a Visual Studio Project file to build a library.',
    'vcsubdirs' => 'Creates a Visual Studio Solution file to build projects in sub-directories.',
    # from : http://doc.qt.nokia.com/4.7-snapshot/qmake-common-projects.html
    'dll'   => 'The library is a shared library (dll).',
    'staticlib' => 'The library is a static library.',
    'plugin' => 'The library is a plugin; this also enables the dll option.' );

# CONFIG
# General Configuration
# The CONFIG variable specifies the options and features that the compiler should use and the 
# libraries that should be linked against. Anything can be added to the CONFIG variable, but 
# the options covered below are recognized by qmake internally.
# The following options control the compiler flags that are used to build the project:
#  CONFIG      += designer plugin
my %qmake_configs = (
    'release' => 'The project is to be built in release mode. This is ignored if debug is also specified.',
    'debug' => 'The project is to be built in debug mode.',
    'debug_and_release' => 'The project is built in both debug and release modes.',
    'debug_and_release_target' => 'The project is built in both debug and release modes. TARGET is built into both the debug and release directories.',
    'build_all' => 'If debug_and_release is specified, the project is built in both debug and release modes by default.',
    'autogen_precompile_source' => 'Automatically generates a .cpp file that includes the precompiled header file specified in the .pro file.',
    'ordered' => 'When using the subdirs template, this option specifies that the directories listed should be processed in the order in which they are given.',
    'warn_on' => 'The compiler should output as many warnings as possible. This is ignored if warn_off is specified.',
    'warn_off' => 'The compiler should output as few warnings as possible.',
    'copy_dir_files' => 'Enables the install rule to also copy directories, not just files.',
    # from : http://doc.qt.nokia.com/4.7-snapshot/qmake-common-projects.html
    'designer' => 'Qt Designer plugins are built using a specific set of configuration settings',
    'plugin'   => 'Qt Designer plugins are built using a specific set of configuration settings' );
# The debug_and_release option is special in that it enables both debug and release versions of a 
# project to be built. In such a case, the Makefile that qmake generates includes a rule that builds 
# both versions, and this can be invoked in the following way: make all
# conditional 
# CONFIG(opengl) {
#     message(Building with OpenGL support.)
# } else {
#     message(OpenGL support is not available.)
# }
# qt - The project is a Qt application and should link against the Qt library. You can use the QT variable to 
#      control any additional Qt modules that are required by your application.
# thread - The project is a multi-threaded application.
# x11 - The project is an X11 application or library.
# like  CONFIG += qt thread debug
# Declaring Qt Libraries
#  CONFIG += qt
#  QT += network xml
# Note that QT includes the core and gui modules by default
# QT = network xml # This will omit the core and gui modules.
# QT -= gui # Only the core module is used.
# QT variable
my %cmake_modules = (
    'QT_USE_QTNETWORK' => 'network',
    'QT_USE_QTOPENGL'  => 'opengl',
    'QT_USE_QTSQL'     => 'sql',
    'QT_USE_QTXML'     => 'xml',
    'QT_USE_QTSVG'     => 'svg',
    'QT_USE_QTTEST'    => '?',
    'QT_USE_QTDBUS'    => '?',
    'QT_USE_QTSCRIPT'  => 'script',
    'QT_USE_QTWEBKIT'  => 'webkit',
    'QT_USE_QTXMLPATTERNS' => 'xmlpatterns',
    'QT_USE_PHONON'    => '?' );

my %qmake_modules = (
    'core'    => '', # when negative handled QT_DONT_USE_QTCORE',  # (included by default)
    'gui'     => '', # when neg handled QT_DONT_USE_QTGUI',   # (included by default)
    'network' => 'QT_USE_QTNETWORK',
    'opengl'  => 'QT_USE_QTOPENGL',
    'sql'     => 'QT_USE_QTSQL',
    'svg'     => 'QT_USE_QTSVG',
    'xml'     => 'QT_USE_QTXML',
    'xmlpatterns' => 'QT_USE_QTXMLPATTERNS',
    'script' => 'QT_USE_QTSCRIPT',
    'webkit' => 'QT_USE_QTWEBKIT',
    'qt3support' => 'QT_USE_QT3SUPPORT' );
#  CONFIG += link_pkgconfig
# PKGCONFIG += ogg dbus-1

sub is_complete_pro_line($) {
    my $line = shift;
    my $iret = 1;   # assume it is a complete line
    my @braces = ();
    my @brackets = ();
    my $len = length($line);
    my ($i,$ch,$pc,$inquot);
    $ch = '';
    $inquot = 0;
    for ($i = 0; $i < $len; $i++) {
        $pc = $ch;
        $ch = substr($line,$i,1);
        if ($inquot) {
            $inquot = 0 if (($ch eq '"') && ($pc ne "\\"));
        } elsif ($ch eq '"') {
            $inquot = 1;
        } else {
            if ($ch eq '(') {
                push(@brackets,$i);
            } elsif ($ch eq ')') {
                pop @brackets if (@brackets);
            } elsif ($ch eq '{') {
                push(@braces,$i);
            } elsif ($ch eq '}') {
                pop @braces if (@braces);
            }
        }
    }
    $iret = 0 if (@brackets);
    $iret = 0 if (@braces);
    return $iret;
}

sub not_same_dir($$) {
    my ($d1,$d2) = @_;
    $d1 =~ s/\.$//;
    $d2 =~ s/\.$//;
    $d1 =~ s/(\\|\/)$//;
    $d2 =~ s/(\\|\/)$//;
    return 0 if ($d1 ne $d2);
    return 1;   # NOT THE SAME
}

sub collect_include_dirs($$) {
    my ($rf,$rh) = @_;
    my $rdh = ${$rh}{'curr_incs'};
    my ($name,$dir) = fileparse($rf);
    $dir =~ s/^\.(\\|\/)//;
    $dir =~ s/(\\|\/)$//;
    ${$rdh}{$dir} = 1 if (length($dir));
}

sub check_file_for_q_object($) {
    my $file = shift;
    if (!open INF, "<$file") {
        return 1;   # can NOT open so assume YES
    }
    my @lines = <INF>;
    close INF;
    my ($line);
    foreach $line (@lines) {
        return 1 if ($line =~ /\bQ_OBJECT\b/);
    }
    return 0;
}

sub get_rel_path($$) {
    my ($tdir,$dir) = @_;
    my $from = File::Spec->rel2abs($tdir);
    my $to = File::Spec->rel2abs($dir);
    my $rpath = get_relative_path4($to,$from);
    prt("To $to, from $from, rel $rpath. In $tdir, $dir\n");
    ###pgm_exit(1,"TEMP EXIT\n");
    return $rpath;
}

# process the input .pro file
sub process_in_file($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    #################################################################
    prt("[v2] Processing $lncnt lines, from [$inf]...\n") if (VERB2());
    my %project_items = ();
    my $rh = \%project_items;
    my ($i,$line,$inc,$lnn,$tag,$val,@arr,$pname,$tmp,$j,$ff,$ok,$rf,$tdir);
    my ($hcnt,$rcnt,$fcnt,$scnt,$ismoc);
    ${$rh}{'curr_inf'} = $inf;
    ${$rh}{'curr_incs'} = { };
    my ($name,$dir,$ext) = fileparse($inf, qr/\.[^.]*/ );
    my $fixrel = (length($usr_targ_dir) && not_same_dir($dir,$usr_targ_dir)) ? 1 : 0;
    #my $reldir = ($fixrel) ? get_rel_dir($targ_dir,$dir) : '';
    my $reldir = length($usr_targ_dir) ? get_relative_path($dir,$usr_targ_dir) : '';
    ($tmp,$tdir) = fileparse($out_list_file);
    $reldir = get_rel_path($tdir,$dir);
    $fixrel = (length($reldir) ? 1 : 0);
    prt("[v9] Relative dir [$reldir] ($fixrel)\n") if ($fixrel && VERB9());
    ut_fix_directory(\$dir);
    $pname = $name;
    $scnt = 0;
    $hcnt = 0;
    $rcnt = 0;
    $fcnt = 0;
    $lnn = 0;
    my $missed_hdrs = 0;
    my $missed_srcs = 0;
    my $total_hdrs = 0;
    my $total_srcs = 0;
    my ($bgnln,$endln,$rta);
    # line by line
    for ($i = 0; $i < $lncnt; $i++) {
        $line = trim_all($lines[$i]);
        $lnn = $i + 1;
        next if (length($line) == 0);   # skip blanks
        next if ($line =~ /^\s*\#/);     # skip comments
        $bgnln = $i;    # this line BEGINS here
        while (($line =~ /\\$/) && (($i+1) < $lncnt)) {
            $line =~ s/\\$//;
            $line .= ' ' if ($line =~ /\S$/);
            $i++;
            $line .= trim_all($lines[$i]) if ($i < $lncnt);
        }
        while (!is_complete_pro_line($line) && (($i+1) < $lncnt)) {
            $line .= ' ' if ($line =~ /\S$/);
            $i++;
            if ($i < $lncnt) {
                $line .= trim_all($lines[$i]);
                while ($line =~ /\\$/) {
                    $line =~ s/\\$//;
                    $line .= ' ' if ($line =~ /\S$/);
                    $i++;
                    $line .= trim_all($lines[$i]) if ($i < $lncnt);
                }
            } else {
                prtw("WARNING: Ran out of line in a block! $lnn\n");
                last;
            }
        }
        $endln = $i;    # this line ENDS here
        prt("$lnn: $line\n") if (VERB1());
        # main verbs
        if ($line =~ /^\s*TEMPLATE\s*\+*=\s*(.+)$/) {
            $tag = 'TEMPLATE';
            ${$rh}{$tag} = $1;
        } elsif ($line =~ /^\s*TARGET\s*\+*=\s*(.+)$/) {
            $tag = 'TARGET';
            ${$rh}{$tag} = $1;
        } elsif ($line =~ /^\s*DEPENDPATH\s*\+*=\s*(.+)$/) {
            $tag = 'DEPENDPATH';
            ${$rh}{$tag} = $1;
        } elsif ($line =~ /^\s*INCLUDEPATH\s*\+*=\s*(.+)$/) {
            $tag = 'INCLUDEPATH';
            ${$rh}{$tag} = $1;
        } elsif ($line =~ /^\s*HEADERS\s*\+*=\s*(.+)$/) {
            $val = $1;
            @arr = space_split($val);
            $hcnt = scalar @arr;
            $total_hdrs += $hcnt;
            prt("[v5] Project [$pname] found $hcnt headers...\n") if (VERB5());
            my @mochdrs = ();
            my @normhdrs = ();
            for ($j = 0; $j < $hcnt; $j++) {
                $tmp = strip_quotes($arr[$j]);
                $rf = ($fixrel) ? $reldir.$tmp : $tmp;  # ok HAVE TO FIX, or NOT
                $rf = fix_rel_path($rf);
                $rf = path_d2u($rf);    # always unix for for cmake
                collect_include_dirs($rf,$rh);
                $ff = $dir.$rf;
                $ok = 'NOT FOUND';
                $ismoc = 1;
                if (-f $ff) {
                    $ismoc = check_file_for_q_object($ff);
                    $ok = "ok($ismoc)";
                } else {
                    $missed_hdrs++;
                }
                ### $ok = (-f $ff) ? 'ok' : 'NOT FOUND!';
                $ff = '"'.$ff.'"' if ($ff =~ /\s/);
                $arr[$j] = $rf;
                if ($ismoc) {
                    push(@mochdrs,$rf);
                } else {
                    push(@normhdrs,$rf);
                }
                prt("[v5] $ff $ok\n") if (VERB5());
            }

            if ($put_all_in_moc) {
                $val = join(" ",@arr);  # get potentially NEW values
                $tag = 'HEADERS';
                ${$rh}{$tag} .= ' ' if (defined ${$rh}{$tag});
                ${$rh}{$tag} .= $val;    # store
            } else {
                if (@mochdrs) {
                    $val = join(" ",@mochdrs);  # get potentially NEW values
                    $tag = 'HEADERS';
                    ${$rh}{$tag} .= ' ' if (defined ${$rh}{$tag});
                    ${$rh}{$tag} .= $val;    # store
                } 
                if (@normhdrs) {
                    $tag = 'OTHERS';
                    ${$rh}{$tag} .= ' ' if (defined ${$rh}{$tag});
                    ${$rh}{$tag} .= join(" ",@normhdrs);
                }
            }
        } elsif ($line =~ /^\s*SOURCES\s*\+*=\s*(.+)$/) {
            $val = $1;
            $tag = 'SOURCES';
            @arr = space_split($val);
            $scnt = scalar @arr;
            $total_srcs += $scnt;
            prt("[v5] Project [$pname] found $scnt sources...\n") if (VERB5());
            # now need to FIND each of these source,
            # relative to the <proj>.pro file - see ($name,$dir,$ext) above.
            # only a problem if $targ_dir is other that == $dir, so
            #if (length($targ_dir) && not_same_dir($dir,$targ_dir)) {
            for ($j = 0; $j < $scnt; $j++) {
                $tmp = strip_quotes($arr[$j]);
                $rf = ($fixrel) ? $reldir.$tmp : $tmp;  # ok HAVE TO FIX, or NOT
                $rf = fix_rel_path($rf);
                $rf = path_d2u($rf);    # always unix for for cmake
                collect_include_dirs($rf,$rh);
                $ff = $dir.$rf;
                $ok = (-f $ff) ? 'ok' : 'NOT FOUND!';
                $ff = '"'.$ff.'"' if ($ff =~ /\s/);
                $arr[$j] = $rf;
                prt("[v5] $ff $ok\n") if (VERB5());
            }
            $val = join(" ",@arr);  # get NEW value
            ${$rh}{$tag} .= ' ' if (defined ${$rh}{$tag});
            ${$rh}{$tag} .= $val;
        } elsif ($line =~ /^\s*RESOURCES\s*\+*=\s*(.+)$/) {
            $val = $1;
            $tag = 'RESOURCES';
            @arr = space_split($val);
            $rcnt = scalar @arr;
            prt("[v5] Project [$pname] found $rcnt resources...\n") if (VERB5());
            for ($j = 0; $j < $rcnt; $j++) {
                $tmp = strip_quotes($arr[$j]);
                $rf = ($fixrel) ? $reldir.$tmp : $tmp;  # ok HAVE TO FIX, or NOT
                $rf = fix_rel_path($rf);
                $rf = path_d2u($rf);    # always unix for for cmake
                collect_include_dirs($rf,$rh);
                $ff = $dir.$rf;
                $ok = (-f $ff) ? 'ok' : 'NOT FOUND!';
                $ff = '"'.$ff.'"' if ($ff =~ /\s/);
                $arr[$j] = $rf;
                prt("[v5] $ff $ok\n") if (VERB5());
            }
            $val = join(" ",@arr);  # get NEW value
            ${$rh}{$tag} = $val;
        } elsif ($line =~ /^\s*FORMS\s*\+*=\s*(.+)$/) {
            $val = $1;
            $tag = 'FORMS';
            @arr = space_split($val);
            $fcnt = scalar @arr;
            prt("[v5] Project [$pname] found $fcnt forms...\n") if (VERB5());
            for ($j = 0; $j < $fcnt; $j++) {
                $tmp = strip_quotes($arr[$j]);
                $rf = ($fixrel) ? $reldir.$tmp : $tmp;  # ok HAVE TO FIX, or NOT
                $rf = fix_rel_path($rf);
                $rf = path_d2u($rf);    # always unix for for cmake
                collect_include_dirs($rf,$rh);
                $ff = $dir.$rf;
                ###$ok = (-f $ff) ? 'ok' : 'NOT FOUND!';
                if (-f $ff) {
                    $ok = 'ok'
                } else {
                    $ok = 'NOT FOUND';
                    $missed_srcs++;
                }
                $ff = '"'.$ff.'"' if ($ff =~ /\s/);
                $arr[$j] = $rf;
                prt("[v5] $ff $ok\n") if (VERB5());
            }
            $val = join(" ",@arr);  # get NEW value
            ${$rh}{$tag} .= ' ' if (defined ${$rh}{$tag});
            ${$rh}{$tag} .= $val;
        } elsif ($line =~ /^\s*CONFIG\s*=\s*(.+)$/) {
            $tag = 'CONFIG';
            ${$rh}{$tag} = $1;
        } elsif ($line =~ /^\s*CONFIG\s*\++=\s*(.+)$/) {
            $tag = 'CONFIG';
            ${$rh}{$tag} .= ' ' if (defined ${$rh}{$tag});
            ${$rh}{$tag} .= $1;
        } elsif ($line =~ /^\s*DEFINES\s*=\s*(.+)$/) {
            $val = $1;
            $tag = 'DEFINES';
            ##${$rh}{$tag} = $1;
        } elsif ($line =~ /^\s*DEFINES\s*\++=\s*(.+)$/) {
            $val = $1;
            $tag = 'DEFINES';
            ##${$rh}{$tag} .= ' ' if (defined ${$rh}{$tag});
            ##${$rh}{$tag} .= $1;
        } elsif ($line =~ /^\s*QT\s*\++=\s*(.+)$/) {
            $tag = 'QT';
            ${$rh}{$tag} .= ' ' if (defined ${$rh}{$tag});
            ${$rh}{$tag} .= $1;
        } elsif ($line =~ /^\s*QT\s*=\s*(.+)$/) {
            $tag = 'QT';
            ${$rh}{$tag} = $1;
        } elsif ($line =~ /^\s*mac/) {
            # can be -
            # macx|linux {
            #  DEFINES += HAVE_NANOSLEEP HAVE_LIBUSB HAVE_GLOB
            #  SOURCES += gbser_posix.cc
            # JEEPS += jeeps/gpslibusb.cc
            # INCLUDEPATH += jeeps
            # }
            # for now ignore for mac
        } elsif ($line =~ /^\s*unix/) {
            # for now ignore for unix
        } elsif ($line =~ /^!win32/) {
            # !win32:VERSION = 12.0.0 from qcintilla.pro
        } elsif (($line =~ /^\s*win32/)||($line =~ /^\s*windows/)) {
            # ah, some stuff specific for WINDOWS
            # can be win32:TARGET = something
            # or win32 (
            #   TARGET = something
            #   DEFINES += __WIN32__ _CONSOLE
            #   DEFINES -= UNICODE ZLIB_INHIBITED
            #   CONFIG(debug, debug|release) {
            #    DEFINES += _DEBUG
            #   }
            #   SOURCES += gbser_win.cc
            #   JEEPS += jeeps/gpsusbwin.cc
            #   LIBS += "C:/Program Files/Windows Kits/8.0/Lib/win8/um/x86/setupapi.lib" "C:/Program Files/Windows Kits/8.0/Lib/win8/um/x86/hid.lib"
            #      ...
            #          )
            # or
            # win32-msvc*{
            #   DEFINES += _CRT_SECURE_NO_DEPRECATE
            #   INCLUDEPATH += ../../src/core src/core
            #   QMAKE_CXXFLAGS += /MP -wd4100
            #   TEMPLATE=vcapp
            # }
            # or 'windows:SOURCES += serial_win.cc'
            prtw("WARNING: TODO: $bgnln:$endln: '$line'\n");
        } elsif ($line =~ /^\s*ICON\s*=\s*(.+)$/) {
            $val = $1;
            $tag = 'ICON';
            ${$rh}{$tag} = [] if (!defined ${$rh}{$tag});
            $rta = ${$rh}{$tag};
            push(@{$rta},$val);
        } elsif ($line =~ /^\s*UI_DIR\s*=\s*(.+)$/) {
            $val = $1;
            $tag = 'UI_DIR';
            ${$rh}{$tag} = $val;
        } elsif ($line =~ /^\s*RC_FILE\s*=\s*(.+)$/) {
            $val = $1;
            $tag = 'RC_FILE';
            ${$rh}{$tag} = $val;
        } elsif ($line =~ /^\s*TRANSLATIONS\s*\+*=\s*(.+)$/) {
            $val = $1;
            $tag = 'TRANSLATIONS';
            ${$rh}{$tag} = [] if (!defined ${$rh}{$tag});
            $rta = ${$rh}{$tag};
            push(@{$rta},$val);
        } elsif ($line =~ /^\s*INSTALLS\s*\+*=\s*(.+)$/) {
            $val = $1;
            $tag = 'INSTALLS';
            ${$rh}{$tag} = [] if (!defined ${$rh}{$tag});
            $rta = ${$rh}{$tag};
            push(@{$rta},$val);
        } elsif ($line =~ /^\s*greaterThan/) {
            prtw("WARNING:$lnn: TODO: $bgnln:$endln: '$line'\n") if (VERB5());
        } elsif ($line =~ /^\s*isEmpty/) {
            prtw("WARNING:$lnn: TODO: $bgnln:$endln: '$line'\n") if (VERB5());
        } else {
            prtw("WARNING:$lnn: Unparsed line [$line] FIX ME!\n");
        }
    }
    prt("Srcs $total_srcs, NF $missed_srcs, Hdrs $total_hdrs, NF $missed_hdrs\n");
    return $rh;
}

sub add_gui_message($) {
    my $rcm = shift;
    ${$rcm} .= "# Added for DEBUG only\n";
    ${$rcm} .= "IF(UNIX)\n";
    ${$rcm} .= "  IF(APPLE)\n";
    ${$rcm} .= "    SET(GUI \"Cocoa\")\n";
    ${$rcm} .= "  ELSE(APPLE)\n";
    ${$rcm} .= "    SET(GUI \"X11\")\n";
    ${$rcm} .= "  ENDIF(APPLE)\n";
    ${$rcm} .= "ELSE(UNIX)\n";
    ${$rcm} .= "  IF(WIN32)\n";
    ${$rcm} .= "    SET(GUI \"Win32\")\n";
    ${$rcm} .= "  ELSE(WIN32)\n";
    ${$rcm} .= "    SET(GUI \"Unknown\")\n";
    ${$rcm} .= "  ENDIF(WIN32)\n";
    ${$rcm} .= "ENDIF(UNIX)\n";
    ${$rcm} .= "MESSAGE(\"*** GUI system is \${GUI} ***\")\n\n";
}

sub add_linux_windows($) { # if ($add_linux_win);
    my $rcm = shift;
    my $txt = "# Add LINUX or WINDOWS definitions\n";
    $txt .= "if(UNIX)\n";
    $txt .= "   add_definitions( -DLINUX )\n";
    $txt .= "else(UNIX)\n";
    $txt .= "   add_definitions( -DWINDOWS )\n";
    $txt .= "endif(UNIX)\n";
    ${$rcm} .= $txt;
}

# 20150901 - Add this sort of standard block of cmake
sub add_compiler_block($) {
    my $rcm = shift;
    my $txt = <<EOF;

# Allow developers to select if Dynamic or static libraries are built.
set( LIB_TYPE STATIC )  # set default static
option( BUILD_SHARED_LIB    "Set ON to build Shared Libraries"      OFF )
option( BUILD_TEST_PROGRAMS "Set ON to build the utility programs"  OFF )

# read 'version' file into a variable (stripping any newlines or spaces)
#file(READ version versionFile)
#if (NOT versionFile)
#    message(FATAL_ERROR "Unable to determine version. version file is missing.")
#endif()
#string(STRIP "\${versionFile}" MY_VERSION)
#add_definitions( -DVERSION="\${MY_VERSION}" )

# Uncomment to REDUCE the Windows configurations buildable
# set(CMAKE_CONFIGURATION_TYPES "Release;Debug" CACHE STRING "" FORCE) # Disables MinSizeRel & MaxSpeedRel

if(CMAKE_COMPILER_IS_GNUCXX)
    set( WARNING_FLAGS -Wall )
endif(CMAKE_COMPILER_IS_GNUCXX)

if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang") 
   set( WARNING_FLAGS "-Wall -Wno-overloaded-virtual" )
endif() 

if(WIN32 AND MSVC)
    # turn off various warnings
    set(WARNING_FLAGS "\${WARNING_FLAGS} /wd4996")
    # foreach(warning 4244 4251 4267 4275 4290 4786 4305)
    #     set(WARNING_FLAGS "\${WARNING_FLAGS} /wd\${warning}")
    # endforeach(warning)
    set( MSVC_FLAGS "-DNOMINMAX -D_USE_MATH_DEFINES -D_CRT_SECURE_NO_WARNINGS -D_SCL_SECURE_NO_WARNINGS -D__CRT_NONSTDC_NO_WARNINGS" )
    # if (\${MSVC_VERSION} EQUAL 1600)
    #    set( MSVC_LD_FLAGS "/FORCE:MULTIPLE" )
    # endif ()
    # set( NOMINMAX 1 )
    list(APPEND extra_LIBS ws2_32.lib Winmm.lib)
    # to distinguish between debug and release lib
    set( CMAKE_DEBUG_POSTFIX "d" )
else ()
    # unix stuff
endif()

set( CMAKE_C_FLAGS "\${CMAKE_C_FLAGS} \${WARNING_FLAGS} \${MSVC_FLAGS} -D_REENTRANT" )
set( CMAKE_CXX_FLAGS "\${CMAKE_CXX_FLAGS} \${WARNING_FLAGS} \${MSVC_FLAGS} -D_REENTRANT" )
set( CMAKE_EXE_LINKER_FLAGS "\${CMAKE_EXE_LINKER_FLAGS} \${MSVC_LD_FLAGS}" )

if( "\${CMAKE_SIZEOF_VOID_P}" STREQUAL "8" )
    set(IS_64_BIT 1)
    message(STATUS "*** Seems a 64-bit BUILD")
else ()
    message(STATUS "*** Seems a 32-bit BUILD")
endif ()

if (BUILD_SHARED_LIB)
    set(LIB_TYPE SHARED)
    message(STATUS "*** Building SHARED library...")
else ()
    message(STATUS "*** Building STATIC library...")
endif ()

EOF
    ${$rcm} .= $txt;
}

sub fix_out_file($) {
    my $dir = shift;
    if (length($out_list_file) == 0) {
        if (length($usr_targ_dir)) {
            ut_fix_directory(\$usr_targ_dir);
            $out_list_file = $usr_targ_dir."CMakeLists.txt";
        } else {
            $out_list_file = $dir."CMakeLists.txt";
        }
    }
}

sub process_input($) {
    my $file = shift;
    my ($name,$dir,$ext) = fileparse($file, qr/\.[^.]*/ );
    fix_out_file($dir);
    my $rh = process_in_file($file);
    my ($keys,$val,$pname,$tmp,$fnd,$line,$msg,$tdir,$ff,$rpath);
    my @arr = keys(%{$rh});
    my $cnt = scalar @arr;
    prt("[v9] Got $cnt keys: [".join(" ",@arr)."]...\n") if (VERB9());
    my $inf = ${$rh}{'curr_inf'};
    if (defined ${$rh}{'TARGET'}) {
        $pname = ${$rh}{'TARGET'};
        if (length($proj_name) && ($pname ne $proj_name)) {
            prtw("WARNING: Setting project name per user input!\n".
                "Replacing [$pname] with [$proj_name]\n");
            $pname = $proj_name;
        }
    } elsif ( length($proj_name) ) {
        $pname = $proj_name;
    } else {
        # hmm no TARGET unusual, and NO user input of name, so
        $pname = $name;   # take NAME of file
    }
    # we have a pname set, choose the out file
    ($tmp,$tdir) = fileparse($out_list_file);
    $rpath = get_rel_path($tdir,$dir);

    ###if (length($proj_name) == 0) {
    ###    $proj_name = $name;
    ###    prt("Set project name to [$proj_name]\n");
    ###}
    ###if (length($targ_dir) == 0) {
    ###    $targ_dir = $dir;
    ###    prt("Set target directory to [$targ_dir]\n");
    ###}


    my $cmake = '';
    my $rcm = \$cmake;

    $cmake .= "#\n";
    $cmake .= "# DO NOT MODIFY THIS SCRIPT - IT IS AUTOGENERATED\n";
    $cmake .= "# ===============================================\n";
    $cmake .= "# If there is a problem, either 'fix' ${name}${ext},\n";
    $cmake .= "# or modify the Qt2cmake.pl script accordingly.\n";
    $cmake .= "# CMakeLists.txt, generated from [$file]\n\n";

    $cmake .= "cmake_minimum_required( VERSION 2.8.8 )\n\n";

    add_gui_message(\$cmake) if ($add_cmake_debug && VERB9());

    $cmake .= "project( $pname )\n";

    add_compiler_block(\$cmake);

    add_linux_windows(\$cmake) if ($add_linux_win);

    get_user_defines(\$cmake);  # add any USER defines

    my $config = '';
    my $qtvar = '';
    my $components = "COMPONENTS QtCore QtGui";
    if (defined ${$rh}{'QT'}) {
        $qtvar = ${$rh}{'QT'};
        $cmake .= "# QT = $qtvar\n" if ($add_cmake_debug);
        $components .= " QtNetwork" if ($qtvar =~ /network/);
        $components .= " QtWebkit" if ($qtvar =~ /webkit/);
        $components .= " QtXml QtXmlPatterns" if ($qtvar =~ /xml/);
        $components .= " QtScript QtScriptTools" if ($qtvar =~ /script/);
    }
    # Then I read through the FindQt4.cmake file that comes with CMake
    # 2.8.4, and found that I could fix the problem with
    # find_package(Qt4 COMPONENTS QtCore QtGui QtNetwork REQUIRED)
    # find_package(Qt4 REQUIRED QtCore QtGui QtNetwork) will set QT_USE_QTNETWORK=1 for you.
    if (defined ${$rh}{'CONFIG'}) {
        $val = ${$rh}{'CONFIG'};
        $config = $val;
        $cmake .= "# CONFIG = $config\n" if ($add_cmake_debug);
        @arr = keys(%qmake_configs);
        $cnt = 0;
        while (length($val)) {
            $cnt++;
            if ($val =~ /debug_and_release/i) {
                $cmake .= "set( CMAKE_BUILD_TYPE RelWithDebInfo )\n";
                $val =~ s/debug_and_release//gi;
            } elsif ($val =~ /debug/i) {
                $cmake .= "set( CMAKE_BUILD_TYPE Debug )\n";
                $val =~ s/debug//gi;
            } elsif ($val =~ /release/i) {
                $cmake .= "set( CMAKE_BUILD_TYPE Release )\n";
                $val =~ s/release//gi;
            } elsif ($val =~ /qt/i) {
                # done later
                # $cmake .= "find_package ( Qt4 REQUIRED )\n";
                # $cmake .= "include ( \${QT_USE_FILE} )\n";
                # $cmake .= "add_definitions( \${QT_DEFINITIONS} )\n";
                $val =~ s/qt//ig;
            } elsif ($val =~ /thread/i) {
                # what to add
                $val =~ s/thread//ig;
            } elsif ($val =~ /warn_on/i) {
                $val =~ s/warn_on//ig;
                $cmake .= "add_definitions( -Wall )\n";
            } elsif ($val =~ /warn_off/i) {
                $val =~ s/warn_off//ig;
            } elsif ($val =~ /largefile/) {
                $val =~ s/largfile//ig;
                $cmake .= "add_definitions( -D_FILE_OFFSET_BITS=64 )\n";
            } elsif ($val =~ /console/) {
                $val =~ s/console//ig;
            } elsif ($val =~ /exceptions/) {
                $val =~ s/exceptions//ig;
                # TODO: What to do with this, if anything - qscintilla.pro
            } else {
                $fnd = 0;
                foreach $tmp (@arr) {
                    if ($val =~ /$tmp/) {
                        $val =~ s/$tmp//ig;
                        $fnd = 1;
                        last;
                    }
                }
                if (!$fnd) {
                    prtw("WARNING: 'CONFIG' item [$val] DISCARDED! FIX ME\n");
                    $val = '';
                }
            }
            $val = trim_all($val);
        }
        if ($cnt) {
            $cmake .= "\n";
        }
    }


    $cmake .= "message(STATUS \"*** Finding Qt4 components ${components}\")\n";
    $cmake .= "find_package ( Qt4 $components REQUIRED )\n";
    $cmake .= "include ( \${QT_USE_FILE} )\n";
    if ($use_static_lib) {
        # The solution is to define QT_NODLL in your .pro (DEFINES += QT_NODLL), 
        # as qmake automatically inserts -DQT_DLL when QT_NODLL is not defined 
        # (see mkspecs/features/qt.prf). 
        $cmake .= "add_definitions( -DQT_NODLL )\n";
    } else {
        $cmake .= "add_definitions( \${QT_DEFINITIONS} )\n";
    }
    if ($add_cmake_debug) {
        ${$rcm} .= "# debug messages\n";
        ${$rcm} .= "message(STATUS \"*** include \${QT_USE_FILE}\")\n";
        if (!$use_static_lib) {
            ${$rcm} .= "message(STATUS \"*** defs  \${QT_DEFINITIONS}\")\n";
        }
        ${$rcm} .= "message(STATUS \"*** libs \${QT_LIBRARIES}\")\n";
    }

    my %dupe_mods = ();
    if (length($qtvar)) {   # from = ${$rh}{'QT'};
        @arr = split(" ",$qtvar);
        $cnt = scalar @arr;
        prt("[v5] Got $cnt 'QT' items [".join(" ",sort @arr)."]\n") if (VERB5());
        #my %qmake_modules = (
        #    'core'    => '', # when negative handled QT_DONT_USE_QTCORE',  # (included by default)
        #    'gui'     => '', # when neg handled QT_DONT_USE_QTGUI',   # (included by default)
        #    'network' => 'QT_USE_QTNETWORK',
        #    'opengl'  => 'QT_USE_QTOPENGL',
        #    'sql'     => 'QT_USE_QTSQL',
        #    'svg'     => 'QT_USE_QTSVG',
        #    'xml'     => 'QT_USE_QTXML',
        #    'xmlpatterns' => 'QT_USE_QTXMLPATTERNS',
        #    'script' => 'QT_USE_QTSCRIPT',
        #    'webkit' => 'QT_USE_QTWEBKIT',
        #    'qt3support' => '' );
        $cnt = 0;
        foreach $tmp (@arr) {
            $tmp = trim_all($tmp);
            if (defined $qmake_modules{$tmp}) {
                $val = $qmake_modules{$tmp};
                if (length($val)) {
                    if (!defined $dupe_mods{$val}) {
                        $dupe_mods{$val} = 1;
                        $line = "set( $val TRUE )";
                        $cmake .= "$line\n";
                        prt("[v5] QT item: $tmp, added $line\n") if (VERB5());
                        $cnt++;
                    }
                } else {
                    if (($tmp eq 'core')||($tmp eq 'gui')) {
                        prt("[v5] QT item: $tmp, included by DEFAULT\n") if (VERB5());
                    } else {
                        prtw("WARNING: QT item: $tmp, defined, but NO VALUE!\n");
                    }
                }
            } else {
                if ($tmp eq 'webkit') {
                    prt("[v5] QT item: $tmp, included in 'COMPONENTS'\n") if (VERB5());
                } elsif ($tmp eq 'script') {
                    prt("[v5] QT item: $tmp, included in 'COMPONENTS'\n") if (VERB5());
                } else {
                    prtw("WARNING: QT item: $tmp, NOT DEFINED\n");
                }
            }
        }
        $cmake .= "\n" if ($cnt);
    }
    $cmake .= "\n";
    # =============================================================================================
    my $add_srcs = 0;
    my $add_hdrs = 0;
    my $add_others = 0;
    my $add_forms = 0;
    my $add_rsrcs = 0;
    my $missed_hdrs = 0;
    my $missed_srcs = 0;
    if (defined ${$rh}{'SOURCES'}) {
        $val = ${$rh}{'SOURCES'};
        @arr = space_split($val);
        $add_srcs = scalar @arr;
        ###$cmake .= "set( ${pname}_SRCS ".join(" ",@arr)." )\n\n";
        $cmake .= "set( ${pname}_SRCS\n";
        $line = '';
        foreach $tmp (@arr) {
            $cmake .= "    $tmp\n";
            if (! -f $tmp) {
                $missed_srcs++;
                if ($missed_srcs < 10) {
                    prtw("WARNING:$missed_srcs: Can NOT locate src '$tmp'\n");
                }
            }
        }
        $cmake .= "    )\n";
    } else {
        prtw("WARNING: Project [$pname] HAS NO SOURCES!!!\n");
        $cmake .= "# WARNING: Project [$pname] HAS NO SOURCES!!!\n";
    }
    if (defined ${$rh}{'HEADERS'}) {
        $val = ${$rh}{'HEADERS'};
        @arr = space_split($val);
        $add_hdrs = scalar @arr;
        ###$cmake .= "set( ${pname}_HDRS ".join(" ",@arr)." )\n\n";
        $cmake .= "set( ${pname}_HDRS\n";
        $line = '';
        foreach $tmp (@arr) {
            $cmake .= "    $tmp\n";
            $missed_hdrs++ if (! -f $tmp);
        }
        $cmake .= "    )\n";
    } else {
        #prt("NOTE: Project [$pname] HAS NO HEADERS!!!\n");
    }
    if (!$put_all_in_moc) {
        if (defined ${$rh}{'OTHERS'}) {
            $val = ${$rh}{'OTHERS'};
            @arr = space_split($val);
            $add_others = scalar @arr;
            ###$cmake .= "set( ${pname}_HDRS ".join(" ",@arr)." )\n\n";
            $cmake .= "set( ${pname}_OTHERS\n";
            $line = '';
            foreach $tmp (@arr) {
                $cmake .= "    $tmp\n";
            }
            $cmake .= "    )\n";
        } else {
            #prt("NOTE: Project [$pname] HAS NO OTHERS!!!\n");
        }
    }

    if (defined ${$rh}{'FORMS'}) {
        $val = ${$rh}{'FORMS'};
        @arr = space_split($val);
        $add_forms = scalar @arr;
        ###$cmake .= "set( ${pname}_FORMS ".join(" ",@arr)." )\n\n";
        $cmake .= "set( ${pname}_FORMS\n";
        $line = '';
        foreach $tmp (@arr) {
            $cmake .= "    $tmp\n";
        }
        $cmake .= "    )\n";
    }
    if (defined ${$rh}{'RESOURCES'}) {
        $val = ${$rh}{'RESOURCES'};
        @arr = space_split($val);
        $add_rsrcs = scalar @arr;
        ###$cmake .= "set( ${pname}_RCS ".join(" ",@arr)." )\n\n";
        $cmake .= "set( ${pname}_RCS\n";
        $line = '';
        foreach $tmp (@arr) {
            $cmake .= "    $tmp\n";
        }
        $cmake .= "    )\n";
    }
    $cmake .= "\n" if ($add_srcs || $add_hdrs || $add_forms || $add_rsrcs);

    my $rdh = ${$rh}{'curr_incs'};
    @arr = keys(%{$rdh});
    if (@arr) {
        $cmake .= "include_directories( ";
        $line = '';
        foreach $tmp (@arr) {
            $cmake .= "    $tmp\n";
        }
        # maybe ALSO add INCLUDE_DIRECTORIES(
        #    ${CMAKE_CURRENT_SOURCE_DIR}
        #    ${QT_INCLUDE_DIR}
        #)
        $cmake .= "    \${CMAKE_CURRENT_SOURCE_DIR}\n";
        $cmake .= "    \${QT_INCLUDE_DIR}\n";
        $cmake .= "    )\n";
    }
    if ($add_cmake_debug) {
        $cmake .= "# Added for DEBUG only\n";
        $cmake .= "get_property(inc_dirs DIRECTORY PROPERTY INCLUDE_DIRECTORIES)\n";
        $cmake .= "message(STATUS \"*** inc_dirs = \${inc_dirs}\")\n\n";
    }

    $cmake .= "QT4_WRAP_CPP( ${pname}_HDRS_MOC \${${pname}_HDRS} )\n" if ($add_hdrs);
    $cmake .= "QT4_WRAP_UI( ${pname}_FORMS_HDRS \${${pname}_FORMS} )\n" if ($add_forms);
    $cmake .= "QT4_ADD_RESOURCES( ${pname}_RESOURCES_RCC \${${pname}_RCS} )\n" if ($add_rsrcs);
    $cmake .= "\n" if ($add_hdrs || $add_forms || $add_rsrcs);

    if (defined ${$rh}{'TEMPLATE'}) {
        $val = ${$rh}{'TEMPLATE'};
    } else {
        $val = 'app';
    }
    #my %qmake_templates = (
    #'app' => 'Creates a Makefile to build an application.', # the default if NO TEMPLATE given
    #'lib' => 'Creates a Makefile to build a library.',
    #'subdirs' => 'Creates a Makefile containing rules for the subdirectories specified using the SUBDIRS variable. Each subdirectory must contain its own project file.',
    #'vcapp' => 'Creates a Visual Studio Project file to build an application.',
    #'vclib' => 'Creates a Visual Studio Project file to build a library.',
    #'vcsubdirs' => 'Creates a Visual Studio Solution file to build projects in sub-directories.' );
    # if(CONFIG.contains("plugin"))
    #     text << "MODULE ";
    # else
    #  text << "SHARED ";

    if (($val eq 'app')||($val eq 'vcapp')) {
        $cmake .= "add_executable( $pname \${${pname}_SRCS}";
    } elsif (($val eq 'lib')||($val eq 'vclib')) {
        $cmake .= "add_library( $pname \${${pname}_SRCS}";
    } else {
        pgm_exit(1,"ERROR: TEMPLATE of build [$val] NOT HANDLED!\n");
    }

    # add components to product
    $cmake .= " \${${pname}_HDRS_MOC}" if ($add_hdrs);
    $cmake .= " \${${pname}_FORMS_HDRS}" if ($add_forms);
    $cmake .= " \${${pname}_RESOURCES_RCC}" if ($add_rsrcs);
    $cmake .= " \${${pname}_OTHERS}" if ($add_others);
    $cmake .= " )\n";

    ${$rcm} .= "target_link_libraries( $pname \${QT_LIBRARIES} )\n";

    if (($val eq 'app')||($val eq 'vcapp')) {
        $cmake .= "if (MSVC)\n";
        $cmake .= "    set_target_properties( $pname PROPERTIES DEBUG_POSTFIX d )\n";
        $cmake .= "endif ()\n";
        $cmake .= "# deal with install \n";
        $cmake .= "install(TARGETS $pname DESTINATION bin )\n";
    } else {
        $cmake .= "# deal with install \n";
        $cmake .= "install( TARGETS $pname\n";
        $cmake .= "         RUNTIME DESTINATION bin\n";
        $cmake .= "         LIBRARY DESTINATION lib\n";
        $cmake .= "         ARCHIVE DESTINATION lib )\n";
    }

    # end of file
    $cmake .= "\n";
    $cmake .= "# eof - original generated by $pgmname, on ".lu_get_YYYYMMDD_hhmmss(time())."\n";

    # write to target file
    my $res = rename_2_old_bak($out_list_file);
    if ($res == 0) {
        $msg = "First time write of [$out_list_file]";
    } elsif ($res == 1) {
        $msg = "Renamed [$out_list_file] to [$out_list_file.old]";
    } elsif ($res == 2) {
        $msg = "Renamed [$out_list_file] to [$out_list_file.bak]";
    } elsif ($res == 3) {
        $msg = "Renamed [$out_list_file] to [$out_list_file.bak] deleting previous.";
    } else {
        pgm_exit(1,"ERROR: service rename_2_old_bak() returned other than 0, 1, 2 or 3 [$res}! Unknown return!\n");
    }
    prt("[v9] $msg\n") if (VERB9());
    write2file($cmake,$out_list_file);
    prt("Written [$out_list_file]\n"); # if (VERB1());
    prt("Srcs $add_srcs, NF $missed_srcs, Hdrs $add_hdrs, NF $missed_hdrs\n");

    if ($load_cmake_list) {
        if ($load_cmake_list == 1) {
            system("np $out_list_file");
        } else {
            system("ep $out_list_file");
        }
    }
}

#########################################
### MAIN ###
parse_args(@ARGV);
process_input($in_file);
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
            } elsif ($sarg =~ /^a/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $user_defines .= ";" if (length($user_defines));
                $user_defines .= $sarg;
                prt("Added a user define [$sarg]\n") if (VERB1());
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
                $load_log = 1;
                prt("Set to load log at end.\n") if (VERB1());
            } elsif ($sarg =~ /^n/) {   # project name
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $proj_name = $sarg;
                prt("Set project name to [$proj_name].\n") if (VERB1());
            } elsif ($sarg =~ /^t/) {   # target directory
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $usr_targ_dir = $sarg;
                prt("Set target root directory to [$usr_targ_dir].\n") if (VERB1());
            } elsif ($sarg =~ /^o/) {   # set output file
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $out_list_file = $sarg;
                prt("Set output file to [$out_list_file].\n") if (VERB1());
            } else {
                pgm_exit(1,"ERROR: Invalid argument [$arg]! Try -?\n");
            }
        } else {
            $in_file = $arg;
        }
        shift @av;
    }

    if ((length($in_file) ==  0) && $debug_on) {
        $in_file = $def_file;
        prt("Set DEFAULT input to [$in_file]\n");
        $usr_targ_dir = $def_targ;
        prt("Set DEFAULT target directory to [$usr_targ_dir]\n");
        #$load_log = 2;
        $load_cmake_list = 2;
    }
    if (length($in_file) ==  0) {
        pgm_exit(1,"ERROR: No input files found in command!\n");
    }
    if (! -f $in_file) {
        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
    }
}

sub get_ruby_text {
    my $txt = <<EOF;
#!/usr/bin/ruby -w
# from : http://www.cmake.org/Wiki/CMake:ConvertFromQmake
# Get the file into a string
file = IO.read(ARGV[0]);

# Convert special qmake variables
projectName = String.new;
file.sub!(/TARGET = (.+)\$/) {
    projectName = \$1.dup;
    "PROJECT(#{projectName})"
}
templateType = String.new;  # We remove the project type and stick it at the end
file.sub!(/TEMPLATE = (.+)\$\n/) {
    templateType = \$1.dup;
    ""
}
file.gsub!(/include\((.+)\)/,
           'INCLUDE(\1 OPTIONAL)');
file.gsub!(/includeforce\((.+)\)/,
           'INCLUDE(\1)');
file.gsub!(/INCLUDEPATH \*= (.+)((\n[ \t]+.+\$)*)/,
           'SET(CMAKE_INCLUDE_PATH \${CMAKE_INCLUDE_PATH} \1\2)');
file.gsub!(/SOURCES \*= (.+)((\n[ \t]+.+\$)*)/,
           "SET(#{projectName}_sources \$#{projectName}_sources" ' \1\2)');
file.gsub!(/HEADERS \*= (.+)((\n[ \t]+.+\$)*)/,
           "SET(#{projectName}_headers \$#{projectName}_headers" ' \1\2)');
file.gsub!(/DEFINES \*= (.+)((\n[ \t]+.+\$)*)/,
           'SET(DEFINES \${DEFINES} \1\2)');

# Now deal with other variables
file.gsub!(/(.+)\\s\*=\\s(.+)/,
           'SET(\1 \${\1} \2)');
file.gsub!(/(.+)\\s=\\s(.+)/,
           'SET(\1 \2)');
file.gsub!(/\\$\\$\{(.+)\}/,
           '\${\1}');
file.gsub!(/\\$\\$\((.+)\)/,
           '\$ENV{\1}');
file.gsub!(/([A-Za-z_\-.]+)\.pri/,
           '\1.cmake');

# Cleanup steps
file.gsub!(/\\\)/, ')');

# Put the project type back in
file += "ADD_EXECUTABLE(#{projectName} #{projectName}_sources)" if templateType == "app";
file += "ADD_LIBRARY(#{projectName} \${#{projectName}_sources})" if templateType == "lib";

# Write the new file to CMakeLists.txt
if ARGV.length > 1
    outname = ARGV[1];
else
    if ARGV[0] =~ /.+\.pro\$/
        outname = File.join(File.dirname(ARGV[0]), "CMakeLists.txt");
    elsif (ARGV[0] =~ /.+\.pri\$/) || (ARGV[0] =~ /.+\.prf\$/)
        outbase = File.basename(ARGV[0]);
        outbase.sub!(/\.pr./, ".cmake");
        outname = File.join(File.dirname(ARGV[0]), outbase)
    end
end
outfile = File.new(outname, "w");
outfile.puts(file);
outfile.close;

EOF
    return $txt;
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] <Project>.pro\n");
    prt("Options:\n");
    prt(" --help    (-h or -?) = This help, and exit 0.\n");
    prt(" --add def[:val] (-a) = Add a define, with '=val' if given.\n");
    prt(" --load          (-l) = Load LOG at end. ($outfile)\n");
    prt(" --name <proj>   (-n) = Set the project name.\n");
    prt(" --out <file>    (-o) = Write output to this file.\n");
    prt(" --targ <dir>    (-t) = Establish 'target' root directory.\n");
    prt(" --verb[n]       (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt("Aim is to convert a Qt <proj>.pro file to a <root>\\CMakeLists.txt file.\n");
    prt(" If no project name is given, then the name of the <project>.pro file is used.\n");
    prt(" If no target directory is given, then the path of <project>.pro file is used.\n");
    prt(" If an output file is given, then the cmake script is written to that,\n");
    prt(" else it is written to 'CMakeLists.txt' in the 'target' root directory, where\n");
    prt(" any existing CMakeLists.txt will be renamed to .old or .bak if one already exists.\n");
    prt(" The current list of qmake directives parsed is\n");
    prt(" ".join(" ",@qmake_nouns)."\n");
    prt(" Any others found will be shown as a WARNING!\n");
    prt(" A TODO item is to correctly write multiple CMakeLists.txt files, one for the root,\n");
    prt(" and one for each SUBDIR where source is to be compiled.\n");
}

# eof - Qt2cmake.pl
