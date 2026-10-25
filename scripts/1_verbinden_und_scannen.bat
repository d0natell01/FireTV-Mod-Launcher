@echo off
setlocal
cd /d "%~dp0"
set IP=
if exist "%~dp0ip.txt" set /p IP=<"%~dp0ip.txt"
if "%IP%"=="" set /p IP=IP-Adresse des Fire TV Sticks: 
echo %IP%>"%~dp0ip.txt"

if not exist platform-tools\adb.exe (
  echo [1/3] Lade ADB platform-tools...
  powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest -Uri https://dl.google.com/android/repository/platform-tools-latest-windows.zip -OutFile pt.zip; Expand-Archive pt.zip -DestinationPath . -Force; Remove-Item pt.zip"
)
set ADB=%~dp0..\platform-tools\adb.exe
if not exist "%ADB%" set ADB=%~dp0platform-tools\adb.exe

echo [2/3] Verbinde mit %IP%:5555 ...
%ADB% kill-server >nul 2>&1
%ADB% connect %IP%:5555
echo.
echo *** Falls auf dem TV ein Dialog "USB-Debugging zulassen?" erscheint: "Immer zulassen" + OK, dann hier Taste druecken. ***
pause
%ADB% connect %IP%:5555

echo [3/3] Sammle Infos...
%ADB% devices > 01_status.txt
%ADB% shell getprop ro.build.version.name >> 01_status.txt 2>&1
%ADB% shell getprop ro.product.model >> 01_status.txt 2>&1
%ADB% shell pm list packages -e > 02_packages_aktiv.txt
%ADB% shell pm list packages -d > 03_packages_deaktiviert.txt
echo.
echo Fertig. Dateien 01_status.txt / 02_packages_aktiv.txt / 03_packages_deaktiviert.txt wurden erstellt.
type 01_status.txt
pause
