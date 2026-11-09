# RSOS

**Debian-basiertes Linux-Image von Steffes Industries** — schlank, aber voll
funktionsfähig. Kein Remaster mit angeklebten Skripten, sondern ein eigenes
Image aus dem Debian-Baukasten (`live-build`).

* Website: https://steffes.industries/
* Bauherr: Raphael Steffes / Steffes Industries
* Lizenz: GPL-3.0 (siehe `LICENSE`)

## Version

| | |
|---|---|
| Aktuell im Repo | **2.0** (siehe `VERSION`) |
| Debian-Basis | **13 „trixie"** |
| Desktop | **KDE Plasma 6.3** (minimal: `kde-plasma-desktop`, kein `kde-full`) |
| Architektur | amd64 |
| Installer | Calamares (angepasstes Branding) |
| Paketquellen | ausschließlich orginale Debian-Repos, keine eigenen Quellen |
| Vorgänger | 1.08/1.09 „Hannah" auf Debian 12 mit XFCE |

Geplanter Nachfolger der 1.x-Reihe. Der Umstieg auf KDE Plasma ist der Kern
der 2.0 (Begründung siehe `docs/ROADMAP.md`), ebenso der Wechsel von Debian 12
auf Debian 13.

## Aufbau

```
.
├── auto/                     # Einstiegspunkte für live-build (config, build, clean)
├── config/                   # die eigentliche Systemdefinition
│   ├── package-lists/        #   welche Pakete ins Image
│   ├── hooks/normal/         #   Anpassungen im Chroot, die kein Paket erledigen kann
│   ├── includes.chroot/      #   Dateien, die 1:1 ins System kopiert werden
│   │   ├── etc/calamares/    #     Installer-Konfiguration + Branding
│   │   ├── etc/skel/.config/ #     Desktop-Voreinstellungen für neue Nutzer
│   │   ├── usr/local/bin/    #     eigene Werkzeuge (rsos-admin u. a.)
│   │   └── usr/share/...     #     Hintergründe, Icons, .desktop-Dateien
│   └── bootloaders/          # Bootsplash und Bootmenü
├── assets/                   # Rohmaterial: Logo, Wallpaper, Slides, Altbestand
├── scripts/                  # Bauskripte (Host, Container, rootless)
├── docs/                     # Bauanleitung, Roadmap, Migration
└── VERSION                   # Versionsnummer, eine Zeile
```

`config/` ist die einzige Quelle der Wahrheit: beide Bauwege (live-build und
der rootless-Weg) lesen dieselben Paketlisten und dasselbe `includes.chroot`.

## Bauen (ohne virtuelle Maschine)

Drei Wege, keiner braucht einen Hypervisor. Die Langfassung mit allen
Fallstricken steht in **[`docs/BUILD.md`](docs/BUILD.md)**.

```bash
# 1) auf dem eigenen Rechner -- der uebliche Weg, braucht einmal das Passwort
sudo apt install live-build debootstrap squashfs-tools xorriso \
                 isolinux syslinux-common grub-efi-amd64-bin grub-pc-bin
./scripts/build.sh

# 2) im Container -- kein root auf dem Wirt, aber ein laufender Docker-Daemon
./scripts/container/build.sh

# 3) ohne root und ohne Docker -- User-Namespace, mit Einschraenkungen
./scripts/toolchain.sh && ./scripts/build-rootless.sh
```

Weg 4 ist GitHub Actions: `.github/workflows/build-iso.yml` baut auf einem
Wegwerf-Runner und legt die ISO als Artefakt ab.

`live-build` entpackt das Basissystem per `debootstrap` in einen Ordner,
mountet dort `/proc`, `/sys` und `/dev`, installiert im Chroot die Pakete und
presst das Ergebnis zu `filesystem.squashfs` und daraus eine hybride ISO. Das
ist genau der Weg „in einen Ordner bauen und zur ISO machen" — ein Hypervisor
wird dafür nicht gebraucht. Näheres und die Alternativen (Container, rootless
im User-Namespace, GitHub Actions) in `docs/BUILD.md`.

## Was in 2.0 nicht mehr drin ist

Die 1.x-Versionen trugen eine komplette XFCE-Sitzung samt eznix-Vollausstattung
(zwei Büro-Suiten, CD-Brennprogramme, `clonezilla`, `dosbox` …). 2.0 ist
bewusst kleiner: ein KDE Plasma, ein Browser, eine Büro-Suite, Multimedia und
Werkzeuge. Alles Weitere installiert der Nutzer über `plasma-discover`.
