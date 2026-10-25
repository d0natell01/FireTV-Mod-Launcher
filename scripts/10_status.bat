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
echo === Geraet ===
%ADB% shell getprop ro.product.model
%ADB% shell getprop ro.build.version.name
%ADB% shell getprop ro.product.cpu.abilist
echo.
echo === Launcher-Mod ===
%ADB% shell pm list packages | find "minilm" >nul && echo Launcher Manager Mini: OK || echo Launcher Manager Mini: FEHLT
%ADB% shell pm list packages | find "projengmenu" >nul && echo Projectivy: OK || echo Projectivy: FEHLT
echo.
echo === Animationen ===
%ADB% shell settings get global window_animation_scale
echo === Privater DNS ===
%ADB% shell settings get global private_dns_mode
%ADB% shell settings get global private_dns_specifier
echo.
echo === Deaktivierte Pakete ===
%ADB% shell pm list packages -d
echo.
echo === Drittanbieter-Apps ===
%ADB% shell pm list packages -3
echo.
echo === Speicher ===
%ADB% shell df -h /data | find "/data"
pause
