@echo off
REM build.bat — Master build script for Windows native builds.
REM
REM Usage:  build.bat [target]
REM
REM Targets:
REM   windows   — Build the Windows exe (default)
REM   android   — Build the Android APK
REM   www       — Build plain-browser version into bin\WWW\
REM   icons     — Generate icon sets
REM   sign-windows — Sign the Windows exe with Azure Trusted Signing (requires jsign)
REM   clean     — Remove build artifacts
REM   all       — windows (alias)
REM
REM Requires (for windows target):
REM   - GCC (MinGW-w64) on PATH   — or set WIN_CC
REM   - curl on PATH               (for WebView2Loader.dll download)
REM   - PowerShell                  (for zip/hex conversion)
REM
setlocal enabledelayedexpansion

set VERSION=1.0.0
set CONTENT=src\www

set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set WIN_BINDIR=%SCRIPT_DIR%\bin\Windows

if "%WIN_CC%"=="" set WIN_CC=gcc
if "%WIN_WINDRES%"=="" set WIN_WINDRES=windres

REM ── Read settings from src\config ──
set PROGNAME=
set BUNDLE_ID=
if exist "%SCRIPT_DIR%\src\config" (
    for /F "tokens=1,*" %%A in (%SCRIPT_DIR%\src\config) do (
        if /I "%%A"=="PROGNAME"             set PROGNAME=%%B
        if /I "%%A"=="DISPLAYNAME"          set DISPLAYNAME=%%B
        if /I "%%A"=="BUNDLE_ID"            set BUNDLE_ID=%%B
        if /I "%%A"=="uselocation"          if /I "%%B"=="true" set PERM_LOCATION=true
        if /I "%%A"=="usecamera"            if /I "%%B"=="true" set PERM_CAMERA=true
        if /I "%%A"=="usemicrophone"        if /I "%%B"=="true" set PERM_MICROPHONE=true
        if /I "%%A"=="allowremotedebugging" if /I "%%B"=="true" set PERM_REMOTEDEBUGGING=true
        if /I "%%A"=="theme" set THEME=%%B
        if /I "%%A"=="port" set CFGPORT=%%B
    )
)
if "!PROGNAME!"=="" set PROGNAME=HeckinChonker
if "!DISPLAYNAME!"=="" set DISPLAYNAME=!PROGNAME!
if "!BUNDLE_ID!"=="" set BUNDLE_ID=com.pulpgrinder.!PROGNAME!

set WIN_CFLAGS=-Wall -Wextra -O2 -D__USE_MINGW_ANSI_STDIO=1 -DPROGNAME_STR=\"!PROGNAME!\"
set WIN_LDFLAGS=-lws2_32 -lshell32 -lgdi32 -lole32 -luuid -mwindows -static -lpthread
if "!PERM_LOCATION!"=="true" set WIN_CFLAGS=!WIN_CFLAGS! -DPERM_LOCATION
if "!PERM_CAMERA!"=="true" set WIN_CFLAGS=!WIN_CFLAGS! -DPERM_CAMERA
if "!PERM_MICROPHONE!"=="true" set WIN_CFLAGS=!WIN_CFLAGS! -DPERM_MICROPHONE
if "!PERM_REMOTEDEBUGGING!"=="true" set WIN_CFLAGS=!WIN_CFLAGS! -DPERM_REMOTEDEBUGGING
if "%THEME%"=="" set THEME=default
if defined CFGPORT (
    set WIN_CFLAGS=!WIN_CFLAGS! -DDEFAULT_PORT=!CFGPORT!
)

set WV2_NUGET_VER=1.0.2903.40
set WV2_NUGET_URL=https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/%WV2_NUGET_VER%

set TARGET=%~1
if "%TARGET%"=="" set TARGET=windows

