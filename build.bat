@echo off
REM build.bat — Master build script for Windows native builds.
REM
REM Usage:  build.bat [target]
REM
REM Targets:
REM   windows   — Build the Windows exe (default)
REM   android   — Build the Android APK
REM   icons     — Generate icon sets
REM   clean     — Remove build artifacts
REM   all       — windows (alias)
REM
REM Requires (for windows target):
REM   - GCC (MinGW-w64) on PATH   — or set WIN_CC
REM   - curl on PATH               (for WebView2Loader.dll download)
REM   - PowerShell                  (for zip/hex conversion)
REM
setlocal enabledelayedexpansion

set PROGNAME=HeckinChonker
set BUNDLE_ID=com.example.%PROGNAME%
set VERSION=1.0.0
set CONTENT=src\www

set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set WIN_BINDIR=%SCRIPT_DIR%\bin\Windows

if "%WIN_CC%"=="" set WIN_CC=gcc
if "%WIN_WINDRES%"=="" set WIN_WINDRES=windres

set WIN_CFLAGS=-Wall -Wextra -O2
set WIN_LDFLAGS=-lws2_32 -lshell32 -lgdi32 -lole32 -luuid -mwindows -static -lpthread

set WV2_NUGET_VER=1.0.2903.40
set WV2_NUGET_URL=https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/%WV2_NUGET_VER%

set TARGET=%~1
if "%TARGET%"=="" set TARGET=windows

if /I "%TARGET%"=="clean" goto :do_clean
if /I "%TARGET%"=="icons" goto :do_icons
if /I "%TARGET%"=="android" goto :do_android
if /I "%TARGET%"=="all" goto :do_all
if /I "%TARGET%"=="windows" goto :do_windows
echo Unknown target: %TARGET%
echo Usage: %~nx0 [windows^|android^|icons^|clean^|all]
exit /b 1

REM ================================================================
REM  clean
REM ================================================================
:do_clean
echo [clean] Removing build artifacts...
if exist "%SCRIPT_DIR%\src\C\generated" rmdir /S /Q "%SCRIPT_DIR%\src\C\generated" 2>nul
del /Q "%SCRIPT_DIR%\wv2loader.h" 2>nul
del /Q "%SCRIPT_DIR%\src\www\generated\systemid.js" 2>nul
if exist "%SCRIPT_DIR%\src\www\generated" rmdir /S /Q "%SCRIPT_DIR%\src\www\generated" 2>nul
if exist "%WIN_BINDIR%" (
    del /Q "%WIN_BINDIR%\%PROGNAME%.exe" 2>nul
    del /Q "%WIN_BINDIR%\app.rc" 2>nul
    del /Q "%WIN_BINDIR%\app_res.o" 2>nul
    rmdir "%WIN_BINDIR%" 2>nul
)
if exist "%SCRIPT_DIR%\bin\Android" (
    del /Q "%SCRIPT_DIR%\bin\Android\*.apk" 2>nul
    rmdir "%SCRIPT_DIR%\bin\Android" 2>nul
)
if exist "%SCRIPT_DIR%\bin\Android\gradle-build" rmdir /S /Q "%SCRIPT_DIR%\bin\Android\gradle-build" 2>nul
if exist "%SCRIPT_DIR%\bin\Android\gradle-cache" rmdir /S /Q "%SCRIPT_DIR%\bin\Android\gradle-cache" 2>nul
if exist "%SCRIPT_DIR%\src\android\.gradle" rmdir /S /Q "%SCRIPT_DIR%\src\android\.gradle" 2>nul
if exist "%SCRIPT_DIR%\src\android\app\.cxx" rmdir /S /Q "%SCRIPT_DIR%\src\android\app\.cxx" 2>nul
rmdir "%SCRIPT_DIR%\bin" 2>nul
echo [clean] Done.
goto :eof

REM ================================================================
REM  icons
REM ================================================================
:do_icons
call "%SCRIPT_DIR%\winscripts\buildicons.bat"
if errorlevel 1 exit /b 1
goto :eof

REM ================================================================
REM  android
REM ================================================================
:do_android
echo [android] Generating systemid.js for Android...
mkdir src\www\generated 2>nul
echo // Auto-generated file — DO NOT EDIT. This file is overwritten on every build.> src\www\generated\systemid.js
echo PASSIFLORA_OS_NAME = "Android";>> src\www\generated\systemid.js
echo [android] Generating zipdata.c...
mkdir src\C\generated 2>nul
call "%SCRIPT_DIR%\winscripts\mkzipfile.bat" %CONTENT% src\C\generated\zipdata.c
if errorlevel 1 exit /b 1
echo [android] Generating PassifloraMenus.js from src\android\menus\menu.txt...
call "%SCRIPT_DIR%\winscripts\mkmenu_json.bat" src\android\menus\menu.txt %PROGNAME% src\www\generated\PassifloraMenus.js
if errorlevel 1 exit /b 1
echo [android] Building APK...
call "%SCRIPT_DIR%\winscripts\mkandroid.bat" %PROGNAME% %BUNDLE_ID% %VERSION%
if errorlevel 1 exit /b 1
echo [android] Done.
goto :eof

REM ================================================================
REM  all
REM ================================================================
:do_all
call :do_windows
if errorlevel 1 exit /b 1
goto :eof

REM ================================================================
REM  windows
REM ================================================================
:do_windows

REM ── Step 1: Generate systemid.js ──
echo [windows] Generating systemid.js for Windows...
mkdir src\www\generated 2>nul
echo // Auto-generated file — DO NOT EDIT. This file is overwritten on every build.> src\www\generated\systemid.js
echo PASSIFLORA_OS_NAME = "Windows";>> src\www\generated\systemid.js

