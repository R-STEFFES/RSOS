# RSOS 2.0 „Janina“ — Plan

## Ausgangslage

Die 1.x-Reihe (zuletzt 1.09 „Hannah") war ein `eznixOS`-Ableger: Debian 12
„bookworm", XFCE, ein Bau-Skript namens `bldeznix12X`, das live-build von außen
ansteuerte. Das Image war voll ausgestattet — zwei Büro-Suiten, Brennprogramme,
`clonezilla`, `dosbox`, `smplayer`, `audacious`, `filezilla`, dazu ein eigenes
Verwaltungswerkzeug (`ezadmin`), das unter anderem den Wechsel auf Debian
„testing" anbot.

Das ist für 2.0 zu viel. Ziel ist ein schlankes, deutsches System, das man
jemandem in die Hand drücken kann, ohne 40 Anwendungen zu erklären.

## Was 2.0 ist

| | |
|---|---|
| Name | **RSOS 2.0 „Janina"** |
| Basis | Debian 13 „trixie" |
| Desktop | KDE Plasma 6.3, minimal (`kde-plasma-desktop`) |
| Anmeldung | SDDM (Breeze) |
| Installer | Calamares mit eigenem Branding |
| Architektur | amd64 |
| Sprachen | Deutsch (Standard), Englisch (Rückfall) |
| Quellen | ausschließlich originale Debian-Repos |
| Bauweise | live-build im Projektordner, keine VM |

## Was drin ist

* Plasma mit Dolphin, Konsole, Kate, Ark, Gwenview, Okular, Spectacle, KCalc
* Firefox ESR (deutsch)
* Multimedia: Audacious, FFmpeg, die GStreamer-Sätze, SoundConverter, SoX
* Luanti (Blockwelt)
* Netz: NetworkManager, OpenVPN, Remmina, FileZilla, SMB
* Datenträger: GParted, cryptsetup, NTFS/exFAT/Btrfs/XFS, BleachBit
* Drucken und Scannen: CUPS, Gutenprint, Simple Scan
* Firmware: der komplette Satz der 1.x-Reihe (WLAN, Grafik, Sound)
* Systemübersicht: neofetch mit der RSOS-Bildmarke als Blockgrafik und
  fastfetch als Alternative

## Was Raphael am 2026-11-10 gestrichen hat

* Büro: LibreOffice (Writer, Calc, Impress, Draw)
* Mail: Thunderbird
* Videoschnitt: Kdenlive
* Medienwiedergabe: MPV (Celluloid ist jetzt der Videoplayer)
* Musik: Audacious samt Plugins, SoundConverter („Klangumwandler")
* Grafik: Inkscape, ImageMagick, GIMP
* Sicherheit: KeePassXC samt Browser-Anbindung
* Netz: FileZilla, Remmina
* Dateien: Transmission (BitTorrent), BleachBit
* Terminal: xterm (das Paket liefert UXTerm)

**GParted bleibt** — Raphael wollte es ausdrücklich behalten, als Werkzeug für
später. Die Partitionierung während der Installation macht ohnehin Calamares.

Diese Pakete stehen in keiner Liste mehr; die Begründung steht als Kommentar in
`config/package-lists/20-apps.list.chroot` und `00-base.list.chroot`, damit sie
nicht versehentlich wieder auftauchen.

## Was nicht mehr drin ist

* XFCE (vollständig ersetzt)
* `ezadmin` (das Werkzeug war eznix-spezifisch; ein RSOS-eigenes Gegenstück ist
  offen — siehe unten)
* zweite Büro-Suite, `clonezilla`, `dosbox`, `smplayer`, `asunder`, `geany`,
  `xscreensaver`, `light-locker`, `lightdm`
* eigene Paketquellen (es gab keine — das bleibt so)

## Offene Punkte

1. **Plasma-Layout festlegen.** Panel, Widgets, Farbschema und Wandbild lassen
   sich nicht sinnvoll erfinden. Ablauf: einmal bauen, von Hand einstellen,
   `scripts/capture-kde-config.sh` laufen lassen, Ergebnis committen.
   Siehe `docs/KDE-KONFIGURATION.md`.
2. **Mindestanforderung an Hardware.** Plasma 6 braucht mehr als XFCE der
   1.x-Reihe. Vorschlag: 2 GB RAM, 2 Kerne, 15 GB Platte. Bestätigen oder
   anpassen, dann in `welcome.conf` (`requiredRam`, `requiredStorage`)
   eintragen — dort steht noch der Wert der 1.x-Reihe (1.0 GB / 10 GB).
3. **Ersatz für `ezadmin`.** Braucht es ein RSOS-Werkzeug (Systeminfo,
   Sprachwechsel, Backports an/aus)? Wenn ja: neu schreiben, nicht das
   eznix-Skript umbenennen.
4. **Beiname: erledigt.** 2.0 heißt **„Janina"** (von Raphael gesetzt am
   2026-11-09). Steht in `CODENAME`, im Branding und in `os-release`.
5. **XFCE als Zweitimage?** Für schwache Hardware war XFCE im Gespräch. Erst
   entscheiden, wenn 2.0 steht.
6. **Release-Notes.** Für 1.09 „Hannah" fehlen sie noch; für 2.0 gehören sie
   ins Repo (`docs/releases/`).

## Nächste Schritte

1. Ersten Bau machen (`./scripts/build.sh`) und in einer VM starten.
2. Plasma einrichten, Konfiguration abziehen, committen.
3. Zweiten Bau machen, Calamares durchspielen (BIOS und UEFI).
4. Release-Notes schreiben, Tag setzen, ISO als GitHub-Release anhängen.
