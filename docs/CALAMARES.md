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

## Noch offen

* Die Bilder der Diashow (`show.qml`, `slide*.png`) sind noch im alten
  lila/orangen Stil. Raphael wollte sie vorerst lassen.
* `welcome.png` und `slide_cs.png` (Willkommensseite) ebenfalls.
* `bootloader.conf` enthält die Pfade `/vmlinuz-linux` und
  `/initramfs-linux.img` — das ist **Debians eigene Vorgabe**, keine
  Arch-Vorlage. Debian korrigiert sie zur Laufzeit über das Modul
  `bootloader-config`. Nicht „aufräumen".
