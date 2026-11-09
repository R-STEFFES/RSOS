# Plasma-Aussehen festlegen

Plasma speichert sein Aussehen nicht in einer Datei, sondern in mehreren
Dateien unter `~/.config` — Panel-Aufbau, Widgets, Farbschema, Wandbild,
Fensterecken. Diese Dateien kann man nicht sinnvoll von Hand erfinden: sie
entstehen nur, wenn jemand Plasma einmal einrichtet.

Deshalb dieser Ablauf, statt geratener Konfiguration:

## 1. Bauen und starten

```bash
./scripts/build.sh
```

Die ISO in einer VM oder auf einem Testrechner starten (für den Test reicht
VirtualBox, QEMU oder ein alter Laptop — fürs *Bauen* braucht es keine VM).

## 2. Einrichten

Auf dem laufenden System:

* Panel: Position, Höhe, Widgets (Anwendungsstarter, Aufgabenleiste, Uhr,
  Systemabschnitt, Arbeitsflächen)
* Farbschema: Breeze mit Cyan-Akzent (`#00E5FF`)
* Wandbild aus `/usr/share/backgrounds/rsos/`
* Anmeldebildschirm: Breeze
* Fensterdekoration: Breeze
* Schrift: Noto Sans, 10 pt

## 3. Abziehen

```bash
./scripts/capture-kde-config.sh
```

Das Skript kopiert die relevanten Dateien nach
`config/includes.chroot/etc/skel/.config/`. Sie landen damit im Image und
gelten für jeden neu angelegten Benutzer.

## 4. Aufräumen und committen

**Vor dem Commit prüfen:**

* keine persönlichen Pfade (`/home/<name>/…`)
* keine Benutzernamen, keine Rechnernamen
* keine Zugangsdaten, keine WLAN-Schlüssel, keine Passwort-Hashes
* keine Verweise auf Testgeräte (Bildschirmauflösung, GPU-Kennung)

```bash
git diff config/includes.chroot/etc/skel/.config/
git commit -am "Plasma-Layout aus Referenzlauf übernommen"
```

## Was wohin gehört

| Datei | Inhalt |
|---|---|
| `kdeglobals` | Farbschema, Schrift, Symbole, Ein-Klick-Öffnen |
| `plasma-org.kde.plasma.desktop-appletsrc` | Panel, Widgets, Wandbild |
| `kwinrc` | Fensterdekoration, Effekte, Arbeitsflächen |
| `kglobalshortcutsrc` | Tastenkürzel |
| `kscreenlockerrc` | Sperrbildschirm |
| `baloofilerc` | Dateiindex (in RSOS abgeschaltet) |
| `color-schemes/` | eigenes Farbschema, falls angelegt |

## Solange nichts abgezogen ist

Im Image liegen nur die Mindestwerte aus
`config/hooks/normal/0400-rsos-plasma.hook.chroot` (Breeze, deutsch,
Ein-Klick-aus, Baloo aus). Plasma startet damit sauber, sieht aber aus wie
Standard-KDE — ohne RSOS-Handschrift. Das ist der Stand, bis ein Referenzlauf
abgezogen und committet ist.
