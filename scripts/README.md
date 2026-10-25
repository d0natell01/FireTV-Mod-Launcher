# Einzelskripte (ohne GUI)

Fallback für Nutzer, die lieber einzelne Schritte ausführen. Beim ersten Start wird die IP abgefragt und in `ip.txt` gemerkt. ADB wird aus `../platform-tools` oder `./platform-tools` verwendet (Skript 1 lädt es bei Bedarf).

| Skript | Funktion |
|---|---|
| 1_verbinden_und_scannen | Verbindung testen, App-Liste erzeugen |
| 2_werbung_entfernen | Werbung, Teaser, Tracking, Telemetrie deaktivieren |
| 3_launcher_installieren | Projectivy + Launcher Manager Mini aus `../apk` installieren |
| 4_bloatware_entfernen | Amazon-Zusatzdienste deaktivieren |
| 5_animationen | Animationsgeschwindigkeit |
| 6_apps_installieren / 6b | APKs aus `../apk_sideload` installieren / App entfernen |
| 7_dns_werbeblocker | Privater DNS |
| 8_cache_speicher | Caches leeren |
| 9 / 9b_rueckgaengig | Skripte 2 / 4 rückgängig |
| 10_status | Übersicht |
| 11_neustart | Stick neu starten |
