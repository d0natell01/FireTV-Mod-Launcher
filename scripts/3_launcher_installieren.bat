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

echo === Alten Launcher Manager (FOS5) entfernen ===
%ADB% uninstall com.wolf.fos5.settings
echo.

echo === Projectivy installieren ===
set FOUND=0
for %%f in (apk\*.apkm) do (
  set FOUND=1
  echo Bundle: %%~nxf
  if exist apk\_splits rd /s /q apk\_splits
  copy /y "%%f" apk\_bundle.zip >nul
  powershell -NoProfile -Command "Expand-Archive apk\_bundle.zip -DestinationPath apk\_splits -Force"
  del apk\_bundle.zip
  set LIST=
  for %%s in (apk\_splits\*.apk) do (
    echo %%~nxs | find /i "arm64" >nul || set LIST=!LIST! "%%s"
  )
  echo Installiere: !LIST!
  %ADB% install-multiple -r -g !LIST!
)
for %%f in (apk\*.apk) do (
  set FOUND=1
  echo APK: %%~nxf
  %ADB% install -r -g "%%f"
)
if %FOUND%==0 echo Keine .apk/.apkm im Ordner apk gefunden!
echo.

echo === Berechtigungen Projectivy ===
%ADB% shell pm grant com.spocky.projengmenu android.permission.SYSTEM_ALERT_WINDOW
%ADB% shell dumpsys deviceidle whitelist +com.spocky.projengmenu
echo.

echo === Pruefung ===
%ADB% shell pm list packages | find "projengmenu" && echo Projectivy: OK || echo Projectivy: FEHLT
%ADB% shell pm list packages | find "minilm" && echo Launcher Manager Mini: OK || echo Launcher Manager Mini: FEHLT
echo.
echo FERTIG.
pause
