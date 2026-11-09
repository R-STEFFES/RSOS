# Von 1.x auf 2.0 — was sich ändert

Das alte Build-Verzeichnis (`RSOS_1`, zuletzt 1.09 „Hannah") ist als
Rohmaterial in `assets/legacy/` mitgezogen: Branding, Splash, Wallpaper,
Bootloader-Konfigurationen, das eznix-Dokumentationspaket und das alte
Bau-Skript. Nichts davon ist gelöscht — es ist nur nicht mehr Teil des Baus.

## Der größte Unterschied: die Bauweise

**1.x** — ein Shell-Skript (`RSOS_1_Build`, abgeleitet von `bldeznix12X`) hat
`lb config` mit einem langen Argumenteschwanz aufgerufen, die Paketliste per
`echo … > config/package-lists/xfcedesktop.list.chroot` in eine Datei
geschrieben, das eznix-`bootloaders/`-Verzeichnis hineinkopiert und dann
`lb build` gestartet. Die Projektdatei war also ein Skript, das die
Konfiguration erzeugte.

**2.0** — die Konfiguration liegt als Dateibaum im Repo (`config/`), `auto/`
enthält nur noch drei kurze Einstiegspunkte, die live-build ohnehin aufruft.
Kein Skript schreibt Konfiguration; die Konfiguration ist die Quelle.

Vorteil: `git diff` zeigt jede Änderung am System, nicht am Generator.
`lb build` allein baut das Projekt, ohne Umweg über ein Skript.

## Einzelne Punkte

### Firmware-Patch entfällt

Die 1.x-Reihe hat `usr/share/live/build/functions/firmwarelists.sh` gepatcht
(`firmwarelists.sh` in `assets/legacy/livebuild/patches/`), damit live-build die
Firmware-Pakete aus den `Contents-*`-Dateien zieht. live-build 20250505
erledigt das selbst — der Patch ist nicht nur unnötig, er würde den Bau
brechen. **Nicht übernehmen.**

### eznix-Branding

`branding.desc`, `show.qml` und die Slides stammen aus dem eznix-Bestand und
sind auf RSOS umgeschrieben. Sie liegen jetzt in
`config/includes.chroot/etc/calamares/branding/rsos/`.

Die Farbe `sidebarTextHighlight` war Magenta (`#FF3DEF`) — sie ist jetzt Cyan
(`#00E5FF`), passend zur Marke (schwarz/weiß + Cyan).

### `ezadmin` fliegt raus

Das Skript (`assets/legacy/scripts/ezadmin`) hat unter anderem einen Wechsel
auf Debian „testing" angeboten, eznix-Meldungen gezeigt und ein eigenes
Aktualisierungsmenü gehabt. Es ist eznix-Marketing, nicht RSOS. Ein Ersatz ist
offen (`docs/ROADMAP.md`, Punkt 3).

### XFCE → KDE Plasma

| 1.x (XFCE) | 2.0 (Plasma) |
|---|---|
| `xfce4`, `xfce4-goodies` | `kde-plasma-desktop` |
| `lightdm`, `lightdm-gtk-greeter` | `sddm`, `sddm-theme-breeze` |
| `mousepad` | `kate` |
| `galculator` | `kcalc` |
| `gthumb` | `gwenview` |
| `atril` | `okular` |
| `xarchiver` | `ark` |
| `pavucontrol` | `plasma-pa` |
| `network-manager-gnome` | `plasma-nm` |
| `gnome-system-tools` | `kinfocenter`, `plasma-systemmonitor` |
| `xscreensaver` | KScreenLocker |
| `light-locker` | KScreenLocker |
| `gnome-keyring` | KWallet (`libpam-kwallet5`) |
| `arc-theme`, `numix`, `greybird` | Breeze |

### Debian 12 → 13

* Python 3.11 → 3.13, glibc 2.36 → 2.41
* `libc6`-Umbenennungen (`libpam0g`, `libgcc-s1` bleiben, `t64`-Übergang ist
  abgeschlossen)
* `zulucrypt-gui` und `zulumount-gui` sind aus Debian verschwunden — in 2.0
  nicht mehr enthalten. Verschlüsselte Container macht `cryptsetup` (ist drin).
* `isolinux` liegt weiter in `main`, `syslinux-common` ebenfalls.

### Was aus dem Altbestand weiterverwendet wird

| Datei | Verwendung |
|---|---|
| `assets/wallpapers/Poly*.png` | Wandbilder, jetzt in `config/includes.chroot/usr/share/backgrounds/rsos/` |
| `assets/splash/` | Bootsplash für isolinux/GRUB |
| `assets/calamares-branding/` | Branding-Vorlagen (Live-Kopie liegt in `config/`) |
| `assets/icons/lava-lamp.*`, `sti-install.svg` | Programm-Icons |
| `assets/legacy/launchers/*.desktop` | Vorlagen für Menüeinträge |
| `assets/legacy/eznix-doc/` | Nachschlagewerk zur ursprünglichen Bauweise |
| `assets/legacy/livebuild/live-manual/` | live-build-Handbuch, offline |

### Nicht übernommen

* `eznix-sources-*`-Paketquellen (es waren ohnehin nur Debian-Quellen)
* `misc64/`, `xfce4/`-Anpassungen
* `RSOS_1_Build` (das alte Generator-Skript)
* der `firmwarelists.sh`-Patch
* `ezadmin`

## Prüfpunkte beim ersten Bau

1. Startet das Live-System bis zum SDDM? (live-config muss den Benutzer `rsos`
   automatisch anmelden.)
2. Ist die Sprache deutsch, die Tastatur `de`, die Zeitzone Europe/Berlin?
3. Erkennt Plasma Bildschirm, WLAN und Ton?
4. Startet Calamares aus dem Menü, und installiert es auf BIOS **und** UEFI?
5. Ist nach der Installation das Branding da (GRUB-Eintrag „rsos", os-release,
   Anmeldebildschirm)?
