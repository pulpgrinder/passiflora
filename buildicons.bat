@echo off
REM buildicons.bat — Generate all app icon sets.
REM This is a convenience wrapper around src\icons\buildiconset.bat.
REM Run this explicitly when you want to regenerate icons from source images.
REM
setlocal
set SCRIPT_DIR=%~dp0
if "%SCRIPT_DIR:~-1%"=="\" set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

call "%SCRIPT_DIR%\src\icons\buildiconset.bat"
if errorlevel 1 exit /b 1
