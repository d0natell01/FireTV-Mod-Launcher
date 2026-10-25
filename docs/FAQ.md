# FAQ

**Der Launcher startet nicht.**
`FireTV Mod Launcher (Debug).bat` ausführen – Fehler stehen danach in `launcher_fehler.txt`. Häufig: Datei ohne UTF-8-BOM gespeichert (Umlaute) oder Ausführungsrichtlinie; die .bat setzt `-ExecutionPolicy Bypass`.

**Stick wird nicht gefunden.**
ADB-Debugging eingeschaltet? Gleiches WLAN? Stick aus dem Standby wecken. Port 5555 muss erreichbar sein (manche Router isolieren WLAN-Clients: »AP Isolation« ausschalten).

**»USB-Debugging zulassen?« erscheint nicht.**
ADB-Debugging am Stick aus- und wieder einschalten, dann erneut verbinden.

**INSTALL_FAILED_NO_MATCHING_ABIS**
Falsche Architektur. 32-Bit-Sticks (Lite, 4K, 4K Max 1. Gen) brauchen armeabi-v7a-APKs.

**INSTALL_FAILED_OLDER_SDK**
Die App verlangt ein neueres Android. Fire OS 7 = Android 9 (API 28), Fire OS 8 = Android 11 (API 30). Projectivy: Version 4.66 (Bundle arm64+armeabi, Android 6.0+).

**Home-Taste führt weiter zum Amazon-Startbildschirm.**
Launcher Manager Mini am TV öffnen und den gewünschten Launcher auswählen. Die Auswahl speichert die Mini-App selbst; per ADB lässt sie sich nicht setzen.

**Screenshot ist leer oder schwarz.**
Läuft DRM-geschützter Inhalt (Netflix, Prime Video). Startbildschirm öffnen und erneut versuchen.

**Fire OS hat sich trotzdem aktualisiert.**
Das OTA-Paket ist systemgeschützt. Sperre die Hosts aus »Netzwerk → Update-Sperre« im Router oder DNS-Filter. Danach »Mods neu anwenden« im Dashboard.

**Welche Pakete werden deaktiviert?**
Siehe `$Features` am Anfang von `FireTV_Mod_Launcher.ps1`. Alles lässt sich mit dem Schalter wieder aktivieren.
