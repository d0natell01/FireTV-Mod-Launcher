@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -STA -Command "try { & \"%~dp0FireTV_Mod_Launcher.ps1\" } catch { $_ | Out-String; $_.ScriptStackTrace }" > launcher_fehler.txt 2>&1
echo Fertig - Fehler stehen in launcher_fehler.txt
pause
