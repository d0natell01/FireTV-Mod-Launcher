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
echo Animationsgeschwindigkeit waehlen:
echo   1 = Schnell (0.5x)  - empfohlen
echo   2 = Sehr schnell (0.25x)
echo   3 = Aus (0, keine Animationen)
echo   4 = Standard (1x, zuruecksetzen)
set /p W=Auswahl [1-4]: 
if "%W%"=="1" set S=0.5
if "%W%"=="2" set S=0.25
if "%W%"=="3" set S=0
if "%W%"=="4" set S=1
if not defined S (echo Ungueltige Eingabe & pause & exit /b 1)
%ADB% shell settings put global window_animation_scale %S%
%ADB% shell settings put global transition_animation_scale %S%
%ADB% shell settings put global animator_duration_scale %S%
echo.
echo Gesetzt auf %S%x. Aktuelle Werte:
%ADB% shell settings get global window_animation_scale
%ADB% shell settings get global transition_animation_scale
%ADB% shell settings get global animator_duration_scale
pause
