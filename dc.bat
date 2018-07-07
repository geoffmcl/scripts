@setlocal
@REM #======================================================================
@REM # download-and-compile.bat, dc.bat for short
@REM #
@REM # Build SG, FG, OSG, and TG Tools.
@REM # Copyright (C) 2018  Geoff R. McLane (geoffmcl) ubuntu@geoffair.info
@REM # Inspired by fg-from-scratch.cmd, by Scott Giese (xDraconian) scttgs0@gmail.com
@REM #
@REM # GNU GPL v2.0, or later - see LICENSE.txt for the copyright notice. 
@REM #
@REM # requires cmake, git, Qt5, MSVC installed
@REM # TODO: Lots of work to be done on configuration, options, etc... 
@REM # presently has some rigid default... lots of work... help needed...
@REM #======================================================================
@REM Deal with script version - pre release
@set DC_VERSION=0.0.11
@set DC_DATE=20180708
@REM Set VERSION dc.v0.2.bat 20180627
@REM Set VERSION dc.v0.1.bat 20180627
@REM Set VERSION dc.bat 20180626
@REM d-and-c.x64.bat v1.3.11 20160522 - use external make3rd.x64.bat ...
@REM Original: Clement de l'Hamaide - Oct 2013
@REM Required software: Visual Studio 10, CMake, SVN, GIT, gmp and libcgal
@set DC_TG_VERSION=N/A
@set ROOT_DIR=%CD%
@set DC_WANTS_HELP=
@set DC_ERRORS=0
@REM * -a y/n  y=do vcpkg update n=skip vcpkg update            default=y
@REM if /I "%TMPARG%" == "a" GOTO :SET_DO_UPDATES
@set DC_DO_UPDATES=y
@REM set DC_ARGUMENTS=CMAKE OSG PLIB OPENRTI SIMGEAR FGFS DATA FGRUN FGO FGX OPENRADAR ATCPIE TERRAGEAR TERRAGEARGUI
@REM set DC_ARGUMENTS=OSG PLIB SIMGEAR FGFS DATA TERRAGEAR TERRAGEARGUI
@set DC_ARGUMENTS=SIMGEAR FLIGHTGEAR FGDATA TERRAGEAR TERRAGEARGUI
@set DC_SET_ARGS=
@set DC_DEFAULT=SIMGEAR TERRAGEAR
@set DC_DO_OSG=y
@REM set DC_DO_BOOST=y
@REM * -r y|n  y=reconfigure programs before compiling them  n=do not reconfigure    default=y
@REM * -r y/n  y=reconfigure del CMakeLists.txt  n=do not reconfigure default=n
@REM if /I "%TMPARG%" == "r" GOTO :SET_DO_RECONFIG
@set DC_DO_CMAKE=y
@set DC_TRIPLET=x64-windows
@set DC_VCPKG_TRIP=--triplet %DC_TRIPLET%
@set ERROR_COUNT=0
@set FAILED_PROJ=
@set DOPAUSE=echo No pause requested
@set GIT_EXE=git
@set CMAKE_EXE=cmake
@REM set TMPDRV=x:
@REM if NOT EXIST %TMPDRV%\nul (
@REM echo Warning: The %TMPDRV% is not setup...
@REM )
@REM set DOPAUSE=pause
@REM Begin some configuration options... like download_and_compile.sh
@if %DC_TGBRANCH%x EQU x (
@set DC_TGBRANCH=next
)
@if %DC_TGREPO%x EQU x (
@set DC_TGREPO=https://git.code.sf.net/p/flightgear/terragear
)
@set DC_3RDPARTY=boost cgal curl freeglut freetype gdal glew jasper libxml2 openal-soft openjpeg openssl sdl2 tiff zlib
@REM set DC_3RDPARTY=boost cgal curl freeglut freetype gdal glew jasper libxml2 openal-soft openjpeg openssl sdl2 tiff zlib
@set DC_FGREPO=https://git.code.sf.net/p/flightgear/flightgear
@set DC_SGREPO=https://git.code.sf.net/p/flightgear/simgear
@set DC_OSGBRANCH=OpenSceneGraph-3.4
@REM TG GUI
@set "DC_TGGUI_REPO=git://git.code.sf.net/p/flightgear/fgscenery/terrageargui"
@set "DC_TGGUI_BRANCH=master"
@set TGGUI_INSTALL_DIR=%ROOT_DIR%/Stage
@REM fgdata
@set DC_FGDATA_REPO=git://git.code.sf.net/p/flightgear/fgdata
@set DC_FGDATA_BRANCH=next

