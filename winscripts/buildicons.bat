@echo off
REM buildicons.bat — Generate all app icon sets.
REM This is a convenience wrapper around src\icons\buildiconset.bat.
REM Run this explicitly when you want to regenerate icons from source images.
REM
setlocal
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%
set PROJECT_ROOT=%SCRIPT_DIR%\..
for %%I in ("%PROJECT_ROOT%") do set PROJECT_ROOT=%%~fI

call "%PROJECT_ROOT%\src\icons\buildiconset.bat"
if errorlevel 1 exit /b 1
