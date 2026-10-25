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
echo === Apps aus Ordner apk_sideload installieren ===
set N=0
for %%f in (apk_sideload\*.apkm) do (
  set /a N+=1
  echo Bundle: %%~nxf
  if exist apk_sideload\_splits rd /s /q apk_sideload\_splits
  copy /y "%%f" apk_sideload\_bundle.zip >nul
  powershell -NoProfile -Command "Expand-Archive apk_sideload\_bundle.zip -DestinationPath apk_sideload\_splits -Force"
  del apk_sideload\_bundle.zip
  set LIST=
  for %%s in (apk_sideload\_splits\*.apk) do (
    echo %%~nxs | find /i "arm64" >nul || set LIST=!LIST! "%%s"
  )
  %ADB% install-multiple -r -g !LIST!
  rd /s /q apk_sideload\_splits
)
for %%f in (apk_sideload\*.apk) do (
  set /a N+=1
  echo APK: %%~nxf
  %ADB% install -r -g "%%f"
)
if %N%==0 (echo Keine .apk/.apkm in apk_sideload gefunden. Siehe README.txt fuer Download-Quellen.)
echo.
echo === Installierte Drittanbieter-Apps ===
%ADB% shell pm list packages -3
echo.
echo FERTIG. Apps erscheinen in Projectivy automatisch.
pause