@REM These should be passed in on command, or in environment...
@REM set OSG_DIR=%TMPDRV%\install\msvc140-64\OpenSceneGraph
@REM set BOOST_ROOT=C:\local\boost_1_62_0
@REM set BOOST_ROOT=C:\local\boost_1_61_0
@REM set BOOST_ROOT=%TMPDRV%\boost_1_60_0
@REM set BOOST_LIBRARYDIR=%BOOST_ROOT%\lib64-msvc-14.0

@REM SET QT5x64=C:/Qt/Qt5/5.10.1/msvc2017_64
@if "%QT5x64%x" == "x" (
@set QT5x64=D:\Qt5.6.1\5.6\msvc2015_64
)

@REM SET CMAKE_TOOLCHAIN="Visual Studio 15 2017 Win64"
@REM SET CMAKE_TOOLCHAIN="Visual Studio %VCVERS% %VCYEAR% Win64"
@if %CMAKE_TOOLCHAIN%x EQU x (
@SET CMAKE_TOOLCHAIN="Visual Studio 14 2015 Win64"
@REM SET CMAKE_TOOLCHAIN="Visual Studio 15 2017 Win64"
) else (
@echo Using external CMAKE_TOOLCHAIN=%CMAKE_TOOLCHAIN% 
)

@REM Some checks
@if NOT EXIST %QT5x64%\nul (
@echo Error: Unable to locate QT5 on %QT5x64%! *** FIX ME ***
@exit /b 1
)
@REM if NOT EXIST %OSG_DIR%\nul (
@REM echo Warning: Unable to locate OSG install %OSG_DIR%
@REM set DC_DO_OSG=y
@REM ) else (
@REM echo Skipping download and build of OSG, have %OSG_DIR%
@REM )

@set DC_PREFIX_PATH=%ROOT_DIR%/Stage;%ROOT_DIR%/vcpkg-git/installed/x64-windows

@REM if NOT EXIST %BOOST_ROOT%\nul (
@REM echo Warning: Unable to locate Boost %BOOST_ROOT%
@REM set DC_DO_BOOST=y
@REM	-DCMAKE_PREFIX_PATH:PATH=%DC_PREFIX_PATH%%ROOT_DIR%/Stage;%ROOT_DIR%/vcpkg-git/installed/x64-windows
@REM ) else (
@REM echo Using installed boost %BOOST_ROOT%
@REM set DC_PREFIX_PATH=%BOOST_ROOT%;%ROOT_DIR%/Stage;%ROOT_DIR%/vcpkg-git/installed/x64-windows
@REM )

@REM SET PATH=%PATH%;%ProgramFiles%/CMake/bin;%ROOT_DIR%/vcpkg-git/installed/x64-windows/bin
@set PATH=%PATH%;%ROOT_DIR%/vcpkg-git/installed/x64-windows/bin
@REM ####################################################
@REM command line parsing
:RPT
@if "%~1x" == "x" goto :GOTCMD
@set TMPARG=%~1
  @if "%TMPARG%" == "-h" GOTO :SET_WANTS_HELP
  @if "%TMPARG%" == "/h" GOTO :SET_WANTS_HELP
  @if "%TMPARG%" == "-?" GOTO :SET_WANTS_HELP
  @if "%TMPARG%" == "/?" GOTO :SET_WANTS_HELP
  @if "%TMPARG%" == "/help" GOTO :SET_WANTS_HELP
  @if "%TMPARG%" == "--help" GOTO :SET_WANTS_HELP

  @rem # At this point we're expecting a real argument and value.
  @if "%TMPARG:~0,1%" == "/" GOTO :PROCESS_ARGUMENT
  @if "%TMPARG:~0,1%" == "-" GOTO :PROCESS_ARGUMENT

  @rem # bare action option argument
  @if %TMPARG% EQU ALL GOTO :ADD_ARGUMENT
  
  @for %%i in (%DC_ARGUMENTS%) do @(
    @if "%TMPARG%" EQU "%%i" goto :ADD_ARGUMENT
  )
