# Fire TV Mod Launcher v3 – Windows GUI (PowerShell + WPF)
# Start über "FireTV Mod Launcher.bat" (oder .vbs ohne Konsolenfenster)
# Headless: FireTV_Mod_Launcher.ps1 -Run "<Makroname>" -Device <IP>
param([string]$Run = '', [string]$Device = '')
$script:Version = '3.3'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ADB = Join-Path $Root 'platform-tools\adb.exe'
$script:ApkDir = Join-Path $Root 'apk'; $script:SideloadDir = Join-Path $Root 'apk_sideload'
$script:ShotDir = Join-Path $Root 'screenshots'; $script:DlDir = Join-Path $Root 'downloads'; $script:BackupDir = Join-Path $Root 'backups'
$script:DevFile = Join-Path $Root 'geraete.json'; $script:SetFile = Join-Path $Root 'einstellungen.json'; $script:LogFile = Join-Path $Root 'launcher_log.txt'
foreach ($d in $script:ApkDir, $script:SideloadDir, $script:ShotDir, $script:DlDir, $script:BackupDir) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
$script:IP = '192.168.0.15'; $script:Connected = $false; $script:Scanned = $false; $script:Initial = @{}
$script:Is64 = $false; $script:SDK = 28; $script:Model = ''
# ---- Einstellungen laden
$script:Set = @{ Dark = $false; AutoConnect = $true; Width = 1060; Height = 700; Favorites = @(); Macros = @(); UpdateUrl = '' }
if (Test-Path $script:SetFile) { try { $j = Get-Content $script:SetFile -Raw -Encoding UTF8 | ConvertFrom-Json; foreach ($k in @($script:Set.Keys)) { if ($null -ne $j.$k) { $script:Set[$k] = $j.$k } } } catch {} }
$script:Set.Favorites = @($script:Set.Favorites); $script:Set.Macros = @($script:Set.Macros)
function Save-Settings { try { $script:Set | ConvertTo-Json -Depth 5 | Set-Content $script:SetFile -Encoding UTF8 } catch {} }
if ($script:Set.Macros.Count -eq 0) { $script:Set.Macros = @(
  [pscustomobject]@{ Name='Abend-Modus'; Steps="lautstaerke 5`nstart com.teamsmart.videomanager.tv" },
  [pscustomobject]@{ Name='Gaming-Modus'; Steps="animationen 0`nhintergrund 1`nalle-stoppen`ncache" },
  [pscustomobject]@{ Name='Wartung'; Steps="cache`nneustart" },
  [pscustomobject]@{ Name='Gute Nacht'; Steps="alle-stoppen`nstandby" } ) }

# ================================================================== Basis (auch headless)
function Log($msg) { $line = "[$(Get-Date -Format HH:mm:ss)] $msg`r`n"; try { Add-Content $script:LogFile $line.TrimEnd() -ErrorAction SilentlyContinue } catch {}
  if ($script:UiReady) { foreach ($n in 'Log', 'LogMini') { $t = UI $n; $t.AppendText($line); $t.ScrollToEnd() }; Refresh-UI } }
function Run-Adb { param([string[]]$Arguments)
  $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName = $script:ADB
  $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '\s|"') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
  $p = [System.Diagnostics.Process]::Start($psi); $out = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd(); $p.WaitForExit(); return $out.Trim() }
function Dev { return @('-s', "$($script:IP):5555") }
function Shell($cmd) { return Run-Adb ((Dev) + @('shell', $cmd)) }
function Key($code) { Shell "input keyevent $code" | Out-Null }
function Start-Package($pkg) { $r = Shell "monkey -p $pkg -c android.intent.category.LAUNCHER 1"; if ($r -match 'No activities') { Shell "monkey -p $pkg -c android.intent.category.LEANBACK_LAUNCHER 1" | Out-Null }; Log "Starte $pkg" }

