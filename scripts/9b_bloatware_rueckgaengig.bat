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
echo === Bloatware wieder aktivieren ===

%ADB% shell pm enable com.amazon.bueller.music

%ADB% shell pm enable com.amazon.bueller.photos

%ADB% shell pm enable com.amazon.tahoe

%ADB% shell pm enable com.amazon.hedwig

%ADB% shell pm enable com.amazon.tv.support

%ADB% shell pm enable com.amazon.tv.csapp

%ADB% shell pm enable com.amazon.kso.blackbird

%ADB% shell pm enable com.amazon.smarthomemapviewapp

%ADB% shell pm enable com.amazon.tv.matter

%ADB% shell pm enable com.amazon.tv.mattercohost

%ADB% shell pm enable com.amazon.wha.mediabrowserservice

%ADB% shell pm enable com.amazon.whad

%ADB% shell pm enable com.amazon.whasettings

%ADB% shell pm enable com.amazon.ods.kindleconnect

%ADB% shell pm enable com.amazon.tmm.tutorial

%ADB% shell pm enable com.amazon.storm.lightning.tutorial

%ADB% shell pm enable com.amazon.tv.releasenotes

%ADB% shell pm enable com.amazon.tv.livetv

%ADB% shell pm enable com.amazon.tv.easyupgrade

%ADB% shell pm enable com.amazon.tv.legal.notices

%ADB% shell settings put global window_animation_scale 1
%ADB% shell settings put global transition_animation_scale 1
%ADB% shell settings put global animator_duration_scale 1
echo FERTIG.
pause
