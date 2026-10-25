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
echo === Alles wieder aktivieren ===

%ADB% shell pm enable com.amazon.ftvads.deeplinking

%ADB% shell pm enable com.amazon.hybridadidservice

%ADB% shell pm enable com.amazon.device.sale.service

%ADB% shell pm enable com.amazon.shoptv.client

%ADB% shell pm enable com.amazon.shoptv.firetv.client

%ADB% shell pm enable com.amazon.sneakpeek

%ADB% shell pm enable com.amazon.stillwatching.activity

%ADB% shell pm enable com.amazon.tv.acr

%ADB% shell pm enable com.amazon.tv.alexanotifications

%ADB% shell pm enable com.amazon.tv.alexaalerts

%ADB% shell pm enable com.amazon.client.metrics

%ADB% shell pm enable com.amazon.device.metrics

%ADB% shell pm enable com.amazon.wirelessmetrics.service

%ADB% shell pm enable com.amazon.tv.fw.metrics

%ADB% shell pm enable com.amazon.perfcollection

%ADB% shell pm enable com.amazon.minitv.android.app

%ADB% shell pm enable com.amazon.gamehub

%ADB% shell am force-stop com.amazon.tv.launcher

echo FERTIG - alles zurueckgesetzt.

pause

