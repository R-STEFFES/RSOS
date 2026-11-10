# Calamares in RSOS

Was beim Branding und beim Installer zu beachten ist. Alle Angaben gelten für
**Calamares 3.3** (`calamares-settings-debian` 13.0.13, Debian 13 „trixie").

## Wo was liegt

| Pfad | Inhalt |
|---|---|
| `config/includes.chroot/etc/calamares/branding/rsos/` | Branding: `branding.desc`, `stylesheet.qss`, Bilder, `show.qml` |
| `config/includes.chroot/etc/calamares/settings.conf` | Modulreihenfolge, `branding: rsos` |
| `config/includes.chroot/etc/calamares/modules/` | Modulkonfigurationen |
| `config/includes.chroot/usr/share/applications/calamares-install-debian.desktop` | Starter im Live-System |
| `config/hooks/normal/0500-rsos-calamares.hook.chroot` | schreibt Starter-Einträge um (Absicherung) |
| `scripts/make-calamares-artwork.py` | erzeugt das Hintergrundbild neu |

Vergleichsfassung von Debian im laufenden System:
`/etc/calamares/branding/debian/branding.desc`. Die Paketfassung holt man mit
`apt-get download calamares-settings-debian` und `dpkg-deb -x`.

## Fallstrick 1 — die `style:`-Schlüssel heißen in 3.3 anders

```yaml
style:
   SidebarBackground:        "#0C0C0C"
   SidebarText:              "#FAFAF8"
   SidebarTextCurrent:       "#00E5FF"
   SidebarBackgroundCurrent: "#16181B"
```

Die alten Namen `sidebarBackground`, `sidebarTextSelect`, `sidebarTextHighlight`
werden **still ignoriert**. Die Schrift in der Seitenleiste bleibt dann farblos
und ist bei ungünstigem Farbschema der Sitzung nicht lesbar.

Die Schrittliste in der Seitenleiste lässt sich **nicht** per QSS stylen — sie
hat einen eigenen C++-Delegate und kommt ausschließlich aus diesen vier Werten.
Alles andere (Inhaltsflächen) folgt der Qt-Palette der Sitzung und lässt sich
über `stylesheet.qss` im Branding-Verzeichnis festnageln.

## Fallstrick 2 — der Starter heißt anders, als man vermutet

Das Paket legt `calamares-install-debian.desktop` an, **nicht**
`install-debian.desktop`. Ein Hook, der den falschen Namen sucht, läuft ins
Leere und der Eintrag heißt weiter „Install Debian". Der Hook 0500 sucht
deshalb per Muster (`*calamares*.desktop`, `*install*.desktop`) und schreibt
alle Treffer um.

Als Symbol gibt es `calamares` (aus dem Calamares-Paket) — passend, weil die
Marke kein eigenes Bildzeichen hat.

## Fallstrick 3 — der Bootloader-Helfer ruft `apt` auf

Debians Helfer `/usr/share/calamares/helpers/calamares-bootloader-config` macht
beim Installieren im Zielsystem:

```bash
if [ -d /sys/firmware/efi/efivars ]; then
    chroot $CHROOT apt-get -y install grub-efi      # UEFI
else
    chroot $CHROOT apt-get -y install grub-pc       # BIOS
fi
```

Die RSOS-ISO bringt **keinen Paketpool** mit, und im Ziel gibt es keine
Netzquelle — der Aufruf scheitert, die Installation bricht mit einem Fehler zu
`grub-pc` ab.

**Die Metapakete sind keine Lösung:** `grub-efi-amd64` hat
`Conflicts: grub-pc`. Beide ins Live-System zu legen, lässt schon den **Bau**
scheitern (`E: Unable to correct problems, you have held broken packages`).
Genau das ist einmal passiert.

**Die Lösung:** RSOS überschreibt den Helfer
(`config/includes.chroot/usr/share/calamares/helpers/calamares-bootloader-config`)
und lässt den `apt`-Aufruf weg. Er prüft stattdessen, ob die Bausteine da sind:

| Was | Paket | Ort |
|---|---|---|
| BIOS-Module | `grub-pc-bin` | `/usr/lib/grub/i386-pc` (304 Dateien) |
| UEFI-Module | `grub-efi-amd64-bin` | `/usr/lib/grub/x86_64-efi` (286 Dateien) |
| Werkzeuge | `grub2-common`, `grub-common` | `grub-install`, `grub-mkconfig`, `grub-probe`, `update-grub` |
| EFI-Eintrag | `efibootmgr` | `/usr/bin/efibootmgr` |
| LUKS | `cryptsetup`, `cryptsetup-initramfs`, `keyutils` | Paketliste |

Alle liegen im Live-System und damit in der Zielkopie. Den Bootloader trägt
danach das Calamares-Modul `bootloader` ein — der Helfer war nur für die
Paketinstallation zuständig.

Ändert Debian den Helfer, muss der Ersatz mitgezogen werden: der Vergleich ist
`apt-get download calamares-settings-debian && dpkg-deb -x … `.

## Hintergrundbild neu erzeugen

```bash
python3 scripts/make-calamares-artwork.py
```

Schreibt `wallpaper.png` (1920×1080) nach `config/includes.chroot/...` — der
einzigen maßgeblichen Fassung.

**Wortmarke:** `assets/brand/wordmark_white.png` im Projekt. Das ist die
aktuelle Fassung — „STEFFES" **mager und aufrecht mit Unterstrich**,
„INDUSTRIES" **fett und kursiv mit Überstrich**. Quelle ist
`~/Schreibtisch/STI-Marketing/assets/logo/wordmark_white_scharf_2026-11.png`;
dieselbe Datei benutzen die Produktionsskripte.

**Nicht verwenden:** `Videos/fundus/logo/logo_white.png` und
`LOGO GANZ.png` — dort stehen beide Wörter im selben Gewicht, das ist die alte
Fassung. Ebenfalls nicht verwenden: `wordmark_white.png` aus dem Fundus (zu
niedrig aufgelöst, 318×35).

Farben: Grund `#0C0C0C`, Akzent `#00E5FF`, Speed-Slash als dünne Cyan-Linie mit
Lücke um die Wortmarke.

## Schrift und Grund der Inhaltsflächen

Raphael: „Mach die Schrift in dem Installer weiß und nicht schwarz."

Der Zusammenhang, der dabei wichtig ist — aus der Beschreibung im
Calamares-Beispiel-Branding:

> `productWallpaper` … will **replace the normal solid background on every page**
> of the application. It can be any size and proportion, and **will be tiled** to
> fit the entire window.

Das Wandbild liegt also **hinter** den Seiten. Eine deckende Farbe auf `#mainApp`
verdeckt es — und genau das stand vorher im Stylesheet (weiß auf `#FAFAF8`, Text
schwarz). Ergebnis: weißer Inhalt, kein Bild, schwarze Schrift.

Jetzt gilt in `stylesheet.qss`:

| Element | Wert |
|---|---|
| `#mainApp` | `background: transparent` — das Bild scheint durch |
| Schrift | `#FAFAF8` (hell) |
| Eingabefelder, Knöpfe, Listen | halbdurchsichtiges Dunkel `rgba(12,12,12,0.72)` mit hellem Text |
| Akzent | Cyan `#00E5FF`, bei Knöpfen als Hover und in der Fortschrittsanzeige |

**Nicht** über QSS erreichbar: die Schrittliste links. Sie hat einen eigenen
C++-Delegate; ihre Farben kommen ausschließlich aus den `style:`-Werten in
`branding.desc`.

### Die zweite Ursache: die Farbpalette

Raphael: „Der Hintergrund bei der Partitionierung ist ein fast weißes Feld und
dann bei weißer Schrift."

Die Partitionsseite benutzt eine eigene Ansichtsklasse
(`PartitionView`, ein `QTreeView`) und **zeichnet ihren Grund aus der
Farbpalette** — nicht aus dem Stylesheet. Eine QSS-Regel färbt dort nur die
Schrift.

Und die Palette war hell, obwohl das System dunkel eingestellt war. Grund:

> `ColorScheme=BreezeDark` in der `kdeglobals` genügt **nicht**. Plasma liest
> daraus das Schema; **Qt-Programme** — und Calamares ist eines — holen ihre
> Palette aus den `[Colors:…]`-Gruppen derselben Datei. Fehlen die, gilt die
> helle Standardpalette.

Deshalb nimmt
`config/hooks/normal/0400-rsos-plasma.hook.chroot` die Farbwerte jetzt direkt
aus `/usr/share/color-schemes/BreezeDark.colors` und schreibt sie in die
`kdeglobals` (für `/etc/skel` und `/etc/xdg`) — so bleiben sie richtig, wenn
Debian das Schema ändert. Zusätzlich decken neue QSS-Regeln `PartitionView`,
`QTreeView`, `QListView`, `QTableView` und `QAbstractScrollArea` ab.

> **Kachelung:** Calamares kachelt Bilder, die nicht fenstergroß sind
> (`windowSize: 900px,620px`). Angezeigt wird Raphaels Bild unverändert
> (`wallpaper.png`, 1920×1080). Daneben liegt die auf Fenstergröße gebrachte
> Fassung `wallpaper-fenster.png` (900×620, mittig beschnitten) — sie lässt sich
> in `branding.desc` mit einer Zeile umstellen:
>
> ```yaml
>     productWallpaper:    "wallpaper-fenster.png"
> ```

## Bootloader-Schritt: der `sed`-Fehler bei `/etc/default/grub`

**Meldung während der Installation:**

```
sed: can't read /tmp/calamares-root-67v78vsd/etc/default/grub: No such file or directory
```

**Ursache:** Der Helfer `calamares-bootloader-config` schaltet vor dem Eintragen
des Bootloaders mit `sed` die Suche nach anderen Betriebssystemen ein — in
`${ZIEL}/etc/default/grub`. Diese Datei fehlte aber im Ziel, und zwar aus einem
Grund, der nicht offensichtlich ist:

> `/etc/default/grub` kommt in Debian aus `grub-pc` beziehungsweise `grub-efi`.
> Diese beiden Metapakete **schließen sich gegenseitig aus** (`grub-efi-amd64
> Conflicts: grub-pc`) und liegen deshalb nicht im Image — der Versuch, beide
> vorzuinstallieren, hat den Bau einmal scheitern lassen. Die GRUB-Module und
> Werkzeuge kommen aus `grub-pc-bin`, `grub-efi-amd64-bin` und `grub2-common`;
> die Konfigurationsdatei bringt keines davon mit.

**Behoben doppelt:**

1. `config/includes.chroot/etc/default/grub` liegt jetzt im Live-System und
   damit auch im Ziel (Wartezeit 5 s, `GRUB_DISTRIBUTOR="RSOS"`, `quiet`,
   os-prober an).
2. Der Helfer bricht nicht mehr ab: ist die Datei da, wird nur die
   os-prober-Zeile gesetzt; fehlt sie, legt er sie an. `update-grub` darf
   fehlschlagen — das Modul `bootloader` schreibt die Konfiguration direkt
   danach ohnehin neu.

**Nicht** die Lösung: `grub-pc` und `grub-efi` in die Paketliste aufnehmen
(Konflikt, siehe oben).

## Hintergrundbild

`wallpaper.png` ist das Bild, das Calamares anzeigt — **von Raphael vorgegeben**,
nicht errechnet. Es wird direkt ersetzt, nicht erzeugt.

`scripts/make-calamares-artwork.py` erzeugt eine *alternative* Fassung in den
Markenfarben und schreibt sie bewusst nach `wallpaper-marke.png`, damit sie ein
erneuter Skriptlauf nicht überschreibt.

## Startzeichen des Anwendungsstarters

Siehe `docs/KDE-KONFIGURATION.md` — das Symbol kommt aus dem Symbolthema, nicht
aus dem Branding-Ordner von Calamares.

## grub-install scheitert mit Rückgabewert 1 (BIOS-Modus)

**Meldung:** `grub-install -target=i386-pc --recheck --force /dev/sda` → Fehlercode 1.

Nachgestellt im Container gegen Testplatten — die Ursache ist eindeutig:

| Platte | Ergebnis |
|---|---|
| GPT **mit** BIOS-Startpartition | Erfolg |
| GPT **ohne** BIOS-Startpartition | `warning: this GPT partition label contains no BIOS Boot Partition; embedding won't be possible` → `error: embedding is not possible, but this is required for cross-disk install` → **1** |
| MBR (msdos) | Erfolg |

**Was das heißt:** GRUB braucht im BIOS-Betrieb auf einer GPT-Platte eine kleine,
unformatierte Partition vom Typ `bios_grub` (8 MiB), in die es seinen
Zwischencode schreiben kann. Fehlt sie, bricht die Installation ab — obwohl
`grub-install` vorhanden ist und alle GRUB-Module im Ziel liegen (276 Dateien
unter `/usr/lib/grub/i386-pc`, geprüft).

**Ursache im Testlauf:** Die virtuelle Platte trug noch eine GPT-Tabelle aus
einem früheren Versuch. Calamares legt die BIOS-Startpartition nur an, wenn es
die Partitionstabelle **selbst neu schreibt**.

**Abhilfe:**

* In der VM die Platte vorher leeren bzw. im Installer **„Festplatte löschen"**
  wählen — dann schreibt Calamares die Tabelle neu, samt BIOS-Startpartition.
* Bei **manueller** Partitionierung auf einer GPT-Platte selbst eine 8 MiB
  große, unformatierte Partition mit der Markierung „BIOS-GRUB" anlegen.
* Alternative ohne BIOS-Startpartition: die Platte mit einer **MBR**-Tabelle
  (msdos) versehen oder die VM im **UEFI**-Modus starten (dann wird
  `--target=x86_64-efi` benutzt und eine EFI-Partition gebraucht).

Am Image ist dafür nichts zu ändern — `grub2-common`, `grub-pc-bin` und
`grub-efi-amd64-bin` liegen vollständig drin.

## Diashow-Bilder

Die vier Slides tragen jetzt die aktuelle Wortmarke und deutsche Sprüche statt
der alten grünen Flächen. Erzeugt von `scripts/make-calamares-slides.py`
(1920×1200, wie zuvor), Grundlage sind Ausschnitte aus den Weltraum-Wandbildern
— Installer und Schreibtisch gehören damit sichtbar zusammen.

Sprüche: „Freiheit fängt beim System an." · „Schlank. Schnell. Sauber." ·
„Wir setzen die Standards von morgen." · „Dein System. Deine Regeln."

Die Bildmarke steht als sehr blasses Wasserzeichen rechts; die Wortmarke oben
links mit dem Cyan-Strich darüber. Schrift ist Libre Franklin (Markenvorgabe).

## Noch offen

* `welcome.png` und `slide_cs.png` (Willkommensseite) zeigen einen Laptop mit
  dem alten lila Vieleck-Hintergrund. Die Wortmarke darin ist **korrekt**, nur
  der Hintergrund passt nicht mehr zum Weltraum-Stil. Auf Wunsch ersetzbar.
* `bootloader.conf` enthält die Pfade `/vmlinuz-linux` und
  `/initramfs-linux.img` — das ist **Debians eigene Vorgabe**, keine
  Arch-Vorlage. Debian korrigiert sie zur Laufzeit über das Modul
  `bootloader-config`. Nicht „aufräumen".
