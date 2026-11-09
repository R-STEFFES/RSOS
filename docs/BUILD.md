# RSOS bauen — ohne virtuelle Maschine

Die Frage war: *„Kann ich das nicht einfach in einen Ordner bauen und daraus
eine ISO machen, statt eine VM hochzufahren?"*

Ja. Genau das ist der Normalfall. `live-build` — das Werkzeug, mit dem auch die
1.x-Reihe gebaut wurde — arbeitet so:

```
config/  ──►  chroot/   (debootstrap legt Debian in einen Ordner)
             ├─ Pakete installieren, Hooks ausführen, Dateien kopieren
             └─►  binary/  (Squashfs + Kernel + Bootloader)
                          └─►  *.hybrid.iso
```

Kein Hypervisor, keine VM, kein QEMU. Ein Ordner auf der Platte, ein
`chroot`-Aufruf, am Ende eine Datei. Das ist derselbe Mechanismus, den
`debootstrap` für jede Debian-Installation benutzt.

Die einzige Einschränkung: der `chroot`-Schritt braucht root (oder einen
User-Namespace). Drei Wege, alle ohne VM.

---

## Weg 1 — auf dem eigenen Rechner (empfohlen)

Der klassische, dokumentierte, am besten unterstützte Weg. Root wird nur für
den `chroot` gebraucht, nicht für eine VM.

```bash
sudo apt install live-build debootstrap squashfs-tools xorriso \
                 isolinux syslinux-common grub-efi-amd64-bin grub-pc-bin

cd ~/Schreibtisch/RSOS
./scripts/build.sh            # fragt einmal nach dem Passwort
```

Ergebnis: `out/RSOS-2.0-Janina-<datum>-amd64.hybrid.iso`

Die ISO ist *hybrid*: sie bootet von DVD **und** vom USB-Stick.

