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

## Fallstrick 3 — `grub-pc` muss im Live-System liegen

Debians Helfer `/usr/share/calamares/helpers/calamares-bootloader-config` ruft
beim Installieren im Zielsystem auf:

```bash
if [ -d /sys/firmware/efi/efivars ]; then
    chroot $CHROOT apt-get -y install grub-efi      # UEFI
else
    chroot $CHROOT apt-get -y install grub-pc       # BIOS
fi
```

Die RSOS-ISO bringt **keinen Paketpool** mit, und im Ziel gibt es keine
Netzquelle — ohne die Pakete bricht die Installation mit einem Fehler zu
`grub-pc` ab. Deshalb stehen `grub-pc`, `grub-efi` und `efibootmgr` in
`config/package-lists/00-base.list.chroot`.

Nachgemessen: ist `grub-pc` bereits installiert, liefert
`apt-get install -y grub-pc` auch **ganz ohne Paketlisten** `rc=0`
(„already the newest version"). Die Metapakete im Live-System genügen also.

## Hintergrundbild neu erzeugen

```bash
python3 scripts/make-calamares-artwork.py
```

Schreibt `wallpaper.png` (1920×1080) nach `config/includes.chroot/...` und nach
`assets/calamares-branding/...`. Farben und Wortmarke kommen aus
`~/Schreibtisch/Videos/fundus/` (siehe `marke.md`): Grund `#0C0C0C`, Akzent
`#00E5FF`, weiße Wortmarke, Speed-Slash als dünne Cyan-Linie mit Lücke um die
Wortmarke.

## Noch offen

* Die Bilder der Diashow (`show.qml`, `slide*.png`) sind noch im alten
  lila/orangen Stil. Raphael wollte sie vorerst lassen.
* `welcome.png` und `slide_cs.png` (Willkommensseite) ebenfalls.
* `bootloader.conf` enthält die Pfade `/vmlinuz-linux` und
  `/initramfs-linux.img` — das ist **Debians eigene Vorgabe**, keine
  Arch-Vorlage. Debian korrigiert sie zur Laufzeit über das Modul
  `bootloader-config`. Nicht „aufräumen".
