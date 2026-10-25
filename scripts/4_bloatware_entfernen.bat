@echo off
setlocal
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
echo === Bloatware deaktivieren ===

echo Amazon Music

%ADB% shell pm disable-user --user 0 com.amazon.bueller.music

echo Amazon Photos

%ADB% shell pm disable-user --user 0 com.amazon.bueller.photos

echo Amazon Kids / FreeTime

%ADB% shell pm disable-user --user 0 com.amazon.tahoe

echo Hilfe-App

%ADB% shell pm disable-user --user 0 com.amazon.hedwig

echo Kundendienst

%ADB% shell pm disable-user --user 0 com.amazon.tv.support

echo Kundendienst-App

%ADB% shell pm disable-user --user 0 com.amazon.tv.csapp

echo Alexa Smart-Home

%ADB% shell pm disable-user --user 0 com.amazon.kso.blackbird

echo Smart-Home Kartenansicht

%ADB% shell pm disable-user --user 0 com.amazon.smarthomemapviewapp

echo Matter Smart-Home

%ADB% shell pm disable-user --user 0 com.amazon.tv.matter

echo Matter Smart-Home

%ADB% shell pm disable-user --user 0 com.amazon.tv.mattercohost

echo Whole Home Audio

%ADB% shell pm disable-user --user 0 com.amazon.wha.mediabrowserservice

echo Whole Home Audio

%ADB% shell pm disable-user --user 0 com.amazon.whad

echo Whole Home Audio Einstellungen

%ADB% shell pm disable-user --user 0 com.amazon.whasettings

echo Kindle Connect

%ADB% shell pm disable-user --user 0 com.amazon.ods.kindleconnect

echo Tutorial

%ADB% shell pm disable-user --user 0 com.amazon.tmm.tutorial

echo Fernbedienungs-Tutorial

%ADB% shell pm disable-user --user 0 com.amazon.storm.lightning.tutorial

echo Release Notes

%ADB% shell pm disable-user --user 0 com.amazon.tv.releasenotes

echo Amazon Live-TV-Reihe

%ADB% shell pm disable-user --user 0 com.amazon.tv.livetv

echo Upgrade-Werbung fuer neue Sticks

%ADB% shell pm disable-user --user 0 com.amazon.tv.easyupgrade

echo Rechtliche Hinweise Popups

%ADB% shell pm disable-user --user 0 com.amazon.tv.legal.notices

echo.
echo === Animationen beschleunigen ===
%ADB% shell settings put global window_animation_scale 0.5
%ADB% shell settings put global transition_animation_scale 0.5
%ADB% shell settings put global animator_duration_scale 0.5
echo.
%ADB% shell pm list packages -d > 03_packages_deaktiviert.txt
echo FERTIG. Aktuell deaktiviert:
type 03_packages_deaktiviert.txt
pause