$KeyNames = @{ home=3; zurueck=4; ok=23; hoch=19; runter=20; links=21; rechts=22; play=85; pause=85; menue=82; lauter=24; leiser=25; stumm=164; standby=223; aufwecken=224; vor=90; rueck=89 }
function Run-Macro($name, [switch]$Quiet) {
  $m = $script:Set.Macros | Where-Object { $_.Name -eq $name } | Select-Object -First 1; if (-not $m) { Log "Makro nicht gefunden: $name"; return }
  Log "Makro »$name« startet"
  foreach ($line in ($m.Steps -split "`n")) { $line = $line.Trim(); if (-not $line -or $line.StartsWith('#')) { continue }
    $cmd, $arg = $line -split '\s+', 2; $cmd = $cmd.ToLower()
    try { switch ($cmd) {
      'taste' { $c = if ($KeyNames.ContainsKey($arg.ToLower())) { $KeyNames[$arg.ToLower()] } else { [int]$arg }; Key $c }
      'start' { Start-Package $arg } 'stop' { Shell "am force-stop $arg" | Out-Null }
      'alle-stoppen' { Shell 'am kill-all' | Out-Null }
      'hintergrund' { if ([int]$arg -ge 0) { Shell "settings put global activity_manager_constants max_cached_processes=$arg" | Out-Null } else { Shell 'settings delete global activity_manager_constants' | Out-Null } }
      'lautstaerke' { Shell "media volume --stream 3 --set $arg" | Out-Null; Shell "cmd media_session volume --stream 3 --set $arg" | Out-Null }
      'animationen' { foreach ($k in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') { Shell "settings put global $k $arg" | Out-Null } }
      'dns' { if ($arg -eq 'an') { Shell 'settings put global private_dns_mode hostname' | Out-Null } else { Shell 'settings put global private_dns_mode off' | Out-Null } }
      'standby' { Key 223 } 'aufwecken' { Key 224 } 'neustart' { Run-Adb ((Dev) + @('reboot')) | Out-Null }
      'cache' { Shell 'pm trim-caches 100G' | Out-Null } 'warte' { Start-Sleep -Seconds ([int]$arg) }
      'text' { $esc = $arg -replace '([\\()<>|;&*~"''`$])', '\$1' -replace ' ', '%s'; Shell "input text `"$esc`"" | Out-Null }
      'shell' { Shell $arg | Out-Null }
      default { Log "  unbekannter Befehl: $line" } }
      if (-not $Quiet) { Log "  ✓ $line" } } catch { Log "  Fehler bei »$line«: $($_.Exception.Message)" } }
  Log "Makro »$name« fertig" }
function Load-Devices { if (Test-Path $script:DevFile) { try { return @(Get-Content $script:DevFile -Raw -Encoding UTF8 | ConvertFrom-Json | Where-Object { $_.IP -match '^\d{1,3}(\.\d{1,3}){3}$' }) } catch {} }; return @() }
# ---- Headless-Modus (Zeitplan)
if ($Run) { if ($Device) { $script:IP = $Device } elseif ((Load-Devices).Count -gt 0) { $script:IP = (Load-Devices | Sort-Object Last -Descending | Select-Object -First 1).IP }
  if (Test-Path $script:ADB) { Run-Adb @('connect', "$($script:IP):5555") | Out-Null; Start-Sleep 1; $script:Connected = $true; Run-Macro $Run -Quiet; "[$(Get-Date -Format s)] Zeitplan »$Run« auf $($script:IP) ausgeführt" | Add-Content $script:LogFile }
  else { "[$(Get-Date -Format s)] ADB fehlt – Zeitplan »$Run« nicht ausgeführt" | Add-Content $script:LogFile }; exit }



# ================================================================== Funktionen (Dashboard)
$Features = @(
  @{ Id='ads'; Type='toggle'; Title='Werbung & Tracking entfernen'
     Desc='Sponsored-Deeplinks, Werbe-ID, Amazon-Shopping, Film-Teaser, »Schaust du noch?«, Inhaltserkennung, Alexa-Werbung, Telemetrie.'
     Pkgs=@('com.amazon.ftvads.deeplinking','com.amazon.hybridadidservice','com.amazon.device.sale.service','com.amazon.shoptv.client','com.amazon.shoptv.firetv.client','com.amazon.sneakpeek','com.amazon.stillwatching.activity','com.amazon.tv.acr','com.amazon.tv.alexanotifications','com.amazon.tv.alexaalerts','com.amazon.client.metrics','com.amazon.device.metrics','com.amazon.wirelessmetrics.service','com.amazon.tv.fw.metrics','com.amazon.perfcollection','com.amazon.minitv.android.app','com.amazon.gamehub') },
  @{ Id='bloat'; Type='toggle'; Title='Bloatware entfernen'
     Desc='Amazon Music/Photos, Kids, Hilfe, Smart-Home/Matter, Whole-Home-Audio, Tutorials, Live-TV-Reihe, Upgrade-Werbung. Appstore, Prime, YouTube bleiben.'
     Pkgs=@('com.amazon.bueller.music','com.amazon.bueller.photos','com.amazon.tahoe','com.amazon.hedwig','com.amazon.tv.support','com.amazon.tv.csapp','com.amazon.kso.blackbird','com.amazon.smarthomemapviewapp','com.amazon.tv.matter','com.amazon.tv.mattercohost','com.amazon.wha.mediabrowserservice','com.amazon.whad','com.amazon.whasettings','com.amazon.ods.kindleconnect','com.amazon.tmm.tutorial','com.amazon.storm.lightning.tutorial','com.amazon.tv.releasenotes','com.amazon.tv.livetv','com.amazon.tv.easyupgrade','com.amazon.tv.legal.notices') },
  @{ Id='ota'; Type='toggle'; Title='Zwangs-Updates blockieren'
     Desc='Schaltet den Zwangs-Updater ab, damit Updates den Launcher-Mod nicht zurücksetzen. Zusätzlich Router-/DNS-Sperre empfohlen (Netzwerk).'
     Pkgs=@('com.amazon.tv.forcedotaupdater.v2') },
  @{ Id='anim'; Type='toggle'; Title='Animationen beschleunigen'; Desc='Halbiert alle Fenster- und Übergangsanimationen (0.5×) – der Stick fühlt sich flotter an.' },
  @{ Id='dns'; Type='toggle'; Title='Werbeblocker in Apps (DNS)'; Desc='Privater DNS (Profil siehe Netzwerk). Blockt Werbung und Tracker systemweit, auch in Apps.' },
  @{ Id='launcher'; Type='toggle'; Title='Werbefreier Startbildschirm'; Desc='Ein = Projectivy + Launcher Manager Mini aus Ordner »apk« installieren. Aus = entfernen, Amazon-Startbildschirm zurück.' },
  @{ Id='cache'; Type='action'; Btn='Ausführen'; Title='Cache leeren'; Desc='Leert die Caches aller Apps. Keine Logins oder Daten gehen verloren.' },
  @{ Id='reboot'; Type='action'; Btn='Neu starten'; Title='Stick neu starten'; Desc='Startet den Stick neu, damit alle Änderungen greifen (ca. 1 Minute).' }
)

# ================================================================== Katalog
$Apps = @(
  @{ Cat='apps'; Id='smarttube'; Site='https://github.com/yuliskov/SmartTube'; Name='SmartTube'; PkgMatch='com\.teamsmart\.videomanager\.tv|com\.liskovsoft\.smarttubetv'; Desc='YouTube ohne Werbung, mit SponsorBlock, Google-Login möglich.'; Src='github'; Repo='yuliskov/SmartTube'; Prefer='stable' },
  @{ Cat='apps'; Id='kodi'; Site='https://kodi.tv/download/android/'; Name='Kodi'; PkgMatch='org\.xbmc\.kodi'; Desc='Mediacenter für lokale Filme, Serien, Musik und NAS.'; Src='listing'; Url='https://mirrors.kodi.tv/releases/android/{arch}/'; Match='kodi-[\d.]+-\w+-{abi}\.apk' },
  @{ Cat='apps'; Id='vlc'; Site='https://www.videolan.org/vlc/download-android.html'; Name='VLC'; PkgMatch='org\.videolan\.vlc'; Desc='Spielt praktisch jedes Video-/Audioformat, auch aus dem Netzwerk.'; Src='listing'; Url='https://get.videolan.org/vlc-android/last/'; Match='VLC-Android-[\d.]+-{abi}\.apk' },
  @{ Cat='apps'; Id='jellyfin'; Site='https://github.com/jellyfin/jellyfin-androidtv'; Name='Jellyfin'; PkgMatch='org\.jellyfin\.androidtv'; Desc='Client für den kostenlosen Jellyfin-Medienserver.'; Src='github'; Repo='jellyfin/jellyfin-androidtv' },
  @{ Cat='apps'; Id='nova'; Site='https://github.com/nova-video-player/aos-AVP'; Name='Nova Video Player'; PkgMatch='org\.courville\.nova'; Desc='Open-Source-Videoplayer mit Bibliothek und Untertiteln.'; Src='github'; Repo='nova-video-player/aos-AVP' },
  @{ Cat='apps'; Id='tvbro'; Site='https://github.com/truefedex/tv-bro'; Name='TV Bro'; PkgMatch='com\.phlox\.tvwebbrowser'; Desc='Browser für den Fernseher, bedienbar mit der Fernbedienung.'; Src='github'; Repo='truefedex/tv-bro' },
  @{ Cat='apps'; Id='smarttubebeta'; Site='https://github.com/yuliskov/SmartTube'; Name='SmartTube Beta'; PkgMatch='com\.liskovsoft\.smarttubetv\.beta|com\.teamsmart\.videomanager\.tv\.beta'; Desc='Beta-Version mit neuesten Funktionen (parallel zur Stable installierbar).'; Src='github'; Repo='yuliskov/SmartTube'; Prefer='beta' },
  @{ Cat='apps'; Id='newpipe'; Site='https://github.com/TeamNewPipe/NewPipe'; Name='NewPipe'; PkgMatch='org\.schabi\.newpipe'; Desc='YouTube/PeerTube/SoundCloud ohne Konto und Werbung, Hintergrundwiedergabe.'; Src='github'; Repo='TeamNewPipe/NewPipe' },
  @{ Cat='apps'; Id='antennapod'; Site='https://github.com/AntennaPod/AntennaPod'; Name='AntennaPod'; PkgMatch='de\.danoeh\.antennapod'; Desc='Open-Source-Podcast-Player.'; Src='github'; Repo='AntennaPod/AntennaPod' },
  @{ Cat='apps'; Id='retroarch'; Site='https://www.retroarch.com/?page=platforms'; Name='RetroArch'; PkgMatch='com\.retroarch'; Desc='Retro-Gaming-Emulatoren (SNES, PlayStation, GBA …). Bluetooth-Controller empfohlen.'; Src='direct'; Url32='https://buildbot.libretro.com/nightly/android/latest/RetroArch_ra32.apk'; Url64='https://buildbot.libretro.com/nightly/android/latest/RetroArch_aarch64.apk' },
  @{ Cat='apps'; Id='localsend'; Site='https://github.com/localsend/localsend'; Name='LocalSend'; PkgMatch='org\.localsend\.localsend_app'; Desc='Dateien vom Handy/PC direkt an den Stick schicken (AirDrop-Alternative).'; Src='github'; Repo='localsend/localsend' },
  @{ Cat='apps'; Id='buttonmapper'; Site='https://www.apkmirror.com/apk/flar2/button-mapper-remap-your-keys/'; Name='Button Mapper'; PkgMatch='flar2\.homebutton'; Desc='Tasten der Fernbedienung umbelegen (Netflix/Prime-Taste → beliebige App). Manuell: APK von APKMirror in Ordner »apk« legen.'; Src='manual'; FileMatch='homebutton|button.?mapper' },
  @{ Cat='launcher'; Id='projectivy'; Site='https://www.apkmirror.com/apk/spocky/projectivy-launcher-android-tv/'; Name='Projectivy Launcher'; PkgMatch='com\.spocky\.projengmenu'; Desc='Beliebtester Fire-TV-Launcher: Kacheln, Kategorien, Wallpaper. Manuell: APK/APKM von APKMirror in Ordner »apk« legen.'; Src='manual'; FileMatch='projengmenu|projectivy' },
  @{ Cat='launcher'; Id='ltv'; Site='https://github.com/LeanBitLab/LtvLauncher'; Name='LTvLauncher'; PkgMatch='ltvlauncher'; Desc='Minimalistisch, schnell, OLED-Bildschirmschoner, WLAN-Widget. Fork von FLauncher.'; Src='github'; Repo='LeanBitLab/LtvLauncher' },
  @{ Cat='launcher'; Id='flauncher'; Site='https://gitlab.com/flauncher/flauncher'; Name='FLauncher'; PkgMatch='me\.efesser\.flauncher'; Desc='Schlicht und werbefrei, App-Reihen mit eigenen Kategorien und Wallpaper.'; Src='gitlab'; Project='flauncher/flauncher;etienn01/flauncher' },
  @{ Cat='launcher'; Id='at4k'; Site='https://github.com/avadhesh18/at4k'; Name='AT4K Launcher'; PkgMatch='com\.overdevs\.at4k'; Desc='Klassischer Android-TV-Look mit Reihen und Vorschauen.'; Src='github'; Repo='avadhesh18/at4k' },
  @{ Cat='launcher'; Id='leap'; Site='https://github.com/HazAnwar/leap-launcher'; Name='Leap Launcher'; PkgMatch='com\.haztech\.launcher'; Desc='Modern, mit Favoriten, Farbschemata und Schnellzugriff.'; Src='github'; Repo='HazAnwar/leap-launcher' },
  @{ Cat='launcher'; Id='alauncher'; Site='https://github.com/4v3ngR/aLauncher'; Name='aLauncher'; PkgMatch='alauncher'; Desc='Sehr leichtgewichtig, App-Raster ohne Schnickschnack.'; Src='github'; Repo='4v3ngR/aLauncher' },
  @{ Cat='launcher'; Id='arc'; Site='https://github.com/meddouribadis/arclauncher'; Name='Arc Launcher'; PkgMatch='arclauncher'; Desc='Open-Source-Launcher mit schlichtem Raster und Hintergrundbildern.'; Src='github'; Repo='meddouribadis/arclauncher' },
  @{ Cat='launcher'; Id='simpletv'; Site='https://github.com/alescdb/LauncherTV'; Name='Simple TV Launcher'; PkgMatch='org\.cosinus\.launchertv'; Desc='Extrem einfach: feste App-Kacheln, ideal für ältere Sticks.'; Src='github'; Repo='alescdb/LauncherTV' },
  @{ Cat='launcher'; Id='letihome'; Site='https://github.com/pkoretic/LetiHome'; Name='LetiHome'; PkgMatch='hr\.envizia\.letihome'; Desc='Schnell und übersichtlich, mit App-Gruppen und Bildschirmschoner.'; Src='github'; Repo='pkoretic/LetiHome' },
  @{ Cat='launcher'; Id='launchy'; Site='https://github.com/hugegreenbug/launchy'; Name='Launchy'; PkgMatch='com\.hugegreenbug\.launchy'; Desc='Einfacher Open-Source-Launcher mit Favoritenleiste.'; Src='github'; Repo='hugegreenbug/launchy' },
  @{ Cat='launcher'; Id='lightning'; Site='https://github.com/threethan/LightningLauncher'; Name='Lightning Launcher'; PkgMatch='threethan'; Desc='Sehr schnell, Icon-Packs und Gruppen (läuft auch auf Android TV).'; Src='github'; Repo='threethan/LightningLauncher' },
  @{ Cat='launcher'; Id='leanback'; Site='https://github.com/tsynik/LeanbackLauncher'; Name='Leanback Launcher'; PkgMatch='leanbacklauncher'; Desc='Nachbau des originalen Android-TV-Startbildschirms (Google-Look).'; Src='github'; Repo='tsynik/LeanbackLauncher' },
  @{ Cat='launcher'; Id='wolf'; Site='https://xdaforums.com/t/app-wolf-launcher-for-fire-tv.4322067/'; Name='Wolf Launcher'; PkgMatch='com\.wolf\.firelauncher'; Desc='Beliebter Fire-TV-Launcher mit Widgets. Manuell: APK von XDA in Ordner »apk« legen.'; Src='manual'; FileMatch='wolf' }
)
$script:LauncherNames = @{ 'com.amazon.tv.launcher'='Amazon Fire TV (Original)'; 'com.spocky.projengmenu'='Projectivy Launcher'; 'me.efesser.flauncher'='FLauncher'; 'com.wolf.firelauncher'='Wolf Launcher'; 'ca.dstudio.atvlauncher.free'='ATV Launcher'; 'ca.dstudio.atvlauncher.pro'='ATV Launcher Pro'; 'com.overdevs.at4k'='AT4K Launcher'; 'com.haztech.launcher'='Leap Launcher'; 'org.cosinus.launchertv'='Simple TV Launcher'; 'hr.envizia.letihome'='LetiHome'; 'com.hugegreenbug.launchy'='Launchy'; 'com.spauldhaliwal.dispatch'='Dispatch'; 'com.overdevs.kyulauncher'='Kyu Launcher' }
$DnsProfiles = @(
  @{ Name='AdGuard DNS (Werbung + Tracker)'; Host='dns.adguard-dns.com' },
  @{ Name='AdGuard Family (zusätzlich Jugendschutz)'; Host='family.adguard-dns.com' },
  @{ Name='Mullvad Adblock'; Host='adblock.dns.mullvad.net' },
  @{ Name='Cloudflare Family (Malware + Erwachseneninhalte)'; Host='family.cloudflare-dns.com' },
  @{ Name='Quad9 (Malware-Schutz, keine Werbefilter)'; Host='dns.quad9.net' },
  @{ Name='Eigener Server (Pi-hole / NextDNS) …'; Host='' }
)
$VpnApps = @(
  @{ Name='NordVPN'; Pkg='com.nordvpn.android' }, @{ Name='Surfshark'; Pkg='com.surfshark.vpnclient.android' }, @{ Name='ExpressVPN'; Pkg='com.expressvpn.vpn' },
  @{ Name='ProtonVPN'; Pkg='ch.protonvpn.android' }, @{ Name='WireGuard'; Pkg='com.wireguard.android' }, @{ Name='OpenVPN'; Pkg='net.openvpn.openvpn' }, @{ Name='CyberGhost'; Pkg='de.mobileconcepts.cyberghost' }
)
$Keys = @(
  @{ Id='up'; Txt='▲'; Code=19 }, @{ Id='down'; Txt='▼'; Code=20 }, @{ Id='left'; Txt='◀'; Code=21 }, @{ Id='right'; Txt='▶'; Code=22 }, @{ Id='ok'; Txt='OK'; Code=23 },
  @{ Id='back'; Txt='Zurück'; Code=4 }, @{ Id='home'; Txt='Home'; Code=3 }, @{ Id='menu'; Txt='Menü'; Code=82 },
  @{ Id='rew'; Txt='◀◀'; Code=89 }, @{ Id='play'; Txt='▶❚❚'; Code=85 }, @{ Id='ff'; Txt='▶▶'; Code=90 },
  @{ Id='volup'; Txt='Vol +'; Code=24 }, @{ Id='voldn'; Txt='Vol −'; Code=25 }, @{ Id='mute'; Txt='Stumm'; Code=164 },
  @{ Id='sleep'; Txt='Standby'; Code=223 }, @{ Id='wake'; Txt='Aufwecken'; Code=224 }
)

# ================================================================== XAML
function Esc($t) { [System.Security.SecurityElement]::Escape([string]$t) }
$cardsXaml = ''
foreach ($f in $Features) {
  $ctrl = if ($f.Type -eq 'toggle') { "<CheckBox x:Name=""sw_$($f.Id)"" Style=""{StaticResource Switch}"" VerticalAlignment=""Center""/>" } else { "<Button x:Name=""bt_$($f.Id)"" Content=""$($f.Btn)"" Style=""{StaticResource Secondary}"" VerticalAlignment=""Center""/>" }
  $cardsXaml += @"
<Border Style="{StaticResource Card}"><Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <StackPanel Margin="0,0,14,0">
    <StackPanel Orientation="Horizontal">
      <TextBlock Text="$(Esc $f.Title)" Style="{StaticResource H3}"/>
      <Border x:Name="bd_$($f.Id)" Style="{StaticResource Badge}"><TextBlock x:Name="bt_txt_$($f.Id)" Text="INAKTIV" Style="{StaticResource BadgeTxt}"/></Border>
    </StackPanel>
    <TextBlock Text="$(Esc $f.Desc)" Style="{StaticResource P}"/>
    <TextBlock x:Name="st_$($f.Id)" FontSize="11" Foreground="#34C759" Margin="0,4,0,0" Visibility="Collapsed"/>
  </StackPanel>
  <StackPanel Grid.Column="1" VerticalAlignment="Center">$ctrl</StackPanel>
</Grid></Border>
"@
}
$appsXaml = ''; $launchersXaml = ''
foreach ($a in $Apps) {
  $srcHost = ([uri]$a.Site).Host -replace '^www\.', ''
  $card = @"
<Border Style="{StaticResource Card}"><Grid>
  <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
  <CheckBox x:Name="ck_$($a.Id)" VerticalAlignment="Top" Margin="0,2,12,0"/>
  <StackPanel Grid.Column="1">
    <StackPanel Orientation="Horizontal">
      <TextBlock Text="$(Esc $a.Name)" Style="{StaticResource H3}"/>
      <Border x:Name="bd_$($a.Id)" Style="{StaticResource Badge}"><TextBlock x:Name="bt_txt_$($a.Id)" Text="NICHT INSTALLIERT" Style="{StaticResource BadgeTxt}"/></Border>
    </StackPanel>
    <TextBlock Text="$(Esc $a.Desc)" Style="{StaticResource P}"/>
    <TextBlock x:Name="src_$($a.Id)" Text="Quelle: $srcHost" FontSize="10.5" Foreground="#0A84FF" Cursor="Hand" Margin="0,4,0,0" ToolTip="$(Esc $a.Site)"/>
  </StackPanel>
</Grid></Border>
"@
  if ($a.Cat -eq 'launcher') { $launchersXaml += $card } else { $appsXaml += $card }
}
$keysXaml = ''
foreach ($k in $Keys) { $keysXaml += "<Button x:Name=""key_$($k.Id)"" Content=""$($k.Txt)"" Style=""{StaticResource KeyBtn}""/>" }
$vpnXaml = ''
foreach ($v in $VpnApps) { $id = $v.Pkg.Replace('.', '_'); $vpnXaml += "<StackPanel x:Name=""vpn_$id"" Orientation=""Horizontal"" Margin=""0,0,0,6"" Visibility=""Collapsed""><TextBlock Text=""$($v.Name)"" Width=""120"" VerticalAlignment=""Center"" FontSize=""12.5""/><Button x:Name=""vpnStart_$id"" Content=""Starten"" Style=""{StaticResource Secondary}"" Margin=""0,0,6,0""/><Button x:Name=""vpnStop_$id"" Content=""Stoppen"" Style=""{StaticResource Secondary}""/></StackPanel>" }

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Fire TV Mod" Width="1060" Height="700" MinWidth="900" MinHeight="580" WindowStartupLocation="CenterScreen" Background="{DynamicResource BgBrush}" FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>
    <SolidColorBrush x:Key="BgBrush" Color="#F5F5F7"/><SolidColorBrush x:Key="CardBrush" Color="#FFFFFF"/><SolidColorBrush x:Key="TextBrush" Color="#1D1D1F"/><SolidColorBrush x:Key="MutedBrush" Color="#6E6E73"/>
    <SolidColorBrush x:Key="Btn2Brush" Color="#E9E9EB"/><SolidColorBrush x:Key="HoverBrush" Color="#DCDCDE"/><SolidColorBrush x:Key="SideBrush" Color="#ECECF1"/><SolidColorBrush x:Key="BorderBrush" Color="#D2D2D7"/>
    <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="{DynamicResource CardBrush}"/><Setter Property="CornerRadius" Value="12"/><Setter Property="Padding" Value="16,12"/><Setter Property="Margin" Value="0,0,10,10"/>
      <Setter Property="Effect"><Setter.Value><DropShadowEffect BlurRadius="18" ShadowDepth="0" Opacity="0.07"/></Setter.Value></Setter></Style>
    <Style x:Key="H1" TargetType="TextBlock"><Setter Property="FontSize" Value="20"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="{DynamicResource TextBrush}"/></Style>
    <Style x:Key="H3" TargetType="TextBlock"><Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Foreground" Value="{DynamicResource TextBrush}"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
    <Style x:Key="P" TargetType="TextBlock"><Setter Property="FontSize" Value="11.5"/><Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/><Setter Property="TextWrapping" Value="Wrap"/><Setter Property="Margin" Value="0,3,0,0"/><Setter Property="LineHeight" Value="15"/></Style>
    <Style x:Key="Sub" TargetType="TextBlock"><Setter Property="FontSize" Value="12"/><Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/><Setter Property="Margin" Value="0,2,0,0"/><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style x:Key="Sec" TargetType="TextBlock"><Setter Property="FontSize" Value="10"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/><Setter Property="Margin" Value="2,6,0,6"/></Style>
    <Style x:Key="Badge" TargetType="Border"><Setter Property="CornerRadius" Value="8"/><Setter Property="Background" Value="{DynamicResource Btn2Brush}"/><Setter Property="Padding" Value="6,1"/><Setter Property="Margin" Value="8,0,0,0"/><Setter Property="VerticalAlignment" Value="Center"/></Style>
    <Style x:Key="BadgeTxt" TargetType="TextBlock"><Setter Property="FontSize" Value="9"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="Foreground" Value="{DynamicResource MutedBrush}"/></Style>
    <Style x:Key="Primary" TargetType="Button"><Setter Property="Background" Value="#0A84FF"/><Setter Property="Foreground" Value="White"/><Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Padding" Value="18,8"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="10" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#0071E3"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Background" Value="#B9D7FF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Secondary" TargetType="Button" BasedOn="{StaticResource Primary}"><Setter Property="Background" Value="{DynamicResource Btn2Brush}"/><Setter Property="Foreground" Value="{DynamicResource TextBrush}"/><Setter Property="Padding" Value="14,6"/><Setter Property="FontWeight" Value="Normal"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource HoverBrush}"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Background" Value="{DynamicResource Btn2Brush}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Secondary}"><Setter Property="Foreground" Value="#FF3B30"/></Style>
    <Style x:Key="KeyBtn" TargetType="Button" BasedOn="{StaticResource Secondary}"><Setter Property="Width" Value="78"/><Setter Property="Height" Value="40"/><Setter Property="Margin" Value="3"/><Setter Property="Padding" Value="0"/><Setter Property="FontSize" Value="14"/></Style>
    <Style x:Key="Nav" TargetType="Button"><Setter Property="Background" Value="Transparent"/><Setter Property="Foreground" Value="{DynamicResource TextBrush}"/><Setter Property="FontSize" Value="13"/><Setter Property="Padding" Value="14,9"/><Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0,0,0,2"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource HoverBrush}"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Switch" TargetType="CheckBox"><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Grid Width="42" Height="25"><Border x:Name="Track" CornerRadius="12.5" Background="{DynamicResource Btn2Brush}"/><Ellipse x:Name="Knob" Width="21" Height="21" Fill="White" HorizontalAlignment="Left" Margin="2,0,0,0"><Ellipse.Effect><DropShadowEffect BlurRadius="4" ShadowDepth="1" Opacity="0.25"/></Ellipse.Effect></Ellipse></Grid>
        <ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Track" Property="Background" Value="#34C759"/><Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/><Setter TargetName="Knob" Property="Margin" Value="0,0,2,0"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Track" Property="Opacity" Value="0.4"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Input" TargetType="TextBox"><Setter Property="FontSize" Value="13"/><Setter Property="Padding" Value="10,6"/><Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/><Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox"><Border Background="{DynamicResource CardBrush}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="9" Padding="{TemplateBinding Padding}"><ScrollViewer x:Name="PART_ContentHost"/></Border></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Mono" TargetType="TextBox"><Setter Property="IsReadOnly" Value="True"/><Setter Property="Background" Value="#1D1D1F"/><Setter Property="Foreground" Value="#E5E5EA"/><Setter Property="BorderThickness" Value="0"/><Setter Property="FontFamily" Value="Consolas"/><Setter Property="FontSize" Value="11.5"/><Setter Property="VerticalScrollBarVisibility" Value="Auto"/><Setter Property="HorizontalScrollBarVisibility" Value="Auto"/><Setter Property="Padding" Value="10"/></Style>
    <Style x:Key="ListItem" TargetType="ListBoxItem"><Setter Property="Padding" Value="10,6"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="b" CornerRadius="8" Background="Transparent" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="{DynamicResource Btn2Brush}"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="#0A84FF"/><Setter Property="Foreground" Value="White"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  </Window.Resources>

  <Grid>
    <!-- ======================= Assistent ======================= -->
    <Grid x:Name="PanelWizard" MaxWidth="640" VerticalAlignment="Center" Margin="24">
      <Border Style="{StaticResource Card}" Padding="32,28" Margin="0"><StackPanel>
        <TextBlock x:Name="WzStep" Text="SCHRITT 1 VON 3" FontSize="11" FontWeight="SemiBold" Foreground="#0A84FF"/>
        <TextBlock x:Name="WzTitle" Text="" FontSize="24" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" Margin="0,6,0,12"/>
        <TextBlock x:Name="WzText" Text="" FontSize="14" Foreground="{DynamicResource TextBrush}" TextWrapping="Wrap" LineHeight="22"/>
        <StackPanel x:Name="WzConnect" Margin="0,16,0,0" Visibility="Collapsed">
          <TextBlock Text="IP-Adresse des Fire TV Sticks" Style="{StaticResource Sub}" Margin="0,0,0,6"/>
          <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBox x:Name="WzIP" Style="{StaticResource Input}" FontSize="15" Text="192.168.0.15"/>
            <Button x:Name="WzBtnConnect" Grid.Column="1" Content="Verbinden" Style="{StaticResource Primary}" Margin="10,0,0,0"/></Grid>
          <Grid Margin="0,14,0,0"><TextBlock Text="Gespeicherte und gefundene Geräte" Style="{StaticResource Sub}" VerticalAlignment="Center"/><Button x:Name="WzScan" Content="Netzwerk durchsuchen" Style="{StaticResource Secondary}" HorizontalAlignment="Right"/></Grid>
          <Border x:Name="WzListBox" Visibility="Collapsed" Background="{DynamicResource BgBrush}" CornerRadius="10" Margin="0,8,0,0" Padding="4">
            <ListBox x:Name="WzList" Background="Transparent" BorderThickness="0" MaxHeight="150" FontSize="13" ItemContainerStyle="{StaticResource ListItem}"/></Border>
          <TextBlock x:Name="WzStatus" Text="" FontSize="13" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap" Margin="0,12,0,0" LineHeight="20"/>
        </StackPanel>
        <Grid Margin="0,24,0,0"><Button x:Name="WzBack" Content="Zurück" Style="{StaticResource Secondary}" HorizontalAlignment="Left"/><Button x:Name="WzNext" Content="Weiter" Style="{StaticResource Primary}" HorizontalAlignment="Right"/></Grid>
      </StackPanel></Border>
    </Grid>

    <!-- ======================= Hauptfenster ======================= -->
    <Grid x:Name="PanelMain" Visibility="Collapsed">
      <Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <!-- Sidebar -->
      <Border Background="{DynamicResource SideBrush}" Padding="12,18,12,12"><Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <StackPanel>
          <TextBlock Text="Fire TV Mod" FontSize="17" FontWeight="SemiBold" Foreground="{DynamicResource TextBrush}" Margin="12,0,0,14"/>
          <Button x:Name="NavDash" Content="⌂   Dashboard" Style="{StaticResource Nav}"/>
          <Button x:Name="NavApps" Content="▦   Apps &amp; Launcher" Style="{StaticResource Nav}"/>
          <Button x:Name="NavRemote" Content="◉   Fernbedienung" Style="{StaticResource Nav}"/>
          <Button x:Name="NavFiles" Content="▤   Dateien" Style="{StaticResource Nav}"/>
          <Button x:Name="NavSystem" Content="▣   System" Style="{StaticResource Nav}"/>
          <Button x:Name="NavNet" Content="◎   Netzwerk" Style="{StaticResource Nav}"/>
          <Button x:Name="NavAuto" Content="▷   Automation" Style="{StaticResource Nav}"/>
          <Button x:Name="NavTools" Content="✎   Werkzeuge" Style="{StaticResource Nav}"/>
          <Button x:Name="NavHelp" Content="?   Hilfe" Style="{StaticResource Nav}"/>
          <Button x:Name="NavSettings" Content="⚙   Einstellungen" Style="{StaticResource Nav}"/>
        </StackPanel>
        <StackPanel Grid.Row="2">
          <StackPanel Orientation="Horizontal" Margin="12,0,0,6"><Ellipse Width="8" Height="8" Fill="#34C759" VerticalAlignment="Center" Margin="0,0,6,0"/><TextBlock x:Name="SbModel" Text="" FontSize="11.5" Foreground="{DynamicResource TextBrush}" TextWrapping="Wrap"/></StackPanel>
          <TextBlock x:Name="SbInfo" Text="" FontSize="10.5" Foreground="{DynamicResource MutedBrush}" Margin="12,0,0,10" TextWrapping="Wrap"/>
          <Button x:Name="BtLog" Content="Protokoll" Style="{StaticResource Secondary}" Margin="0,0,0,6"/>
          <Button x:Name="BtDisconnect" Content="Trennen" Style="{StaticResource Secondary}"/>
        </StackPanel>
      </Grid></Border>

      <!-- Inhalt -->
      <Grid Grid.Column="1" Margin="22,16,12,12">
        <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

        <!-- Dashboard -->
        <Grid x:Name="PgDash"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <Grid Margin="0,0,10,10"><StackPanel><TextBlock Text="Dashboard" Style="{StaticResource H1}"/><TextBlock x:Name="HdDevice" Style="{StaticResource Sub}"/></StackPanel>
            <Button x:Name="BtRefresh" Content="Aktualisieren" Style="{StaticResource Secondary}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Top"><StackPanel>
            <Border x:Name="Banner" Style="{StaticResource Card}" Background="#D9F5E1" Visibility="Collapsed"><Grid><TextBlock x:Name="BannerTxt" Text="" FontSize="12.5" Foreground="#1E8E3E" TextWrapping="Wrap" VerticalAlignment="Center"/><Button x:Name="BtBannerFix" Content="Mods neu anwenden" Style="{StaticResource Secondary}" HorizontalAlignment="Right" Visibility="Collapsed"/></Grid></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <Grid><TextBlock Text="Favoriten – Schnellstart" Style="{StaticResource H3}"/><TextBlock Text="Apps unter »Apps › Installierte Apps« mit »Favorit« hinzufügen" Style="{StaticResource Sub}" HorizontalAlignment="Right"/></Grid>
              <WrapPanel x:Name="FavPanel" Margin="0,6,0,0"/></StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <Grid><StackPanel Orientation="Horizontal"><TextBlock Text="Live" Style="{StaticResource H3}"/><Ellipse x:Name="LiveDot" Width="8" Height="8" Fill="#FF3B30" Margin="8,0,0,0" VerticalAlignment="Center"/><TextBlock x:Name="LiveApp" Text="" FontSize="12" Foreground="{DynamicResource MutedBrush}" Margin="14,0,0,0" VerticalAlignment="Center"/></StackPanel>
                <TextBlock x:Name="LiveUptime" Text="" FontSize="12" Foreground="{DynamicResource MutedBrush}" HorizontalAlignment="Right" VerticalAlignment="Center"/></Grid>
              <UniformGrid Columns="5" Margin="0,8,0,0">
                <StackPanel Margin="0,0,10,0"><TextBlock Text="CPU" FontSize="10" Foreground="{DynamicResource MutedBrush}"/><TextBlock x:Name="LvCpu" Text="–" FontSize="15" FontWeight="SemiBold"/><ProgressBar x:Name="PbCpu" Height="4" Maximum="100" BorderThickness="0" Background="{DynamicResource Btn2Brush}" Foreground="#0A84FF" Margin="0,4,0,0"/></StackPanel>
                <StackPanel Margin="0,0,10,0"><TextBlock Text="RAM" FontSize="10" Foreground="{DynamicResource MutedBrush}"/><TextBlock x:Name="LvRam" Text="–" FontSize="15" FontWeight="SemiBold"/><ProgressBar x:Name="PbRam" Height="4" Maximum="100" BorderThickness="0" Background="{DynamicResource Btn2Brush}" Foreground="#5E5CE6" Margin="0,4,0,0"/></StackPanel>
                <StackPanel Margin="0,0,10,0"><TextBlock Text="SPEICHER" FontSize="10" Foreground="{DynamicResource MutedBrush}"/><TextBlock x:Name="LvDisk" Text="–" FontSize="15" FontWeight="SemiBold"/><ProgressBar x:Name="PbDisk" Height="4" Maximum="100" BorderThickness="0" Background="{DynamicResource Btn2Brush}" Foreground="#FF9500" Margin="0,4,0,0"/></StackPanel>
                <StackPanel Margin="0,0,10,0"><TextBlock Text="TEMPERATUR" FontSize="10" Foreground="{DynamicResource MutedBrush}"/><TextBlock x:Name="LvTemp" Text="–" FontSize="15" FontWeight="SemiBold"/><ProgressBar x:Name="PbTemp" Height="4" Maximum="100" BorderThickness="0" Background="{DynamicResource Btn2Brush}" Foreground="#FF3B30" Margin="0,4,0,0"/></StackPanel>
                <StackPanel><TextBlock Text="WLAN" FontSize="10" Foreground="{DynamicResource MutedBrush}"/><TextBlock x:Name="LvWifi" Text="–" FontSize="15" FontWeight="SemiBold"/><ProgressBar x:Name="PbWifi" Height="4" Maximum="100" BorderThickness="0" Background="{DynamicResource Btn2Brush}" Foreground="#34C759" Margin="0,4,0,0"/></StackPanel>
              </UniformGrid></StackPanel></Border>
            <Border Style="{StaticResource Card}"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel Margin="0,0,14,0"><TextBlock Text="Startbildschirm (Launcher)" Style="{StaticResource H3}"/><TextBlock Text="Welcher Launcher bei der Home-Taste erscheint. Amazon = Original, andere laufen über Launcher Manager Mini." Style="{StaticResource P}"/></StackPanel>
              <ComboBox x:Name="CbLauncher" Grid.Column="1" Width="230" FontSize="12.5" VerticalAlignment="Center" Margin="0,0,10,0"/>
              <Button x:Name="BtLauncherApply" Grid.Column="2" Content="Wechseln" Style="{StaticResource Secondary}" VerticalAlignment="Center" Margin="0,0,6,0"/>
              <Button x:Name="BtLauncherUninstall" Grid.Column="3" Content="Deinstallieren" Style="{StaticResource Danger}" VerticalAlignment="Center"/></Grid></Border>
            <UniformGrid x:Name="Cards" Columns="2" VerticalAlignment="Top">__CARDS__</UniformGrid>
          </StackPanel></ScrollViewer>
          <Grid Grid.Row="2" Margin="0,4,10,0"><TextBlock x:Name="FtStatus" Text="Bereit." Style="{StaticResource Sub}" VerticalAlignment="Center"/><Button x:Name="BtApply" Content="Änderungen anwenden" Style="{StaticResource Primary}" HorizontalAlignment="Right"/></Grid>
        </Grid>

        <!-- Apps -->
        <Grid x:Name="PgApps" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="Apps &amp; Launcher" Style="{StaticResource H1}"/><TextBlock Text="Ankreuzen – der Launcher lädt die passende Version für diesen Stick automatisch und installiert sie." Style="{StaticResource Sub}"/></StackPanel>
          <TabControl x:Name="TabApps" Grid.Row="1" Background="Transparent" BorderThickness="0" Padding="0,8,0,0">
            <TabItem Header="Katalog"><ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel>
              <TextBlock Text="APPS" Style="{StaticResource Sec}"/><UniformGrid Columns="3" VerticalAlignment="Top">__APPS__</UniformGrid>
              <TextBlock Text="LAUNCHER (STARTBILDSCHIRM)" Style="{StaticResource Sec}"/><UniformGrid Columns="3" VerticalAlignment="Top">__LAUNCHERS__</UniformGrid>
              <Grid Margin="0,4,10,8"><TextBlock x:Name="AppStatus" Text="" Style="{StaticResource Sub}" VerticalAlignment="Center"/><StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="BtAppsUpdates" Content="Updates prüfen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAppsInstall" Content="Ausgewählte installieren" Style="{StaticResource Primary}"/></StackPanel></Grid>
              <TextBlock Text="APK AUS DOWNLOAD-LINK" Style="{StaticResource Sec}"/>
              <Grid Margin="0,0,10,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="TxtApkUrl" Style="{StaticResource Input}" ToolTip="https://…/app.apk"/><Button x:Name="BtApkUrl" Grid.Column="1" Content="Laden &amp; installieren" Style="{StaticResource Secondary}" Margin="6,0,0,0"/></Grid>
            </StackPanel></ScrollViewer></TabItem>
            <TabItem Header="Installierte Apps"><Grid Margin="0,8,10,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                <Button x:Name="BtAppsReload" Content="Liste laden" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAppStart" Content="Starten" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAppStop" Content="Stoppen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/>
                <Button x:Name="BtAppClear" Content="Daten löschen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAppBackup" Content="APK sichern" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAppUninstall" Content="Deinstallieren" Style="{StaticResource Danger}" Margin="0,0,6,0"/>
                <Button x:Name="BtAppFav" Content="★ Favorit" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAppHide" Content="Ausblenden / Einblenden" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAppPerms" Content="Berechtigungen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAppDataBackup" Content="App-Daten sichern" Style="{StaticResource Secondary}"/>
                <CheckBox x:Name="CkShowSystem" Content="System-Apps" VerticalAlignment="Center" Margin="14,0,0,0" FontSize="12"/></StackPanel>
              <Border Grid.Row="1" Background="{DynamicResource CardBrush}" CornerRadius="10" Padding="4"><ListBox x:Name="LbApps" Background="Transparent" BorderThickness="0" FontSize="12.5" FontFamily="Consolas" ItemContainerStyle="{StaticResource ListItem}"/></Border>
            </Grid></TabItem>
            <TabItem Header="Berechtigungen"><Grid Margin="0,8,10,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8"><TextBlock x:Name="PermApp" Text="Keine App gewählt – unter »Installierte Apps« eine App markieren und »Berechtigungen« klicken." Style="{StaticResource Sub}" VerticalAlignment="Center" Margin="0,0,10,0"/><Button x:Name="BtPermToggle" Content="Gewähren / Entziehen" Style="{StaticResource Secondary}"/></StackPanel>
              <Border Grid.Row="1" Background="{DynamicResource CardBrush}" CornerRadius="10" Padding="4"><ListBox x:Name="LbPerms" Background="Transparent" BorderThickness="0" FontSize="12" FontFamily="Consolas" ItemContainerStyle="{StaticResource ListItem}"/></Border></Grid></TabItem>
            <TabItem Header="Laufende Apps"><Grid Margin="0,8,10,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8"><Button x:Name="BtRunReload" Content="Aktualisieren" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtRunStop" Content="Ausgewählte beenden" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtRunKillAll" Content="Alle beenden" Style="{StaticResource Danger}" Margin="0,0,14,0"/>
                <Button x:Name="BtRecStart" Content="● Aufzeichnung starten" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtRecStop" Content="■ Stopp &amp; Auswertung" Style="{StaticResource Secondary}" Margin="0,0,6,0" IsEnabled="False"/><Button x:Name="BtRecOpen" Content="CSV öffnen" Style="{StaticResource Secondary}"/>
                <TextBlock x:Name="RunStatus" Style="{StaticResource Sub}" Margin="10,0,0,0" VerticalAlignment="Center"/></StackPanel>
              <Border Grid.Row="1" Background="{DynamicResource CardBrush}" CornerRadius="10" Padding="4"><ListBox x:Name="LbRunning" Background="Transparent" BorderThickness="0" FontSize="12" FontFamily="Consolas" ItemContainerStyle="{StaticResource ListItem}"/></Border></Grid></TabItem>
          </TabControl>
        </Grid>

        <!-- Fernbedienung -->
        <Grid x:Name="PgRemote" Visibility="Collapsed" Focusable="True"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="Fernbedienung" Style="{StaticResource H1}"/><TextBlock Text="Stick vom PC aus steuern, Text eintippen, Bildschirm aufnehmen." Style="{StaticResource Sub}"/></StackPanel>
          <Grid Grid.Row="1"><Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <StackPanel Width="300">
              <Border Style="{StaticResource Card}"><StackPanel>
                <TextBlock Text="Steuerung" Style="{StaticResource H3}"/>
                <WrapPanel x:Name="KeyPad" Margin="0,8,0,0" Width="260">__KEYS__</WrapPanel>
                <TextBlock Text="Tipp: Pfeiltasten, Enter, Backspace und Escape der Tastatur funktionieren, solange das Textfeld nicht aktiv ist." Style="{StaticResource P}"/></StackPanel></Border>
              <Border Style="{StaticResource Card}"><StackPanel>
                <TextBlock Text="Text eingeben" Style="{StaticResource H3}"/>
                <TextBlock Text="Z. B. Passwörter oder Suchbegriffe – landet im gerade aktiven Textfeld auf dem TV." Style="{StaticResource P}"/>
                <Grid Margin="0,8,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <TextBox x:Name="TxtSend" Style="{StaticResource Input}"/><Button x:Name="BtSendText" Grid.Column="1" Content="Senden" Style="{StaticResource Primary}" Margin="8,0,0,0"/></Grid>
              </StackPanel></Border>
            </StackPanel>
            <Border Grid.Column="1" Style="{StaticResource Card}"><Grid><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <StackPanel Orientation="Horizontal"><TextBlock Text="Bildschirm" Style="{StaticResource H3}"/>
                <Button x:Name="BtShot" Content="Screenshot" Style="{StaticResource Secondary}" Margin="14,0,6,0"/>
                <Button x:Name="BtRec" Content="Aufnahme 15 s" Style="{StaticResource Secondary}" Margin="0,0,6,0"/>
                <Button x:Name="BtShotFolder" Content="Ordner öffnen" Style="{StaticResource Secondary}"/>
                <TextBlock x:Name="ShotStatus" Text="" Style="{StaticResource Sub}" Margin="12,0,0,0" VerticalAlignment="Center"/></StackPanel>
              <Border Grid.Row="1" Background="#1D1D1F" CornerRadius="10" Margin="0,10,0,0"><Image x:Name="ImgShot" Stretch="Uniform" Margin="6"/></Border>
            </Grid></Border>
          </Grid>
        </Grid>

        <!-- Dateien -->
        <Grid x:Name="PgFiles" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="Dateien" Style="{StaticResource H1}"/><TextBlock Text="Filme, Musik, Untertitel oder APKs auf den Stick kopieren und zurückholen." Style="{StaticResource Sub}"/></StackPanel>
          <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
            <TextBlock Text="Ordner auf dem Stick:" Style="{StaticResource Sub}" VerticalAlignment="Center" Margin="0,0,8,0"/>
            <ComboBox x:Name="CbFolder" Width="200" FontSize="12.5" Margin="0,0,10,0"/>
            <Button x:Name="BtFilesReload" Content="Laden" Style="{StaticResource Secondary}" Margin="0,0,6,0"/>
            <Button x:Name="BtUpload" Content="Hochladen …" Style="{StaticResource Primary}" Margin="0,0,6,0"/>
            <Button x:Name="BtDownload" Content="Herunterladen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/>
            <Button x:Name="BtDelete" Content="Löschen" Style="{StaticResource Danger}" Margin="0,0,6,0"/>
            <Button x:Name="BtDlFolder" Content="PC-Ordner öffnen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/>
            <Button x:Name="BtScreensaver" Content="Bildschirmschoner-Fotos …" Style="{StaticResource Secondary}"/>
            <TextBlock x:Name="FileStatus" Text="" Style="{StaticResource Sub}" Margin="12,0,0,0" VerticalAlignment="Center"/></StackPanel>
          <Border Grid.Row="2" Background="{DynamicResource CardBrush}" CornerRadius="10" Padding="4" Margin="0,0,10,0"><ListBox x:Name="LbFiles" Background="Transparent" BorderThickness="0" FontSize="12.5" FontFamily="Consolas" SelectionMode="Extended" ItemContainerStyle="{StaticResource ListItem}"/></Border>
        </Grid>

        <!-- System -->
        <Grid x:Name="PgSystem" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="System" Style="{StaticResource H1}"/><TextBlock Text="Anzeige, Energie, Backup und Wiederherstellung." Style="{StaticResource Sub}"/></StackPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Top"><UniformGrid Columns="2" VerticalAlignment="Top">
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Anzeige" Style="{StaticResource H3}"/><TextBlock Text="Auflösung der Oberfläche und Schriftgrösse (DPI). »Auto« = Werkseinstellung." Style="{StaticResource P}"/>
              <Grid Margin="0,8,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="90"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions><Grid.RowDefinitions><RowDefinition/><RowDefinition/></Grid.RowDefinitions>
                <TextBlock Text="Auflösung" Style="{StaticResource Sub}" VerticalAlignment="Center"/><ComboBox x:Name="CbRes" Grid.Column="1" FontSize="12.5" Margin="0,0,0,6"/>
                <TextBlock Grid.Row="1" Text="Grösse (DPI)" Style="{StaticResource Sub}" VerticalAlignment="Center"/><ComboBox x:Name="CbDpi" Grid.Row="1" Grid.Column="1" FontSize="12.5"/></Grid>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0"><Button x:Name="BtDisplayApply" Content="Anwenden" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtDisplayReset" Content="Zurücksetzen" Style="{StaticResource Secondary}"/><TextBlock x:Name="DispStatus" Style="{StaticResource Sub}" Margin="10,0,0,0" VerticalAlignment="Center"/></StackPanel>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Energie" Style="{StaticResource H3}"/><TextBlock Text="Nach wie vielen Minuten Inaktivität der Stick in den Ruhezustand geht." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><ComboBox x:Name="CbSleep" Width="160" FontSize="12.5" Margin="0,0,6,0"/><Button x:Name="BtSleepApply" Content="Anwenden" Style="{StaticResource Secondary}"/></StackPanel>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0"><Button x:Name="BtStandby" Content="Standby" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtWake" Content="Aufwecken" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtReboot2" Content="Neu starten" Style="{StaticResource Secondary}"/></StackPanel>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Profil sichern &amp; übertragen" Style="{StaticResource H3}"/><TextBlock Text="Speichert deaktivierte Pakete, Animationen, DNS und Launcher-Zustand als Datei. Auf einem anderen Stick importieren = gleiche Konfiguration in einem Schritt." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0"><Button x:Name="BtProfileExport" Content="Profil exportieren" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtProfileImport" Content="Profil importieren …" Style="{StaticResource Secondary}"/></StackPanel>
              <TextBlock x:Name="ProfStatus" Style="{StaticResource Sub}" Margin="0,8,0,0"/>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Apps sichern" Style="{StaticResource H3}"/><TextBlock Text="Lädt die APK-Dateien aller selbst installierten Apps in den Ordner »backups« – zum Wiederherstellen oder für einen zweiten Stick." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,10,0,0"><Button x:Name="BtBackupAll" Content="Alle APKs sichern" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtRestoreAll" Content="Aus »backups« installieren" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtBackupFolder" Content="Ordner" Style="{StaticResource Secondary}"/></StackPanel>
              <TextBlock x:Name="BkStatus" Style="{StaticResource Sub}" Margin="0,8,0,0"/>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Hintergrundprozesse begrenzen" Style="{StaticResource H3}"/><TextBlock Text="Wie viele Apps im Hintergrund im Speicher bleiben dürfen. Weniger = mehr freier RAM und flotteres Umschalten, aber Apps starten öfter neu. Empfehlung bei 2 GB RAM: höchstens 2–3." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><ComboBox x:Name="CbBgLimit" Width="200" FontSize="12.5" Margin="0,0,6,0"/><Button x:Name="BtBgApply" Content="Anwenden" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtBgKill" Content="Jetzt alle beenden" Style="{StaticResource Secondary}"/></StackPanel>
              <CheckBox x:Name="CkFinishAct" Content="Aggressiv: Apps beim Verlassen sofort beenden (always_finish_activities)" FontSize="11.5" Margin="0,8,0,0"/>
              <TextBlock x:Name="BgStatus" Style="{StaticResource Sub}" Margin="0,6,0,0"/>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Gerätename" Style="{StaticResource H3}"/><TextBlock Text="Name des Sticks im Netzwerk, bei Alexa und Bluetooth." Style="{StaticResource P}"/>
              <Grid Margin="0,8,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="TxtDevName" Style="{StaticResource Input}"/><Button x:Name="BtDevName" Grid.Column="1" Content="Umbenennen" Style="{StaticResource Secondary}" Margin="6,0,0,0"/></Grid>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="HDMI-CEC (Fernseher steuern)" Style="{StaticResource H3}"/><TextBlock Text="Stick schaltet TV ein/aus und wechselt den Eingang – der TV muss CEC unterstützen (Anynet+, Simplink, Bravia Sync …)." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><Button x:Name="BtCecOn" Content="CEC aktivieren" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtCecOff" Content="CEC aus" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtTvPower" Content="TV Ein/Aus" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtTvInput" Content="TV-Eingang" Style="{StaticResource Secondary}"/></StackPanel>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Komplett-Backup &amp; Werks-Reset" Style="{StaticResource H3}"/><TextBlock Text="Komplett = Profil + alle APKs in einem Schritt. Werks-Reset löscht alles auf dem Stick; danach ADB wieder aktivieren und »Aus backups installieren« + »Profil importieren«." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><Button x:Name="BtFullBackup" Content="Komplett-Backup" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtFactoryReset" Content="Werks-Reset …" Style="{StaticResource Danger}"/></StackPanel>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Auf alle Sticks ausrollen" Style="{StaticResource H3}"/><TextBlock Text="Wendet ein Profil nacheinander auf alle gespeicherten Sticks an (müssen eingeschaltet und ADB-freigegeben sein)." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><Button x:Name="BtRollout" Content="Profil auf alle Sticks …" Style="{StaticResource Secondary}"/><TextBlock x:Name="RolloutStatus" Style="{StaticResource Sub}" Margin="10,0,0,0" VerticalAlignment="Center"/></StackPanel>
            </StackPanel></Border>
          </UniformGrid></ScrollViewer>
        </Grid>

        <!-- Netzwerk -->
        <Grid x:Name="PgNet" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="Netzwerk" Style="{StaticResource H1}"/><TextBlock Text="WLAN-Status, Werbeblocker-Profile, Update-Sperre und VPN." Style="{StaticResource Sub}"/></StackPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Top"><UniformGrid Columns="2" VerticalAlignment="Top">
            <Border Style="{StaticResource Card}"><StackPanel>
              <Grid><TextBlock Text="WLAN" Style="{StaticResource H3}"/><StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="BtNetReload" Content="Aktualisieren" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtPing" Content="Ping-Test" Style="{StaticResource Secondary}"/></StackPanel></Grid>
              <TextBox x:Name="NetInfo" Style="{StaticResource Mono}" Height="150" Margin="0,8,0,0"/>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Werbeblocker (privater DNS)" Style="{StaticResource H3}"/><TextBlock Text="Filtert Werbung/Tracker für alle Apps. Mit eigenem Pi-hole/NextDNS lassen sich dort auch die Amazon-Update-Server sperren." Style="{StaticResource P}"/>
              <ComboBox x:Name="CbDns" FontSize="12.5" Margin="0,8,0,6"/>
              <TextBox x:Name="TxtDnsHost" Style="{StaticResource Input}" Visibility="Collapsed" Margin="0,0,0,6"/>
              <StackPanel Orientation="Horizontal"><Button x:Name="BtDnsApply" Content="Aktivieren" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtDnsOff" Content="Ausschalten" Style="{StaticResource Secondary}"/><TextBlock x:Name="DnsStatus" Style="{StaticResource Sub}" Margin="10,0,0,0" VerticalAlignment="Center"/></StackPanel>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Update-Sperre (Router)" Style="{StaticResource H3}"/><TextBlock Text="Der Stick selbst kann Fire-OS-Updates nicht vollständig blockieren. Sperre diese Hosts im Router oder im DNS-Filter für die IP des Sticks:" Style="{StaticResource P}"/>
              <TextBox x:Name="TxtHosts" Style="{StaticResource Mono}" Height="70" Margin="0,8,0,6" Text="amzdigitaldownloads.edgesuite.net&#10;softwareupdates.amazon.com&#10;updates.amazon.com&#10;d1s31zyz7dcc2d.cloudfront.net"/>
              <Button x:Name="BtCopyHosts" Content="Liste kopieren" Style="{StaticResource Secondary}" HorizontalAlignment="Left"/>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="VPN" Style="{StaticResource H3}"/><TextBlock Text="Installierte VPN-Apps starten oder beenden." Style="{StaticResource P}"/>
              <StackPanel x:Name="VpnList" Margin="0,8,0,0">__VPN__</StackPanel>
              <TextBlock x:Name="VpnNone" Text="Keine bekannte VPN-App installiert." Style="{StaticResource Sub}"/>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="WLAN wechseln" Style="{StaticResource H3}"/><TextBlock x:Name="WifiHint" Text="Netzwerk und Passwort setzen (ab Fire OS 8 / Android 11)." Style="{StaticResource P}"/>
              <Grid Margin="0,8,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBox x:Name="TxtSsid" Style="{StaticResource Input}" ToolTip="SSID" Margin="0,0,6,0"/><TextBox x:Name="TxtWifiPw" Style="{StaticResource Input}" ToolTip="Passwort" Margin="0,0,6,0"/><Button x:Name="BtWifiConnect" Grid.Column="2" Content="Verbinden" Style="{StaticResource Secondary}"/></Grid>
            </StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel>
              <TextBlock Text="Bandbreitentest" Style="{StaticResource H3}"/><TextBlock Text="Öffnet fast.com im Browser des Sticks (Silk oder TV Bro) – Ergebnis auf dem Fernseher ablesen." Style="{StaticResource P}"/>
              <Button x:Name="BtSpeed" Content="Speedtest am TV starten" Style="{StaticResource Secondary}" HorizontalAlignment="Left" Margin="0,8,0,0"/>
            </StackPanel></Border>
          </UniformGrid></ScrollViewer>
        </Grid>

        <!-- Werkzeuge -->
        <Grid x:Name="PgTools" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="Werkzeuge" Style="{StaticResource H1}"/><TextBlock Text="Geräteinfos, Live-Log, Bluetooth und Protokoll-Export." Style="{StaticResource Sub}"/></StackPanel>
          <TabControl Grid.Row="1" Background="Transparent" BorderThickness="0" Padding="0,8,10,0">
            <TabItem Header="Konsole"><Grid Margin="0,8,0,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <TextBlock Style="{StaticResource P}" Margin="0,0,0,8" Text="Eigene Befehle an den Stick. Ohne Präfix = adb shell (z. B. pm list packages -3, getprop ro.product.model, settings get global private_dns_mode). Mit Präfix »adb « = ADB direkt (z. B. adb devices, adb pull /sdcard/x.txt). ↑/↓ = Verlauf, Enter = ausführen."/>
              <Grid Grid.Row="1" Margin="0,0,0,8"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <TextBox x:Name="TxtCmd" Style="{StaticResource Input}" FontFamily="Consolas"/><Button x:Name="BtCmdRun" Grid.Column="1" Content="Ausführen" Style="{StaticResource Primary}" Margin="6,0,0,0"/>
                <ComboBox x:Name="CbCmdExamples" Grid.Column="2" Width="200" FontSize="12" Margin="6,0,0,0"/><Button x:Name="BtCmdClear" Grid.Column="3" Content="Leeren" Style="{StaticResource Secondary}" Margin="6,0,0,0"/></Grid>
              <TextBox Grid.Row="2" x:Name="TxtCmdOut" Style="{StaticResource Mono}"/></Grid></TabItem>
            <TabItem Header="Geräteinfo"><Grid Margin="0,8,0,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <Button x:Name="BtInfoReload" Content="Laden" Style="{StaticResource Secondary}" HorizontalAlignment="Left" Margin="0,0,0,8"/>
              <TextBox Grid.Row="1" x:Name="TxtInfo" Style="{StaticResource Mono}"/></Grid></TabItem>
            <TabItem Header="Logcat"><Grid Margin="0,8,0,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8"><TextBox x:Name="TxtLogFilter" Style="{StaticResource Input}" Width="260" Margin="0,0,6,0" ToolTip="Filter (z. B. Paketname oder Fehlertext)"/><Button x:Name="BtLogcat" Content="Letzte 500 Zeilen laden" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtLogcatClear" Content="Log auf Stick leeren" Style="{StaticResource Secondary}"/></StackPanel>
              <TextBox Grid.Row="1" x:Name="TxtLogcat" Style="{StaticResource Mono}"/></Grid></TabItem>
            <TabItem Header="Bluetooth"><Grid Margin="0,8,0,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <Button x:Name="BtBtReload" Content="Gekoppelte Geräte laden" Style="{StaticResource Secondary}" HorizontalAlignment="Left" Margin="0,0,0,8"/>
              <TextBox Grid.Row="1" x:Name="TxtBt" Style="{StaticResource Mono}"/></Grid></TabItem>
            <TabItem Header="Protokoll"><Grid Margin="0,8,0,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <StackPanel Orientation="Horizontal" Margin="0,0,0,8"><Button x:Name="BtLogExport" Content="Als Datei speichern …" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtLogClear" Content="Leeren" Style="{StaticResource Secondary}"/></StackPanel>
              <TextBox Grid.Row="1" x:Name="Log" Style="{StaticResource Mono}" TextWrapping="Wrap"/></Grid></TabItem>
          </TabControl>
        </Grid>

        <!-- Automation -->
        <Grid x:Name="PgAuto" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="Automation" Style="{StaticResource H1}"/><TextBlock Text="Makros (Befehlsketten) und Zeitpläne, die auch ohne offenes Fenster laufen." Style="{StaticResource Sub}"/></StackPanel>
          <TabControl Grid.Row="1" Background="Transparent" BorderThickness="0" Padding="0,8,10,0">
            <TabItem Header="Makros"><Grid Margin="0,8,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <Grid><Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <Border Background="{DynamicResource CardBrush}" CornerRadius="10" Padding="4" Margin="0,0,10,0"><ListBox x:Name="LbMacros" Background="Transparent" BorderThickness="0" FontSize="12.5" ItemContainerStyle="{StaticResource ListItem}"/></Border>
                <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,0"><Button x:Name="BtMacroNew" Content="Neu" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtMacroDel" Content="Löschen" Style="{StaticResource Danger}"/></StackPanel></Grid>
              <Grid Grid.Column="1"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <TextBox x:Name="TxtMacroName" Style="{StaticResource Input}" Margin="0,0,0,6" ToolTip="Name des Makros"/>
                <TextBox Grid.Row="1" x:Name="TxtMacroSteps" Style="{StaticResource Input}" AcceptsReturn="True" FontFamily="Consolas" VerticalScrollBarVisibility="Auto" MinHeight="160"/>
                <TextBlock Grid.Row="2" Style="{StaticResource P}" Text="Ein Befehl pro Zeile: taste &lt;name|code&gt; (home, zurueck, ok, hoch, runter, links, rechts, play, menue) · start &lt;paket&gt; · stop &lt;paket&gt; · alle-stoppen · hintergrund &lt;0-4|-1&gt; · lautstaerke &lt;0-15&gt; · animationen &lt;0|0.5|1&gt; · dns &lt;an|aus&gt; · standby · aufwecken · neustart · cache · warte &lt;sek&gt; · text &lt;…&gt; · shell &lt;befehl&gt;"/>
                <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,8,0,0"><Button x:Name="BtMacroSave" Content="Speichern" Style="{StaticResource Primary}" Margin="0,0,6,0"/><Button x:Name="BtMacroRun" Content="Jetzt ausführen" Style="{StaticResource Secondary}"/><TextBlock x:Name="MacroStatus" Style="{StaticResource Sub}" Margin="10,0,0,0" VerticalAlignment="Center"/></StackPanel>
              </Grid></Grid></TabItem>
            <TabItem Header="Zeitpläne"><Grid Margin="0,8,0,0"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <TextBlock Style="{StaticResource P}" Text="Legt eine Windows-Aufgabe an, die das Makro zur gewählten Zeit im Hintergrund ausführt (PC muss eingeschaltet sein). Beispiel: »Gute Nacht« täglich 23:30."/>
              <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,8,0,8">
                <ComboBox x:Name="CbSchedMacro" Width="180" FontSize="12.5" Margin="0,0,6,0"/><ComboBox x:Name="CbSchedWhen" Width="140" FontSize="12.5" Margin="0,0,6,0"/>
                <TextBox x:Name="TxtSchedTime" Style="{StaticResource Input}" Width="70" Text="23:30" Margin="0,0,6,0"/>
                <Button x:Name="BtSchedAdd" Content="Zeitplan anlegen" Style="{StaticResource Primary}" Margin="0,0,6,0"/><Button x:Name="BtSchedDel" Content="Ausgewählten löschen" Style="{StaticResource Danger}" Margin="0,0,6,0"/><Button x:Name="BtSchedReload" Content="Aktualisieren" Style="{StaticResource Secondary}"/></StackPanel>
              <Border Grid.Row="2" Background="{DynamicResource CardBrush}" CornerRadius="10" Padding="4"><ListBox x:Name="LbSched" Background="Transparent" BorderThickness="0" FontSize="12.5" FontFamily="Consolas" ItemContainerStyle="{StaticResource ListItem}"/></Border>
            </Grid></TabItem>
          </TabControl></Grid>

        <!-- Hilfe -->
        <Grid x:Name="PgHelp" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="Hilfe &amp; FAQ" Style="{StaticResource H1}"/><TextBlock x:Name="HelpVersion" Text="" Style="{StaticResource Sub}"/></StackPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><Border Style="{StaticResource Card}"><TextBlock x:Name="HelpText" Style="{StaticResource P}" FontSize="12.5" LineHeight="19"/></Border></ScrollViewer></Grid>

        <!-- Einstellungen -->
        <Grid x:Name="PgSettings" Visibility="Collapsed"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <StackPanel Margin="0,0,10,10"><TextBlock Text="Einstellungen" Style="{StaticResource H1}"/><TextBlock Text="Darstellung und Verhalten des Mod-Launchers." Style="{StaticResource Sub}"/></StackPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" VerticalAlignment="Top"><UniformGrid Columns="2" VerticalAlignment="Top">
            <Border Style="{StaticResource Card}"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel><TextBlock Text="Dark Mode" Style="{StaticResource H3}"/><TextBlock Text="Dunkles Farbschema für den Launcher." Style="{StaticResource P}"/></StackPanel><CheckBox x:Name="SwDark" Grid.Column="1" Style="{StaticResource Switch}" VerticalAlignment="Center"/></Grid></Border>
            <Border Style="{StaticResource Card}"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel><TextBlock Text="Automatisch verbinden" Style="{StaticResource H3}"/><TextBlock Text="Beim Start direkt mit dem zuletzt genutzten Stick verbinden, Assistent überspringen." Style="{StaticResource P}"/></StackPanel><CheckBox x:Name="SwAuto" Grid.Column="1" Style="{StaticResource Switch}" VerticalAlignment="Center"/></Grid></Border>
            <Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="Mit Windows starten" Style="{StaticResource H3}"/><TextBlock Text="Legt eine Verknüpfung im Autostart-Ordner an (ohne Konsolenfenster)." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><Button x:Name="BtAutostartOn" Content="Aktivieren" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtAutostartOff" Content="Entfernen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtDesktopLink" Content="Desktop-Verknüpfung" Style="{StaticResource Secondary}"/><TextBlock x:Name="AutostartStatus" Style="{StaticResource Sub}" Margin="10,0,0,0" VerticalAlignment="Center"/></StackPanel></StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="Selbst-Update" Style="{StaticResource H3}"/><TextBlock Text="URL eines Ordners mit version.txt und FireTV_Mod_Launcher.ps1 (z. B. GitHub-Raw). Leer = deaktiviert." Style="{StaticResource P}"/>
              <TextBox x:Name="TxtUpdateUrl" Style="{StaticResource Input}" Margin="0,8,0,6"/>
              <StackPanel Orientation="Horizontal"><Button x:Name="BtUpdateCheck" Content="Nach Update suchen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><TextBlock x:Name="UpdateStatus" Style="{StaticResource Sub}" VerticalAlignment="Center"/></StackPanel></StackPanel></Border>
            <Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="Daten des Launchers" Style="{StaticResource H3}"/><TextBlock Text="Alle Einstellungen, Makros, Favoriten und gespeicherten Sticks liegen als JSON im Launcher-Ordner." Style="{StaticResource P}"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0"><Button x:Name="BtOpenRoot" Content="Ordner öffnen" Style="{StaticResource Secondary}" Margin="0,0,6,0"/><Button x:Name="BtResetSettings" Content="Einstellungen zurücksetzen" Style="{StaticResource Danger}"/></StackPanel></StackPanel></Border>
          </UniformGrid></ScrollViewer></Grid>

        <!-- Mini-Protokoll unten -->
        <Border Grid.Row="1" x:Name="LogBox" Visibility="Collapsed" Background="#1D1D1F" CornerRadius="10" Margin="0,10,10,0" Padding="2"><TextBox x:Name="LogMini" Style="{StaticResource Mono}" Height="110" TextWrapping="Wrap"/></Border>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@
$xaml = $xaml.Replace('__CARDS__', $cardsXaml).Replace('__APPS__', $appsXaml).Replace('__LAUNCHERS__', $launchersXaml).Replace('__KEYS__', $keysXaml).Replace('__VPN__', $vpnXaml)
$Window = [Windows.Markup.XamlReader]::Parse($xaml)
function UI($n) { $Window.FindName($n) }
function Apply-Theme {
  $t = if ($script:Set.Dark) { @{ BgBrush='#1C1C1E'; CardBrush='#2C2C2E'; TextBrush='#F5F5F7'; MutedBrush='#98989D'; Btn2Brush='#3A3A3C'; HoverBrush='#48484A'; SideBrush='#232325'; BorderBrush='#48484A' } }
       else { @{ BgBrush='#F5F5F7'; CardBrush='#FFFFFF'; TextBrush='#1D1D1F'; MutedBrush='#6E6E73'; Btn2Brush='#E9E9EB'; HoverBrush='#DCDCDE'; SideBrush='#ECECF1'; BorderBrush='#D2D2D7' } }
  foreach ($k in $t.Keys) { $Window.Resources[$k] = (New-Object System.Windows.Media.BrushConverter).ConvertFromString($t[$k]) } }
$script:UiReady = $true
Apply-Theme
if ($script:Set.Width -ge 800) { $Window.Width = $script:Set.Width }; if ($script:Set.Height -ge 500) { $Window.Height = $script:Set.Height }
$Window.Add_Closing({ $script:Set.Width = [int]$Window.Width; $script:Set.Height = [int]$Window.Height; Save-Settings })

# ================================================================== Helfer
function Refresh-UI { $f = New-Object System.Windows.Threading.DispatcherFrame
  [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [System.Windows.Threading.DispatcherOperationCallback]{ param($o) $o.Continue = $false; $null }, $f) | Out-Null
  [System.Windows.Threading.Dispatcher]::PushFrame($f) }
function Status($msg) { (UI 'FtStatus').Text = $msg; Refresh-UI }
function Brush($hex) { (New-Object System.Windows.Media.BrushConverter).ConvertFromString($hex) }
function Set-Badge($id, [bool]$on, $textOn = 'AKTIV', $textOff = 'INAKTIV') { $b = UI "bd_$id"; $t = UI "bt_txt_$id"
  if ($on) { $b.Background = (Brush '#D9F5E1'); $t.Foreground = (Brush '#1E8E3E'); $t.Text = $textOn } else { $b.Background = $Window.Resources['Btn2Brush']; $t.Foreground = $Window.Resources['MutedBrush']; $t.Text = $textOff } }
function Open-Folder($p) { Start-Process explorer.exe $p }
function Ensure-Adb {
  if (Test-Path $script:ADB) { return $true }
  (UI 'WzStatus').Text = 'Lade ADB (platform-tools) herunter …'; Refresh-UI
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $zip = Join-Path $Root 'pt.zip'
    Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip; Expand-Archive $zip -DestinationPath $Root -Force; Remove-Item $zip; return (Test-Path $script:ADB)
  } catch { (UI 'WzStatus').Text = "ADB-Download fehlgeschlagen: $($_.Exception.Message)"; return $false } }

# ================================================================== Geräte-Profile
function Save-Device($ip, $name) {
  $list = @(Load-Devices | Where-Object { $_.IP -ne $ip }); $list += [pscustomobject]@{ IP = $ip; Name = $name; Last = (Get-Date).ToString('s') }
  (, $list) | ConvertTo-Json -Depth 4 | Set-Content $script:DevFile -Encoding UTF8 }
function Fill-DeviceList($found) {
  $list = UI 'WzList'; $list.Items.Clear(); $n = 0; $saved = @(Load-Devices)
  foreach ($d in ($saved | Sort-Object Last -Descending)) { $i = New-Object System.Windows.Controls.ListBoxItem; $i.Content = "$($d.IP)   ·   $($d.Name)   (gespeichert)"; $i.Tag = $d.IP; $list.Items.Add($i) | Out-Null; $n++ }
  foreach ($ip in $found) { if ($saved | Where-Object { $_.IP -eq $ip }) { continue }; $name = ''; try { $name = ([System.Net.Dns]::GetHostEntry($ip)).HostName } catch {}
    $i = New-Object System.Windows.Controls.ListBoxItem; $i.Content = "$ip   ·   $(if($name){$name}else{'ADB-Gerät'})"; $i.Tag = $ip; $list.Items.Add($i) | Out-Null; $n++ }
  (UI 'WzListBox').Visibility = if ($n -gt 0) { 'Visible' } else { 'Collapsed' } }

# ================================================================== Verbindung
function Scan-Network {
  $btn = UI 'WzScan'; $btn.IsEnabled = $false
  $local = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and $_.ToString() -notlike '127.*' -and $_.ToString() -notlike '169.254.*' }
  $subnets = $local | ForEach-Object { ($_.ToString() -split '\.')[0..2] -join '.' } | Select-Object -Unique
  if (-not $subnets) { (UI 'WzStatus').Text = 'Kein Netzwerk gefunden – ist der PC mit dem WLAN/LAN verbunden?'; Fill-DeviceList @(); $btn.IsEnabled = $true; return }
  (UI 'WzStatus').Text = "Suche Fire TV Geräte in $($subnets -join ', ').x …"; Refresh-UI
  $tasks = @(); foreach ($sn in $subnets) { foreach ($i in 1..254) { $ip = "$sn.$i"; $c = New-Object System.Net.Sockets.TcpClient; $tasks += [pscustomobject]@{ IP = $ip; Client = $c; Task = $c.ConnectAsync($ip, 5555) } } }
  $deadline = (Get-Date).AddSeconds(4); while ((Get-Date) -lt $deadline -and ($tasks | Where-Object { -not $_.Task.IsCompleted })) { Start-Sleep -Milliseconds 150; Refresh-UI }
  $found = @(); foreach ($t in $tasks) { if ($t.Task.IsCompleted -and -not $t.Task.IsFaulted -and -not $t.Task.IsCanceled -and $t.Client.Connected) { $found += $t.IP }; try { $t.Client.Close() } catch {} }
  Fill-DeviceList $found
  (UI 'WzStatus').Text = if ($found.Count -gt 0) { "$($found.Count) Gerät(e) mit aktivem ADB gefunden – zum Verbinden anklicken." } else { 'Kein Gerät mit offenem ADB-Port gefunden. ADB-Debugging eingeschaltet? Stick an?' }
  if ($found.Count -eq 1) { (UI 'WzIP').Text = $found[0] }
  $btn.IsEnabled = $true }

function Try-Connect {
  $script:IP = (UI 'WzIP').Text.Trim()
  if ($script:IP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { (UI 'WzStatus').Text = 'Bitte eine gültige IP-Adresse eingeben (z. B. 192.168.0.15).'; return }
  (UI 'WzBtnConnect').IsEnabled = $false
  if (-not (Ensure-Adb)) { (UI 'WzBtnConnect').IsEnabled = $true; return }
  (UI 'WzStatus').Text = "Verbinde mit $($script:IP) …"; Refresh-UI
  $r = Run-Adb @('connect', "$($script:IP):5555"); Start-Sleep -Milliseconds 800
  $line = ((Run-Adb @('devices')) -split "`n" | Where-Object { $_ -like "$($script:IP):5555*" }) -join ''
  if ($line -match 'unauthorized') { (UI 'WzStatus').Text = 'Auf dem Fernseher erscheint »USB-Debugging zulassen?« → »Immer zulassen« wählen und OK drücken. Danach erneut auf Verbinden klicken.' }
  elseif ($line -match '\sdevice') {
    $script:Model = Shell 'getprop ro.product.model'; $os = Shell 'getprop ro.build.version.name'; if (-not $os) { $os = "Android $(Shell 'getprop ro.build.version.release')" }
    $script:ABI = Shell 'getprop ro.product.cpu.abilist'; $script:Is64 = ($script:ABI -match 'arm64'); $sdk = Shell 'getprop ro.build.version.sdk'; if ($sdk -match '^\d+$') { $script:SDK = [int]$sdk }
    $script:Connected = $true; Save-Device $script:IP $script:Model
    (UI 'HdDevice').Text = "$($script:Model) · $os · $(if($script:Is64){'64-Bit'}else{'32-Bit'}) · API $($script:SDK) · $($script:IP)"
    (UI 'SbModel').Text = $script:Model; (UI 'SbInfo').Text = "$os · $($script:IP)"
    (UI 'WifiHint').Text = if ($script:SDK -ge 30) { 'Netzwerk und Passwort setzen.' } else { "Dieser Stick (Android-API $($script:SDK)) unterstützt WLAN-Wechsel per ADB nicht – nur ab Fire OS 8." }; (UI 'BtWifiConnect').IsEnabled = ($script:SDK -ge 30)
    (UI 'PanelWizard').Visibility = 'Collapsed'; (UI 'PanelMain').Visibility = 'Visible'
    Log "Verbunden mit $($script:Model) ($os) unter $($script:IP)"; Show-Page 'Dash'; Read-State; $script:LastCpu = $null; Update-Live
  } else { (UI 'WzStatus').Text = "Keine Verbindung. Stick eingeschaltet? ADB-Debugging aktiv? Gleiches WLAN? Antwort: $r" }
  (UI 'WzBtnConnect').IsEnabled = $true }

function Disconnect-Device { Run-Adb @('disconnect') | Out-Null; $script:Connected = $false; (UI 'PanelMain').Visibility = 'Collapsed'; (UI 'PanelWizard').Visibility = 'Visible'; Show-Step 2; (UI 'WzStatus').Text = '' }

# ================================================================== Seiten
$Pages = @('Dash', 'Apps', 'Remote', 'Files', 'System', 'Net', 'Auto', 'Tools', 'Help', 'Settings')
function Show-Page($p) {
  foreach ($x in $Pages) { (UI "Pg$x").Visibility = if ($x -eq $p) { 'Visible' } else { 'Collapsed' }; (UI "Nav$x").Background = if ($x -eq $p) { $Window.Resources['CardBrush'] } else { (Brush '#00FFFFFF') }; (UI "Nav$x").FontWeight = if ($x -eq $p) { [System.Windows.FontWeights]::SemiBold } else { [System.Windows.FontWeights]::Normal } }
  switch ($p) { 'Files' { if ((UI 'LbFiles').Items.Count -eq 0) { Load-Files } } 'Net' { Load-NetInfo; Update-Vpn } 'System' { Load-SystemState } 'Apps' { Update-AppState; if ((UI 'LbApps').Items.Count -eq 0) { Load-AppList } } 'Remote' { (UI 'PgRemote').Focus() | Out-Null } 'Auto' { Load-Macros; Load-Schedules } 'Settings' { Load-SettingsPage } } }

# ================================================================== Dashboard
function Read-State {
  Status 'Lese Zustand des Sticks …'
  $disabled = (Shell 'pm list packages -d') -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() }
  $all = (Shell 'pm list packages') -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() }
  foreach ($f in $Features) { if ($f.Type -ne 'toggle') { continue }
    switch ($f.Id) {
      'launcher' { $on = ($all -contains 'com.spocky.projengmenu') -and ($all -contains 'com.wolf.minilm') }
      'anim' { $v = Shell 'settings get global window_animation_scale'; $on = ($v -match '^\d*\.?\d+$' -and [double]$v -lt 1) }
      'dns' { $on = ((Shell 'settings get global private_dns_mode') -eq 'hostname') }
      default { $present = @($f.Pkgs | Where-Object { $all -contains $_ }); $off = @($present | Where-Object { $disabled -contains $_ }); $on = ($present.Count -gt 0 -and $off.Count -ge [math]::Ceiling($present.Count / 2)) } }
    (UI "sw_$($f.Id)").IsChecked = $on; $script:Initial[$f.Id] = $on; Set-Badge $f.Id $on }
  $free = ((Shell 'df -h /data') -split "`n" | Select-Object -Last 1) -split '\s+'; if ($free.Count -ge 4) { Set-Badge 'cache' $true "$($free[3]) FREI" }
  Set-Badge 'reboot' $true 'VERBUNDEN'
  Read-Launchers; Check-ModStatus; (UI 'TxtDevName').Text = (Shell 'settings get global device_name'); Status 'Bereit.' }

function Set-Packages($pkgs, [bool]$disable) { foreach ($p in $pkgs) { $r = if ($disable) { Shell "pm disable-user --user 0 $p" } else { Shell "pm enable $p" }; $first = ($r -split "`n")[0]
    if ($first -match 'protected') { Log "  $p – systemgeschützt, übersprungen" } elseif ($first -match 'not found|Unknown package') { Log "  $p – nicht vorhanden" } else { Log "  $p – $(if($disable){'deaktiviert'}else{'aktiviert'})" } } }
function Do-Apply {
  (UI 'BtApply').IsEnabled = $false; (UI 'LogBox').Visibility = 'Visible'
  foreach ($f in $Features) { if ($f.Type -ne 'toggle') { continue }; $want = [bool](UI "sw_$($f.Id)").IsChecked; if ($want -eq $script:Initial[$f.Id]) { continue }
    Status "Wende an: $($f.Title) …"; Log "$($f.Title): $(if($want){'EIN'}else{'AUS'})"
    switch ($f.Id) {
      'anim' { $v = if ($want) { '0.5' } else { '1' }; foreach ($k in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') { Shell "settings put global $k $v" | Out-Null }; Log "  Animationen auf ${v}x" }
      'dns' { if ($want) { Apply-Dns } else { Shell 'settings put global private_dns_mode off' | Out-Null; Log '  Privater DNS aus' } }
      'launcher' { if ($want) { Do-Launcher } else { Do-LauncherRemove } }
      default { Set-Packages $f.Pkgs $want; if ($f.Id -eq 'ads') { Shell 'am force-stop com.amazon.tv.launcher' | Out-Null } } } }
  Log 'Fertig.'; Read-State; (UI 'BtApply').IsEnabled = $true }
function Do-Cache { Status 'Leere Cache …'; Log 'Cache leeren'; Log "  Vorher:  $((Shell 'df -h /data' -split "`n" | Select-Object -Last 1))"; Shell 'pm trim-caches 100G' | Out-Null; Log "  Nachher: $((Shell 'df -h /data' -split "`n" | Select-Object -Last 1))"; Read-State }
function Do-Reboot { Log 'Neustart …'; Run-Adb ((Dev) + @('reboot')) | Out-Null; $script:Connected = $false; (UI 'PanelMain').Visibility = 'Collapsed'; (UI 'PanelWizard').Visibility = 'Visible'; Show-Step 2; (UI 'WzStatus').Text = 'Der Stick startet neu. Nach ca. 1 Minute auf Verbinden klicken.' }

# ---- Launcher
function Install-Bundle($file, $tag) { $tmp = Join-Path $env:TEMP "ftvmod_$([guid]::NewGuid().ToString('N'))"; New-Item -ItemType Directory -Path $tmp | Out-Null
  $zip = Join-Path $tmp 'b.zip'; Copy-Item $file $zip; Expand-Archive $zip -DestinationPath $tmp -Force
  $all = @(Get-ChildItem $tmp -Filter *.apk); $drop = if ($script:Is64 -and ($all.Name -match 'arm64')) { 'armeabi|x86' } else { 'arm64|x86' }
  $parts = @($all | Where-Object { $_.Name -notmatch $drop } | ForEach-Object { $_.FullName })
  $r = Run-Adb ((Dev) + @('install-multiple', '-r', '-g') + $parts); Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue; Log "  $tag → $(($r -split "`n")[-1])"; return ($r -match 'Success') }
function Install-Apk($file, $tag) { $r = Run-Adb ((Dev) + @('install', '-r', '-g', $file)); Log "  $tag → $(($r -split "`n")[-1])"; return ($r -match 'Success') }
function Install-File($file, $tag) { if ($file -match '\.apkm$') { return (Install-Bundle $file $tag) } else { return (Install-Apk $file $tag) } }
function Do-Launcher {
  (UI 'LogBox').Visibility = 'Visible'; Status 'Installiere Launcher …'; Log 'Launcher-Installation'
  $all = (Shell 'pm list packages') -replace 'package:', ''
  $proj = Get-ChildItem $script:ApkDir -Include *.apk, *.apkm -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'projengmenu|projectivy' -and $_.Name -notmatch '^_' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $lm = Get-ChildItem $script:ApkDir -Include *.apk -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'minilm|mini' -and $_.Name -notmatch '^_|FOS5' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($proj) { Install-File $proj.FullName 'Projectivy' | Out-Null } elseif ($all -notmatch 'projengmenu') { Log '  Keine Projectivy-Datei im Ordner apk. 32-Bit-Sticks: Version 4.66 (arm64-v8a + armeabi-v7a, Android 6.0+) von APKMirror.' }
  if ($lm) { Install-Apk $lm.FullName 'Launcher Manager Mini' | Out-Null } elseif ($all -notmatch 'minilm') { Log '  Launcher Manager Mini fehlt. Am TV per Downloader-App Code 632067 installieren, oder APK in Ordner apk legen.' }
  Grant-LauncherPerms 'com.spocky.projengmenu'
  Shell 'pm disable-user --user 0 com.amazon.tv.forcedotaupdater.v2' | Out-Null
  Log '  Jetzt am TV: Launcher Manager Mini öffnen → Projectivy wählen → Home-Taste drücken.' }
function Grant-LauncherPerms($pkg) { foreach ($c in 'pm grant com.wolf.minilm android.permission.SYSTEM_ALERT_WINDOW', 'pm grant com.wolf.minilm android.permission.READ_LOGS', 'dumpsys deviceidle whitelist +com.wolf.minilm', "pm grant $pkg android.permission.SYSTEM_ALERT_WINDOW", "dumpsys deviceidle whitelist +$pkg") { Shell $c | Out-Null } }
function Do-LauncherRemove { Status 'Entferne Launcher …'; Log 'Launcher entfernen'
  foreach ($pkg in 'com.spocky.projengmenu', 'com.wolf.minilm') { $r = Run-Adb ((Dev) + @('uninstall', $pkg)); Log "  $pkg → $r" }
  Shell 'pm enable com.amazon.tv.launcher' | Out-Null; Shell 'am start -n com.amazon.tv.launcher/.ui.HomeActivity_vNext' | Out-Null; Log '  Amazon-Startbildschirm ist wieder aktiv.' }
function Read-Launchers {
  $cb = UI 'CbLauncher'; $cb.Items.Clear(); $script:Launchers = @()
  $q = Shell 'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null; pm query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null'
  $acts = @([regex]::Matches($q, '([a-zA-Z0-9_.]+)/([a-zA-Z0-9_.$]+)') | ForEach-Object { $_.Groups[0].Value } | Select-Object -Unique)
  # Fallback: alle Drittanbieter-Pakete auf HOME-Activity prüfen (falls query-activities nichts liefert oder ein Launcher fehlt)
  $third = @((Shell 'pm list packages -3') -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch 'overlay|minilm' })
  $known = @($acts | ForEach-Object { $_.Split('/')[0] })
  foreach ($pk in $third) { if ($known -contains $pk) { continue }
    $isL = ($pk -match 'launcher|projengmenu|flauncher|leanback|letihome|launchy') -or ($Apps | Where-Object { $_.Cat -eq 'launcher' -and $pk -match $_.PkgMatch }) -or ($script:LauncherNames.ContainsKey($pk))
    if (-not $isL) { $d = Shell "dumpsys package $pk | grep -c android.intent.category.HOME"; $isL = ($d -match '^[1-9]') }
    if ($isL) { $ra = Shell "cmd package resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN $pk 2>/dev/null | tail -1"
      $act = if ($ra -match '^[a-zA-Z0-9_.]+/[a-zA-Z0-9_.$]+$') { $ra.Trim() } else { "$pk/" }; $acts += $act } }
  foreach ($a in $acts) { $pkg = $a.Split('/')[0]; if ($pkg -eq 'com.wolf.minilm' -or $pkg -match 'oobe|setup') { continue }; if ($script:Launchers | Where-Object { $_.Pkg -eq $pkg }) { continue }
    $name = if ($script:LauncherNames.ContainsKey($pkg)) { $script:LauncherNames[$pkg] } else { $m = $Apps | Where-Object { $_.Cat -eq 'launcher' -and $pkg -match $_.PkgMatch } | Select-Object -First 1; if ($m) { $m.Name } else { $pkg } }
    $script:Launchers += [pscustomobject]@{ Pkg = $pkg; Activity = $a; Name = $name } }
  if (-not ($script:Launchers | Where-Object { $_.Pkg -eq 'com.amazon.tv.launcher' })) { $script:Launchers += [pscustomobject]@{ Pkg = 'com.amazon.tv.launcher'; Activity = 'com.amazon.tv.launcher/.ui.HomeActivity_vNext'; Name = 'Amazon Fire TV (Original)' } }
  $script:Launchers = @($script:Launchers | Sort-Object { $_.Pkg -ne 'com.amazon.tv.launcher' }, Name)
  foreach ($l in $script:Launchers) { $cb.Items.Add($l.Name) | Out-Null }
  $lmOn = ((Shell 'pm list packages -e') -match 'com.wolf.minilm')
  $pkgs = @($script:Launchers | ForEach-Object { $_.Pkg })
  $cur = if (-not $lmOn) { 'com.amazon.tv.launcher' } elseif ($pkgs -contains 'com.spocky.projengmenu') { 'com.spocky.projengmenu' } else { ($script:Launchers | Where-Object { $_.Pkg -ne 'com.amazon.tv.launcher' } | Select-Object -First 1).Pkg }
  $idx = [array]::IndexOf($pkgs, $cur); if ($idx -ge 0) { $cb.SelectedIndex = $idx } }
function Do-LauncherUninstall {
  $cb = UI 'CbLauncher'; if ($cb.SelectedIndex -lt 0) { return }; $l = $script:Launchers[$cb.SelectedIndex]
  if ($l.Pkg -eq 'com.amazon.tv.launcher') { Log 'Der Amazon-Startbildschirm ist Teil des Systems und kann nicht deinstalliert werden.'; return }
  if ([System.Windows.MessageBox]::Show("$($l.Name) vom Stick entfernen?", 'Launcher deinstallieren', 'YesNo', 'Warning') -ne 'Yes') { return }
  (UI 'LogBox').Visibility = 'Visible'; $r = Run-Adb ((Dev) + @('uninstall', $l.Pkg)); Log "Launcher entfernt: $($l.Name) → $r"
  $rest = @($script:Launchers | Where-Object { $_.Pkg -ne $l.Pkg -and $_.Pkg -ne 'com.amazon.tv.launcher' })
  if ($rest.Count -eq 0) { Shell 'pm disable-user --user 0 com.wolf.minilm' | Out-Null; Shell 'am start -n com.amazon.tv.launcher/.ui.HomeActivity_vNext' | Out-Null; Log '  Kein alternativer Launcher mehr – Amazon-Startbildschirm aktiv.' }
  else { if ($rest[0].Activity -match '/$') { Start-Package $rest[0].Pkg } else { Shell "am start -n $($rest[0].Activity)" | Out-Null }; Log "  Verbleibender Launcher gestartet: $($rest[0].Name) – ggf. in Launcher Manager Mini am TV auswählen." }
  Read-State }
function Do-LauncherSwitch {
  $cb = UI 'CbLauncher'; if ($cb.SelectedIndex -lt 0) { return }; $l = $script:Launchers[$cb.SelectedIndex]
  (UI 'LogBox').Visibility = 'Visible'; Log "Startbildschirm wechseln → $($l.Name)"
  if ($l.Pkg -eq 'com.amazon.tv.launcher') { Shell 'pm disable-user --user 0 com.wolf.minilm' | Out-Null; Shell "am start -n $($l.Activity)" | Out-Null; Log '  Launcher Manager Mini pausiert – Home-Taste führt wieder zu Amazon.' }
  else { if (-not ((Shell 'pm list packages') -match 'com.wolf.minilm')) { Log '  Launcher Manager Mini fehlt – zuerst Schalter »Werbefreier Startbildschirm« einschalten.'; return }
    Shell 'pm enable com.wolf.minilm' | Out-Null; Grant-LauncherPerms $l.Pkg; if ($l.Activity -match '/$') { Start-Package $l.Pkg } else { Shell "am start -n $($l.Activity)" | Out-Null }
    Log "  $($l.Name) gestartet. Falls die Home-Taste noch woanders landet: am TV Launcher Manager Mini öffnen und $($l.Name) auswählen." }
  Status "Startbildschirm: $($l.Name)" }

# ---- Live
$script:LiveBusy = $false
function Update-Live {
  if (-not $script:Connected -or $script:LiveBusy -or (UI 'PgDash').Visibility -ne 'Visible') { return }; $script:LiveBusy = $true
  try {
    $cmd = 'echo CPU; cat /proc/stat | head -1; echo MEM; cat /proc/meminfo | head -3; echo DISK; df /data | tail -1; echo TEMP; for z in /sys/class/thermal/thermal_zone*; do echo $(cat $z/type 2>/dev/null) $(cat $z/temp 2>/dev/null); done; dumpsys thermalservice 2>/dev/null | grep -m3 -o "mValue=[0-9.]*, mType=[0-9]*, mName=[^,]*"; echo WIFI; dumpsys wifi 2>/dev/null | grep -m1 -o "RSSI: *-[0-9]*"; echo UP; cat /proc/uptime; echo APP; dumpsys activity activities 2>/dev/null | grep -m1 -E "mResumedActivity|ResumedActivity:"'
    $out = Shell $cmd; if (-not $out) { (UI 'LiveDot').Fill = (Brush '#FF3B30'); return }; (UI 'LiveDot').Fill = (Brush '#34C759')
    $sec = @{}; $k = ''; foreach ($l in ($out -split "`n")) { $l = $l.Trim(); if ($l -in 'CPU', 'MEM', 'DISK', 'TEMP', 'WIFI', 'UP', 'APP') { $k = $l; $sec[$k] = @() } elseif ($k) { $sec[$k] += $l } }
    if ($sec.CPU) { $v = ($sec.CPU[0] -split '\s+')[1..7] | ForEach-Object { [double]$_ }; $idle = $v[3] + $v[4]; $total = ($v | Measure-Object -Sum).Sum
      if ($script:LastCpu) { $dt = $total - $script:LastCpu.Total; $di = $idle - $script:LastCpu.Idle; if ($dt -gt 0) { $pct = [math]::Round(100 * (1 - $di / $dt)); (UI 'LvCpu').Text = "$pct %"; (UI 'PbCpu').Value = $pct } }
      $script:LastCpu = @{ Total = $total; Idle = $idle } }
    if ($sec.MEM -and $sec.MEM.Count -ge 3) { $tot = [double](($sec.MEM[0] -split '\s+')[1]); $avail = [double](($sec.MEM[2] -split '\s+')[1]); $used = $tot - $avail; (UI 'LvRam').Text = "{0:N1} / {1:N1} GB" -f ($used / 1MB), ($tot / 1MB); (UI 'PbRam').Value = [math]::Round(100 * $used / $tot) }
    if ($sec.DISK) { $d = $sec.DISK[0] -split '\s+'; if ($d.Count -ge 4) { $tot = [double]$d[1]; $usd = [double]$d[2]; (UI 'LvDisk').Text = "{0:N1} GB frei" -f (($tot - $usd) / 1MB); (UI 'PbDisk').Value = [math]::Round(100 * $usd / $tot) } }
    if ($sec.TEMP) { $cands = @(); foreach ($l in $sec.TEMP) { if ($l -match '^(\S+)\s+(-?\d+)$') { $cands += [pscustomobject]@{ Name = $matches[1]; Val = [double]$matches[2] } } elseif ($l -match 'mValue=([\d.]+), mType=\d+, mName=(.+)$') { $cands += [pscustomobject]@{ Name = $matches[2]; Val = [double]$matches[1] } } }
      $cands = @($cands | ForEach-Object { if ($_.Val -gt 1000) { $_.Val = $_.Val / 1000 }; $_ } | Where-Object { $_.Val -gt 5 -and $_.Val -lt 150 })
      $pick = $cands | Where-Object { $_.Name -match 'cpu|soc|tsens|ap|mtk' } | Select-Object -First 1; if (-not $pick) { $pick = $cands | Sort-Object Val -Descending | Select-Object -First 1 }
      if ($pick) { (UI 'LvTemp').Text = "{0:N0} °C" -f $pick.Val; (UI 'PbTemp').Value = [math]::Min(100, $pick.Val) } }
    if ($sec.WIFI -and $sec.WIFI[0] -match '(-\d+)') { $r = [int]$matches[1]; (UI 'LvWifi').Text = "$r dBm"; (UI 'PbWifi').Value = [math]::Max(0, [math]::Min(100, 2 * ($r + 100))) }
    if ($sec.UP -and $sec.UP[0] -match '^([\d.]+)') { $ts = [TimeSpan]::FromSeconds([double]$matches[1]); (UI 'LiveUptime').Text = "Laufzeit {0}d {1:D2}:{2:D2}" -f $ts.Days, $ts.Hours, $ts.Minutes }
    if ($sec.APP -and $sec.APP[0] -match '([a-zA-Z0-9_.]+)/') { (UI 'LiveApp').Text = "Aktive App: $($matches[1])" }
  } catch {} finally { $script:LiveBusy = $false } }
$script:LiveTimer = New-Object System.Windows.Threading.DispatcherTimer; $script:LiveTimer.Interval = [TimeSpan]::FromSeconds(3); $script:LiveTimer.Add_Tick({ Update-Live }); $script:LiveTimer.Start()

# ================================================================== Apps
function Pick-Asset($names, $prefer) {
  $names = @($names | Where-Object { $_ -match '\.apk$' -and $_ -notmatch 'x86' }); if ($prefer) { $p = @($names | Where-Object { $_ -match $prefer }); if ($p.Count -gt 0) { $names = $p } }
  $want = if ($script:Is64) { 'arm64' } else { 'armeabi|armv7|arm-v7|arm7' }; $other = if ($script:Is64) { 'armeabi|armv7|arm-v7|arm7' } else { 'arm64' }
  $a = $names | Where-Object { $_ -match $want } | Select-Object -First 1; if (-not $a) { $a = $names | Where-Object { $_ -notmatch $other } | Select-Object -First 1 }; return $a }
function Resolve-AppUrl($a) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $abi = if ($script:Is64) { 'arm64-v8a' } else { 'armeabi-v7a' }; $arch = if ($script:Is64) { 'arm64-v8a' } else { 'arm' }
  switch ($a.Src) {
    'github' { $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($a.Repo)/releases/latest" -Headers @{ 'User-Agent' = 'FireTVMod' }
      $pick = Pick-Asset ($rel.assets | ForEach-Object { $_.name }) $a.Prefer; if ($pick) { $hit = $rel.assets | Where-Object { $_.name -eq $pick } | Select-Object -First 1; return @{ Url = $hit.browser_download_url; File = $hit.name } } }
    'gitlab' { $rels = @(); foreach ($pr in ($a.Project -split ';')) { try { $rels = @(Invoke-RestMethod -Uri "https://gitlab.com/api/v4/projects/$([uri]::EscapeDataString($pr))/releases" -Headers @{ 'User-Agent' = 'FireTVMod' }); if ($rels.Count -gt 0) { break } } catch {} }
      foreach ($r in $rels) { $links = @($r.assets.links | Where-Object { $_.url -match '\.apk$' }); if ($links.Count -gt 0) { $pick = Pick-Asset ($links | ForEach-Object { $_.url }) $a.Prefer; if ($pick) { return @{ Url = $pick; File = ($pick -split '/')[-1] } } } } }
    'listing' { $url = $a.Url.Replace('{arch}', $arch); $rx = $a.Match.Replace('{abi}', $abi); $html = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
      $names = [regex]::Matches($html, $rx) | ForEach-Object { $_.Value } | Select-Object -Unique
      $best = $names | Sort-Object { [version](([regex]::Match($_, '\d+(\.\d+)+')).Value) } -Descending | Select-Object -First 1; if ($best) { return @{ Url = ($url.TrimEnd('/') + '/' + $best); File = $best } } }
    'direct' { $u = if ($script:Is64) { $a.Url64 } else { $a.Url32 }; return @{ Url = $u; File = "$($a.Id)_$(if($script:Is64){'64'}else{'32'}).apk" } }
    'manual' { $f = Get-ChildItem $script:ApkDir, $script:SideloadDir -Include *.apk, *.apkm -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $a.FileMatch -and $_.Name -notmatch '^_' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if ($f) { return @{ Url = $null; File = $f.FullName; Local = $true } } } }
  return $null }
function Update-AppState { if (-not $script:Connected) { return }; $all = (Shell 'pm list packages') -replace 'package:', ''
  foreach ($a in $Apps) { $inst = [bool]($all -match $a.PkgMatch); if ($inst) { Set-Badge $a.Id $true 'INSTALLIERT' } elseif ($a.Src -eq 'manual') { Set-Badge $a.Id $false '' 'MANUELL' } else { Set-Badge $a.Id $false '' 'NICHT INSTALLIERT' }; (UI "ck_$($a.Id)").IsChecked = $false } }
function Do-AppsInstall {
  $sel = @($Apps | Where-Object { (UI "ck_$($_.Id)").IsChecked }); if ($sel.Count -eq 0) { (UI 'AppStatus').Text = 'Nichts ausgewählt.'; return }
  (UI 'BtAppsInstall').IsEnabled = $false; (UI 'LogBox').Visibility = 'Visible'
  foreach ($a in $sel) { try {
      (UI 'AppStatus').Text = "$($a.Name): suche aktuelle Version …"; Refresh-UI; Log "$($a.Name): suche Download"
      $r = Resolve-AppUrl $a
      if (-not $r) { if ($a.Src -eq 'manual') { Log '  keine Datei gefunden – APK manuell in Ordner »apk« legen (siehe Quelle)' } else { Log "  keine passende Datei für diesen Stick gefunden ($(if($script:Is64){'64-Bit'}else{'32-Bit'}))" }; continue }
      if ($r.Local) { $dest = $r.File } else { $dest = Join-Path $script:SideloadDir $r.File; if (-not (Test-Path $dest)) { (UI 'AppStatus').Text = "$($a.Name): lade $($r.File) …"; Refresh-UI; Log "  lade $($r.Url)"; Invoke-WebRequest -Uri $r.Url -OutFile $dest -UseBasicParsing } else { Log "  bereits vorhanden: $($r.File)" } }
      (UI 'AppStatus').Text = "$($a.Name): installiere …"; Refresh-UI; Install-File $dest $a.Name | Out-Null
      if ($a.Cat -eq 'launcher') { Log '  Tipp: Im Dashboard unter »Startbildschirm« aktivieren.' }
      if ($a.Id -eq 'buttonmapper') { Shell 'settings put secure enabled_accessibility_services flar2.homebutton/flar2.homebutton.AccessibilityService' | Out-Null; Shell 'settings put secure accessibility_enabled 1' | Out-Null; Log '  Bedienungshilfe für Button Mapper aktiviert.' }
    } catch { Log "  Fehler: $($_.Exception.Message)" } }
  (UI 'AppStatus').Text = 'Fertig.'; Update-AppState; (UI 'BtAppsInstall').IsEnabled = $true }

# ---- Installierte Apps
function Load-AppList { $lb = UI 'LbApps'; $lb.Items.Clear(); $flag = if ((UI 'CkShowSystem').IsChecked) { '' } else { '-3' }
  $pk = @((Shell "pm list packages $flag") -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
  $dis = (Shell 'pm list packages -d') -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() }
  foreach ($p in $pk) { $label = $p; $m = $Apps | Where-Object { $p -match $_.PkgMatch } | Select-Object -First 1; if ($m) { $label = "$p   [$($m.Name)$(if($m.Cat -eq 'launcher'){' · Launcher'})]" } elseif ($script:LauncherNames.ContainsKey($p)) { $label = "$p   [$($script:LauncherNames[$p]) · Launcher]" }
    if ($dis -contains $p) { $label += '   (ausgeblendet)' }
    $i = New-Object System.Windows.Controls.ListBoxItem; $i.Content = $label; $i.Tag = $p; $lb.Items.Add($i) | Out-Null }; Log "App-Liste: $($pk.Count) Pakete" }
function Sel-App { $i = (UI 'LbApps').SelectedItem; if ($i) { return $i.Tag }; Log 'Bitte zuerst eine App auswählen.'; return $null }
function App-Start { $p = Sel-App; if (-not $p) { return }; $r = Shell "monkey -p $p -c android.intent.category.LAUNCHER 1"; if ($r -match 'No activities') { $r = Shell "monkey -p $p -c android.intent.category.LEANBACK_LAUNCHER 1" }; Log "Starte $p" }
function App-Stop { $p = Sel-App; if (-not $p) { return }; Shell "am force-stop $p" | Out-Null; Log "Gestoppt: $p" }
function App-Clear { $p = Sel-App; if (-not $p) { return }; if ([System.Windows.MessageBox]::Show("Alle Daten und Logins von $p löschen?", 'Daten löschen', 'YesNo', 'Warning') -ne 'Yes') { return }; Log "Daten gelöscht: $p → $(Shell "pm clear $p")" }
function App-Backup($p) { if (-not $p) { $p = Sel-App }; if (-not $p) { return }; $paths = @((Shell "pm path $p") -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $dir = Join-Path $script:BackupDir $p; New-Item -ItemType Directory -Force -Path $dir | Out-Null
  foreach ($x in $paths) { Run-Adb ((Dev) + @('pull', $x, $dir)) | Out-Null }; Log "Gesichert: $p ($($paths.Count) Datei(en)) → backups\$p" }
function App-Uninstall { $p = Sel-App; if (-not $p) { return }; if ([System.Windows.MessageBox]::Show("$p wirklich deinstallieren?", 'Deinstallieren', 'YesNo', 'Warning') -ne 'Yes') { return }
  $r = Run-Adb ((Dev) + @('uninstall', $p)); if ($r -notmatch 'Success') { $r = Shell "pm uninstall -k --user 0 $p" }; Log "Deinstallieren $p → $r"; Load-AppList }

# ---- App-Updates, URL-Install, Berechtigungen, laufende Apps
function Installed-Version($pkgMatch) { $all = (Shell 'pm list packages') -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() }; $pkg = $all | Where-Object { $_ -match $pkgMatch } | Select-Object -First 1; if (-not $pkg) { return $null }
  $v = ([regex]::Match((Shell "dumpsys package $pkg | grep -m1 versionName"), 'versionName=([\d.]+)')).Groups[1].Value; return $v }
function Remote-Version($a) { try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    switch ($a.Src) {
      'github' { $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$($a.Repo)/releases/latest" -Headers @{ 'User-Agent' = 'FireTVMod' }; return ([regex]::Match($rel.tag_name, '\d+(\.\d+)+')).Value }
      'listing' { $r = Resolve-AppUrl $a; if ($r) { return ([regex]::Match($r.File, '\d+(\.\d+)+')).Value } }
      'gitlab' { $r = Resolve-AppUrl $a; if ($r) { return ([regex]::Match($r.File, '\d+(\.\d+)+')).Value } } } } catch {}; return $null }
function Check-AppUpdates { (UI 'BtAppsUpdates').IsEnabled = $false; $n = 0
  foreach ($a in $Apps) { if ($a.Src -notin 'github', 'listing', 'gitlab') { continue }; $iv = Installed-Version $a.PkgMatch; if (-not $iv) { continue }
    (UI 'AppStatus').Text = "Prüfe $($a.Name) …"; Refresh-UI; $rv = Remote-Version $a; if (-not $rv) { continue }
    try { if ([version]$rv -gt [version]$iv) { Set-Badge $a.Id $true "UPDATE $iv → $rv"; $b = UI "bd_$($a.Id)"; $b.Background = (Brush '#FFE8CC'); (UI "bt_txt_$($a.Id)").Foreground = (Brush '#C25E00'); (UI "ck_$($a.Id)").IsChecked = $true; $n++; Log "$($a.Name): Update $iv → $rv" } else { Set-Badge $a.Id $true "AKTUELL $iv" } } catch {} }
  (UI 'AppStatus').Text = if ($n -gt 0) { "$n Update(s) verfügbar – bereits angekreuzt, »Ausgewählte installieren« klicken." } else { 'Alle installierten Katalog-Apps sind aktuell.' }; (UI 'BtAppsUpdates').IsEnabled = $true }
function Install-FromUrl { $u = (UI 'TxtApkUrl').Text.Trim(); if ($u -notmatch '^https?://') { (UI 'AppStatus').Text = 'Bitte einen http(s)-Link angeben.'; return }
  try { $name = ($u -split '/')[-1] -replace '[^\w.\-]', '_'; if ($name -notmatch '\.apkm?$') { $name += '.apk' }; $dest = Join-Path $script:SideloadDir $name
    (UI 'AppStatus').Text = "Lade $name …"; Refresh-UI; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $u -OutFile $dest -UseBasicParsing
    (UI 'LogBox').Visibility = 'Visible'; Install-File $dest $name | Out-Null; (UI 'AppStatus').Text = 'Fertig.'; Update-AppState } catch { (UI 'AppStatus').Text = "Fehler: $($_.Exception.Message)" } }
function Load-Perms($pkg) { $script:PermPkg = $pkg; (UI 'PermApp').Text = "App: $pkg"; $lb = UI 'LbPerms'; $lb.Items.Clear()
  $out = Shell "dumpsys package $pkg"; $sect = ''; foreach ($l in ($out -split "`n")) { $t = $l.Trim()
    if ($t -match '^(requested|install|runtime) permissions:') { $sect = $matches[1]; continue }; if ($t -match '^[A-Za-z ]+:$') { $sect = ''; continue }
    if ($sect -and $t -match '^([a-zA-Z0-9_.]+)(: granted=(true|false))?') { $perm = $matches[1]; $g = $matches[3]; if ($sect -eq 'requested' -and ($lb.Items | Where-Object { $_.Tag.Perm -eq $perm })) { continue }
      $i = New-Object System.Windows.Controls.ListBoxItem; $i.Content = ('{0,-9} {1}' -f ($(if ($g -eq 'true') { 'ERLAUBT' } elseif ($g -eq 'false') { 'VERWEIGERT' } else { '' })), $perm); $i.Tag = @{ Perm = $perm; Granted = ($g -eq 'true') }; $lb.Items.Add($i) | Out-Null } } }
function Toggle-Perm { $i = (UI 'LbPerms').SelectedItem; if (-not $i -or -not $script:PermPkg) { return }; $perm = $i.Tag.Perm
  $r = if ($i.Tag.Granted) { Shell "pm revoke $($script:PermPkg) $perm" } else { Shell "pm grant $($script:PermPkg) $perm" }
  Log "$(if($i.Tag.Granted){'Entzogen'}else{'Gewährt'}): $perm → $(if($r){$r}else{'OK'})"; Load-Perms $script:PermPkg }
function Load-Running { $lb = UI 'LbRunning'; $lb.Items.Clear(); $procs = Get-Processes; $n = 0
  foreach ($p in $procs) { $i = New-Object System.Windows.Controls.ListBoxItem; $i.Content = ('{0,8:N1} MB   {1}' -f $p.MB, $p.Pkg); $i.Tag = $p.Pkg; $lb.Items.Add($i) | Out-Null; $n++ }
  (UI 'RunStatus').Text = "$n Prozesse (nach RAM sortiert)" }
# ---- Prozess-Aufzeichnung
$script:RecSamples = @{}; $script:RecCount = 0; $script:RecFile = ''
function Get-Processes { $out = Shell 'dumpsys meminfo 2>/dev/null | grep -A 60 "Total PSS by process" | grep -E "^\s+[0-9,]+K: "'; $list = @()
  foreach ($l in ($out -split "`n")) { if ($l -match '([\d,]+)K:\s+([a-zA-Z0-9_.:]+)\s+\(pid\s+(\d+)') { $pkg = ($matches[2] -split ':')[0]; if ($pkg -match '^(system|com\.android\.systemui|surfaceflinger|zygote|android|webview_zygote|kernel)') { continue }; $list += [pscustomobject]@{ Pkg = $pkg; MB = [math]::Round(([double]($matches[1] -replace ',', '')) / 1024, 1) } } }
  return $list }
function Rec-Tick { if (-not $script:Connected) { return }; $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'; $procs = Get-Processes; $script:RecCount++
  $fg = ''; $a = Shell 'dumpsys activity activities 2>/dev/null | grep -m1 -E "mResumedActivity|ResumedActivity:"'; if ($a -match '([a-zA-Z0-9_.]+)/') { $fg = $matches[1] }
  $lines = @(); foreach ($p in $procs) { $bg = if ($p.Pkg -eq $fg) { 'vordergrund' } else { 'hintergrund' }; $lines += "$now;$($p.Pkg);$($p.MB);$bg"
    if (-not $script:RecSamples.ContainsKey($p.Pkg)) { $script:RecSamples[$p.Pkg] = @{ Seen = 0; Bg = 0; MaxMB = 0; First = $now } }
    $e = $script:RecSamples[$p.Pkg]; $e.Seen++; if ($bg -eq 'hintergrund') { $e.Bg++ }; if ($p.MB -gt $e.MaxMB) { $e.MaxMB = $p.MB } }
  Add-Content $script:RecFile ($lines -join "`r`n") -Encoding UTF8
  (UI 'RunStatus').Text = "Aufzeichnung läuft · $($script:RecCount) Messungen · $($script:RecSamples.Count) Prozesse gesehen · $(Get-Date -Format HH:mm:ss)" }
function Rec-Start { $script:RecSamples = @{}; $script:RecCount = 0; $script:RecFile = Join-Path $script:BackupDir "prozesse_$(Get-Date -Format yyyyMMdd_HHmmss).csv"; Set-Content $script:RecFile 'zeit;paket;ram_mb;zustand' -Encoding UTF8
  $script:RecTimer2 = New-Object System.Windows.Threading.DispatcherTimer; $script:RecTimer2.Interval = [TimeSpan]::FromSeconds(10); $script:RecTimer2.Add_Tick({ Rec-Tick }); $script:RecTimer2.Start(); Rec-Tick
  (UI 'BtRecStart').IsEnabled = $false; (UI 'BtRecStop').IsEnabled = $true; Log "Prozess-Aufzeichnung gestartet (alle 10 s) → $(Split-Path $script:RecFile -Leaf)" }
function Rec-Stop { if ($script:RecTimer2) { $script:RecTimer2.Stop() }; (UI 'BtRecStart').IsEnabled = $true; (UI 'BtRecStop').IsEnabled = $false
  $lb = UI 'LbRunning'; $lb.Items.Clear(); $n = [math]::Max(1, $script:RecCount)
  $h = New-Object System.Windows.Controls.ListBoxItem; $h.Content = ('{0,-46} {1,7} {2,9} {3,8}   {4}' -f 'PROZESS', 'AKTIV%', 'HINTERGR%', 'MAX MB', 'ERSTMALS'); $h.IsEnabled = $false; $lb.Items.Add($h) | Out-Null
  foreach ($k in ($script:RecSamples.Keys | Sort-Object { $script:RecSamples[$_].Bg } -Descending)) { $e = $script:RecSamples[$k]; $i = New-Object System.Windows.Controls.ListBoxItem
    $i.Content = ('{0,-46} {1,6:N0}% {2,8:N0}% {3,8:N1}   {4}' -f $k, (100 * $e.Seen / $n), (100 * $e.Bg / $n), $e.MaxMB, $e.First.Substring(11)); $i.Tag = $k; $lb.Items.Add($i) | Out-Null }
  $top = @($script:RecSamples.Keys | Where-Object { $script:RecSamples[$_].Bg -ge $n * 0.5 -and $_ -notmatch '^com\.amazon\.tv\.launcher$|projengmenu|minilm' } | Sort-Object { $script:RecSamples[$_].MaxMB } -Descending | Select-Object -First 5)
  (UI 'RunStatus').Text = "Auswertung: $($script:RecCount) Messungen, $($script:RecSamples.Count) Prozesse. Dauerhaft im Hintergrund: $($top -join ', ')"
  Log "Prozess-Aufzeichnung beendet. Dauerläufer im Hintergrund: $($top -join ', ') – CSV: $(Split-Path $script:RecFile -Leaf)" }
function App-DataBackup { $p = Sel-App; if (-not $p) { return }; $file = Join-Path $script:BackupDir "$p.ab"; Log "App-Daten-Backup $p → am TV bestätigen (»Meine Daten sichern«) …"; (UI 'LogBox').Visibility = 'Visible'
  $r = Run-Adb ((Dev) + @('backup', '-f', $file, '-noapk', $p)); if ((Test-Path $file) -and (Get-Item $file).Length -gt 100) { Log "  gespeichert: backups\$p.ab (Wiederherstellen: adb restore)" } else { Log "  nicht möglich – Fire OS erlaubt adb backup für diese App nicht ($r)" } }
function App-Hide { $p = Sel-App; if (-not $p) { return }; $dis = (Shell 'pm list packages -d') -match [regex]::Escape($p); $r = if ($dis) { Shell "pm enable $p" } else { Shell "pm disable-user --user 0 $p" }; Log "$p → $r"; Load-AppList }

# ================================================================== Fernbedienung
function Send-Text { $t = (UI 'TxtSend').Text; if (-not $t) { return }
  $esc = $t -replace '([\\()<>|;&*~"''`$])', '\$1' -replace ' ', '%s'; Shell "input text `"$esc`"" | Out-Null; Log "Text gesendet: $t"; (UI 'TxtSend').Text = '' }
function Take-Shot { (UI 'ShotStatus').Text = 'Erstelle Screenshot …'; Refresh-UI
  $name = "shot_$(Get-Date -Format yyyyMMdd_HHmmss).png"; $local = Join-Path $script:ShotDir $name
  try {
    # Variante 1: Binärstrom direkt vom Stick (exec-out)
    $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName = $script:ADB; $psi.Arguments = "-s $($script:IP):5555 exec-out screencap -p"
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $pr = [System.Diagnostics.Process]::Start($psi); $fs = [System.IO.File]::Create($local); $pr.StandardOutput.BaseStream.CopyTo($fs); $fs.Close(); $err = $pr.StandardError.ReadToEnd(); $pr.WaitForExit()
    $ok = (Test-Path $local) -and ((Get-Item $local).Length -gt 1000)
    if (-not $ok) {
      # Variante 2: auf dem Stick speichern und holen
      Log "  exec-out lieferte nichts ($err) – versuche Umweg über /sdcard"
      $r1 = Shell 'screencap -p /sdcard/ftvmod_shot.png'; $r2 = Run-Adb ((Dev) + @('pull', '/sdcard/ftvmod_shot.png', $local)); Shell 'rm -f /sdcard/ftvmod_shot.png' | Out-Null
      $ok = (Test-Path $local) -and ((Get-Item $local).Length -gt 1000); if (-not $ok) { throw "screencap: $r1 | pull: $r2" } }
    $bytes = [System.IO.File]::ReadAllBytes($local); $ms = New-Object System.IO.MemoryStream(,$bytes)
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage; $bi.BeginInit(); $bi.CacheOption = 'OnLoad'; $bi.StreamSource = $ms; $bi.EndInit(); $bi.Freeze(); (UI 'ImgShot').Source = $bi
    (UI 'ShotStatus').Text = "Gespeichert: screenshots\$name"; Log "Screenshot: $name"
  } catch { (UI 'ShotStatus').Text = 'Screenshot fehlgeschlagen – Details im Protokoll.'; Log "Screenshot-Fehler: $($_.Exception.Message)"; (UI 'LogBox').Visibility = 'Visible'; if (Test-Path $local) { Remove-Item $local -ErrorAction SilentlyContinue } } }
function Start-Rec { $btn = UI 'BtRec'; $btn.IsEnabled = $false; (UI 'ShotStatus').Text = 'Aufnahme läuft (15 s) …'; Refresh-UI
  $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName = $script:ADB; $psi.Arguments = "-s $($script:IP):5555 shell screenrecord --time-limit 15 /sdcard/ftvmod_rec.mp4"; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $script:RecProc = [System.Diagnostics.Process]::Start($psi)
  $t = New-Object System.Windows.Threading.DispatcherTimer; $t.Interval = [TimeSpan]::FromSeconds(1); $script:RecTimer = $t; $script:RecStart = Get-Date
  $t.Add_Tick({ $el = [int]((Get-Date) - $script:RecStart).TotalSeconds; (UI 'ShotStatus').Text = "Aufnahme läuft … $el s"
      if ($script:RecProc.HasExited -or $el -gt 20) { $script:RecTimer.Stop(); $name = "rec_$(Get-Date -Format yyyyMMdd_HHmmss).mp4"; $local = Join-Path $script:ShotDir $name
        Run-Adb ((Dev) + @('pull', '/sdcard/ftvmod_rec.mp4', $local)) | Out-Null; Shell 'rm /sdcard/ftvmod_rec.mp4' | Out-Null
        (UI 'ShotStatus').Text = if (Test-Path $local) { "Video: screenshots\$name" } else { 'Aufnahme fehlgeschlagen (Stick unterstützt screenrecord evtl. nicht).' }; Log (UI 'ShotStatus').Text; (UI 'BtRec').IsEnabled = $true } })
  $t.Start() }

# ================================================================== Dateien
$Folders = @('/sdcard/Download', '/sdcard/Movies', '/sdcard/Music', '/sdcard/Pictures', '/sdcard/DCIM', '/sdcard')
function Cur-Folder { $cb = UI 'CbFolder'; if ($cb.SelectedIndex -ge 0) { return $Folders[$cb.SelectedIndex] }; return $Folders[0] }
function Load-Files { if (-not $script:Connected) { return }; $lb = UI 'LbFiles'; $lb.Items.Clear(); $dir = Cur-Folder
  $out = Shell "ls -la `"$dir`" 2>/dev/null"; $n = 0
  foreach ($l in ($out -split "`n")) { if ($l -match '^([-dl])\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\S+\s+\S+)\s+(.+)$') { $isDir = $matches[1] -eq 'd'; $size = [long]$matches[2]; $name = $matches[4].Trim(); if ($name -in '.', '..') { continue }
      $sz = if ($isDir) { '<DIR>' } elseif ($size -gt 1GB) { '{0:N1} GB' -f ($size / 1GB) } elseif ($size -gt 1MB) { '{0:N1} MB' -f ($size / 1MB) } else { '{0:N0} KB' -f ($size / 1KB) }
      $i = New-Object System.Windows.Controls.ListBoxItem; $i.Content = ('{0,-10} {1,-18} {2}' -f $sz, $matches[3], $name); $i.Tag = @{ Name = $name; Dir = $isDir }; $lb.Items.Add($i) | Out-Null; $n++ } }
  (UI 'FileStatus').Text = "$n Einträge in $dir" }
function Upload-Files { $dlg = New-Object System.Windows.Forms.OpenFileDialog; $dlg.Multiselect = $true; $dlg.Title = 'Dateien auf den Stick kopieren'
  if ($dlg.ShowDialog() -ne 'OK') { return }; $dir = Cur-Folder
  foreach ($f in $dlg.FileNames) { (UI 'FileStatus').Text = "Kopiere $(Split-Path $f -Leaf) …"; Refresh-UI; $r = Run-Adb ((Dev) + @('push', $f, "$dir/")); Log "Hochgeladen: $(Split-Path $f -Leaf) → $dir ($(($r -split "`n")[-1]))" }; Load-Files }
function Download-Files { $sel = @((UI 'LbFiles').SelectedItems); if ($sel.Count -eq 0) { (UI 'FileStatus').Text = 'Bitte Dateien auswählen.'; return }; $dir = Cur-Folder
  foreach ($i in $sel) { $n = $i.Tag.Name; (UI 'FileStatus').Text = "Lade $n …"; Refresh-UI; $r = Run-Adb ((Dev) + @('pull', "$dir/$n", $script:DlDir)); Log "Heruntergeladen: $n → downloads ($(($r -split "`n")[-1]))" }; (UI 'FileStatus').Text = 'Fertig – Ordner »downloads«.' }
function Delete-Files { $sel = @((UI 'LbFiles').SelectedItems); if ($sel.Count -eq 0) { return }; if ([System.Windows.MessageBox]::Show("$($sel.Count) Eintrag/Einträge auf dem Stick endgültig löschen?", 'Löschen', 'YesNo', 'Warning') -ne 'Yes') { return }
  $dir = Cur-Folder; foreach ($i in $sel) { $n = $i.Tag.Name; Shell "rm -rf `"$dir/$n`"" | Out-Null; Log "Gelöscht: $dir/$n" }; Load-Files }

# ================================================================== System
$ResOptions = @(@{ N='Auto (Werkseinstellung)'; V='reset' }, @{ N='3840 × 2160 (4K)'; V='3840x2160' }, @{ N='1920 × 1080'; V='1920x1080' }, @{ N='1280 × 720'; V='1280x720' })
$DpiOptions = @(@{ N='Auto (Werkseinstellung)'; V='reset' }, @{ N='Kleiner (240)'; V='240' }, @{ N='Etwas kleiner (280)'; V='280' }, @{ N='Standard (320)'; V='320' }, @{ N='Grösser (360)'; V='360' }, @{ N='Viel grösser (400)'; V='400' })
$SleepOptions = @(@{ N='5 Minuten'; V=300000 }, @{ N='10 Minuten'; V=600000 }, @{ N='20 Minuten'; V=1200000 }, @{ N='30 Minuten'; V=1800000 }, @{ N='1 Stunde'; V=3600000 }, @{ N='2 Stunden'; V=7200000 }, @{ N='Nie'; V=2147483647 })
function Load-SystemState { if (-not $script:Connected) { return }; Load-BgState
  (UI 'DispStatus').Text = "Aktuell: $((Shell 'wm size') -replace 'Physical size: ','') · $((Shell 'wm density') -replace 'Physical density: ','') dpi"
  $to = Shell 'settings get system screen_off_timeout'; $idx = -1; for ($i = 0; $i -lt $SleepOptions.Count; $i++) { if ("$($SleepOptions[$i].V)" -eq $to) { $idx = $i } }; if ($idx -ge 0) { (UI 'CbSleep').SelectedIndex = $idx } }
function Apply-Display { $r = $ResOptions[[math]::Max(0, (UI 'CbRes').SelectedIndex)].V; $d = $DpiOptions[[math]::Max(0, (UI 'CbDpi').SelectedIndex)].V
  Shell "wm size $r" | Out-Null; Shell "wm density $d" | Out-Null; Log "Anzeige: Auflösung $r, DPI $d"; Load-SystemState }
function Reset-Display { Shell 'wm size reset' | Out-Null; Shell 'wm density reset' | Out-Null; Log 'Anzeige zurückgesetzt'; (UI 'CbRes').SelectedIndex = 0; (UI 'CbDpi').SelectedIndex = 0; Load-SystemState }
function Apply-Sleep { $i = (UI 'CbSleep').SelectedIndex; if ($i -lt 0) { return }; Shell "settings put system screen_off_timeout $($SleepOptions[$i].V)" | Out-Null; Log "Ruhezustand nach: $($SleepOptions[$i].N)" }
function Export-Profile {
  $disabled = @((Shell 'pm list packages -d') -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $third = @((Shell 'pm list packages -3') -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  $prof = [ordered]@{ Erstellt = (Get-Date).ToString('s'); Modell = $script:Model; Deaktiviert = $disabled; Apps = $third
    Animation = (Shell 'settings get global window_animation_scale'); DnsMode = (Shell 'settings get global private_dns_mode'); DnsHost = (Shell 'settings get global private_dns_specifier'); Ruhezustand = (Shell 'settings get system screen_off_timeout') }
  $file = Join-Path $script:BackupDir "profil_$($script:Model -replace '[^\w]','')_$(Get-Date -Format yyyyMMdd_HHmm).json"; $prof | ConvertTo-Json -Depth 4 | Set-Content $file -Encoding UTF8
  (UI 'ProfStatus').Text = "Gespeichert: $(Split-Path $file -Leaf)"; Log "Profil exportiert → $file" }
function Import-Profile { $dlg = New-Object System.Windows.Forms.OpenFileDialog; $dlg.Filter = 'Profil (*.json)|*.json'; $dlg.InitialDirectory = $script:BackupDir; if ($dlg.ShowDialog() -ne 'OK') { return }
  $p = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json; (UI 'LogBox').Visibility = 'Visible'; Log "Profil importieren: $(Split-Path $dlg.FileName -Leaf) (von $($p.Modell))"
  Set-Packages @($p.Deaktiviert) $true
  if ($p.Animation) { foreach ($k in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') { Shell "settings put global $k $($p.Animation)" | Out-Null } }
  if ($p.DnsMode -eq 'hostname' -and $p.DnsHost) { Shell 'settings put global private_dns_mode hostname' | Out-Null; Shell "settings put global private_dns_specifier $($p.DnsHost)" | Out-Null }
  if ($p.Ruhezustand) { Shell "settings put system screen_off_timeout $($p.Ruhezustand)" | Out-Null }
  $installed = Shell 'pm list packages'; $missing = @($p.Apps | Where-Object { -not ($installed -match [regex]::Escape($_)) }); if ($missing.Count -gt 0) { Log "  Nicht installierte Apps aus dem Profil: $($missing -join ', ') – mit »Aus backups installieren« oder Katalog nachholen." }
  (UI 'ProfStatus').Text = 'Profil angewendet.'; Log 'Profil angewendet.'; Read-State }
function Backup-All { $third = @((Shell 'pm list packages -3') -replace 'package:', '' -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch 'overlay' }); (UI 'LogBox').Visibility = 'Visible'
  foreach ($p in $third) { (UI 'BkStatus').Text = "Sichere $p …"; Refresh-UI; App-Backup $p }; (UI 'BkStatus').Text = "$($third.Count) Apps gesichert → backups" }
function Restore-All { (UI 'LogBox').Visibility = 'Visible'; $dirs = Get-ChildItem $script:BackupDir -Directory; foreach ($d in $dirs) { $apks = @(Get-ChildItem $d.FullName -Filter *.apk | ForEach-Object { $_.FullName }); if ($apks.Count -eq 0) { continue }
    (UI 'BkStatus').Text = "Installiere $($d.Name) …"; Refresh-UI; $r = if ($apks.Count -gt 1) { Run-Adb ((Dev) + @('install-multiple', '-r', '-g') + $apks) } else { Run-Adb ((Dev) + @('install', '-r', '-g', $apks[0])) }; Log "  $($d.Name) → $(($r -split "`n")[-1])" }; (UI 'BkStatus').Text = 'Fertig.' }

# ---- System-Erweiterungen
$BgOptions = @(@{ N='Standard (System entscheidet)'; V=-1 }, @{ N='Höchstens 4 Prozesse'; V=4 }, @{ N='Höchstens 3 Prozesse'; V=3 }, @{ N='Höchstens 2 Prozesse (empfohlen)'; V=2 }, @{ N='Höchstens 1 Prozess'; V=1 }, @{ N='Keine Hintergrundprozesse'; V=0 })
function Get-BgLimit { $c = Shell 'settings get global activity_manager_constants'; if ($c -match 'max_cached_processes=(\d+)') { return [int]$matches[1] }; return -1 }
function Load-BgState { $cur = Get-BgLimit; $idx = 0; for ($i = 0; $i -lt $BgOptions.Count; $i++) { if ($BgOptions[$i].V -eq $cur) { $idx = $i } }; (UI 'CbBgLimit').SelectedIndex = $idx
  (UI 'CkFinishAct').IsChecked = ((Shell 'settings get global always_finish_activities') -eq '1')
  $mem = Shell 'cat /proc/meminfo | grep -E "MemAvailable"'; (UI 'BgStatus').Text = "Aktuell: $(if($cur -lt 0){'Standard'}else{"max. $cur"}) · frei: $([math]::Round(([double](($mem -split '\s+')[1]))/1MB,2)) GB" }
function Apply-BgLimit { $i = (UI 'CbBgLimit').SelectedIndex; if ($i -lt 0) { return }; $v = $BgOptions[$i].V
  $c = Shell 'settings get global activity_manager_constants'; $parts = @(); if ($c -and $c -ne 'null') { $parts = @($c -split ',' | Where-Object { $_ -and $_ -notmatch '^max_cached_processes=' }) }
  if ($v -ge 0) { $parts += "max_cached_processes=$v" }
  if ($parts.Count -gt 0) { Shell "settings put global activity_manager_constants `"$($parts -join ',')`"" | Out-Null } else { Shell 'settings delete global activity_manager_constants' | Out-Null }
  Shell "settings put global always_finish_activities $(if((UI 'CkFinishAct').IsChecked){1}else{0})" | Out-Null
  Shell 'am kill-all' | Out-Null; Log "Hintergrundprozesse: $($BgOptions[$i].N)$(if((UI 'CkFinishAct').IsChecked){' + aggressiv'})"; Load-BgState }
function Set-DevName { $n = (UI 'TxtDevName').Text.Trim(); if (-not $n) { return }; Shell "settings put global device_name `"$n`"" | Out-Null; Shell "settings put secure bluetooth_name `"$n`"" | Out-Null; Log "Gerätename: $n" }
function Full-Backup { Export-Profile; Backup-All; (UI 'BkStatus').Text = 'Komplett-Backup fertig (Profil + APKs in »backups«).' }
function Factory-Reset { if ([System.Windows.MessageBox]::Show("ACHTUNG: Setzt den Stick komplett zurück – alle Apps, Logins und Einstellungen werden gelöscht. Vorher Komplett-Backup gemacht?`n`nWirklich fortfahren?", 'Werks-Reset', 'YesNo', 'Warning') -ne 'Yes') { return }
  $r = Shell 'am broadcast -a android.intent.action.MASTER_CLEAR -n android/com.android.server.MasterClearReceiver'; if ($r -match 'Broadcast completed') { Log 'Werks-Reset ausgelöst – der Stick startet neu.'; Disconnect-Device } else { Log "Werks-Reset per ADB nicht erlaubt ($r). Am TV: Einstellungen → Mein Fire TV → Auf Werkseinstellungen zurücksetzen." } }
function Apply-ProfileObject($p) { Set-Packages @($p.Deaktiviert) $true
  if ($p.Animation) { foreach ($k in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') { Shell "settings put global $k $($p.Animation)" | Out-Null } }
  if ($p.DnsMode -eq 'hostname' -and $p.DnsHost) { Shell 'settings put global private_dns_mode hostname' | Out-Null; Shell "settings put global private_dns_specifier $($p.DnsHost)" | Out-Null }
  if ($p.Ruhezustand) { Shell "settings put system screen_off_timeout $($p.Ruhezustand)" | Out-Null } }
function Rollout { $dlg = New-Object System.Windows.Forms.OpenFileDialog; $dlg.Filter = 'Profil (*.json)|*.json'; $dlg.InitialDirectory = $script:BackupDir; if ($dlg.ShowDialog() -ne 'OK') { return }
  $p = Get-Content $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json; $devs = @(Load-Devices); $orig = $script:IP; (UI 'LogBox').Visibility = 'Visible'; $ok = 0
  foreach ($d in $devs) { (UI 'RolloutStatus').Text = "Verbinde $($d.IP) …"; Refresh-UI; Run-Adb @('connect', "$($d.IP):5555") | Out-Null; Start-Sleep -Milliseconds 800
    $line = ((Run-Adb @('devices')) -split "`n" | Where-Object { $_ -like "$($d.IP):5555*" }) -join ''; if ($line -notmatch '\sdevice') { Log "Rollout: $($d.IP) ($($d.Name)) nicht erreichbar – übersprungen"; continue }
    $script:IP = $d.IP; Log "Rollout → $($d.Name) ($($d.IP))"; Apply-ProfileObject $p; $ok++ }
  $script:IP = $orig; (UI 'RolloutStatus').Text = "Fertig: $ok von $($devs.Count) Sticks."; Read-State }
function Check-ModStatus { # Banner im Dashboard: Mods aktiv? Fire-OS-Update erkannt?
  $inactive = @(); foreach ($f in $Features) { if ($f.Type -eq 'toggle' -and $f.Id -ne 'dns' -and -not $script:Initial[$f.Id]) { $inactive += $f.Title } }
  $osNow = Shell 'getprop ro.build.version.name'; $dev = Load-Devices | Where-Object { $_.IP -eq $script:IP } | Select-Object -First 1; $osOld = if ($dev -and $dev.PSObject.Properties['OS']) { $dev.OS } else { $null }
  $bn = UI 'Banner'; $tx = UI 'BannerTxt'; $fix = UI 'BtBannerFix'
  if ($osOld -and $osNow -and $osOld -ne $osNow) { $bn.Background = (Brush '#FFE8CC'); $tx.Foreground = (Brush '#C25E00'); $tx.Text = "Fire OS wurde aktualisiert ($osOld → $osNow). Mods prüfen und ggf. neu anwenden – die Update-Sperre im Router kontrollieren."; $fix.Visibility = 'Visible'; $bn.Visibility = 'Visible' }
  elseif ($inactive.Count -gt 0) { $bn.Background = (Brush '#FFF4CC'); $tx.Foreground = (Brush '#8A6D00'); $tx.Text = "Nicht aktiv: $($inactive -join ', ')"; $fix.Visibility = 'Visible'; $bn.Visibility = 'Visible' }
  else { $bn.Background = (Brush '#D9F5E1'); $tx.Foreground = (Brush '#1E8E3E'); $tx.Text = 'Alle Mods aktiv ✓'; $fix.Visibility = 'Collapsed'; $bn.Visibility = 'Visible' }
  Save-DeviceOS $script:IP $osNow }
function Save-DeviceOS($ip, $os) { $list = @(Load-Devices); foreach ($d in $list) { if ($d.IP -eq $ip) { if ($d.PSObject.Properties['OS']) { $d.OS = $os } else { $d | Add-Member -NotePropertyName OS -NotePropertyValue $os } } }; (, $list) | ConvertTo-Json -Depth 4 | Set-Content $script:DevFile -Encoding UTF8 }
function Fix-Mods { foreach ($f in $Features) { if ($f.Type -eq 'toggle' -and $f.Id -ne 'dns' -and $f.Id -ne 'launcher') { (UI "sw_$($f.Id)").IsChecked = $true } }; Do-Apply }
function Wifi-Connect { if ($script:SDK -lt 30) { Log 'WLAN wechseln per ADB braucht Android 11+ (Fire OS 8). Dieser Stick: am TV unter Einstellungen → Netzwerk.'; return }
  $ssid = (UI 'TxtSsid').Text.Trim(); $pw = (UI 'TxtWifiPw').Text; if (-not $ssid) { return }; $r = Shell "cmd wifi connect-network `"$ssid`" wpa2 `"$pw`""; Log "WLAN → $ssid : $r" }
function Speed-Test { $r = Shell 'am start -a android.intent.action.VIEW -d https://fast.com'; if ($r -match 'Error|No Activity') { $r = Shell 'am start -n com.amazon.cloud9/com.amazon.cloud9.BrowserActivity -a android.intent.action.VIEW -d https://fast.com' }; Log "Speedtest am TV gestartet ($r)" }
function Upload-Screensaver { $dlg = New-Object System.Windows.Forms.FolderBrowserDialog; $dlg.Description = 'Ordner mit Fotos (JPG/PNG) für den Bildschirmschoner'; if ($dlg.ShowDialog() -ne 'OK') { return }
  $files = Get-ChildItem $dlg.SelectedPath -Include *.jpg, *.jpeg, *.png -Recurse -File; Shell 'mkdir -p /sdcard/Pictures/Screensaver' | Out-Null; $n = 0
  foreach ($f in $files) { (UI 'FileStatus').Text = "Kopiere $($f.Name) …"; Refresh-UI; Run-Adb ((Dev) + @('push', $f.FullName, '/sdcard/Pictures/Screensaver/')) | Out-Null; $n++ }
  (UI 'FileStatus').Text = "$n Fotos → /sdcard/Pictures/Screensaver"; Log "Bildschirmschoner: $n Fotos hochgeladen. In Projectivy: Einstellungen → Bildschirmschoner → Lokale Bilder → Ordner Pictures/Screensaver wählen." }

# ================================================================== Netzwerk
function Load-NetInfo { if (-not $script:Connected) { return }
  $w = Shell 'dumpsys wifi 2>/dev/null | grep -E -m8 "mWifiInfo|SSID|RSSI|Link speed|Frequency|MAC"'; $ip = Shell 'ip -4 addr show wlan0 2>/dev/null | grep -o "inet [0-9.]*/[0-9]*"'; $gw = Shell 'ip route 2>/dev/null | grep -o "default via [0-9.]*"'
  $dns = Shell 'getprop net.dns1'; $pd = Shell 'settings get global private_dns_mode'; $pdh = Shell 'settings get global private_dns_specifier'
  $txt = @(); $ssid = ([regex]::Match($w, 'SSID: ([^,\n]+)')).Groups[1].Value; $rssi = ([regex]::Match($w, 'RSSI: (-?\d+)')).Groups[1].Value; $ls = ([regex]::Match($w, 'Link speed: (\d+)')).Groups[1].Value; $fq = ([regex]::Match($w, 'Frequency: (\d+)')).Groups[1].Value
  $band = ''; if ($fq -match '^\d+$') { $band = if ([int]$fq -gt 3000) { '(5 GHz)' } else { '(2.4 GHz)' } }
  $txt += "WLAN:          $ssid"; $txt += "Signal:        $rssi dBm"; $txt += "Link-Speed:    $ls Mbps"; $txt += "Frequenz:      $fq MHz $band"
  $txt += "IP:            $($ip -replace 'inet ','')"; $txt += "Gateway:       $($gw -replace 'default via ','')"; $txt += "DNS (Router):  $dns"; $txt += "Privater DNS:  $(if($pd -eq 'hostname'){$pdh}else{'aus'})"
  (UI 'NetInfo').Text = ($txt -join "`r`n"); (UI 'DnsStatus').Text = if ($pd -eq 'hostname') { "Aktiv: $pdh" } else { 'Aus' } }
function Ping-Test { (UI 'NetInfo').Text += "`r`n`r`nPing-Test läuft …"; Refresh-UI; $r = Shell 'ping -c 4 -W 2 8.8.8.8 2>&1 | tail -3'; $r2 = Shell 'ping -c 2 -W 2 amazon.com 2>&1 | tail -2'; (UI 'NetInfo').Text += "`r`n$r`r`n$r2"; Log 'Ping-Test ausgeführt' }
function Apply-Dns { $i = (UI 'CbDns').SelectedIndex; if ($i -lt 0) { $i = 0 }; $h = $DnsProfiles[$i].Host; if (-not $h) { $h = (UI 'TxtDnsHost').Text.Trim() }; if (-not $h) { (UI 'DnsStatus').Text = 'Hostname eingeben.'; return }
  Shell 'settings put global private_dns_mode hostname' | Out-Null; Shell "settings put global private_dns_specifier $h" | Out-Null; Log "Privater DNS: $h"; (UI 'DnsStatus').Text = "Aktiv: $h" }
function Update-Vpn { if (-not $script:Connected) { return }; $all = Shell 'pm list packages'; $any = $false
  foreach ($v in $VpnApps) { $id = $v.Pkg.Replace('.', '_'); $has = [bool]($all -match [regex]::Escape($v.Pkg)); (UI "vpn_$id").Visibility = if ($has) { 'Visible' } else { 'Collapsed' }; if ($has) { $any = $true } }
  (UI 'VpnNone').Visibility = if ($any) { 'Collapsed' } else { 'Visible' } }

# ================================================================== Werkzeuge
# ---- Konsole
$CmdExamples = @('Beispiele …', 'pm list packages -3', 'pm list packages -d', 'getprop ro.product.model', 'getprop | grep version', 'settings get global private_dns_mode', 'settings list global', 'dumpsys battery', 'dumpsys wifi | grep -E "SSID|RSSI"', 'df -h', 'free -m', 'top -n 1 -m 15', 'ls -la /sdcard', 'am start -n com.amazon.tv.launcher/.ui.HomeActivity_vNext', 'input keyevent 3', 'pm path com.spocky.projengmenu', 'adb devices', 'adb pull /sdcard/Download downloads', 'adb logcat -d -t 50')
$script:CmdHistory = @(); $script:CmdHistIdx = -1
function Run-Command { $c = (UI 'TxtCmd').Text.Trim(); if (-not $c) { return }
  $script:CmdHistory = @($script:CmdHistory | Where-Object { $_ -ne $c }) + $c; $script:CmdHistIdx = $script:CmdHistory.Count
  $out = UI 'TxtCmdOut'; $out.AppendText("> $c`r`n"); Refresh-UI
  $r = try { if ($c -match '^adb\s+(.+)$') { $argv = [regex]::Matches($matches[1], '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') }; Run-Adb ((Dev) + $argv) } else { Shell $c } } catch { "Fehler: $($_.Exception.Message)" }
  if (-not $r) { $r = '(keine Ausgabe)' }; $out.AppendText(($r -replace "(?<!`r)`n", "`r`n") + "`r`n`r`n"); $out.ScrollToEnd(); Log "Konsole: $c"; (UI 'TxtCmd').Text = '' }
function Load-Info { $props = @('ro.product.model', 'ro.product.device', 'ro.product.name', 'ro.build.version.name', 'ro.build.version.fireos', 'ro.build.version.release', 'ro.build.version.sdk', 'ro.build.version.security_patch', 'ro.product.cpu.abilist', 'ro.serialno', 'ro.build.display.id', 'ro.hardware', 'ro.product.manufacturer')
  $txt = @(); foreach ($p in $props) { $v = Shell "getprop $p"; if ($v) { $txt += ('{0,-34} {1}' -f $p, $v) } }
  $txt += ''; $txt += 'SPEICHER'; $txt += (Shell 'df -h /data /system 2>/dev/null'); $txt += ''; $txt += 'ARBEITSSPEICHER'; $txt += (Shell 'cat /proc/meminfo | head -3'); $txt += ''; $txt += 'CPU'; $txt += (Shell 'cat /proc/cpuinfo | grep -E -m3 "Hardware|model name|Processor"'); $txt += (Shell 'cat /sys/devices/system/cpu/present')
  $txt += ''; $txt += 'DEAKTIVIERTE PAKETE'; $txt += (Shell 'pm list packages -d'); (UI 'TxtInfo').Text = ($txt -join "`r`n") }
function Load-Logcat { $f = (UI 'TxtLogFilter').Text.Trim(); $out = Run-Adb ((Dev) + @('logcat', '-d', '-t', '500', '-v', 'time')); if ($f) { $out = (($out -split "`n") | Where-Object { $_ -match [regex]::Escape($f) }) -join "`r`n" }; (UI 'TxtLogcat').Text = $out }
function Load-Bt { $out = Shell 'dumpsys bluetooth_manager 2>/dev/null | grep -A 30 -i "bonded" | head -40'; if (-not $out) { $out = Shell 'dumpsys bluetooth_manager | head -60' }; (UI 'TxtBt').Text = $out }
function Export-Log { $dlg = New-Object System.Windows.Forms.SaveFileDialog; $dlg.Filter = 'Textdatei (*.txt)|*.txt'; $dlg.FileName = "firetv_protokoll_$(Get-Date -Format yyyyMMdd_HHmm).txt"; if ($dlg.ShowDialog() -eq 'OK') { (UI 'Log').Text | Set-Content $dlg.FileName -Encoding UTF8; Log "Protokoll gespeichert: $($dlg.FileName)" } }

# ================================================================== Favoriten
function Render-Favorites { $wp = UI 'FavPanel'; $wp.Children.Clear()
  foreach ($f in $script:Set.Favorites) { $b = New-Object System.Windows.Controls.Button; $b.Content = $f.Name; $b.Style = $Window.Resources['Secondary']; $b.Margin = '0,0,6,6'; $b.Tag = $f.Pkg; $b.ToolTip = "Start: $($f.Pkg)  (Rechtsklick = entfernen)"
    $b.Add_Click({ param($x, $e) Start-Package $x.Tag }); $b.Add_MouseRightButtonUp({ param($x, $e) Remove-Favorite $x.Tag }); $wp.Children.Add($b) | Out-Null }
  if ($script:Set.Favorites.Count -eq 0) { $t = New-Object System.Windows.Controls.TextBlock; $t.Text = 'Noch keine Favoriten.'; $t.Style = $Window.Resources['Sub']; $wp.Children.Add($t) | Out-Null } }
function Add-Favorite($pkg) { if (-not $pkg) { return }; if ($script:Set.Favorites | Where-Object { $_.Pkg -eq $pkg }) { Log "Favorit existiert: $pkg"; return }
  $name = $pkg; $m = $Apps | Where-Object { $pkg -match $_.PkgMatch } | Select-Object -First 1; if ($m) { $name = $m.Name } elseif ($script:LauncherNames.ContainsKey($pkg)) { $name = $script:LauncherNames[$pkg] } else { $name = ($pkg -split '\.')[-1] }
  $script:Set.Favorites = @($script:Set.Favorites) + [pscustomobject]@{ Name = $name; Pkg = $pkg }; Save-Settings; Render-Favorites; Log "Favorit hinzugefügt: $name" }
function Remove-Favorite($pkg) { $script:Set.Favorites = @($script:Set.Favorites | Where-Object { $_.Pkg -ne $pkg }); Save-Settings; Render-Favorites; Log "Favorit entfernt: $pkg" }

# ================================================================== Makros
function Load-Macros { $lb = UI 'LbMacros'; $lb.Items.Clear(); foreach ($m in $script:Set.Macros) { $lb.Items.Add($m.Name) | Out-Null }
  $cb = UI 'CbSchedMacro'; $cb.Items.Clear(); foreach ($m in $script:Set.Macros) { $cb.Items.Add($m.Name) | Out-Null }; if ($cb.Items.Count -gt 0) { $cb.SelectedIndex = 0 }
  if ($lb.Items.Count -gt 0 -and $lb.SelectedIndex -lt 0) { $lb.SelectedIndex = 0 } }
function Show-Macro { $i = (UI 'LbMacros').SelectedIndex; if ($i -lt 0) { return }; $m = $script:Set.Macros[$i]; (UI 'TxtMacroName').Text = $m.Name; (UI 'TxtMacroSteps').Text = ($m.Steps -replace "(?<!`r)`n", "`r`n") }
function Save-Macro { $i = (UI 'LbMacros').SelectedIndex; $name = (UI 'TxtMacroName').Text.Trim(); $steps = (UI 'TxtMacroSteps').Text -replace "`r", ''; if (-not $name) { (UI 'MacroStatus').Text = 'Name fehlt.'; return }
  $obj = [pscustomobject]@{ Name = $name; Steps = $steps }
  if ($i -ge 0) { $list = @($script:Set.Macros); $list[$i] = $obj; $script:Set.Macros = $list } else { $script:Set.Macros = @($script:Set.Macros) + $obj }
  Save-Settings; Load-Macros; (UI 'LbMacros').SelectedIndex = [math]::Max(0, $i); (UI 'MacroStatus').Text = 'Gespeichert.' }
function New-Macro { $script:Set.Macros = @($script:Set.Macros) + [pscustomobject]@{ Name = "Neues Makro $($script:Set.Macros.Count + 1)"; Steps = "taste home" }; Save-Settings; Load-Macros; (UI 'LbMacros').SelectedIndex = $script:Set.Macros.Count - 1 }
function Del-Macro { $i = (UI 'LbMacros').SelectedIndex; if ($i -lt 0) { return }; $list = @($script:Set.Macros); $script:Set.Macros = @($list | Where-Object { $_.Name -ne $list[$i].Name }); Save-Settings; Load-Macros; (UI 'TxtMacroName').Text = ''; (UI 'TxtMacroSteps').Text = '' }

# ================================================================== Zeitpläne (Windows-Aufgabenplanung)
$SchedWhen = @(@{ N='Täglich'; A='/SC DAILY' }, @{ N='Montag–Freitag'; A='/SC WEEKLY /D MON,TUE,WED,THU,FRI' }, @{ N='Samstag+Sonntag'; A='/SC WEEKLY /D SAT,SUN' }, @{ N='Wöchentlich (So)'; A='/SC WEEKLY /D SUN' }, @{ N='Einmalig (heute)'; A='/SC ONCE' })
function Load-Schedules { $lb = UI 'LbSched'; $lb.Items.Clear(); $out = & schtasks.exe /Query /FO CSV /NH 2>$null | Where-Object { $_ -match '"\\FireTVMod_' }
  foreach ($l in $out) { $f = $l -split '","'; $name = ($f[0] -replace '^"\\', ''); $i = New-Object System.Windows.Controls.ListBoxItem; $i.Content = ('{0,-40} nächste Ausführung: {1}  Status: {2}' -f $name, $f[1], ($f[2] -replace '"', '')); $i.Tag = $name; $lb.Items.Add($i) | Out-Null } }
function Add-Schedule { $mi = (UI 'CbSchedMacro').SelectedIndex; $wi = (UI 'CbSchedWhen').SelectedIndex; $time = (UI 'TxtSchedTime').Text.Trim(); if ($mi -lt 0 -or $wi -lt 0 -or $time -notmatch '^\d{1,2}:\d{2}$') { Log 'Zeitplan: Makro, Rhythmus und Uhrzeit (HH:MM) angeben.'; return }
  $macro = $script:Set.Macros[$mi].Name; $tn = "FireTVMod_$($macro -replace '[^\w]', '_')_$($time -replace ':', '')"
  $ps1 = Join-Path $Root 'FireTV_Mod_Launcher.ps1'; $tr = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \""$ps1\"" -Run \""$macro\"" -Device $($script:IP)"
  $args = "/Create /F /TN `"$tn`" /TR `"$tr`" $($SchedWhen[$wi].A) /ST $time"
  $r = cmd /c "schtasks.exe $args" 2>&1; Log "Zeitplan: $($r -join ' ')"; Load-Schedules }
function Del-Schedule { $i = (UI 'LbSched').SelectedItem; if (-not $i) { return }; $r = & schtasks.exe /Delete /F /TN $i.Tag 2>&1; Log "Zeitplan gelöscht: $($i.Tag) ($r)"; Load-Schedules }

# ================================================================== Einstellungen / Autostart / Update
function Vbs-Path { Join-Path $Root 'FireTV Mod Launcher.vbs' }
function Ensure-Vbs { $v = Vbs-Path; $ps1 = Join-Path $Root 'FireTV_Mod_Launcher.ps1'
  $c = "Set sh = CreateObject(""WScript.Shell"")`r`nsh.Run ""powershell -NoProfile -ExecutionPolicy Bypass -STA -File """"$ps1"""""", 0, False"; Set-Content $v $c -Encoding ASCII; return $v }
function Make-Shortcut($dir, $name) { $v = Ensure-Vbs; $ws = New-Object -ComObject WScript.Shell; $lnk = $ws.CreateShortcut((Join-Path $dir "$name.lnk")); $lnk.TargetPath = 'wscript.exe'; $lnk.Arguments = "`"$v`""; $lnk.WorkingDirectory = $Root; $lnk.IconLocation = '%SystemRoot%\system32\imageres.dll,109'; $lnk.Save() }
function Startup-Dir { [Environment]::GetFolderPath('Startup') }
function Load-SettingsPage { (UI 'SwDark').IsChecked = [bool]$script:Set.Dark; (UI 'SwAuto').IsChecked = [bool]$script:Set.AutoConnect; (UI 'TxtUpdateUrl').Text = [string]$script:Set.UpdateUrl
  (UI 'AutostartStatus').Text = if (Test-Path (Join-Path (Startup-Dir) 'Fire TV Mod.lnk')) { 'Autostart: aktiv' } else { 'Autostart: aus' } }
function Check-Update { $u = (UI 'TxtUpdateUrl').Text.Trim().TrimEnd('/'); $script:Set.UpdateUrl = $u; Save-Settings; if (-not $u) { (UI 'UpdateStatus').Text = 'Keine Update-URL konfiguriert.'; return }
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $v = (Invoke-WebRequest -Uri "$u/version.txt" -UseBasicParsing).Content.Trim()
    if ([version]$v -gt [version]$script:Version) { if ([System.Windows.MessageBox]::Show("Version $v verfügbar (installiert: $($script:Version)). Jetzt laden? Der Launcher startet danach neu.", 'Update', 'YesNo', 'Question') -eq 'Yes') {
        $ps1 = Join-Path $Root 'FireTV_Mod_Launcher.ps1'; Copy-Item $ps1 "$ps1.bak" -Force; Invoke-WebRequest -Uri "$u/FireTV_Mod_Launcher.ps1" -OutFile $ps1 -UseBasicParsing; Start-Process wscript.exe "`"$(Ensure-Vbs)`""; $Window.Close() } }
    else { (UI 'UpdateStatus').Text = "Aktuell (Version $($script:Version))." } } catch { (UI 'UpdateStatus').Text = "Prüfung fehlgeschlagen: $($_.Exception.Message)" } }
$HelpText = @"
VERBINDUNG
• ADB-Debugging am Stick: Einstellungen → Mein Fire TV → Entwickleroptionen → ADB-Debugging EIN. Fehlen die Entwickleroptionen: Info → 7× auf den Gerätenamen.
• »USB-Debugging zulassen?« am TV mit »Immer zulassen« bestätigen. Erscheint die Frage nicht: ADB-Debugging aus- und wieder einschalten.
• Der Stick muss im selben WLAN sein. Feste IP im Router vergeben, damit sie gleich bleibt.

STARTBILDSCHIRM / LAUNCHER
• Alternative Launcher laufen über »Launcher Manager Mini« (am TV per Downloader-App, Code 632067, oder APK in Ordner »apk«).
• Welcher Launcher bei Home erscheint, wählt man einmal in der Mini-App am TV. Danach reicht »Wechseln« im Dashboard.
• Fire OS 7 (Android 9): Projectivy nur bis Version 4.66 (Bundle arm64+armeabi, Android 6.0+) von APKMirror. Neuere Versionen brauchen Android 12.
• 32-Bit-Sticks (Lite, 4K, 4K Max 1. Gen): immer armeabi-v7a-Varianten. Der Launcher wählt das automatisch im Katalog.

UPDATES VON AMAZON
• Der Zwangs-Updater lässt sich deaktivieren, das OTA-Paket selbst nicht (systemgeschützt). Sperre im Router die Hosts aus »Netzwerk › Update-Sperre« für die Stick-IP.
• Kam trotzdem ein Update, zeigt das Dashboard oben einen Hinweis und »Mods neu anwenden«.

FEHLERBILDER
• INSTALL_FAILED_NO_MATCHING_ABIS: falsche Architektur (64-Bit-APK auf 32-Bit-Stick).
• INSTALL_FAILED_OLDER_SDK: App braucht neueres Android. Ältere Version suchen.
• Screenshot schwarz/leer: läuft gerade DRM-Inhalt (Netflix/Prime). Startbildschirm öffnen und erneut versuchen.
• »Stick nicht erreichbar«: Stick im Standby (Aufwecken), anderes WLAN, oder IP geändert.

MAKROS & ZEITPLÄNE
• Makros sind Befehlsketten (Automation). Zeitpläne legen Windows-Aufgaben an, die das Makro im Hintergrund ausführen – der PC muss dabei laufen.
• Befehlszeile: FireTV_Mod_Launcher.ps1 -Run "Makroname" -Device 192.168.0.15

ORDNER
• apk = manuelle APKs (Projectivy, Launcher Manager Mini, Wolf, Button Mapper) · apk_sideload = automatische Downloads · screenshots · downloads · backups (Profile + APKs)
"@

# ================================================================== Assistent
$Steps = @(
  @{ Title='ADB-Debugging einschalten'; Text="Damit dieser Launcher den Stick steuern kann, muss ADB-Debugging aktiv sein.`n`n1. Am Fire TV: Einstellungen → Mein Fire TV → Entwickleroptionen`n2. »ADB-Debugging« auf EIN stellen`n`nFalls »Entwickleroptionen« nicht sichtbar ist: Einstellungen → Mein Fire TV → Info → sieben Mal auf den Gerätenamen drücken." },
  @{ Title='IP-Adresse finden'; Text="Der Stick und dieser PC müssen im selben WLAN sein.`n`n1. Am Fire TV: Einstellungen → Mein Fire TV → Info → Netzwerk`n2. Die angezeigte IP-Adresse notieren (z. B. 192.168.0.15)`n`nTipp: Im Router kann man dem Stick eine feste IP geben, dann bleibt sie immer gleich. Im nächsten Schritt sucht der Launcher auch automatisch nach Sticks." },
  @{ Title='Verbinden'; Text="IP-Adresse eingeben oder ein gefundenes Gerät anklicken. Beim ersten Mal erscheint auf dem Fernseher »USB-Debugging zulassen?« – dort »Immer zulassen« wählen und mit OK bestätigen." }
)
$script:Step = 0
function Show-Step($i) { $script:Step = $i; (UI 'WzStep').Text = "SCHRITT $($i+1) VON 3"; (UI 'WzTitle').Text = $Steps[$i].Title; (UI 'WzText').Text = $Steps[$i].Text
  (UI 'WzBack').Visibility = if ($i -eq 0) { 'Hidden' } else { 'Visible' }; (UI 'WzNext').Visibility = if ($i -eq 2) { 'Collapsed' } else { 'Visible' }; (UI 'WzConnect').Visibility = if ($i -eq 2) { 'Visible' } else { 'Collapsed' }
  if ($i -eq 2) { Fill-DeviceList @(); if (-not $script:Scanned) { $script:Scanned = $true; $Window.Dispatcher.BeginInvoke([action]{ Scan-Network }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null } } }

# ================================================================== Events
(UI 'WzNext').Add_Click({ Show-Step ($script:Step + 1) }); (UI 'WzBack').Add_Click({ Show-Step ($script:Step - 1) })
(UI 'WzBtnConnect').Add_Click({ Try-Connect }); (UI 'WzIP').Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Try-Connect } })
(UI 'WzScan').Add_Click({ Scan-Network }); (UI 'WzList').Add_SelectionChanged({ $sel = (UI 'WzList').SelectedItem; if ($sel) { (UI 'WzIP').Text = $sel.Tag; Try-Connect } })
foreach ($p in $Pages) { $b = UI "Nav$p"; $b.Tag = $p; $b.Add_Click({ param($s, $e) Show-Page $s.Tag }) }
(UI 'BtLog').Add_Click({ $l = UI 'LogBox'; $l.Visibility = if ($l.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' } })
(UI 'BtDisconnect').Add_Click({ Disconnect-Device })
(UI 'BtApply').Add_Click({ Do-Apply }); (UI 'BtRefresh').Add_Click({ Read-State }); (UI 'BtLauncherApply').Add_Click({ Do-LauncherSwitch }); (UI 'BtLauncherUninstall').Add_Click({ Do-LauncherUninstall })
(UI 'bt_cache').Add_Click({ Do-Cache }); (UI 'bt_reboot').Add_Click({ Do-Reboot })
(UI 'BtAppsInstall').Add_Click({ Do-AppsInstall })
foreach ($a in $Apps) { $t = UI "src_$($a.Id)"; $t.Tag = $a.Site; $t.Add_MouseLeftButtonUp({ param($s, $e) Start-Process $s.Tag }) }
(UI 'BtAppsUpdates').Add_Click({ Check-AppUpdates }); (UI 'BtApkUrl').Add_Click({ Install-FromUrl })
(UI 'BtAppFav').Add_Click({ Add-Favorite (Sel-App) }); (UI 'BtAppHide').Add_Click({ App-Hide }); (UI 'BtAppPerms').Add_Click({ $p = Sel-App; if ($p) { Load-Perms $p; (UI 'TabApps').SelectedIndex = 2 } }); (UI 'BtAppDataBackup').Add_Click({ App-DataBackup })
(UI 'BtRecStart').Add_Click({ Rec-Start }); (UI 'BtRecStop').Add_Click({ Rec-Stop }); (UI 'BtRecOpen').Add_Click({ if ($script:RecFile -and (Test-Path $script:RecFile)) { Start-Process $script:RecFile } else { Open-Folder $script:BackupDir } })
(UI 'BtPermToggle').Add_Click({ Toggle-Perm }); (UI 'BtRunReload').Add_Click({ Load-Running }); (UI 'BtRunStop').Add_Click({ $i = (UI 'LbRunning').SelectedItem; if ($i) { Shell "am force-stop $($i.Tag)" | Out-Null; Log "Beendet: $($i.Tag)"; Load-Running } }); (UI 'BtRunKillAll').Add_Click({ Shell 'am kill-all' | Out-Null; Log 'Alle Hintergrund-Apps beendet'; Load-Running })
(UI 'BtAppsReload').Add_Click({ Load-AppList }); (UI 'CkShowSystem').Add_Click({ Load-AppList }); (UI 'BtAppStart').Add_Click({ App-Start }); (UI 'BtAppStop').Add_Click({ App-Stop }); (UI 'BtAppClear').Add_Click({ App-Clear }); (UI 'BtAppBackup').Add_Click({ App-Backup $null }); (UI 'BtAppUninstall').Add_Click({ App-Uninstall })
foreach ($k in $Keys) { $b = UI "key_$($k.Id)"; $b.Tag = $k.Code; $b.Add_Click({ param($s, $e) Key $s.Tag }) }
(UI 'BtSendText').Add_Click({ Send-Text }); (UI 'TxtSend').Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Send-Text } })
(UI 'PgRemote').Add_PreviewKeyDown({ param($s, $e) if ((UI 'TxtSend').IsKeyboardFocused) { return }
  $map = @{ 'Up'=19; 'Down'=20; 'Left'=21; 'Right'=22; 'Return'=23; 'Back'=4; 'Escape'=4; 'Space'=85 }; $k = [string]$e.Key; if ($map.ContainsKey($k)) { Key $map[$k]; $e.Handled = $true } })
(UI 'BtShot').Add_Click({ Take-Shot }); (UI 'BtRec').Add_Click({ Start-Rec }); (UI 'BtShotFolder').Add_Click({ Open-Folder $script:ShotDir })
$cbF = UI 'CbFolder'; foreach ($f in $Folders) { $cbF.Items.Add($f) | Out-Null }; $cbF.SelectedIndex = 0; $cbF.Add_SelectionChanged({ Load-Files })
(UI 'BtFilesReload').Add_Click({ Load-Files }); (UI 'BtUpload').Add_Click({ Upload-Files }); (UI 'BtDownload').Add_Click({ Download-Files }); (UI 'BtDelete').Add_Click({ Delete-Files }); (UI 'BtDlFolder').Add_Click({ Open-Folder $script:DlDir })
$cb = UI 'CbRes'; foreach ($o in $ResOptions) { $cb.Items.Add($o.N) | Out-Null }; $cb.SelectedIndex = 0
$cb = UI 'CbDpi'; foreach ($o in $DpiOptions) { $cb.Items.Add($o.N) | Out-Null }; $cb.SelectedIndex = 0
$cb = UI 'CbSleep'; foreach ($o in $SleepOptions) { $cb.Items.Add($o.N) | Out-Null }
(UI 'BtDisplayApply').Add_Click({ Apply-Display }); (UI 'BtDisplayReset').Add_Click({ Reset-Display }); (UI 'BtSleepApply').Add_Click({ Apply-Sleep })
(UI 'BtStandby').Add_Click({ Key 223; Log 'Standby' }); (UI 'BtWake').Add_Click({ Key 224; Log 'Aufwecken' }); (UI 'BtReboot2').Add_Click({ Do-Reboot })
$cb = UI 'CbBgLimit'; foreach ($o in $BgOptions) { $cb.Items.Add($o.N) | Out-Null }; $cb.SelectedIndex = 0
(UI 'BtBgApply').Add_Click({ Apply-BgLimit }); (UI 'BtBgKill').Add_Click({ Shell 'am kill-all' | Out-Null; Log 'Alle Hintergrund-Apps beendet'; Load-BgState })
(UI 'BtDevName').Add_Click({ Set-DevName }); (UI 'BtCecOn').Add_Click({ Shell 'settings put global hdmi_control_enabled 1' | Out-Null; Log 'HDMI-CEC aktiviert' }); (UI 'BtCecOff').Add_Click({ Shell 'settings put global hdmi_control_enabled 0' | Out-Null; Log 'HDMI-CEC aus' })
(UI 'BtTvPower').Add_Click({ Key 177; Log 'TV Ein/Aus (CEC)' }); (UI 'BtTvInput').Add_Click({ Key 178; Log 'TV-Eingang (CEC)' })
(UI 'BtFullBackup').Add_Click({ Full-Backup }); (UI 'BtFactoryReset').Add_Click({ Factory-Reset }); (UI 'BtRollout').Add_Click({ Rollout }); (UI 'BtBannerFix').Add_Click({ Fix-Mods })
(UI 'BtWifiConnect').Add_Click({ Wifi-Connect }); (UI 'BtSpeed').Add_Click({ Speed-Test }); (UI 'BtScreensaver').Add_Click({ Upload-Screensaver })
(UI 'BtProfileExport').Add_Click({ Export-Profile }); (UI 'BtProfileImport').Add_Click({ Import-Profile }); (UI 'BtBackupAll').Add_Click({ Backup-All }); (UI 'BtRestoreAll').Add_Click({ Restore-All }); (UI 'BtBackupFolder').Add_Click({ Open-Folder $script:BackupDir })
$cb = UI 'CbDns'; foreach ($o in $DnsProfiles) { $cb.Items.Add($o.Name) | Out-Null }; $cb.SelectedIndex = 0; $cb.Add_SelectionChanged({ $i = (UI 'CbDns').SelectedIndex; if ($i -ge 0) { (UI 'TxtDnsHost').Visibility = if ($DnsProfiles[$i].Host) { 'Collapsed' } else { 'Visible' } } })
(UI 'BtNetReload').Add_Click({ Load-NetInfo }); (UI 'BtPing').Add_Click({ Ping-Test }); (UI 'BtDnsApply').Add_Click({ Apply-Dns }); (UI 'BtDnsOff').Add_Click({ Shell 'settings put global private_dns_mode off' | Out-Null; (UI 'DnsStatus').Text = 'Aus'; Log 'Privater DNS aus' })
(UI 'BtCopyHosts').Add_Click({ [System.Windows.Clipboard]::SetText((UI 'TxtHosts').Text); Log 'Host-Liste kopiert' })
foreach ($v in $VpnApps) { $id = $v.Pkg.Replace('.', '_'); $bs = UI "vpnStart_$id"; $bs.Tag = $v.Pkg; $bs.Add_Click({ param($s, $e) Shell "monkey -p $($s.Tag) -c android.intent.category.LAUNCHER 1" | Out-Null; Log "VPN gestartet: $($s.Tag)" }); $bx = UI "vpnStop_$id"; $bx.Tag = $v.Pkg; $bx.Add_Click({ param($s, $e) Shell "am force-stop $($s.Tag)" | Out-Null; Log "VPN gestoppt: $($s.Tag)" }) }
(UI 'BtCmdRun').Add_Click({ Run-Command }); (UI 'BtCmdClear').Add_Click({ (UI 'TxtCmdOut').Text = '' })
(UI 'TxtCmd').Add_PreviewKeyDown({ param($x, $e) switch ([string]$e.Key) {
  'Return' { Run-Command; $e.Handled = $true }
  'Up' { if ($script:CmdHistory.Count -gt 0) { $script:CmdHistIdx = [math]::Max(0, $script:CmdHistIdx - 1); (UI 'TxtCmd').Text = $script:CmdHistory[$script:CmdHistIdx]; (UI 'TxtCmd').CaretIndex = (UI 'TxtCmd').Text.Length; $e.Handled = $true } }
  'Down' { if ($script:CmdHistory.Count -gt 0) { $script:CmdHistIdx = [math]::Min($script:CmdHistory.Count, $script:CmdHistIdx + 1); (UI 'TxtCmd').Text = if ($script:CmdHistIdx -lt $script:CmdHistory.Count) { $script:CmdHistory[$script:CmdHistIdx] } else { '' }; $e.Handled = $true } } } })
$cb = UI 'CbCmdExamples'; foreach ($o in $CmdExamples) { $cb.Items.Add($o) | Out-Null }; $cb.SelectedIndex = 0; $cb.Add_SelectionChanged({ $i = (UI 'CbCmdExamples').SelectedIndex; if ($i -gt 0) { (UI 'TxtCmd').Text = $CmdExamples[$i]; (UI 'CbCmdExamples').SelectedIndex = 0; (UI 'TxtCmd').Focus() | Out-Null } })
(UI 'BtInfoReload').Add_Click({ Load-Info }); (UI 'BtLogcat').Add_Click({ Load-Logcat }); (UI 'BtLogcatClear').Add_Click({ Run-Adb ((Dev) + @('logcat', '-c')) | Out-Null; (UI 'TxtLogcat').Text = ''; Log 'Logcat geleert' }); (UI 'BtBtReload').Add_Click({ Load-Bt })
(UI 'BtLogExport').Add_Click({ Export-Log }); (UI 'BtLogClear').Add_Click({ (UI 'Log').Text = ''; (UI 'LogMini').Text = '' })

(UI 'LbMacros').Add_SelectionChanged({ Show-Macro }); (UI 'BtMacroSave').Add_Click({ Save-Macro }); (UI 'BtMacroNew').Add_Click({ New-Macro }); (UI 'BtMacroDel').Add_Click({ Del-Macro })
(UI 'BtMacroRun').Add_Click({ $n = (UI 'TxtMacroName').Text.Trim(); if ($n) { (UI 'LogBox').Visibility = 'Visible'; Run-Macro $n } })
$cb = UI 'CbSchedWhen'; foreach ($o in $SchedWhen) { $cb.Items.Add($o.N) | Out-Null }; $cb.SelectedIndex = 0
(UI 'BtSchedAdd').Add_Click({ Add-Schedule }); (UI 'BtSchedDel').Add_Click({ Del-Schedule }); (UI 'BtSchedReload').Add_Click({ Load-Schedules })
(UI 'SwDark').Add_Click({ $script:Set.Dark = [bool](UI 'SwDark').IsChecked; Save-Settings; Apply-Theme })
(UI 'SwAuto').Add_Click({ $script:Set.AutoConnect = [bool](UI 'SwAuto').IsChecked; Save-Settings })
(UI 'BtAutostartOn').Add_Click({ Make-Shortcut (Startup-Dir) 'Fire TV Mod'; Load-SettingsPage; Log 'Autostart aktiviert' })
(UI 'BtAutostartOff').Add_Click({ Remove-Item (Join-Path (Startup-Dir) 'Fire TV Mod.lnk') -ErrorAction SilentlyContinue; Load-SettingsPage; Log 'Autostart entfernt' })
(UI 'BtDesktopLink').Add_Click({ Make-Shortcut ([Environment]::GetFolderPath('Desktop')) 'Fire TV Mod'; Log 'Desktop-Verknüpfung erstellt' })
(UI 'BtUpdateCheck').Add_Click({ Check-Update }); (UI 'TxtUpdateUrl').Add_LostFocus({ $script:Set.UpdateUrl = (UI 'TxtUpdateUrl').Text.Trim(); Save-Settings })
(UI 'BtOpenRoot').Add_Click({ Open-Folder $Root })
(UI 'BtResetSettings').Add_Click({ if ([System.Windows.MessageBox]::Show('Einstellungen, Makros und Favoriten zurücksetzen?', 'Zurücksetzen', 'YesNo', 'Warning') -eq 'Yes') { Remove-Item $script:SetFile -ErrorAction SilentlyContinue; Log 'Einstellungen zurückgesetzt – bitte Launcher neu starten.' } })
(UI 'HelpText').Text = $HelpText; (UI 'HelpVersion').Text = "Fire TV Mod Launcher Version $($script:Version)"
Ensure-Vbs | Out-Null; Render-Favorites

Show-Step 0
# ---- Auto-Verbinden
if ($script:Set.AutoConnect -and (Load-Devices).Count -gt 0 -and (Test-Path $script:ADB)) { $last = Load-Devices | Sort-Object Last -Descending | Select-Object -First 1; (UI 'WzIP').Text = $last.IP; $script:Scanned = $true; Show-Step 2
  $Window.Dispatcher.BeginInvoke([action]{ Try-Connect }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null }
$Window.ShowDialog() | Out-Null
