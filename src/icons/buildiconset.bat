@echo off
REM buildiconset.bat — Generate all app icons for macOS, iOS, Android, and Windows
REM from two source images in the same directory as this script.
REM
REM Requires: ImageMagick (magick.exe) on PATH.
REM
setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
REM Remove trailing backslash
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

set SQUARE_FILE=%SCRIPT_DIR%\squareicon.png
set CIRCULAR_FILE=%SCRIPT_DIR%\roundicon.png
set DST_PATH=%SCRIPT_DIR%\builticons

REM ── Locate ImageMagick ──
set CONVERT=
where magick >nul 2>&1 && set CONVERT=magick
if "%CONVERT%"=="" where convert >nul 2>&1 && set CONVERT=convert
if "%CONVERT%"=="" (
    echo [ERROR] ImageMagick is not installed. Please install it first.
    exit /b 1
)

if not exist "%SQUARE_FILE%" (
    echo [ERROR] squareicon.png not found in %SCRIPT_DIR%
    exit /b 1
)
if not exist "%CIRCULAR_FILE%" (
    echo [ERROR] roundicon.png not found in %SCRIPT_DIR%
    exit /b 1
)

REM ── Create output directories ──
mkdir "%DST_PATH%\macos\AppIcon.iconset" 2>nul
mkdir "%DST_PATH%\ios" 2>nul
mkdir "%DST_PATH%\windows" 2>nul
mkdir "%DST_PATH%\android\app\src\main\assets\public\assets\images" 2>nul
mkdir "%DST_PATH%\android\app\src\main\res\drawable" 2>nul
for %%D in (hdpi mdpi xhdpi xxhdpi xxxhdpi) do (
    mkdir "%DST_PATH%\android\app\src\main\res\drawable-land-%%D" 2>nul
    mkdir "%DST_PATH%\android\app\src\main\res\drawable-port-%%D" 2>nul
    mkdir "%DST_PATH%\android\app\src\main\res\mipmap-%%D" 2>nul
)

REM ================================================================
REM  macOS — AppIcon.iconset
REM ================================================================
echo [INFO] Generating macOS icons (AppIcon.iconset)...
set ICONSET=%DST_PATH%\macos\AppIcon.iconset

%CONVERT% "%SQUARE_FILE%" -resize 16x16     "%ICONSET%\icon_16x16.png"
%CONVERT% "%SQUARE_FILE%" -resize 32x32     "%ICONSET%\icon_16x16@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 32x32     "%ICONSET%\icon_32x32.png"
%CONVERT% "%SQUARE_FILE%" -resize 64x64     "%ICONSET%\icon_32x32@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 128x128   "%ICONSET%\icon_128x128.png"
%CONVERT% "%SQUARE_FILE%" -resize 256x256   "%ICONSET%\icon_128x128@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 256x256   "%ICONSET%\icon_256x256.png"
%CONVERT% "%SQUARE_FILE%" -resize 512x512   "%ICONSET%\icon_256x256@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 512x512   "%ICONSET%\icon_512x512.png"
%CONVERT% "%SQUARE_FILE%" -resize 1024x1024 "%ICONSET%\icon_512x512@2x.png"

REM ================================================================
REM  iOS — Universal icon + legacy sizes
REM ================================================================
echo [INFO] Generating iOS icons...
set IOS=%DST_PATH%\ios

%CONVERT% "%SQUARE_FILE%" -resize 1024x1024 "%IOS%\AppIcon-1024.png"
%CONVERT% "%SQUARE_FILE%" -resize 20x20     "%IOS%\Icon-20.png"
%CONVERT% "%SQUARE_FILE%" -resize 40x40     "%IOS%\Icon-20@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 60x60     "%IOS%\Icon-20@3x.png"
%CONVERT% "%SQUARE_FILE%" -resize 29x29     "%IOS%\Icon-29.png"
%CONVERT% "%SQUARE_FILE%" -resize 58x58     "%IOS%\Icon-29@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 87x87     "%IOS%\Icon-29@3x.png"
%CONVERT% "%SQUARE_FILE%" -resize 40x40     "%IOS%\Icon-40.png"
%CONVERT% "%SQUARE_FILE%" -resize 80x80     "%IOS%\Icon-40@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 120x120   "%IOS%\Icon-40@3x.png"
%CONVERT% "%SQUARE_FILE%" -resize 60x60     "%IOS%\Icon-60.png"
%CONVERT% "%SQUARE_FILE%" -resize 120x120   "%IOS%\Icon-60@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 180x180   "%IOS%\Icon-60@3x.png"
%CONVERT% "%SQUARE_FILE%" -resize 76x76     "%IOS%\Icon-76.png"
%CONVERT% "%SQUARE_FILE%" -resize 152x152   "%IOS%\Icon-76@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 167x167   "%IOS%\Icon-83.5@2x.png"
%CONVERT% "%SQUARE_FILE%" -resize 512x512   "%IOS%\iTunesArtwork.png"
%CONVERT% "%SQUARE_FILE%" -resize 1024x1024 "%IOS%\iTunesArtwork@2x.png"