if /I "%TARGET%"=="clean" goto :do_clean
if /I "%TARGET%"=="icons" goto :do_icons
if /I "%TARGET%"=="android" goto :do_android
if /I "%TARGET%"=="sign-android" goto :do_sign_android
if /I "%TARGET%"=="googleplay-android" goto :do_googleplay_android
if /I "%TARGET%"=="www" goto :do_www
if /I "%TARGET%"=="sign-windows" goto :do_sign_windows
if /I "%TARGET%"=="all" goto :do_all
if /I "%TARGET%"=="windows" goto :do_windows
if /I "%TARGET%"=="newproject" goto :do_newproject
echo Unknown target: %TARGET%
echo Usage: %~nx0 [windows^|sign-windows^|android^|sign-android^|googleplay-android^|www^|icons^|clean^|newproject^|all]
exit /b 1

REM ================================================================
REM  clean
REM ================================================================
:do_clean
echo [clean] Removing build artifacts...
if exist "%SCRIPT_DIR%\src\C\generated" rmdir /S /Q "%SCRIPT_DIR%\src\C\generated" 2>nul
del /Q "%SCRIPT_DIR%\wv2loader.h" 2>nul
if exist "%SCRIPT_DIR%\src\www\generated" rmdir /S /Q "%SCRIPT_DIR%\src\www\generated" 2>nul
if exist "%WIN_BINDIR%" (
    del /Q "%WIN_BINDIR%\%DISPLAYNAME%.exe" 2>nul
    del /Q "%WIN_BINDIR%\app.rc" 2>nul
    del /Q "%WIN_BINDIR%\app_res.o" 2>nul
    rmdir "%WIN_BINDIR%" 2>nul
)
if exist "%SCRIPT_DIR%\bin\Android" (
    del /Q "%SCRIPT_DIR%\bin\Android\*.apk" 2>nul
    del /Q "%SCRIPT_DIR%\bin\Android\*.aab" 2>nul
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
mkdir src\www\generated 2>nul
mkdir src\C\generated 2>nul
echo [android] Generating generated.js and generated.css...
call "%SCRIPT_DIR%\winscripts\mkgenerated.bat" src\android\menus\menu.txt %PROGNAME% Android "%THEME%" src\config
if errorlevel 1 exit /b 1
echo [android] Generating zipdata.h...
call "%SCRIPT_DIR%\winscripts\mkzipfile.bat" %CONTENT% src\C\generated\zipdata.h
if errorlevel 1 exit /b 1
echo [android] Building APK...
call "%SCRIPT_DIR%\winscripts\mkandroid.bat" %PROGNAME% %BUNDLE_ID% %VERSION%
if errorlevel 1 exit /b 1
echo [android] Done.
goto :eof

REM ================================================================
REM  sign-android
REM ================================================================
:do_sign_android
set SIGNING_SETUP_BAT=%USERPROFILE%\passiflora-keys\signing_setup.bat
if exist "%SIGNING_SETUP_BAT%" (
    echo [sign-android] Loading signing env from %SIGNING_SETUP_BAT%...
    call "%SIGNING_SETUP_BAT%"
    if errorlevel 1 exit /b 1
)

call :do_android
if errorlevel 1 exit /b 1

set ANDROID_APK=%SCRIPT_DIR%\bin\Android\%PROGNAME%.apk
if not exist "%ANDROID_APK%" (
    echo [sign-android] APK not found: %ANDROID_APK% >&2
    exit /b 1
)

if defined RELEASE_KEYSTORE (
    set KS_FILE=%RELEASE_KEYSTORE%
    echo [sign-android] Using keystore from RELEASE_KEYSTORE
) else (
    set KS_FILE=%USERPROFILE%\passiflora-keys\android-keystore.jks
)
if not exist "!KS_FILE!" (
    set KS_FILE=
    set /p KS_FILE="Keystore file: "
    if "!KS_FILE!"=="" (
        echo [sign-android] No keystore file specified. >&2
        exit /b 1
    )
    if not exist "!KS_FILE!" (
        echo [sign-android] Keystore not found: !KS_FILE! >&2
        exit /b 1
    )
) else (
    echo [sign-android] Using keystore !KS_FILE!
)
if defined RELEASE_KEYSTORE_PASSWORD (
    set KS_PASS=%RELEASE_KEYSTORE_PASSWORD%
    echo [sign-android] Using keystore password from RELEASE_KEYSTORE_PASSWORD
) else (
    for /f "delims=" %%P in ('powershell -NoProfile -Command "[Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host 'Keystore password' -AsSecureString)))"') do set KS_PASS=%%P
    if "!KS_PASS!"=="" (
        echo [sign-android] No password specified. >&2
        exit /b 1
    )
)

REM ── Locate apksigner ──
set APKSIGNER=
if defined ANDROID_HOME (
    for /f "delims=" %%F in ('dir /b /s "%ANDROID_HOME%\build-tools\apksigner.bat" 2^>nul') do (
        set APKSIGNER=%%F
    )
)
if "%APKSIGNER%"=="" (
    where apksigner >nul 2>&1
    if !errorlevel! equ 0 (
        set APKSIGNER=apksigner
    ) else (
        echo [sign-android] apksigner not found. Set ANDROID_HOME or add build-tools to PATH. >&2
        exit /b 1
    )
)

REM ── Locate zipalign ──
set ZIPALIGN=
if defined ANDROID_HOME (
    for /f "delims=" %%F in ('dir /b /s "%ANDROID_HOME%\build-tools\zipalign.exe" 2^>nul') do (
        set ZIPALIGN=%%F
    )
)
if not "%ZIPALIGN%"=="" (
    echo [sign-android] Zipaligning APK...
    "%ZIPALIGN%" -f 4 "%ANDROID_APK%" "%ANDROID_APK%.aligned"
    if errorlevel 1 (
        echo [sign-android] zipalign failed >&2
        exit /b 1
    )
    move /Y "%ANDROID_APK%.aligned" "%ANDROID_APK%" >nul
) else (
    echo [sign-android] Warning: zipalign not found, skipping alignment.
)

echo [sign-android] Signing %ANDROID_APK%...
echo %KS_PASS%| call "%APKSIGNER%" sign --ks "%KS_FILE%" --ks-pass stdin "%ANDROID_APK%"
if errorlevel 1 (
    echo [sign-android] Signing failed >&2
    exit /b 1
)

echo [sign-android] Verifying signature...
call "%APKSIGNER%" verify "%ANDROID_APK%"
if errorlevel 1 (
    echo [sign-android] Verification failed >&2
    exit /b 1
)

echo [sign-android] %ANDROID_APK% signed successfully.
goto :eof

REM ================================================================
REM  googleplay-android
REM ================================================================
:do_googleplay_android
mkdir src\www\generated 2>nul
mkdir src\C\generated 2>nul
echo [googleplay-android] Generating generated.js and generated.css...
call "%SCRIPT_DIR%\winscripts\mkgenerated.bat" src\android\menus\menu.txt %PROGNAME% Android "%THEME%" src\config
if errorlevel 1 exit /b 1
echo [googleplay-android] Generating zipdata.h...
call "%SCRIPT_DIR%\winscripts\mkzipfile.bat" %CONTENT% src\C\generated\zipdata.h
if errorlevel 1 exit /b 1
echo [googleplay-android] Building AAB...
set BUILD_TYPE=release
set BUILD_FORMAT=aab
call "%SCRIPT_DIR%\winscripts\mkandroid.bat" %PROGNAME% %BUNDLE_ID% %VERSION%
if errorlevel 1 exit /b 1
echo [googleplay-android] Done.
goto :eof

REM ================================================================
REM  www
REM ================================================================
:do_www
set WWW_BINDIR=%SCRIPT_DIR%\bin\WWW

mkdir src\www\generated 2>nul

echo [www] Generating generated.js and generated.css...
call "%SCRIPT_DIR%\winscripts\mkgenerated.bat" src\www\menus\menu.txt %PROGNAME% WWW "%THEME%" src\config
if errorlevel 1 (
    echo [ERROR] mkgenerated.bat failed >&2
    exit /b 1
)

if exist "%WWW_BINDIR%" rmdir /S /Q "%WWW_BINDIR%"
mkdir "%WWW_BINDIR%" 2>nul

echo [www] Copying src\www to %WWW_BINDIR%...
xcopy /S /E /Q /Y "%SCRIPT_DIR%\src\www\*" "%WWW_BINDIR%\" >nul
if errorlevel 1 (
    echo [ERROR] Copy failed >&2
    exit /b 1
)

echo.
echo === WWW target ready (bin\WWW\) ===
echo Run the development server with:
echo   python webserver.py
echo Then open http://localhost:8000 in your browser.
echo.
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

mkdir src\www\generated 2>nul
mkdir src\C\generated 2>nul

REM ── Step 1: Generate generated.js and generated.css for Windows (before zip!) ──
echo [windows] Generating generated.js and generated.css...
call "%SCRIPT_DIR%\winscripts\mkgenerated.bat" src\Windows\menus\menu.txt %PROGNAME% Windows "%THEME%" src\config
if errorlevel 1 (
    echo [ERROR] mkgenerated.bat failed >&2
    exit /b 1
)

REM ── Step 2: Generate zipdata.h (now includes generated.js) ──
echo [windows] Generating zipdata.h from %CONTENT%...
call "%SCRIPT_DIR%\winscripts\mkzipfile.bat" %CONTENT% src\C\generated\zipdata.h
if errorlevel 1 (
    echo [ERROR] mkzipfile.bat failed >&2
    exit /b 1
)

REM ── Step 2c: Generate win_menu.h ──
echo [windows] Generating win_menu.h from src\Windows\menus\menu.txt...
call "%SCRIPT_DIR%\winscripts\mkmenu.bat" src\Windows\menus\menu.txt %PROGNAME% src\C\generated\win_menu.h
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
echo [windows] Compiling %DISPLAYNAME%.exe...
mkdir "%WIN_BINDIR%" 2>nul

REM Check for icon and windres for embedding app icon + VERSIONINFO
set RES_OBJ=
set _ICON_PATH=%SCRIPT_DIR%\src\icons\builticons\windows\app.ico
if exist "%_ICON_PATH%" (
    where %WIN_WINDRES% >nul 2>&1
    if !errorlevel! equ 0 (
        set "_ICON_FWD=!_ICON_PATH:\=/!"
        > "%WIN_BINDIR%\app.rc" (
            echo 1 ICON "!_ICON_FWD!"
            echo.
            echo 1 VERSIONINFO
            echo FILEVERSION 1,0,0,0
            echo PRODUCTVERSION 1,0,0,0
            echo BEGIN
            echo   BLOCK "StringFileInfo"
            echo   BEGIN
            echo     BLOCK "040904b0"
            echo     BEGIN
            echo       VALUE "ProductName", "!DISPLAYNAME!\0"
            echo       VALUE "FileDescription", "!DISPLAYNAME!\0"
            echo       VALUE "FileVersion", "!VERSION!\0"
            echo       VALUE "ProductVersion", "!VERSION!\0"
            echo       VALUE "InternalName", "!PROGNAME!\0"
            echo       VALUE "OriginalFilename", "!DISPLAYNAME!.exe\0"
            echo     END
            echo   END
            echo   BLOCK "VarFileInfo"
            echo   BEGIN
            echo     VALUE "Translation", 0x0409, 0x04B0
            echo   END
            echo END
        )
        %WIN_WINDRES% "%WIN_BINDIR%\app.rc" -o "%WIN_BINDIR%\app_res.o"
        if !errorlevel! equ 0 (
            set RES_OBJ=%WIN_BINDIR%\app_res.o
        )
    )
)

%WIN_CC% %WIN_CFLAGS% -I. -o "%WIN_BINDIR%\%DISPLAYNAME%.exe" src\C\passiflora.c src\C\UI.c %RES_OBJ% %WIN_LDFLAGS%
if errorlevel 1 (
    echo [ERROR] Compilation failed >&2
    exit /b 1
)

echo [windows] Build complete: %WIN_BINDIR%\%DISPLAYNAME%.exe
goto :eof

REM ================================================================
REM  sign-windows (Azure Trusted Signing via jsign)
REM ================================================================
:do_sign_windows
set SIGNING_SETUP_BAT=%USERPROFILE%\passiflora-keys\signing_setup.bat
if exist "%SIGNING_SETUP_BAT%" (
    echo [sign-windows] Loading signing env from %SIGNING_SETUP_BAT%...
    call "%SIGNING_SETUP_BAT%"
    if errorlevel 1 exit /b 1
)

call :do_windows
if errorlevel 1 exit /b 1

if not exist "%WIN_BINDIR%\%DISPLAYNAME%.exe" (
    echo [sign-windows] exe not found: %WIN_BINDIR%\%DISPLAYNAME%.exe >&2
    exit /b 1
)

where jsign >nul 2>&1
if errorlevel 1 (
    echo [sign-windows] jsign not found on PATH. >&2
    echo         Install with: scoop install jsign  or  choco install jsign >&2
    exit /b 1
)

if "%AZURE_SIGNING_ENDPOINT%"=="" (
    echo [sign-windows] AZURE_SIGNING_ENDPOINT not set. >&2
    echo         Set it to your Artifact Signing endpoint, e.g. https://eus.codesigning.azure.net >&2
    exit /b 1
)
if "%AZURE_SIGNING_ACCOUNT%"=="" (
    echo [sign-windows] AZURE_SIGNING_ACCOUNT not set. >&2
    exit /b 1
)
if "%AZURE_SIGNING_PROFILE%"=="" (
    echo [sign-windows] AZURE_SIGNING_PROFILE not set. >&2
    exit /b 1
)

echo [sign-windows] Obtaining Azure access token...
for /F "tokens=*" %%T in ('az account get-access-token --resource https://codesigning.azure.net --query accessToken -o tsv 2^>nul') do set AZURE_TOKEN=%%T
if "%AZURE_TOKEN%"=="" (
    echo [sign-windows] Failed to obtain Azure access token. >&2
    echo         Make sure the Azure CLI is installed and you are logged in (az login^). >&2
    exit /b 1
)

echo [sign-windows] Signing %WIN_BINDIR%\%DISPLAYNAME%.exe...
jsign --storetype TRUSTEDSIGNING --keystore "%AZURE_SIGNING_ENDPOINT%" --storepass "%AZURE_TOKEN%" --alias "%AZURE_SIGNING_ACCOUNT%/%AZURE_SIGNING_PROFILE%" --tsaurl http://timestamp.acs.microsoft.com "%WIN_BINDIR%\%DISPLAYNAME%.exe"
if errorlevel 1 (
    echo [sign-windows] Signing failed >&2
    exit /b 1
)

echo [sign-windows] %WIN_BINDIR%\%DISPLAYNAME%.exe signed successfully.
goto :eof

REM ================================================================
REM  newproject
REM ================================================================
:do_newproject
where gh >nul 2>&1
if errorlevel 1 (
    echo [newproject] GitHub CLI ^(gh^) is required but not found. >&2
    echo         Install from: https://cli.github.com/ >&2
    exit /b 1
)
where git >nul 2>&1
if errorlevel 1 (
    echo [newproject] git is required but not found. >&2
    exit /b 1
)
set NEWNAME=
set /p NEWNAME="New project name: "
if "!NEWNAME!"=="" (
    echo [newproject] No name provided. >&2
    exit /b 1
)
echo [newproject] Creating new GitHub repository: !NEWNAME!
if exist ".git" rmdir /S /Q ".git"
git init
if errorlevel 1 exit /b 1
git add .
if errorlevel 1 exit /b 1
git commit -m "Initial commit"
if errorlevel 1 exit /b 1
gh repo create "!NEWNAME!" --private --source=. --remote=origin --push
if errorlevel 1 (
    echo [newproject] Failed to create GitHub repository. >&2
    exit /b 1
)
echo.
echo [newproject] New project '!NEWNAME!' created and pushed to GitHub.
goto :eof
