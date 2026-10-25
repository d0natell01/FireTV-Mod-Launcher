@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0FireTV_Mod_Launcher.ps1"
if errorlevel 1 pause