REM ================================================================
REM  Windows — ICO file + individual PNGs
REM ================================================================
echo [INFO] Generating Windows icons...
set WIN=%DST_PATH%\windows

for %%S in (16 24 32 48 64 128 256) do (
    %CONVERT% "%SQUARE_FILE%" -resize %%Sx%%S "%WIN%\icon-%%S.png"
)

%CONVERT% "%SQUARE_FILE%" -resize 44x44     "%WIN%\Square44x44Logo.png"
%CONVERT% "%SQUARE_FILE%" -resize 50x50     "%WIN%\StoreLogo-50.png"
%CONVERT% "%SQUARE_FILE%" -resize 71x71     "%WIN%\SmallTile-71.png"
%CONVERT% "%SQUARE_FILE%" -resize 150x150   "%WIN%\Square150x150Logo.png"
%CONVERT% "%SQUARE_FILE%" -resize 310x310   "%WIN%\Square310x310Logo.png"
%CONVERT% "%SQUARE_FILE%" -resize 310x150   "%WIN%\Wide310x150Logo.png"

%CONVERT% "%SQUARE_FILE%" -resize 44x44     "%WIN%\Square44x44Logo.scale-100.png"
%CONVERT% "%SQUARE_FILE%" -resize 55x55     "%WIN%\Square44x44Logo.scale-125.png"
%CONVERT% "%SQUARE_FILE%" -resize 66x66     "%WIN%\Square44x44Logo.scale-150.png"
%CONVERT% "%SQUARE_FILE%" -resize 88x88     "%WIN%\Square44x44Logo.scale-200.png"
%CONVERT% "%SQUARE_FILE%" -resize 176x176   "%WIN%\Square44x44Logo.scale-400.png"

%CONVERT% "%SQUARE_FILE%" -resize 150x150   "%WIN%\Square150x150Logo.scale-100.png"
%CONVERT% "%SQUARE_FILE%" -resize 188x188   "%WIN%\Square150x150Logo.scale-125.png"
%CONVERT% "%SQUARE_FILE%" -resize 225x225   "%WIN%\Square150x150Logo.scale-150.png"
%CONVERT% "%SQUARE_FILE%" -resize 300x300   "%WIN%\Square150x150Logo.scale-200.png"
%CONVERT% "%SQUARE_FILE%" -resize 600x600   "%WIN%\Square150x150Logo.scale-400.png"

for %%S in (16 24 32 48 256) do (
    %CONVERT% "%SQUARE_FILE%" -resize %%Sx%%S "%WIN%\Square44x44Logo.targetsize-%%S.png"
)

echo [INFO] Building app.ico...
%CONVERT% "%WIN%\icon-16.png" "%WIN%\icon-24.png" "%WIN%\icon-32.png" ^
          "%WIN%\icon-48.png" "%WIN%\icon-64.png" "%WIN%\icon-128.png" ^
          "%WIN%\icon-256.png" "%WIN%\app.ico"

REM ================================================================
REM  Android — Adaptive icons, legacy icons, splash screens
REM ================================================================
echo [INFO] Generating Android icons...
set ANDROID=%DST_PATH%\android\app\src\main\res

%CONVERT% "%SQUARE_FILE%" -resize 512x512 "%DST_PATH%\android\app\src\main\assets\public\assets\images\logo.png"
%CONVERT% "%SQUARE_FILE%" -resize 512x512 "%DST_PATH%\android\play_store_icon.png"

echo [INFO] Generating adaptive icon foreground layers...
%CONVERT% "%SQUARE_FILE%" -resize 108x108 "%ANDROID%\mipmap-mdpi\ic_launcher_foreground.png"
%CONVERT% "%SQUARE_FILE%" -resize 162x162 "%ANDROID%\mipmap-hdpi\ic_launcher_foreground.png"
%CONVERT% "%SQUARE_FILE%" -resize 216x216 "%ANDROID%\mipmap-xhdpi\ic_launcher_foreground.png"
%CONVERT% "%SQUARE_FILE%" -resize 324x324 "%ANDROID%\mipmap-xxhdpi\ic_launcher_foreground.png"
%CONVERT% "%SQUARE_FILE%" -resize 432x432 "%ANDROID%\mipmap-xxxhdpi\ic_launcher_foreground.png"

