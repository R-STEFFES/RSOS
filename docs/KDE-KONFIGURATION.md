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

## Startzeichen des Anwendungsstarters

Der Knopf links in der Leiste (Widget „Anwendungsstarter") zeigt die
**STI-Bildmarke**. Das lässt sich *nicht* über das Panel-Layout einstellen,
sondern läuft über das Symbolthema:

Das Plasmoid `org.kde.plasma.kickoff` hat in
`contents/config/main.xml` den Eintrag

```xml
<entry name="icon" type="String">
    <default>start-here-kde-symbolic</default>
</entry>
```

und zieht das Symbol aus dem Thema. `start-here-kde-symbolic` zeigt in Breeze
einen Ordner (die Datei ist dort ein Verweis auf `folder-activities.svg`) —
deshalb sieht der Starter standardmäßig nach Ordner aus.

**Umsetzung:** `config/hooks/normal/0450-rsos-icons.hook.chroot` legt das Thema
`RSOS` unter `/usr/share/icons/RSOS/` an. Es erbt
`breeze-dark,breeze,hicolor` und belegt nur die Namen `start-here-kde-symbolic`,
`start-here-kde`, `start-here-kde-plasma`, `start-here` sowie
`org.kde.plasma.kickoff` mit der Bildmarke — alles andere kommt weiter aus
Breeze.

Warum ein eigenes Thema und nicht die Dateien in Breeze ersetzen: Breeze gehört
dem Paket `breeze-icons`. Wer dort hineinschreibt, beschädigt die
Paketintegrität und verliert die Änderung beim nächsten Paket-Update.

**Die Farbe kommt aus dem Farbschema.** Die Bildmarke liegt als SVG mit
`fill:currentColor` vor (Breeze-Konvention), wird also auf einem dunklen Panel
hell und auf einem hellen dunkel. Ein PNG wäre immer weiß und auf hellem
Grund unsichtbar.

**Vorgabe setzen:** `[Icons] Theme=RSOS` steht in
`/etc/skel/.config/kdeglobals` (für neue Konten) und in `/etc/xdg/kdeglobals`
(systemweit, falls `/etc/skel` nicht kopiert wurde).

> ⚠️ **Beim Abziehen des Plasma-Layouts beachten:** `capture-kde-config.sh`
> kopiert `kdeglobals` vom Testrechner. Steht dort `Theme=breeze-dark`, ist das
> Startzeichen danach wieder ein Ordner. Nach dem Abziehen kontrollieren, dass
> die Zeile `Theme=RSOS` erhalten bleibt.

### Die Bildmarke als Vektor

Von der Marke gibt es nur Rasterdateien. `scripts/make-logo-svg.sh` tastet die
Silhouette ab und lässt `potrace` (läuft im Container) die Umrisse nachziehen;
Ergebnis ist `assets/brand/monogram_white.svg`, das als
`usr/share/icons/hicolor/scalable/apps/sti-logo.svg` ins Image geht.

Zwei Fallstricke, die dabei aufgetreten sind:

* In XML-Kommentaren sind **zwei Bindestriche hintereinander verboten** — ein
  Gedankenstrich `--` im Kommentar macht die Datei ungültig, und `rsvg-convert`
  bricht mit `Double hyphen within comment` ab.
* Die Quelldatei sollte **auf ihr Inhaltsrechteck beschnitten** und auf eine
  quadratische Fläche mit Rand gesetzt werden, sonst sitzt die Marke schief im
  Symbol.

## Systemübersicht: neofetch (und fastfetch)

Im Terminal zeigt die Systemübersicht die RSOS-Bildmarke als Blockgrafik —
bei `neofetch` wie bei `fastfetch`.

**neofetch oder fastfetch?** Raphael wollte neofetch. Das Programm wurde 2024
eingestellt und ist aus dem Debian-Archiv **entfernt** — in trixie liefert
`apt-cache policy neofetch` keinen Kandidaten mehr. Es kommt deshalb als
Programm aus dem letzten Debian-Paket (7.1.0-4 aus Debian 12) ins Image:

```bash
sh scripts/fetch-neofetch.sh     # lädt, prüft die Prüfsumme, ergänzt die Marke
```

Das Skript legt `config/includes.chroot/usr/bin/neofetch` ab. Damit kommt
**keine zusätzliche Paketquelle** ins Image — die Datei liegt fest im
Repository, der Bau braucht kein Netz. Zusätzlich bleibt `fastfetch` als
gepflegte Alternative installiert.

| Datei | Zweck |
|---|---|
| `usr/bin/neofetch` | neofetch 7.1.0 mit einem zusätzlichen Fall `"RSOS"` in `get_distro_ascii()` |
| `usr/share/neofetch/ascii-rsos.txt` | die Bildmarke als Blockgrafik, mit neofetch-Platzhaltern `${c1}` |
| `etc/fastfetch/config.jsonc` | Systemvorgabe für fastfetch: Blockgrafik, deutsche Beschriftungen, Cyan |
| `etc/fastfetch/sti-ascii.txt` | dieselbe Grafik für fastfetch, mit ANSI-Farben |
| `scripts/make-neofetch-logo.py` | erzeugt beide Grafiken neu |

Die Blockgrafik wird **nicht von Hand gezeichnet**, sondern abgetastet: das
Skript liest den Alphakanal der Bildmarke, verkleinert ihn auf 64 Zeichen Breite
und setzt je zwei Bildzeilen in ein Blockzeichen um (`▀ ▄ █`). Dadurch stimmt
die Form.

**Der Systemname** kommt in beiden Programmen aus `/etc/os-release` — dort steht
`PRETTY_NAME="RSOS 2.0 Janina"`, und genau das wird angezeigt. Ohne diese Zeile
stünde dort „Debian GNU/Linux 13".

**Warum neofetch die Marke findet, ohne dass etwas eingestellt wird:** neofetch
setzt `ascii_distro` aus `NAME=` der `os-release`, hier also `RSOS`. Der
ergänzte Fall `"RSOS"*)` greift damit von allein. Die Farben (`set_colors 6 7`)
setzen Cyan und Weiß; die Platzhalter `${c1}`/`${c2}` in der Grafik füllt
neofetch selbst.

## Dunkles Farbschema

Raphael wollte ein dunkles System. Gesetzt wird es in
`config/hooks/normal/0400-rsos-plasma.hook.chroot`:

| Datei | Eintrag | Wirkung |
|---|---|---|
| `/etc/skel/.config/kdeglobals` | `ColorScheme=BreezeDark` | neue Konten |
| `/etc/skel/.config/kdeglobals` | `LookAndFeelPackage=org.kde.breezedark.desktop` | Fenster, Leisten, Menüs |
| `/etc/xdg/kdeglobals` | dieselben Werte | auch für Konten ohne eigenen Eintrag (etwa den Live-Benutzer) |

`Breeze` (ohne Zusatz) ist die **helle** Fassung — die stand dort vorher.
Vorhanden sind beide: `/usr/share/color-schemes/BreezeDark.colors` und
`/usr/share/plasma/look-and-feel/org.kde.breezedark.desktop`.

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
