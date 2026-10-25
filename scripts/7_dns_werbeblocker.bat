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
echo Systemweiter Werbeblocker per privatem DNS (DNS-over-TLS):
echo   1 = AdGuard DNS        (dns.adguard-dns.com)   - Werbung + Tracker
echo   2 = AdGuard Family     (family.adguard-dns.com) - zusaetzlich Jugendschutz
echo   3 = Mullvad adblock    (adblock.dns.mullvad.net)
echo   4 = Eigener Server     (z.B. Pi-hole / NextDNS-Hostname)
echo   5 = Aus (Standard-DNS des Routers)
set /p W=Auswahl [1-5]: 
if "%W%"=="1" set H=dns.adguard-dns.com
if "%W%"=="2" set H=family.adguard-dns.com
if "%W%"=="3" set H=adblock.dns.mullvad.net
if "%W%"=="4" set /p H=Hostname: 
if "%W%"=="5" (
  %ADB% shell settings put global private_dns_mode off
  echo Privater DNS deaktiviert.
  pause & exit /b 0
)
if not defined H (echo Ungueltig & pause & exit /b 1)
%ADB% shell settings put global private_dns_mode hostname
%ADB% shell settings put global private_dns_specifier %H%
echo.
echo Gesetzt: 
%ADB% shell settings get global private_dns_mode
%ADB% shell settings get global private_dns_specifier
echo.
echo Hinweis: Falls Apps danach keine Verbindung haben, Skript erneut starten und 5 waehlen.
pause
