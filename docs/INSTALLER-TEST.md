# Den Installer vorab selbst prüfen (kopflos in QEMU)

Raphael hat die ISO bisher jedes Mal selbst in einer VM getestet und die Fehler
gemeldet. Mit QEMU ohne Bildschirm geht das vorab — man sieht die Seiten und
kann sogar eine vollständige Installation durchspielen, ohne eine grafische
Sitzung zu brauchen.

> ⚠️ **Nicht gleichzeitig mit einem Bau laufen lassen.** Der Wirt hat nur
> ~1 GB Swap; QEMU plus Docker-VM sprengen ihn, die Docker-VM stirbt mitten im
> Bau (`error waiting for container: unexpected EOF`, rc=125). Erst bauen, dann
> testen — oder umgekehrt. Siehe Skill `docker-desktop-builds`.

## 1. Vorbereiten

```bash
mkdir -p /tmp/rsos-qemu && cd /tmp/rsos-qemu
cp ~/Downloads/RSOS-2.0-Janina-<datum>-amd64.hybrid.iso test.iso
qemu-img create -f qcow2 testplatte.qcow2 20G
```

## 2. Starten

```bash
qemu-system-x86_64 -enable-kvm -m 3072 -smp 2 \
  -drive file=/tmp/rsos-qemu/testplatte.qcow2,if=ide,format=qcow2 \
  -cdrom /tmp/rsos-qemu/test.iso -boot d \
  -usb -device usb-tablet \
  -display none -vnc :5 \
  -qmp unix:/tmp/rsos-qemu/qmp,server,nowait \
  -no-reboot
```

Zwei Punkte sind entscheidend:

* **`-usb -device usb-tablet`** — ohne absolutes Zeigegerät landen Klicks
  daneben, weil QMP dann nur relative Bewegungen schicken kann.
* **`-qmp …`** — der einfache Monitor kann nur Tasten senden, keine Klicks auf
  Koordinaten.

`-drive … if=ide` sorgt dafür, dass die Platte im Gast als `/dev/sda` erscheint
— wichtig, weil der BIOS-Zweig von `grub-install` genau das erwartet.

## 3. Bedienen

```bash
python3 scripts/qemu-steuerung.py bild  /tmp/rsos-qemu/s1.ppm
python3 -c "from PIL import Image; Image.open('/tmp/rsos-qemu/s1.ppm').save('/tmp/rsos-qemu/s1.png')"
```

Ablauf, der sich bewährt hat (Bildschirm 1280×800):

| Schritt | Befehl | Anmerkung |
|---|---|---|
| Startmenü bestätigen | `taste ret` | das Menü wartet auf Eingabe |
| ~2 min warten | | Live-System startet (Plasma) |
| Begrüßungsassistent schließen | `taste alt f4` | KDE-eigener Erstlauf-Dialog |
| Installer aufrufen | `taste alt f2` → `tippen rsos` → `taste ret` | KRunner findet „RSOS installieren" |
| Weiter | `klick 999 695` | dreimal: Willkommen → Standort → Tastatur → Partitionen |

Bildschirmkoordinaten (1280×800): „Weiter" liegt bei **(999, 695)**, „Zurück"
bei (921, 695), „Abbrechen" bei (1098, 695), die Seitenleiste beginnt bei
x≈220 (Einträge im Abstand von ~42 px ab y≈195).

## 4. Worauf dabei achten

* **Partitionierungsseite:** Der Bereich mit „Festplatte löschen" / „Manuelle
  Partitionierung" muss dunkel sein. Er ist der **Viewport einer QScrollArea** —
  ein eigenes Kindfenster, das seine Farbe aus der Palette nimmt. War dort fast
  weiß mit weißer Schrift, weil die Qt-Palette hell war (die `[Colors:…]`-Werte
  fehlten in der `kdeglobals`). Behoben in
  `config/hooks/normal/0400-rsos-plasma.hook.chroot` und im Stylesheet.
* **Schrift:** weiß auf dem Hintergrundbild, nicht schwarz.
* **Seitenleiste:** dunkel, aktueller Schritt in Cyan.
* **Startzeichen** links in der Plasma-Leiste: die STI-Bildmarke.
* **Willkommensbild:** trägt die Wortmarke, aber noch den alten lila Hintergrund
  (siehe `docs/CALAMARES.md`, „Noch offen").

## 5. Vollständige Installation (Bootloader prüfen)

Auf der Partitionierungsseite „Festplatte löschen" wählen (`klick 378 163`), dann
Weiter und die Benutzerseite ausfüllen. Wichtig ist das **Ergebnis des
Bootloader-Schritts** — dort ist die Installation dreimal gescheitert:

| Ursache | Meldung |
|---|---|
| `grub-install` fehlte | `grub2-common` war nicht in der Paketliste |
| `grub-install` Rückgabewert 1 | GPT-Platte **ohne BIOS-Startpartition** |

Weil die Testplatte frisch ist, schreibt Calamares die Partitionstabelle selbst
neu — dann legt es die BIOS-Startpartition an und der Schritt läuft durch. Eine
Platte mit einer Tabelle aus einem früheren Versuch lässt ihn scheitern (siehe
`docs/CALAMARES.md`).