echo [INFO] Generating round launcher icons...
%CONVERT% "%CIRCULAR_FILE%" -resize 48x48   "%ANDROID%\mipmap-mdpi\ic_launcher_round.png"
%CONVERT% "%CIRCULAR_FILE%" -resize 72x72   "%ANDROID%\mipmap-hdpi\ic_launcher_round.png"
%CONVERT% "%CIRCULAR_FILE%" -resize 96x96   "%ANDROID%\mipmap-xhdpi\ic_launcher_round.png"
%CONVERT% "%CIRCULAR_FILE%" -resize 144x144 "%ANDROID%\mipmap-xxhdpi\ic_launcher_round.png"
%CONVERT% "%CIRCULAR_FILE%" -resize 192x192 "%ANDROID%\mipmap-xxxhdpi\ic_launcher_round.png"

echo [INFO] Generating legacy launcher icons...
%CONVERT% "%SQUARE_FILE%" -resize 48x48   "%ANDROID%\mipmap-mdpi\ic_launcher.png"
%CONVERT% "%SQUARE_FILE%" -resize 72x72   "%ANDROID%\mipmap-hdpi\ic_launcher.png"
%CONVERT% "%SQUARE_FILE%" -resize 96x96   "%ANDROID%\mipmap-xhdpi\ic_launcher.png"
%CONVERT% "%SQUARE_FILE%" -resize 144x144 "%ANDROID%\mipmap-xxhdpi\ic_launcher.png"
%CONVERT% "%SQUARE_FILE%" -resize 192x192 "%ANDROID%\mipmap-xxxhdpi\ic_launcher.png"

echo [INFO] Generating monochrome icons for Android 13+ themed icons...
%CONVERT% "%SQUARE_FILE%" -resize 108x108 -colorspace Gray "%ANDROID%\mipmap-mdpi\ic_launcher_monochrome.png"
%CONVERT% "%SQUARE_FILE%" -resize 162x162 -colorspace Gray "%ANDROID%\mipmap-hdpi\ic_launcher_monochrome.png"
%CONVERT% "%SQUARE_FILE%" -resize 216x216 -colorspace Gray "%ANDROID%\mipmap-xhdpi\ic_launcher_monochrome.png"
%CONVERT% "%SQUARE_FILE%" -resize 324x324 -colorspace Gray "%ANDROID%\mipmap-xxhdpi\ic_launcher_monochrome.png"
%CONVERT% "%SQUARE_FILE%" -resize 432x432 -colorspace Gray "%ANDROID%\mipmap-xxxhdpi\ic_launcher_monochrome.png"

echo [INFO] Generating notification icons...
%CONVERT% "%SQUARE_FILE%" -resize 24x24 "%ANDROID%\mipmap-mdpi\ic_stat_notify.png"
%CONVERT% "%SQUARE_FILE%" -resize 36x36 "%ANDROID%\mipmap-hdpi\ic_stat_notify.png"
%CONVERT% "%SQUARE_FILE%" -resize 48x48 "%ANDROID%\mipmap-xhdpi\ic_stat_notify.png"
%CONVERT% "%SQUARE_FILE%" -resize 72x72 "%ANDROID%\mipmap-xxhdpi\ic_stat_notify.png"
%CONVERT% "%SQUARE_FILE%" -resize 96x96 "%ANDROID%\mipmap-xxxhdpi\ic_stat_notify.png"

echo [INFO] Generating splash screens...
%CONVERT% -size 430x320   canvas:#bbb "%ANDROID%\drawable\splash.png"
%CONVERT% -size 800x480   canvas:#bbb "%ANDROID%\drawable-land-hdpi\splash.png"
%CONVERT% -size 480x320   canvas:#bbb "%ANDROID%\drawable-land-mdpi\splash.png"
%CONVERT% -size 1280x720  canvas:#bbb "%ANDROID%\drawable-land-xhdpi\splash.png"
%CONVERT% -size 1600x960  canvas:#bbb "%ANDROID%\drawable-land-xxhdpi\splash.png"
%CONVERT% -size 1920x1280 canvas:#bbb "%ANDROID%\drawable-land-xxxhdpi\splash.png"
%CONVERT% -size 480x800   canvas:#bbb "%ANDROID%\drawable-port-hdpi\splash.png"
%CONVERT% -size 320x480   canvas:#bbb "%ANDROID%\drawable-port-mdpi\splash.png"
%CONVERT% -size 720x1280  canvas:#bbb "%ANDROID%\drawable-port-xhdpi\splash.png"
%CONVERT% -size 960x1600  canvas:#bbb "%ANDROID%\drawable-port-xxhdpi\splash.png"
%CONVERT% -size 1280x1920 canvas:#bbb "%ANDROID%\drawable-port-xxxhdpi\splash.png"

echo [INFO] All done! Icons generated in: %DST_PATH%
endlocal
