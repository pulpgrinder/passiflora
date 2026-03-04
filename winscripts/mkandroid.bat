@echo off
REM mkandroid.bat — Build Android APK from the Gradle project.
REM
REM Usage: mkandroid.bat <progname> [bundleid] [version]
REM
REM Requires:
REM   - Android SDK (ANDROID_HOME or %LOCALAPPDATA%\Android\Sdk)
REM   - gradle on PATH
REM   - Java 17+
REM
REM Produces: bin\Android\<progname>.apk
REM
setlocal enabledelayedexpansion

if "%~1"=="" (
    echo Usage: %~nx0 ^<progname^> [bundleid] [version]
    exit /b 1
)

set PROGNAME=%~1
set BUNDLE_ID=%~2
if "%BUNDLE_ID%"=="" set BUNDLE_ID=com.example.passiflora
set VERSION=%~3
if "%VERSION%"=="" set VERSION=1.0.0

set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set PROJECT_ROOT=%SCRIPT_DIR%\..
for %%I in ("%PROJECT_ROOT%") do set PROJECT_ROOT=%%~fI
set ANDROID_DIR=%PROJECT_ROOT%\src\android
if "%BUILD_TYPE%"=="" set BUILD_TYPE=debug

REM ── Locate Android SDK ──
if "%ANDROID_HOME%"=="" (
    if exist "%LOCALAPPDATA%\Android\Sdk" (
        set ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk
    ) else if exist "%USERPROFILE%\AppData\Local\Android\Sdk" (
        set ANDROID_HOME=%USERPROFILE%\AppData\Local\Android\Sdk
    ) else if exist "C:\Android\Sdk" (
        set ANDROID_HOME=C:\Android\Sdk
    )
)
if "%ANDROID_HOME%"=="" (
    echo mkandroid: ANDROID_HOME not found. Set ANDROID_HOME. >&2
    exit /b 1
)
if not exist "%ANDROID_HOME%" (
    echo mkandroid: ANDROID_HOME directory does not exist: %ANDROID_HOME% >&2
    exit /b 1
)

REM ── Locate gradle ──
set GRADLE=
if exist "%ANDROID_DIR%\gradlew.bat" (
    set GRADLE=%ANDROID_DIR%\gradlew.bat
) else (
    where gradle >nul 2>&1
    if !errorlevel! equ 0 (
        set GRADLE=gradle
    )
)
if "%GRADLE%"=="" (
    echo mkandroid: gradle not found. >&2
    echo   Install Gradle and add to PATH, or generate gradlew first. >&2
    exit /b 1
)

REM ── Write local.properties ──
echo sdk.dir=%ANDROID_HOME:\=/%> "%ANDROID_DIR%\local.properties"

REM ── Generate gradle wrapper if missing ──
if not exist "%ANDROID_DIR%\gradlew.bat" (
    echo mkandroid: generating gradle wrapper...
    pushd "%ANDROID_DIR%"
    call "%GRADLE%" wrapper --gradle-version=8.5 --quiet 2>nul
    popd
    set GRADLE=%ANDROID_DIR%\gradlew.bat
)

REM ── Copy Android icons into res\ if builticons exist ──
set ICON_SRC=%PROJECT_ROOT%\src\icons\builticons\android\app\src\main\res
set RES_DIR=%ANDROID_DIR%\app\src\main\res
if exist "%ICON_SRC%" (
    for /d %%D in ("%ICON_SRC%\mipmap-*" "%ICON_SRC%\drawable-*") do (
        set DNAME=%%~nxD
        mkdir "%RES_DIR%\!DNAME!" 2>nul
        xcopy /Y /Q "%%D\*.png" "%RES_DIR%\!DNAME!\" >nul 2>&1
    )
    if exist "%ICON_SRC%\drawable" (
        mkdir "%RES_DIR%\drawable" 2>nul
        xcopy /Y /Q "%ICON_SRC%\drawable\*.png" "%RES_DIR%\drawable\" >nul 2>&1
    )
)

REM ── Update app_name from PROGNAME ──
set STRINGS=%RES_DIR%\values\strings.xml
if exist "%STRINGS%" (
    powershell -NoProfile -Command ^
        "$f = '%STRINGS%'; $c = [IO.File]::ReadAllText($f); $c = $c -replace '(?m)>.*?</string>', '>%PROGNAME%</string>'; [IO.File]::WriteAllText($f, $c)"
)

REM ── Update applicationId / versionName if non-default ──
set APP_GRADLE=%ANDROID_DIR%\app\build.gradle
if not "%BUNDLE_ID%"=="com.example.passiflora" (
    powershell -NoProfile -Command ^
        "$f = '%APP_GRADLE%'; $c = [IO.File]::ReadAllText($f); $c = $c -replace 'applicationId \""com.example.passiflora\""', 'applicationId \""%BUNDLE_ID%\""'; [IO.File]::WriteAllText($f, $c)"
)
if not "%VERSION%"=="1.0.0" (
    powershell -NoProfile -Command ^
        "$f = '%APP_GRADLE%'; $c = [IO.File]::ReadAllText($f); $c = $c -replace 'versionName \""1.0.0\""', 'versionName \""%VERSION%\""'; [IO.File]::WriteAllText($f, $c)"
)

REM ── Build ──
REM Capitalize first letter of BUILD_TYPE for Gradle task name
set _BT_FIRST=%BUILD_TYPE:~0,1%
set _BT_REST=%BUILD_TYPE:~1%
for %%A in (A B C D E F G H I J K L M N O P Q R S T U V W X Y Z) do set _BT_FIRST=!_BT_FIRST:%%A=%%A!
set GRADLE_TASK=assemble!_BT_FIRST!!_BT_REST!
echo mkandroid: building %BUILD_TYPE% APK (!GRADLE_TASK!)...
pushd "%ANDROID_DIR%"
call "%GRADLE%" !GRADLE_TASK! --quiet --project-cache-dir "%PROJECT_ROOT%\bin\Android\gradle-cache"
if !errorlevel! neq 0 (
    echo mkandroid: Gradle build failed >&2
    popd
    exit /b 1
)
popd

REM ── Copy APK to bin\Android\ ──
set APK_DIR=%PROJECT_ROOT%\bin\Android\gradle-build\app\outputs\apk\%BUILD_TYPE%
set APK=
for %%F in ("%APK_DIR%\*.apk") do (
    set APK=%%F
    goto :found_apk
)
:found_apk
if "%APK%"=="" (
    echo mkandroid: APK not found in build output >&2
    exit /b 1
)
mkdir "%PROJECT_ROOT%\bin\Android" 2>nul
copy /Y "%APK%" "%PROJECT_ROOT%\bin\Android\%PROGNAME%.apk" >nul
echo mkandroid: bin\Android\%PROGNAME%.apk created

endlocal
