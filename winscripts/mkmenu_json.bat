@echo off
REM mkmenu_json.bat — Generate a JSON menu file from a menu template.
REM
REM Usage: mkmenu_json.bat <template> <progname> [output]
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
set OUTPUT=%~3
if "%PROGNAME%"=="" set PROGNAME=passiflora
if "%OUTPUT%"=="" set OUTPUT=src\www\generated\PassifloraMenus.js

if "%TEMPLATE%"=="" (
    echo Usage: %~nx0 ^<template^> [progname] [output] >&2
    exit /b 1
)
if not exist "%TEMPLATE%" (
    echo Error: template file '%TEMPLATE%' not found >&2
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mkmenu_json.ps1" "%TEMPLATE%" "%PROGNAME%" "%OUTPUT%"

if errorlevel 1 (
    echo [ERROR] PowerShell failed generating %OUTPUT% >&2
    endlocal
    exit /b 1
)

echo mkmenu_json: %OUTPUT% generated from %TEMPLATE% (progname=%PROGNAME%)
endlocal
exit /b 0