REM ── Step 2: Generate zipdata.c ──
echo [windows] Generating zipdata.c from %CONTENT%...
mkdir src\C\generated 2>nul
call "%SCRIPT_DIR%\winscripts\mkzipfile.bat" %CONTENT% src\C\generated\zipdata.c
if errorlevel 1 (
    echo [ERROR] mkzipfile.bat failed >&2
    exit /b 1
)

REM ── Step 2b: Generate PassifloraMenus.js for Windows ──
echo [windows] Generating PassifloraMenus.js from src\Windows\menus\menu.txt...
call "%SCRIPT_DIR%\winscripts\mkmenu_json.bat" src\Windows\menus\menu.txt %PROGNAME% src\www\generated\PassifloraMenus.js
if errorlevel 1 (
    echo [ERROR] mkmenu_json.bat failed >&2
    exit /b 1
)

REM ── Step 2c: Generate win_menu.c ──
echo [windows] Generating win_menu.c from src\Windows\menus\menu.txt...
call "%SCRIPT_DIR%\winscripts\mkmenu.bat" src\Windows\menus\menu.txt %PROGNAME% src\C\generated\win_menu.c
if errorlevel 1 (
    echo [ERROR] mkmenu.bat failed >&2
    exit /b 1
)

REM ── Step 3: Download and embed WebView2Loader.dll ──
if not exist "%SCRIPT_DIR%\wv2loader.h" (
    echo [windows] Downloading WebView2Loader.dll...
    mkdir "%WIN_BINDIR%" 2>nul

    curl -sL "%WV2_NUGET_URL%" -o "%WIN_BINDIR%\webview2.zip"
    if errorlevel 1 (
        echo [ERROR] Failed to download WebView2 NuGet package >&2
        exit /b 1
    )

    REM Extract just the x64 DLL using PowerShell
    powershell -NoProfile -Command ^
        "Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead('%WIN_BINDIR%\webview2.zip'); $entry = $zip.Entries | Where-Object { $_.FullName -like 'runtimes/win-x64/native/WebView2Loader.dll' } | Select-Object -First 1; if ($entry) { $stream = $entry.Open(); $fs = [System.IO.File]::Create('%WIN_BINDIR%\WebView2Loader.dll'); $stream.CopyTo($fs); $fs.Close(); $stream.Close() }; $zip.Dispose()"

    if not exist "%WIN_BINDIR%\WebView2Loader.dll" (
        echo [ERROR] Failed to extract WebView2Loader.dll from NuGet package >&2
        del /Q "%WIN_BINDIR%\webview2.zip" 2>nul
        exit /b 1
    )
    del /Q "%WIN_BINDIR%\webview2.zip" 2>nul

    echo [windows] Generating wv2loader.h...
    REM Convert DLL to C byte array using PowerShell
    powershell -NoProfile -Command ^
        "$bytes = [System.IO.File]::ReadAllBytes('%WIN_BINDIR%\WebView2Loader.dll');" ^
        "$sb = [System.Text.StringBuilder]::new();" ^
        "$sb.AppendLine('/* Generated - WebView2Loader.dll embedded as byte array */') | Out-Null;" ^
        "$sb.AppendLine('static const unsigned char wv2loader_dll[] = {') | Out-Null;" ^
        "$line = '';" ^
        "for ($i = 0; $i -lt $bytes.Length; $i++) {" ^
        "  if ($i -gt 0) { $line += ', ' };" ^
        "  if ($line.Length -gt 70) { $sb.AppendLine('  ' + $line) | Out-Null; $line = '' };" ^
        "  $line += '0x' + $bytes[$i].ToString('x2');" ^
        "};" ^
        "if ($line) { $sb.AppendLine('  ' + $line) | Out-Null };" ^
        "$sb.AppendLine('};') | Out-Null;" ^
        "$sb.AppendLine('static const unsigned int wv2loader_dll_len = ' + $bytes.Length + ';') | Out-Null;" ^
        "[System.IO.File]::WriteAllText('%SCRIPT_DIR%\wv2loader.h', $sb.ToString())"

    del /Q "%WIN_BINDIR%\WebView2Loader.dll" 2>nul
    echo [windows] wv2loader.h generated.
)

REM ── Step 4: Compile ──
echo [windows] Compiling %PROGNAME%.exe...
mkdir "%WIN_BINDIR%" 2>nul

REM Check for icon and windres for embedding app icon
set RES_OBJ=
set _ICON_PATH=%SCRIPT_DIR%\src\icons\builticons\windows\app.ico
if exist "%_ICON_PATH%" (
    where %WIN_WINDRES% >nul 2>&1
    if !errorlevel! equ 0 (
        set "_ICON_FWD=!_ICON_PATH:\=/!"
        echo 1 ICON "!_ICON_FWD!"> "%WIN_BINDIR%\app.rc"
        %WIN_WINDRES% "%WIN_BINDIR%\app.rc" -o "%WIN_BINDIR%\app_res.o"
        if !errorlevel! equ 0 (
            set RES_OBJ=%WIN_BINDIR%\app_res.o
        )
    )
)

%WIN_CC% %WIN_CFLAGS% -I. -o "%WIN_BINDIR%\%PROGNAME%.exe" src\C\passiflora.c src\C\UI.c %RES_OBJ% %WIN_LDFLAGS%
if errorlevel 1 (
    echo [ERROR] Compilation failed >&2
    exit /b 1
)

echo [windows] Build complete: %WIN_BINDIR%\%PROGNAME%.exe
goto :eof
