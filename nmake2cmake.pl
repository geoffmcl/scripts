#!/usr/bin/perl -w
# NAME: namke2cmake.pl
# AIM: Try to covert the output of an nname build to a cmake CMakeLists.txt
# 02/09/2015 geoff mclane http://geoffair.net/mperl
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
my $VERS = "0.0.6 2015-09-02";  # first cut
my $load_log = 0;
my $in_file = '';
my $verbosity = 0;
my $out_file = $temp_dir.$PATH_SEP."temp.namke2cmake.txt";
my $user_target_dir = '';
my $user_proj_name = '';

# ### DEBUG ###
my $debug_on = 0;
my $def_file = 'F:\Projects\scintilla\win32\bldlog-1.txt';
my $def_target = 'F:\Projects\scintilla';

### program variables
my @warnings = ();

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

sub is_source_line($) {
    my $line = shift;
    return 1 if (is_c_source($line));

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

my %include_dirs = ();
sub collect_include_dirs($) {
    my ($rf) = @_;
    my ($name,$dir) = fileparse($rf);
    $dir =~ s/^\.(\\|\/)//;
    $dir =~ s/(\\|\/)$//;
    $include_dirs{$dir} = 1 if (length($dir));
}

sub get_include_dirs($) {
    my $rcm = shift;
    my @arr = keys %include_dirs;
    my $cnt = scalar @arr;
    return if ($cnt == 0);
    my $txt = "include_directories( ";
    my ($dir);
    foreach $dir (@arr) {
        $txt .= "$dir ";
    }
    $txt .= ")\n";
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


sub process_in_file($) {
    my ($inf) = @_;
    if (! open INF, "<$inf") {
        pgm_exit(1,"ERROR: Unable to open file [$inf]\n"); 
    }
    my @lines = <INF>;
    close INF;
    my $lncnt = scalar @lines;
    my ($i,$line,$inc,$lnn,$tline,$len,@arr,$cnt,$src,$ff);
    my ($n,$d,$e,$name,$ra,$ltyp,$msg);
    my ($nm,$dir) = fileparse($inf);
    my $rdir = '';
    if (length($user_target_dir)) {
        $rdir = get_rel_path($user_target_dir,$dir);
    }
    my $gotrel = length($rdir);
    my $pname = $user_proj_name;
    if (length($pname) == 0) {
        if (length($user_target_dir)) {
            $inc = File::Spec->rel2abs($user_target_dir);
            ($pname,$d) = fileparse($inc);
        }
    }
    if (length($pname) == 0) {
        $pname = "FIX_PROJECT_NAME";
    }
    $lnn = 0;
    my @srcs = ();
    my @psrcs = ();
    #my @ress = ();
    my $isdll = 0;
    my %projs = ();
    my %projtype = ();
    prt("Processing $lncnt lines, from [$inf]...\n") if (VERB5());
    for ($i = 0; $i < $lncnt; $i++) {
        $line = $lines[$i];
        chomp $line;
        $lnn = $i + 1;
        $tline = trim_all($line);
        $len = length($tline);
        next if ($len == 0);
        if ($tline =~ /^Copyright\s+/) {
        } elsif ($tline =~ /^Microsoft\s+/) {
        } elsif ($tline =~ /^Generating\s+/) {
        } elsif ($tline =~ /^Finished\s+/) {
        } elsif ($tline =~ /^rc\s+/i) {
            # 	rc -fo.\ScintRes.res ScintRes.rc
            @arr = split(/\s+/,$tline);
            $cnt = scalar @arr;
            foreach $src (@arr) {
                if ($src =~ /^rc/i) {
                } elsif ($src =~ /^-/) {

                } else {
                    # SOURCE RC file
                    if ($gotrel) {
                        $ff = $rdir.$src;
                        $ff = fix_rel_path($ff);
                        $src = path_d2u($ff);    # always unix for for cmake
                        collect_include_dirs($src);
                    }
                    prt("$lnn: RC '$src'\n");
                    push(@srcs,$src);
                }
            }

        } elsif ($tline =~ /^cl\s+/i) {
            # this can be a long line
            # cl -Zi -TP -MP -W4 -EHsc -Zc:forScope -Zc:wchar_t -D_CRT_SECURE_CPP_OVERLOAD_STANDARD_NAMES=1 -D_CRT_SECURE_NO_DEPRECATE=1 -O1 -MT -DNDEBUG -GL -I../include -I../src -I../lexlib -c -Fo.\ 
            # ..\lexers\LexA68k.cxx ..\lexers\LexAbaqus.cxx ..\lexers\LexAda.cxx ..\lexers\LexAPDL.cxx ..\lexers\LexAsm.cxx ...
            # ..\src\AutoComplete.cxx ..\src\CallTip.cxx ..\src\CaseConvert.cxx ..\src\CaseFolder.cxx ..\src\CellBuffer.cxx ..\src\CharClassify.cxx ..\src\ContractionState.cxx ..\src\Decoration.cxx ..\src\Document.cxx ..\src\EditModel.cxx ..\src\Editor.cxx ..\src\EditView.cxx ..\src\Indicator.cxx ..\src\KeyMap.cxx ..\src\LineMarker.cxx ..\src\MarginView.cxx ..\src\PerLine.cxx ..\src\PositionCache.cxx ..\src\RESearch.cxx ..\src\RunStyles.cxx ..\src\Selection.cxx ..\src\Style.cxx ..\src\UniConversion.cxx ..\src\ViewStyle.cxx ..\src\XPM.cxx ..\src\ScintillaBase.cxx 
            @arr = split(/\s+/,$tline);
            $cnt = scalar @arr;
            foreach $src (@arr) {
                if ($src =~ /^cl/i) {
                } elsif ($src =~ /^-/) {
                    # TODO: Should look for certain DEFINES to maybe add
                } else {
                    # SOURCE BEING COMPILED
                    if ($gotrel) {
                        $ff = $rdir.$src;
                        $ff = fix_rel_path($ff);
                        $src = path_d2u($ff);    # always unix for for cmake
                        collect_include_dirs($src);
                    }
                    prt("$lnn: src '$src'\n") if (VERB9());
                    push(@srcs,$src);
                }
            }
        } elsif ($tline =~ /^link\s+/i) {
            # perhaps a LONG line
            # 	link -OPT:REF -LTCG -DEBUG -DEF:Scintilla.def -DLL -OUT:..\bin\SciLexer.dll .\AutoComplete.obj .\CallTip.obj .\CaseConvert.obj .\CaseFolder.obj .\CellBuffer.obj 
            @arr = split(/\s+/,$tline);
            $cnt = scalar @arr;
            $name = "Unknown";
            foreach $src (@arr) {
                if ($src =~ /^link/i) {
                } elsif ($src =~ /^-/) {
                    if ($src =~ /^-DEF:(\w+\.\w+)$/) {
                        $inc = $1;
                        # definitions file
                        if ($gotrel) {
                            $ff = $rdir.$inc;
                            $ff = fix_rel_path($ff);
                            $inc = path_d2u($ff);    # always unix for for cmake
                            collect_include_dirs($inc);
                        }
                        prt("$lnn: DEF file '$inc'\n");
                        push(@srcs,$inc);
                    } elsif ($src =~ /^-OUT:(.+)$/) {
                        $inc = $1;
                        ($n,$d,$e) = fileparse($inc, qr/\.[^.]*/ );
                        $name = $n;
                        prt("$lnn: OUT file '$inc'\n");
                    } elsif ($src =~ /^-DLL/) {
                        prt("$lnn: Is DLL link\n");
                        $isdll = 1;
                    }
                } else {
                    prt("$lnn: obj/libs '$src'\n") if (VERB9());
                }
            }
            my @a = @srcs;
            $projs{$name} = \@a;
            $projtype{$name} = 'SHARED';
            @psrcs = @srcs;
            @srcs = (); # restart sources
        } elsif ($tline =~ /^lib\s+/i) {
            # 	LIB /OUT:Lexers.lib  .\LexA68k.obj  .\LexAbaqus.obj  .\LexAda.obj  .\LexAPDL.obj  .\LexAsm.obj  .\LexAsn1.obj  .\LexASY.obj  .\LexAU3.obj  .\LexAVE.obj  .\LexAVS.obj  
            @arr = split(/\s+/,$tline);
            $cnt = scalar @arr;
            $name = "Unknown";
            foreach $src (@arr) {
                if ($src =~ /^lib/i) {
                } elsif ($src =~ /^\//) {
                    if ($src =~ /^\/OUT:(.+)$/) {
                        $inc = $1;
                        ($n,$d,$e) = fileparse($inc, qr/\.[^.]*/ );
                        $name = $n;
                    }
                } else {
                    # could check the source list
                }
            }
            $cnt = scalar @srcs;
            if ($cnt == 0) {
                @srcs = @psrcs;
            }
            my @a = @srcs;
            $projs{$name} = \@a;
            $projtype{$name} = 'STATIC';
            @srcs = (); # restart sources
        } elsif (is_source_line($line)) {
        } elsif ($tline =~ /^Creating\s+/) {
        } elsif ($tline =~ /\s+\/LTCG/) {
        } else {
            prtw("WARNING:$lnn: Unparsed! '$tline' *** FIX ME ***\n");
        }
    }
    my $cmake = '';
    @arr = keys %projs;
    $cnt = scalar @arr;
    prt("Got $cnt projects...\n");
    my @libs = ();
    foreach $name (@arr) {
        $ra = $projs{$name};
        $cnt = scalar @{$ra};
        $ltyp = $projtype{$name};
        $msg = "### $name lib $ltyp, with $cnt sources...\n";
        $cmake .= "\n";
        $cmake .= $msg;
        prt($msg);
        $cmake .= "set(name $name)\n";
        $cmake .= "set(\${name}_SRCS\n";
        @libs = ();
        foreach $src (@{$ra}) {
            if ($src =~ /\.lib$/i) {
                push(@libs,$src);
            } else {
                $cmake .= "    $src\n";
            }
        }
        $cmake .= "    )\n";
        $cmake .= "add_library(\${name} $ltyp \${\${name}_SRCS})\n";
        $cmake .= "# target_link_libraries( \${name} \${QT_LIBRARIES} )\n";
        $cmake .= "# set_target_properties( \${name} PROPERTIES COMPILE_FLAGS \"-DQSCINTILLA_MAKE_DLL\")\n";
        $cmake .= "# list(APPEND add_LIBS \${name})\n";
        $cmake .= "# deal with install \n";
        $cmake .= "# install( TARGETS \${name}\n";
        $cmake .= "#         RUNTIME DESTINATION bin\n";
        $cmake .= "#         LIBRARY DESTINATION lib\n";
        $cmake .= "#         ARCHIVE DESTINATION lib )\n";
        $cmake .= "\n";
    }

    $msg = "###\n# Original CMakeLists.txt, generated from [$inf]\n\n";

    $msg .= "cmake_minimum_required( VERSION 2.8.8 )\n\n";

    # add_gui_message(\$cmake) if ($add_cmake_debug && VERB9());

    $msg .= "project( $pname )\n";

    add_compiler_block(\$msg);

    ##add_linux_windows(\$cmake) if ($add_linux_win);

    ##get_user_defines(\$cmake);  # add any USER defines
    get_include_dirs(\$msg);

    $msg .= $cmake;

    # end of file
    $msg .= "\n";
    $msg .= "# eof - original generated by $pgmname, on ".lu_get_YYYYMMDD_hhmmss(time())."\n";

    rename_2_old_bak($out_file);
    write2file($msg,$out_file);
    prt("Cmake script written to '$out_file'\n");
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
                prt("Set out file to [$out_file].\n") if ($verb);
            } elsif ($sarg =~ /^t/) {
                need_arg(@av);
                shift @av;
                $sarg = $av[0];
                $user_target_dir = $sarg;
                prt("Set target directory to [$user_target_dir].\n") if ($verb);
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
        $user_target_dir = $def_target;
    }
    if (length($in_file) ==  0) {
        give_help();
        pgm_exit(1,"\nERROR: No input files found in command!\n");
    }
    if (! -f $in_file) {
        pgm_exit(1,"ERROR: Unable to find in file [$in_file]! Check name, location...\n");
    }
}

sub give_help {
    prt("$pgmname: version $VERS\n");
    prt("Usage: $pgmname [options] in-file\n");
    prt("Options:\n");
    prt(" --help   (-h or -?) = This help, and exit 0.\n");
    prt(" --verb[n]      (-v) = Bump [or set] verbosity. def=$verbosity\n");
    prt(" --load         (-l) = Load LOG at end. ($outfile)\n");
    prt(" --out <file>   (-o) = Write output to this file.\n");
    prt(" -- proj <name> (-p) = Set the project name.\n");
    prt(" --targ <dir>   (-t) = Set target directory for CMakeLists.txt\n");
    prt("\n");
    prt(" Given an nmake build log, try to convert it to projects, sources...\n");
    prt("\n");
}

# eof - template.pl
