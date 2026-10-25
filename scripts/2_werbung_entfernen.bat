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
echo === Werbung/Tracking deaktivieren ===

echo Werbe-Deeplinks (Sponsored-Kacheln)

%ADB% shell pm disable-user --user 0 com.amazon.ftvads.deeplinking

echo Werbe-ID / interessenbasierte Werbung

%ADB% shell pm disable-user --user 0 com.amazon.hybridadidservice

echo Amazon-Angebote/Shopping-Promos

%ADB% shell pm disable-user --user 0 com.amazon.device.sale.service

echo Amazon Shopping auf TV

%ADB% shell pm disable-user --user 0 com.amazon.shoptv.client

echo Amazon Shopping auf TV

%ADB% shell pm disable-user --user 0 com.amazon.shoptv.firetv.client

echo Film-Teaser / Vorschau-Promos

%ADB% shell pm disable-user --user 0 com.amazon.sneakpeek

echo 'Schaust du noch?'-Einblendung

%ADB% shell pm disable-user --user 0 com.amazon.stillwatching.activity

echo Automatische Inhaltserkennung (Tracking was du schaust)

%ADB% shell pm disable-user --user 0 com.amazon.tv.acr

echo Alexa-Werbe-Benachrichtigungen

%ADB% shell pm disable-user --user 0 com.amazon.tv.alexanotifications

echo Alexa-Hinweise

%ADB% shell pm disable-user --user 0 com.amazon.tv.alexaalerts

echo Telemetrie

%ADB% shell pm disable-user --user 0 com.amazon.client.metrics

echo Telemetrie

%ADB% shell pm disable-user --user 0 com.amazon.device.metrics

echo Telemetrie

%ADB% shell pm disable-user --user 0 com.amazon.wirelessmetrics.service

echo Telemetrie

%ADB% shell pm disable-user --user 0 com.amazon.tv.fw.metrics

echo Telemetrie

%ADB% shell pm disable-user --user 0 com.amazon.perfcollection

echo Amazon MiniTV (Werbe-Streaming, Indien)

%ADB% shell pm disable-user --user 0 com.amazon.minitv.android.app

echo Amazon GameHub-Promos

%ADB% shell pm disable-user --user 0 com.amazon.gamehub

echo.
echo === Autoplay/Sound von Teasern aus ===
%ADB% shell settings put secure feature_autoplay_video 0 2>nul
%ADB% shell settings put secure feature_autoplay_audio 0 2>nul
echo.
echo Launcher neu starten...
%ADB% shell am force-stop com.amazon.tv.launcher
%ADB% shell pm list packages -d > 03_packages_deaktiviert.txt
echo.
echo FERTIG. Deaktivierte Pakete stehen in 03_packages_deaktiviert.txt
pause
