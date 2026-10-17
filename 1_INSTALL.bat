@echo off
rem Install: opens CS 1.6 Server Control, which does the rest in its window.
cd /d "%~dp0"
if not exist "%~dp04_SERVER_CONTROL.exe" (
    echo 4_SERVER_CONTROL.exe is missing. Unpack the complete package again.
    pause
    exit /b 1
)
start "" "%~dp04_SERVER_CONTROL.exe" --install