@GOTO ERROR_BAD_ARGUMENT

:SET_WANTS_HELP
@set DC_WANTS_HELP=y
@shift
@goto RPT
:PROCESS_ARGUMENT
@set TMPARG=%TMPARG:~1%
@if "%~2x" == "x" goto :ERROR_NO_ARGUMENT
@set TMPPARAM=%~2
@shift
@shift
@REM * -a y/n  y=do vcpkg update n=skip vcpkg update            default=y
@if /I "%TMPARG%" == "a" GOTO :SET_DO_UPDATES
@REM * -r y/n  y=reconfigure del CMakeLists.txt  n=do not reconfigure default=y
@if /I "%TMPARG%" == "r" GOTO :SET_DO_RECONFIG
@REM * -o y/n  y=do openscene graph  n=skip redoing OSG - default=y
@if /I "%TMPARG%" == "o" GOTO :SET_DO_OSG
@REM more args
@goto ERROR_UKNOWN_ARGUMENT
:SET_DO_OSG
@if /I "%TMPPARAM%" == "y" GOTO :SET_OSG
@if /I "%TMPPARAM%" == "n" GOTO :SET_OSG
@goto :ERROR_BAD_ARGUMENT2
:SET_OSG
@set DC_DO_OSG=%TMPPARAM%
@goto RPT

:SET_DO_RECONFIG
@if /I "%TMPPARAM%" == "y" GOTO :SET_RECONF
@if /I "%TMPPARAM%" == "n" GOTO :SET_RECONF
@goto :ERROR_BAD_ARGUMENT2
:SET_RECONF
@set DC_DO_CMAKE=%TMPPARAM%
@REM set DC_DO_RECONF=%TMPPARAM%
@goto RPT

:SET_DO_UPDATES
@if /I "%TMPPARAM%" == "y" GOTO :SET_UPDATE
@if /I "%TMPPARAM%" == "n" GOTO :SET_UPDATE
@goto :ERROR_BAD_ARGUMENT2

:SET_UPDATE
@set DC_DO_UPDATES=%TMPPARAM%
@goto RPT


:ERROR_NO_ARGUMENT
@shift
@echo.
@echo Appears no argument following %TMPARG%
:ERROR_BAD_ARGUMENT2
@echo Expect y or n...
@set /A DC_ERRORS+=1
@goto RPT
:ERROR_BAD_ARGUMENT
@echo.
@echo Command %TMPARG% NOT VALID
@echo Must be one of ALL, or one of
@echo %DC_ARGUMENTS%
@shift
@set /A DC_ERRORS+=1
@goto RPT
:ADD_ARGUMENT
@set DC_SET_ARGS=%DC_SET_ARGS% %TMPARG%
@shift
@goto RPT
:ERROR_UKNOWN_ARGUMENT
@echo Command -%TMPARG% %TMPPARAM% NOT VALID
@echo Add --help to see commands...
@set /A DC_ERRORS+=1
@goto RPT
@REM ####################################################
@REM End of command line parsing
:GOTCMD

@REM echo Got command
@if NOT "%DC_WANTS_HELP%x" == "x" goto :HELP

@REM No projects argment given, use default
@if "%DC_SET_ARGS%x" EQU "x" (
@set DC_SET_ARGS=%DC_DEFAULT%
) else (
    @if "%DC_SET_ARGS%x" EQU "ALLx" (
       @set DC_SET_ARGS=%DC_ARGUMENTS%
    )    
)

@if %DC_ERRORS% GTR 0 goto ISERR
@REM if NOT "%DC_ERRORS%x" == "0x" goto ISERR
@set DC_DO_OPTS=do update, -a %DC_DO_UPDATES%, do cmake, -r %DC_DO_CMAKE%, do osg -o %DC_DO_OSG%
@echo By dc %DC_VERSION%, %DC_DATE%, args %DC_SET_ARGS%, %DC_DO_OPTS%

