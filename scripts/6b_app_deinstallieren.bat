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
echo === Installierte Drittanbieter-Apps ===
%ADB% shell pm list packages -3
echo.
set /p P=Paketname zum Deinstallieren (z.B. com.nordvpn.android), leer = abbrechen: 
if "%P%"=="" exit /b 0
%ADB% uninstall %P%
pause