```bash
sudo dd if=out/RSOS-2.0-Janina-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

**Zeit und Platz:** erster Bau ~25–45 min auf einer normalen SSD, ~2,5 GB
Download, ~9 GB im Projektordner. Mit gefülltem `cache/` ist der zweite Bau
deutlich schneller.

---

## Weg 2 — im Container (kein root auf dem Wirt)

Wenn `sudo` nicht erlaubt ist, aber Docker oder Podman läuft:

```bash
cd ~/Schreibtisch/RSOS
./scripts/container/build.sh
```

Das Image (`scripts/container/Dockerfile`) ist Debian 13 mit den offiziellen
Bauwerkzeugen. Der Container hat root, der Wirtsrechner nicht.

Der Container läuft bewusst mit `--privileged`: live-build mountet im Chroot
`/proc`, `/sys` und `/dev` und legt dort Gerätedateien an — ohne
`CAP_SYS_ADMIN` bricht der Bau beim ersten Chroot-Schritt ab. Der Container ist
wegwerfbar.

**Gebaut wird in einem Docker-Volume, nicht im hereingebundenen Projektordner.**
Docker Desktop reicht Bind-Mounts aus dem Heimatverzeichnis über virtiofs
herein; im Container erscheinen sie als Dateisystem `fakeowner`, und das kann
nicht, was `debootstrap` beim Auspacken braucht:

```
E: Tried to extract package, but tar failed. Exit...
```

Gegenprobe mit demselben Container: `debootstrap` auf `fakeowner` bricht beim
allerersten Paket ab, in einem nativen Volume (ext4) läuft es durch
(`rc=0`, Debian 13.7, Chroot startet). Das Skript kopiert die Quellen deshalb
ins Volume, baut dort und holt `out/` und `build.log` per tar-Pipeline heraus —
dadurch gehören die Dateien dem angemeldeten Benutzer und nicht `root`.

Optionen:

| Aufruf | Wirkung |
|---|---|
| `./scripts/container/build.sh` | frischer Bau (Arbeitsvolume wird neu angelegt) |
| `... --keep` | Arbeitsvolume behalten — zweiter Lauf spart Bootstrap und Pakete |
| `... --refresh` | Volume behalten, aber geänderte Stufen neu laufen lassen |
| `... --shell` | Shell im Container, Projektordner lesend unter `/src` |
| `... --clean` | Arbeitsvolume wegwerfen |

`--refresh` ist der Weg nach Änderungen an Paketlisten, Includes oder Hooks:
live-build merkt sich erledigte Stufen als Marker in `.build/` und würde sie
sonst überspringen — die Änderung käme nie im Image an. Zurückgesetzt werden
Paketlisten, Paketinstallation, Includes nach der Installation, Hooks und die
ganze Binary-Stufe.

**Erwartung dämpfen:** live-build räumt die Marker der Chroot-Stufe nach einem
erfolgreichen Bau selbst weg. Nach einem *abgeschlossenen* Bau findet
`--refresh` also nichts mehr zum Wiederverwenden und die Paketinstallation
läuft komplett neu. Der Paketcache (`cache/`, rund 2,5 GB) bleibt aber liegen —
es wird nichts erneut heruntergeladen, nur neu entpackt und eingerichtet.
Richtig Zeit spart der Schalter, wenn ein Bau **abgebrochen** ist: dann stehen
die Marker noch und die fertigen Stufen bleiben unangetastet.

### Squashfs-Kompression

Vorgabe ist `xz`: kleinste ISO, aber langsam und speicherhungrig — `mksquashfs`
läuft mit allen Kernen und großen Wörterbüchern. Auf diesem Rechner hat das die
Docker-VM umgebracht (24 GB VM auf einem 31-GB-Wirt, dazu der Seiten-Cache der
800 MB großen Chroot: der Swap des Wirts lief voll, die VM brach mit
`error waiting for container: unexpected EOF` ab).

Umschalten über eine Umgebungsvariable, ohne die Vorgabe zu ändern:

```bash
RSOS_SQUASHFS=zstd ./scripts/container/build.sh
```

`zstd` ist ein Vielfaches schneller und braucht einen Bruchteil des Speichers,
die ISO wird dafür rund 10 Prozent größer (gemessen: 3,3 GB mit `zstd`).
`gzip` liegt dazwischen. Das Ergebnis ist in jedem Fall bootfähig.

Vorteil: reproduzierbar, gleiche Werkzeugversionen auf jedem Rechner.
Nachteil: braucht einen laufenden Docker-Daemon.

---

## Weg 3 — rootless im User-Namespace

Wenn weder root noch Docker da ist. `unshare -Urm` gibt dem Prozess einen
eigenen Namespace, in dem er root *ist* — `chroot`, `mount` und `debootstrap`
funktionieren darin, ohne dass das System Rechte vergibt.

```bash
cd ~/Schreibtisch/RSOS
./scripts/toolchain.sh            # holt lb, debootstrap, xorriso, mksquashfs nach .toolchain/
./scripts/build-rootless.sh       # baut im User-Namespace
```

**Auf diesem Rechner geprüft** (Debian 12, util-linux 2.38, Kernel 6.1):

| Prüfung | Ergebnis |
|---|---|
| `unshare -Urm true` | funktioniert |
| `mount -t tmpfs` im Namespace | funktioniert |
| `mount --bind` im Namespace | funktioniert |
| `chroot /` im Namespace | funktioniert |
| `debootstrap trixie` im Namespace | läuft, scheitert an einem `tar`-Fehler (siehe unten) |
| `mmdebstrap --mode=unshare` | **scheitert** — `newuidmap` darf `uid_map` nicht schreiben |
| `mmdebstrap --mode=root` | **scheitert** — kein `dpkg` im Ziel |

### Warum `debootstrap` abbricht und was hilft

`debootstrap` entpackt die Pakete mit `tar`. Im User-Namespace ist nur
`gid 0` abgebildet; Dateien mit einer anderen Gruppe lassen sich nicht setzen:

```
tar: ./usr/sbin/unix_chkpwd: Kann Datei-Eigentümer nicht zu uid 0, gid 42
     ändern: Das Argument ist ungültig