@REM TODO: Seems boost IS required for some of the 3rdParty libs, so can NOT be avoided!
@REM if %DC_DO_BOOST% EQU y (
@REM     @set DC_3RDPARTY=boost %DC_3RDPARTY%
@REM     @echo Includng boost in vcpkg...
@REM ) else (
@REM     @echo Skipping Boost install - using %BOOST_LIBRARYDIR%
@REM )

@IF NOT EXIST vcpkg-git/NUL (
    @echo Preparing to install external libraries via vcpkg . . .
    git clone https://github.com/Microsoft/vcpkg.git vcpkg-git
    
    @echo Compiling vcpkg
    @cd vcpkg-git
    call ./bootstrap-vcpkg
    
    @echo Compiling external libraries . . . %DC_VCPKG_TRIP% %DC_3RDPARTY%
    vcpkg install %DC_VCPKG_TRIP% %DC_3RDPARTY%
) ELSE (
    @if %DC_DO_UPDATES% EQU y (
        @echo Updating vcpkg . . .
        @cd vcpkg-git
        @REM ========================
        call git pull
        
        @echo Updating vcpkg . . . %DC_VCPKG_TRIP%
        vcpkg update
        vcpkg upgrade %DC_VCPKG_TRIP% --no-dry-run

        @REM Okay to comment out this line once all the packages have been confirmed to have been installed
        @echo Updating external libraries . . . %DC_VCPKG_TRIP% %DC_3RDPARTY%
        vcpkg install %DC_VCPKG_TRIP% %DC_3RDPARTY%
        @REM ========================
        @cd %ROOT_DIR%

    ) else (
        @echo Skipping Updating vcpkg...
    )
)

@REM OSG HAS to be built once - but until version change, few updates... so skip if requested
@REM TODO: Should be able to switch OSG version
@IF NOT EXIST openscenegraph-3.4-git/NUL (
@set DC_DO_OSG=y
)
@if NOT EXIST %ROOT_DIR%/Stage/bin/osgversion.exe (
@set DC_DO_OSG=y
)

@if %DC_DO_OSG% EQU y (
@call :INSTALL_OSG
) else (
@echo Skip re-install of OSG... use installed OSG %OSG_DIR%
)

@IF NOT EXIST simgear-git/NUL (
	@mkdir simgear-build
	@echo Downloading SimGear . . .
	git clone -b next %DC_SGREPO% simgear-git
) ELSE (
	@echo Updating SimGear . . .
	@cd simgear-git
	@call git pull
    @cd %ROOT_DIR%
)

@IF NOT EXIST flightgear-git/NUL (
	@mkdir flightgear-build
	@echo Downloading FlightGear . . .
	git clone -b next %DC_FGREPO% flightgear-git
) ELSE (
	@echo Updating FlightGear . . .
	cd flightgear-git
	@call git pull
    @cd %ROOT_DIR%
)

@IF NOT EXIST terragear-git/NUL (
	@mkdir terragear-build
	@echo Downloading TerraGear . . .
	git clone -b %DC_TGBRANCH% %DC_TGREPO% terragear-git
) ELSE (
	@echo Updating TerraGear . . .
	@cd terragear-git
	@call git pull
    @cd %ROOT_DIR%
)

@if %DC_DO_OSG% EQU y (
@call :BUILD_OSG
) else (
@echo Skip build osg... use installed OSG %OSG_DIR%
)

@set DC_ACT=n
@set DC_PROJ=SIMGEAR
@for %%i in (%DC_SET_ARGS%) do @(if %%i EQU %DC_PROJ% (@set DC_ACT=y))
@if %DC_ACT% EQU y (
@echo Doing %DC_PROJ%
) else (
@echo Skip %DC_PROJ%
@goto DN_SG_PROJ
)

@echo.
@ECHO Compiling SimGear . . . do cmake %DC_DO_CMAKE%
@echo ##############################
@echo #########  %DC_PROJ%  ##########
@echo ##############################

