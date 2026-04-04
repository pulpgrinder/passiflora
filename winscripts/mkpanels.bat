@echo off
REM mkpanels.bat — Generate panels.js from HTML/JS files in passiflora\panels.
REM Usage: mkpanels.bat [panels_dir] [output]
setlocal enabledelayedexpansion

set PANELS_DIR=%~1
set OUTPUT=%~2
if "%PANELS_DIR%"=="" set PANELS_DIR=src\www\passiflora\panels
if "%OUTPUT%"=="" set OUTPUT=src\www\generated\panels.js

REM Ensure output directory exists
for %%D in ("%OUTPUT%") do if not exist "%%~dpD" mkdir "%%~dpD"

REM Delegate to PowerShell for reliable text processing
powershell -ExecutionPolicy Bypass -File "%~dp0mkpanels.ps1" "%PANELS_DIR%" "%OUTPUT%"
if errorlevel 1 (
    echo [ERROR] mkpanels failed >&2
    exit /b 1
)
