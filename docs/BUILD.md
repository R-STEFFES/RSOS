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

Ergebnis: `out/rsos-2.0-<datum>-amd64.hybrid.iso`

Die ISO ist *hybrid*: sie bootet von DVD **und** vom USB-Stick.

```bash
sudo dd if=out/rsos-2.0-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
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
Bauwerkzeugen. Der Quellordner wird hereingemountet, gebaut wird drinnen. Der
Container hat root, der Wirtsrechner nicht.

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
xorriso -indev out/rsos-2.0-*.iso -find / -type f 2>/dev/null | head -40

# Bootfähigkeit prüfen (El Torito + EFI)
xorriso -indev out/rsos-2.0-*.iso -report_el_torito as_mkisofs

# Inhalt des Squashfs
unsquashfs -l out/../binary/live/filesystem.squashfs | head -40
```

`scripts/verify-iso.sh` macht genau das und prüft zusätzlich, ob Kernel,
Initramfs, Squashfs und Bootloader vorhanden sind.

Zum echten Hineinschauen (nur mit root):

```bash
sudo mount -o loop,ro out/rsos-2.0-*.iso /mnt/iso
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
│   ├── vmlinuz           Kernel
│   ├── initrd.img        Initramfs mit live-boot
│   └── filesystem.squashfs   das komplette System, xz-komprimiert
├── boot/
│   ├── grub/             GRUB für BIOS und EFI
│   └── isolinux/         BIOS-Bootmenü (nur wenn syslinux gewählt)
├── .disk/info            Datenträgerkennung
└── md5sum.txt            Prüfsummen
```

---

## Wenn etwas schiefgeht

| Symptom | Ursache | Abhilfe |
|---|---|---|
| `lb: command not found` | live-build fehlt | `sudo apt install live-build` oder `scripts/toolchain.sh` |
| `debootstrap` bricht mit `tar failed` ab | gid-Mapping (siehe oben) | `TAR_OPTIONS=--no-same-owner` oder mit root bauen |
| `newuidmap ... Operation not permitted` | Sandkasten/Container ohne Rechte | Weg 1 oder 2 nehmen |
| Abbruch bei `apt-get install` im Chroot | Netz oder Paketname falsch | `scripts/check-packages.sh` prüfen lassen |
| ISO startet nicht im UEFI | `grub-efi`-Teil fehlt | `--bootloaders "grub-efi"` in `auto/config` prüfen |
| Bau bleibt bei „Mounting /proc" hängen | alter Chroot noch gemountet | `sudo lb clean`, dann erneut |
| Kein Platz mehr | ~9 GB pro Bau | `sudo lb clean --purge`, `out/` leeren |

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

* Die Konfiguration ist vollständig, aber **noch nicht gebaut**.
* Alle 204 Paketnamen sind gegen den trixie-Index geprüft
  (`scripts/check-packages.sh`): alle vorhanden. Entfernt wurden nur
  `zulucrypt-gui`/`zulumount-gui`, die es in trixie nicht mehr gibt.
* Der rootless-Weg ist auf diesem Rechner bis zur Paket-Extraktion geprüft und
  scheitert dort an den GIDs (siehe oben) — er ist dokumentiert, aber nicht der
  empfohlene Weg.
* Ein vollständiger Bau mit ISO ist noch nicht gelaufen. Der erste Bau braucht
  `sudo` (Weg 1) oder den Container (Weg 2).