@cd simgear-build
@if EXIST CMakeCache.txt (
    @if %DC_DO_CMAKE% EQU y (
        @del CMakeCache.txt
        @echo Reconfigure simgear built
    ) else (
       @goto :DN_SG_CMAKE
    )
)
@echo Doing 'cmake ..\simgear-git -G  %CMAKE_TOOLCHAIN% -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH:PATH=%DC_PREFIX_PATH%  -DCMAKE_INSTALL_PREFIX:PATH=%ROOT_DIR%/Stage'
@cmake ..\simgear-git -G  %CMAKE_TOOLCHAIN% ^
	-DCMAKE_BUILD_TYPE=Release ^
	-DCMAKE_PREFIX_PATH:PATH=%DC_PREFIX_PATH% ^
	-DCMAKE_INSTALL_PREFIX:PATH=%ROOT_DIR%/Stage
:DN_SG_CMAKE    
@echo Doing 'cmake --build . --config Release --target INSTALL'
@cmake --build . --config Release --target INSTALL
@if ERRORLEVEL 1 (
@set /A ERROR_COUNT+=1
@set FAILED_PROJ=%FAILED_PROJ% SimGear
)
@cd %ROOT_DIR%
@ECHO Done SimGear . . .
:DN_SG_PROJ

@REM :DOFG
@set DC_ACT=n
@set DC_PROJ=FLIGHTGEAR
@for %%i in (%DC_SET_ARGS%) do @(if %%i EQU %DC_PROJ% (@set DC_ACT=y))
@if %DC_ACT% EQU y (
@echo Doing %DC_PROJ%
) else (
@echo Skip %DC_PROJ%
@goto DN_FG_PROJ
)

@REM Currently broken. Intended for future use.
@REM Currently fails on PLIB, which does not seem in vcpkg, but can set ENV PLIBDIR to find installed PLIB
@REM Is 'next', so may fail time to time... like Jenkins...
@echo.
@ECHO Compiling FlightGear . . . do cmake %DC_DO_CMAKE%
@echo ##############################
@echo #########  %DC_PROJ%  ##########
@echo ##############################
@cd flightgear-build
@if EXIST CMakeCache.txt (
    @if %DC_DO_CMAKE% EQU y (
        @del CMakeCache.txt
        @echo Reconfigure flightgear built
    ) else (
        @echo Avoiding doing FG cmake...
        @goto :DN_FG_CMAKE
    )
)
@echo Doing 'cmake ..\flightgear-git -G  %CMAKE_TOOLCHAIN% -DCMAKE_PREFIX_PATH:PATH=%DC_PREFIX_PATH%;%QT5x64% -DCMAKE_INSTALL_PREFIX:PATH=%ROOT_DIR%/Stage -DOSG_FSTREAM_EXPORT_FIXED:BOOL=1'
@cmake ..\flightgear-git -G  %CMAKE_TOOLCHAIN% ^
    -DCMAKE_PREFIX_PATH:PATH=%DC_PREFIX_PATH%;%QT5x64% ^
    -DCMAKE_INSTALL_PREFIX:PATH=%ROOT_DIR%/Stage ^
 	-DOSG_FSTREAM_EXPORT_FIXED:BOOL=1
:DN_FG_CMAKE    
@echo Doing 'cmake --build . --config Release --target INSTALL'
@cmake --build . --config Release --target INSTALL
@if ERRORLEVEL 1 (
@set /A ERROR_COUNT+=1
@set FAILED_PROJ=%FAILED_PROJ% FlightGear
)
@cd %ROOT_DIR%
@ECHO Done FlightGear . . .
:DN_FG_PROJ

@REM :DOTERRA
@set DC_ACT=n
@set DC_PROJ=TERRAGEAR
@for %%i in (%DC_SET_ARGS%) do @(if %%i EQU %DC_PROJ% (@set DC_ACT=y))
@if %DC_ACT% EQU y (
@echo Doing %DC_PROJ%
) else (
@echo Skip %DC_PROJ%
@goto DN_TG_PROJ
)