```

`unix_chkpwd` gehört `root:shadow` (gid 42). Abhilfe:

```bash
export TAR_OPTIONS="--no-same-owner"
```

Dann läuft die Extraktion durch. **Folge:** alle Dateien gehören danach
`root:root`; setgid-Programme der Gruppe `shadow` bekommen `root` als Gruppe.
Für ein Live-Image ist das unkritisch — es ändert aber die Rechte einiger
Passwort-Werkzeuge. Wer das nicht will, nimmt Weg 1 oder 2.

### Warum der rootless-Weg trotzdem nicht bis zur ISO kommt

`--no-same-owner` löst nur die Extraktion. Danach scheitern die
Post-Install-Skripte an derselben Grenze: `passwd` verlangt zwingend eine
Gruppe `shadow` mit **gid 42** (`shadowconfig` prüft das und bricht sonst ab),
`base-files` will `/var/mail` auf `root:mail` (gid 8) setzen. Beides ist im
Single-GID-Namespace nicht abbildbar.

Ein Ausweg wäre, alle Gruppen-IDs im Chroot auf 0 zu ziehen — dann meckert
`passwd` aber genau darüber („Group ID 42 has been allocated for the shadow
group"). Ein vollständiges GID-Mapping (0…65535) bräuchte `newgidmap`, und das
ist hier gesperrt. **Ergebnis: der rootless-Weg trägt auf diesem Rechner keine
komplette ISO.**

### Was auf diesem Rechner zusätzlich nicht geht

* `newuidmap` / `newgidmap` verweigern das Schreiben der Abbildung
  (`write to uid_map failed: Operation not permitted`) — die Umgebung ist
  selbst schon eingeschränkt (bubblewrap-Sandkasten, `CapEff` = 0).
* `mmdebstrap --mode=unshare` hängt daran.
* `mmdebstrap --mode=root` scheitert an einem fehlenden `dpkg` im Zielsystem.
* `docker info` — kein laufender Daemon.

Deshalb ist der praktischste Weg für dieses Projekt **Weg 1** (mit `sudo`) oder
**Weg 4** (GitHub Actions, ohne alles).

---

## Die ISO ohne root ansehen

Man muss nicht mounten, um hineinzuschauen:

```bash
# Inhalt der ISO
xorriso -indev out/RSOS-2.0-Janina-*.iso -find / -type f 2>/dev/null | head -40

# Bootfähigkeit prüfen (El Torito + EFI)
xorriso -indev out/RSOS-2.0-Janina-*.iso -report_el_torito as_mkisofs

# Inhalt des Squashfs
unsquashfs -l binary/live/filesystem.squashfs | head -40
```

`scripts/verify-iso.sh` macht genau das und prüft zusätzlich, ob Kernel,
Initramfs, Squashfs und Bootloader vorhanden sind.

Zum echten Hineinschauen (nur mit root):

```bash
sudo mount -o loop,ro out/RSOS-2.0-Janina-*.iso /mnt/iso
sudo mkdir -p /tmp/rsos && sudo mount -t squashfs -o loop,ro \
     /mnt/iso/live/filesystem.squashfs /tmp/rsos
