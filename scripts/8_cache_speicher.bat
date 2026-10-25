@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
set IP=
if exist "%~dp0ip.txt" set /p IP=<"%~dp0ip.txt"
if "%IP%"=="" set /p IP=IP-Adresse des Fire TV Sticks: 
echo %IP%>"%~dp0ip.txt"
set ADB=%~dp0..\platform-tools\adb.exe
if not exist "%ADB%" set ADB=%~dp0platform-tools\adb.exe
%ADB% connect %IP%:5555 >nul
%ADB% devices | find "%IP%" >nul || (echo Stick nicht erreichbar - ist er an? & pause & exit /b 1)
echo.
echo === Speicher vorher ===
%ADB% shell df -h /data | find "/data"
echo.
echo === Caches aller Apps leeren ===
%ADB% shell pm trim-caches 100G
echo.
echo === Groesste Apps (Daten + Cache) ===
%ADB% shell "du -sk /data/data/* 2>/dev/null | sort -rn | head -15"
echo.
echo === Speicher nachher ===
%ADB% shell df -h /data | find "/data"
echo.
echo Tipp: Grosse Apps mit 6b_app_deinstallieren.bat entfernen.
pause