@echo.
@ECHO Compiling TerraGear . . .  do cmake %DC_DO_CMAKE%
@echo ##############################
@echo #########  %DC_PROJ%  ##########
@echo ##############################
@cd terragear-build
@if EXIST CMakeCache.txt (
    @if %DC_DO_CMAKE% EQU y (
        @del CMakeCache.txt
        @echo Reconfigure terragear built
    ) else (
        @echo Avoiding doing TG cmake...
        @goto :DN_TG_CMAKE
    )
)
@echo Doing 'cmake ..\terragear-git -G  %CMAKE_TOOLCHAIN% -DCMAKE_PREFIX_PATH:PATH=%DC_PREFIX_PATH% -DCMAKE_INSTALL_PREFIX:PATH=%ROOT_DIR%/Stage'
@cmake ..\terragear-git -G  %CMAKE_TOOLCHAIN% ^
	-DCMAKE_PREFIX_PATH:PATH=%DC_PREFIX_PATH% ^
	-DCMAKE_INSTALL_PREFIX:PATH=%ROOT_DIR%/Stage
:DN_TG_CMAKE
@echo Doing 'cmake --build . --config Release --target INSTALL'
@cmake --build . --config Release --target INSTALL
@if ERRORLEVEL 1 (
@set /A ERROR_COUNT+=1
@set FAILED_PROJ=%FAILED_PROJ% TerraGear
)
@cd %ROOT_DIR%
:DN_TG_PROJ

@REM ############################################################
@set DC_ACT=n
@set DC_PROJ=terrageargui
@for %%i in (%DC_SET_ARGS%) do @(if /I %%i EQU %DC_PROJ% (@set DC_ACT=y))
@if %DC_ACT% EQU y (
@echo Doing %DC_PROJ% . . . do cmake %DC_DO_CMAKE%
) else (
@echo Skip %DC_PROJ%
@goto :DN_TGGUI_PROJ
)

@echo ##############################
@echo #########  %DC_PROJ%  ##########
@echo ##############################
@REM ########################################################
@REM ### clone/update source
@if EXIST %DC_PROJ%\nul (
	@CALL :_gitUpdate terrageargui
) ELSE (
    @echo Cloning "%DC_TGGUI_REPO%"...
	@call git clone -b %DC_TGGUI_BRANCH% %DC_TGGUI_REPO% %DC_PROJ%
    @if ERRORLEVEL 1 (
        @set /A ERROR_COUNT+=1
        @set FAILED_PROJ=%FAILED_PROJ% %DC_PROJ%
        @echo 'CALL %GIT_EXE% clone "%TG_REPO%"' FAILED!
        @goto :DN_TGGUI_BLD
    )
)

@REM ### configure and build source
@IF NOT exist %DC_PROJ%-build\nul @(mkdir %DC_PROJ%-build)
@REM in BUILD directory
@cd %DC_PROJ%-build
@if EXIST CMakeCache.txt (
    @if %DC_DO_CMAKE% EQU y (
        @del CMakeCache.txt
        @echo Reconfigure %DC_PROJ% built
    ) else (
        @echo Avoiding doing %DC_PROJ% cmake...
        @goto :DN_TGGUI_CMAKE
    )
)

@CALL "%CMAKE_EXE%" ..\%DC_PROJ% ^
		-G %CMAKE_TOOLCHAIN% ^
	    -DCMAKE_PREFIX_PATH:PATH=%DC_PREFIX_PATH% ^
		-DCMAKE_EXE_LINKER_FLAGS="/SAFESEH:NO" ^
		-DCMAKE_INSTALL_PREFIX:PATH="%TGGUI_INSTALL_DIR%"

:DN_TGGUI_CMAKE
@REM IF %COMPILE% EQU 1 (
	@CALL "%CMAKE_EXE%" --build . --config Release --target INSTALL
@REM )
    @if ERRORLEVEL 1 (
        @set /A ERROR_COUNT+=1
        @set FAILED_PROJ=%FAILED_PROJ% %DC_PROJ%
        @echo 'CALL %CMAKE_EXE% --build FAILED!
    )

@cd %ROOT_DIR%
:DN_TGGUI_BLD    

:DN_TGGUI_PROJ
@echo.
@REM ############################################################
@set DC_ACT=n
@set DC_PROJ=fgdata
@for %%i in (%DC_SET_ARGS%) do @(if /I %%i EQU %DC_PROJ% (@set DC_ACT=y))
@if %DC_ACT% EQU y (
@echo Doing %DC_PROJ% . . . do cmake %DC_DO_CMAKE%
) else (
@echo Skip %DC_PROJ%
@goto :DN_FGDATA_PROJ
)

