@echo off
REM mkgenerated.bat — Build generated.js and generated.css from framework files.
REM
REM Usage: mkgenerated.bat <menu_template> <progname> <os_name> <theme> <configfile>
REM
REM Reads boolean flags from <configfile> and concatenates the appropriate
REM JS/CSS framework files into src\www\generated\generated.js and generated.css.
REM
REM Requires: PowerShell 5+
REM
setlocal enabledelayedexpansion

set TEMPLATE=%~1
set PROGNAME=%~2
set OS_NAME=%~3
set THEME=%~4
set CONFIGFILE=%~5
if "%PROGNAME%"=="" set PROGNAME=passiflora
if "%OS_NAME%"=="" set OS_NAME=unknown
if "%THEME%"=="" set THEME=Default
if "%CONFIGFILE%"=="" set CONFIGFILE=src\config

if "%TEMPLATE%"=="" (
    echo Usage: %~nx0 ^<template^> [progname] [os_name] [theme] [configfile] >&2
    exit /b 1
)
if not exist "%TEMPLATE%" (
    echo Error: template file '%TEMPLATE%' not found >&2
    exit /b 1
)

REM Ensure output directory exists
mkdir src\www\generated 2>nul

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mkgenerated.ps1" ^
    "%TEMPLATE%" "%PROGNAME%" "%OS_NAME%" "%THEME%" "%CONFIGFILE%"

if errorlevel 1 (
    echo [ERROR] mkgenerated failed >&2
    exit /b 1
)

endlocal
exit /b 0
