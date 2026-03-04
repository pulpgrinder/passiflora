@echo off
REM mkmenu.bat — Generate menu.c from a menu template file.
REM
REM Usage: mkmenu.bat <template> <progname> [output]
REM
REM Template format:
REM   - Indentation (tabs or groups of 4 spaces) sets nesting level
REM   - Level 0 entries become top-level menu bar items
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
if "%OUTPUT%"=="" set OUTPUT=src\C\generated\menu.c

if "%TEMPLATE%"=="" (
    echo Usage: %~nx0 ^<template^> [progname] [output] >&2
    exit /b 1
)
if not exist "%TEMPLATE%" (
    echo Error: template file '%TEMPLATE%' not found >&2
    exit /b 1
)

REM Run the PowerShell script that lives alongside this BAT
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0mkmenu.ps1" "%TEMPLATE%" "%PROGNAME%" "%OUTPUT%"

if errorlevel 1 (
    echo [ERROR] PowerShell failed generating %OUTPUT% >&2
    endlocal
    exit /b 1
)

echo mkmenu: %OUTPUT% generated from %TEMPLATE% (progname=%PROGNAME%)
endlocal
exit /b 0