@echo ##############################
@echo #########  %DC_PROJ%  ##########
@echo ##############################
@REM ########################################################
@REM ### clone/update source
@if EXIST %DC_PROJ%\nul (
	@CALL :_gitUpdate fgdata
) ELSE (
    @echo Cloning "%DC_FGDATA_REPO%"...
	@call git clone -b %DC_FGDATA_BRANCH% %DC_FGDATA_REPO% %DC_PROJ%
    @if ERRORLEVEL 1 (
        @set /A ERROR_COUNT+=1
        @set FAILED_PROJ=%FAILED_PROJ% %DC_PROJ%
        @echo 'CALL %GIT_EXE% clone "%TG_REPO%"' FAILED!
        @goto :DN_FGDATA_PROJ
    )
)

@echo Done %DC_PROJ% update...

@REM ############################################################
:DN_FGDATA_PROJ

@if EXIST terragear-git\version (
@set /P DC_TG_VERSION=< terragear-git\version
) else (
@echo Failed to locate TG version file
)

@if %ERROR_COUNT% EQU 0 (
@call :WRITE_BAT
@echo Done TerrGear - CD %ROOT_DIR%\Stage\bin - to use TG Tools v.%DC_TG_VERSION%
) else (
@echo Done %DC_SET_ARGS% . . . Need to maybe fix the errors...
)
@echo.
@REM ECHO Done dc.bat %DC_VERSION%, %DC_DATE%. Error count %ERROR_COUNT%, FAILED_PROJ=%FAILED_PROJ%, on args %DC_SET_ARGS%
@ECHO Done dc.bat %DC_VERSION%, %DC_DATE%. On args %DC_SET_ARGS%, Errors %ERROR_COUNT%, Failed=%FAILED_PROJ%, %DC_DO_OPTS%
@echo.

@%DOPAUSE%

@goto END

:WRITE_BAT
@set TMPBAT=%ROOT_DIR%\Stage\bin\run-exe.bat
@echo @setlocal > %TMPBAT%
@echo @set TMP3RD=%ROOT_DIR%\vcpkg-git\installed\x64-windows\bin>> %TMPBAT%
@echo @echo Run a TG Tool v.%DC_TG_VERSION%, by dc %DC_VERSION%, %DC_DATE% >> %TMPBAT%
@echo @if "%%~1x" == "x" goto :HELP >> %TMPBAT%
@echo @set PATH=%%TMP3RD%%;%%PATH%% >> %TMPBAT%
@echo %%* >> %TMPBAT%
@echo @goto END >> %TMPBAT%
@echo :HELP >> %TMPBAT%
@echo @echo Give name of exe, and command to run...>> %TMPBAT%
@echo :END >> %TMPBAT%
@echo Runtime run-exe bat to %TMPBAT%
@goto :EOF



:BUILD_OSG
@ECHO Compiling OpenSceneGraph . . . cmake %DC_DO_CMAKE%
@cd openscenegraph-3.4-build
@if %DC_DO_CMAKE% EQU n goto :DN_OSG_CMAKE
cmake ..\openscenegraph-3.4-git -G %CMAKE_TOOLCHAIN% ^
	-DACTUAL_3RDPARTY_DIR:PATH=%ROOT_DIR%/vcpkg-git/installed/x64-windows ^
	-DCMAKE_CONFIGURATION_TYPES=Debug;Release ^
	-DCMAKE_INSTALL_PREFIX:PATH=%ROOT_DIR%/Stage ^
	-DOSG_USE_UTF8_FILENAME:BOOL=1 ^
	-DWIN32_USE_MP:BOOL=1 ^
	-DCURL_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DCURL_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/libcurl.lib ^
	-DFREETYPE_INCLUDE_DIR_ft2build=%ROOT_DIR%/vcpkg-git/packages/freetype_x64-windows/include ^
	-DFREETYPE_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DFREETPE_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/freetype.lib ^
	-DGDAL_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DGDAL_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/gdal.lib ^
	-DGLUT_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DGLUT_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/freeglut.lib ^
	-DJPEG_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DJPEG_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/jpeg.lib ^
	-DLIBXML2_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DLIBXML2_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/libxml2.lib ^
	-DPNG_PNG_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DPNG_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/libpng16.lib ^
	-DSDL2_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DSDL2_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/SDL2.lib ^
	-DSDL2MAIN_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/manual-link/SDL2main.lib ^
	-DTIFF_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DTIFF_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/tiff.lib ^
	-DZLIB_INCLUDE_DIR=%ROOT_DIR%/vcpkg-git/installed/x64-windows/include ^
	-DZLIB_LIBRARY=%ROOT_DIR%/vcpkg-git/installed/x64-windows/lib/zlib.lib