# ... schauen ...
sudo umount /tmp/rsos /mnt/iso
```

Das ist die „im Ordner mounten"-Idee von Hand. `live-build` macht während des
Baus dasselbe, nur automatisch.

---

## Aufbau der ISO

```
/                     ISO-Wurzel
├── live/
│   ├── vmlinuz                Kernel 6.12 (amd64)
│   ├── initrd.img             Initramfs mit live-boot
│   ├── filesystem.squashfs    das komplette System, zstd-komprimiert
│   └── filesystem.packages    Paketliste der Live-Sitzung
├── isolinux/                  BIOS-Bootmenü (isolinux.bin, isolinux.cfg, boot.cat)
├── EFI/boot/                  UEFI: bootx64.efi, grubx64.efi
├── boot/grub/                 GRUB-Konfiguration
├── .disk/info                 Datenträgerkennung
└── sha512sum.txt              Prüfsummen
```

---

## Wenn etwas schiefgeht

| Symptom | Ursache | Abhilfe |
|---|---|---|
| `lb: command not found` | live-build fehlt | `sudo apt install live-build` oder `scripts/toolchain.sh` |
| `debootstrap` bricht mit `tar failed` ab | gid-Mapping (rootless) **oder** Bind-Mount statt Volume (Container) | `TAR_OPTIONS=--no-same-owner` bzw. Weg 2 mit Arbeitsvolume |
| `newuidmap ... Operation not permitted` | Sandkasten/Container ohne Rechte | Weg 1 oder 2 nehmen |
| `error waiting for container: unexpected EOF` | Docker-VM gestorben, meist Speicher (Squashfs mit xz) | `RSOS_SQUASHFS=zstd`, VM-Speicher senken, Anwendungen schließen |
| Abbruch bei `apt-get install` im Chroot | Netz oder Paketname falsch | `scripts/check-packages.sh` prüfen lassen |
| ISO startet nicht im UEFI | `grub-efi`-Teil fehlt | `--bootloaders "grub-efi"` in `auto/config` prüfen |
| Bau bleibt bei „Mounting /proc" hängen | alter Chroot noch gemountet | `sudo lb clean`, dann erneut |
| Kein Platz mehr | ~12 GB pro Bau | `./scripts/container/build.sh --clean`, `out/` leeren |

---

## In GitHub Actions

`.github/workflows/build-iso.yml` baut bei jedem Tag und auf Knopfdruck. Der
Runner ist eine Wegwerf-VM bei GitHub — für *deinen* Rechner brauchst du keine.
Die fertige ISO liegt danach als Artefakt am Workflow-Lauf.

---

## Weg 4 — GitHub Actions (nichts Lokales nötig)

`.github/workflows/build-iso.yml` baut auf einem Wegwerf-Runner bei GitHub.
Auslösen über *Actions → Build ISO → Run workflow* oder per Tag `v*`. Die ISO
liegt danach als Artefakt am Lauf. Das ist der bequemste Weg, wenn lokal weder
`sudo` noch Docker zur Verfügung stehen — der Runner *ist* die Wegwerf-Maschine,
für deinen Rechner braucht es keine.

---

## Stand

**RSOS 2.0 „Janina" ist gebaut** (2026-11-09). Die ISO liegt in `out/` und
zusätzlich in `~/Downloads`:

```
RSOS-2.0-Janina-20261109-amd64.hybrid.iso    3,3 GB
```

Gebaut im Container (Weg 2) mit `RSOS_SQUASHFS=zstd`. Geprüft wurde:

| Prüfung | Ergebnis |
|---|---|
| Boot-Struktur | isohybrid-MBR, El-Torito, EFI-Image (`/EFI/boot/bootx64.efi`) |
| Kernel / Initramfs | `/live/vmlinuz`, `/live/initrd.img` (6.12.116+deb13-amd64) |
| Squashfs | 3,1 GB, Kompression **zstd** |
| Prüfsumme | `sha512sum.txt` der ISO stimmt mit dem nachgerechneten Wert überein |
| Branding | `PRETTY_NAME="RSOS 2.0 Janina"`, `ID=rsos`, `/etc/rsos-codename` = Janina |

Noch offen:

* **Ein Live-Start in einer VM ist noch nicht gelaufen.** Geprüft ist bisher
  nur der Aufbau der ISO, nicht die laufende Sitzung.
* Plasma-Layout: `scripts/capture-kde-config.sh` muss noch von einem
  Referenzlauf abgezogen werden.
* Hardware-Mindestanforderungen im Calamares stehen noch auf den Werten der
  1.x-Reihe.
* Die ISO ist mit `zstd` 3,3 GB groß. Mit `xz` wären es rund 10 Prozent
  weniger — auf diesem Rechner aber nur mit mehr Speicher für die Docker-VM.

Alle 220 Paketnamen sind gegen den trixie-Index geprüft
(`scripts/check-packages.sh`): alle vorhanden. Entfernt wurden nur
`zulucrypt-gui`/`zulumount-gui`, die es in trixie nicht mehr gibt.

Der rootless-Weg ist auf diesem Rechner bis zur Paket-Extraktion geprüft und
scheitert dort an den GIDs (siehe oben) — er ist dokumentiert, aber nicht der
empfohlene Weg.
