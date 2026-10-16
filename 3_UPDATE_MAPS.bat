@echo off
title CS 1.6 LAN Fun Server - Update maps
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install.ps1" -MapsOnly
pause