:DN_OSG_CMAKE    
cmake --build . --config Release --target INSTALL
@if ERRORLEVEL 1 (
@set /A ERROR_COUNT+=1
@set FAILED_PROJ=%FAILED_PROJ% OpenSceneGraph
)
cd %ROOT_DIR%

@echo Testing OSG . . .
%ROOT_DIR%/Stage/bin/osgversion
@if "%ADD_OSGVIEW%x" == "1x" (
%ROOT_DIR%/Stage/bin/osgviewer %ROOT_DIR%/openscenegraph-data-git/cessnafire.osgt
)

@goto :EOF

:INSTALL_OSG
@REM TODO: Should be able to switch OSG version
@IF NOT EXIST openscenegraph-3.4-git/NUL (
	@mkdir openscenegraph-3.4-build
	@echo Downloading OpenSceneGraph . . .
	git clone -b %DC_OSGBRANCH% https://github.com/openscenegraph/OpenSceneGraph.git openscenegraph-3.4-git
) ELSE (
	@echo Updating OpenSceneGraph . . .
	@cd openscenegraph-3.4-git
	@call git pull
)
@cd %ROOT_DIR%

@IF NOT EXIST openscenegraph-data-git/NUL (
	@echo Downloading OpenSceneGraph Test Data . . .
	git clone https://github.com/openscenegraph/OpenSceneGraph-Data.git openscenegraph-data-git
) ELSE (
	@echo Updating OpenSceneGraph Test Data . . .
	cd openscenegraph-data-git
	@call git pull
)
@cd %ROOT_DIR%
@goto :EOF

:HELP
@echo.
@call :SHOW_HELP
@goto END

:SHOW_HELP
@echo.
@echo Usage: [options] [proj1 [proj2 ...]]
@echo Options:
@echo   --help   (-h) = Show this help and exit
@echo * -a y/n  y=do vcpkg update n=skip vcpkg update            default=y
@REM if /I "%TMPARG%" == "a" GOTO :SET_DO_UPDATES
@echo * -r y/n  y=reconfigure, ie del CMakeCache.txt n=do not reconfigure default=y
@REM if /I "%TMPARG%" == "r" GOTO :SET_DO_RECONFIG
@echo * -o y/n  y=do openscene graph  n=skip redoing OSG - default=y
@REM if /I "%TMPARG%" == "o" GOTO :SET_DO_OSG
@REM TODO: Need more options, and arg list not followed
@echo One or more of %DC_ARGUMENTS%
@echo * without options or with ALL it recompiles the content of the DC_SET_ARGS variable.
@echo * Feel you free to customize the DC_DEFAULT variable available on the top of this script
@echo.
@goto :EOF

REM ###########################    HELPER FUNCTION    ####################################
:_gitUpdate
    @REM @IF %PULL% EQU 1
    @if %DC_DO_UPDATES% EQU y (
       @echo Pulling %1...
		@cd %1
		@CALL %GIT_EXE% stash
		REM CALL %GIT_EXE% pull -r - what is this -r???
		@CALL %GIT_EXE% pull
		@CALL %GIT_EXE% stash pop
		@cd ..
	) else (
@REM * -a y/n  y=do vcpkg update n=skip vcpkg update            default=y
@REM if /I "%TMPARG%" == "a" GOTO :SET_DO_UPDATES
        @echo No update pull configured - -a %DC_DO_UPDATES%
    )
@GOTO :EOF

:ISERR
@endlocal
@echo Is error exit val=%DC_ERRORS%
@exit /b 1

:END
@endlocal
@exit /b 0

@REM eof
