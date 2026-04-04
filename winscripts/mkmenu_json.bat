@echo off
REM mkmenu_json.bat — Generate config.js with PassifloraConfig from a menu template.
REM
REM Usage: mkmenu_json.bat <template> <progname> <os_name> [output]
REM
REM Template format (same as mkmenu.bat):
REM   - Indentation (tabs or groups of 4 spaces) sets nesting level
REM   - Level 0 entries become top-level menu objects
REM   - Level 1+ entries become items within that menu
REM   - "-" alone means a separator
REM   - Blank lines are skipped
REM   - {{progname}} is replaced with the progname argument
REM
REM Requires: PowerShell 5+
REM
setlocal enabledelayedexpansion

set TEMPLATE=%~1
set PROGNAME=%~2
set OS_NAME=%~3
set OUTPUT=%~4
set THEME=%~5
set CONFIGFILE=%~6
if "%PROGNAME%"=="" set PROGNAME=passiflora
if "%OS_NAME%"=="" set OS_NAME=unknown
if "%OUTPUT%"=="" set OUTPUT=src\www\generated\config.js
if "%THEME%"=="" set THEME=Default
if "%CONFIGFILE%"=="" set CONFIGFILE=src\config

if "%TEMPLATE%"=="" (
    echo Usage: %~nx0 ^<template^> [progname] [os_name] [output] >&2
    exit /b 1
)
if not exist "%TEMPLATE%" (
    echo Error: template file '%TEMPLATE%' not found >&2
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mkmenu_json.ps1" "%TEMPLATE%" "%PROGNAME%" "%OS_NAME%" "%OUTPUT%" "%THEME%" "%CONFIGFILE%"

if errorlevel 1 (
    echo [ERROR] PowerShell failed generating %OUTPUT% >&2
    endlocal
    exit /b 1
)

echo mkmenu_json: %OUTPUT% generated from %TEMPLATE% (progname=%PROGNAME%, os=%OS_NAME%, theme=%THEME%)
endlocal
exit /b 0
