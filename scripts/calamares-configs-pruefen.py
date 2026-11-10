#!/usr/bin/env python3
"""Unsere Calamares-Modulkonfigurationen gegen die Schemas des Pakets pruefen.

WARUM
-----
Calamares bringt zu jedem Modul ein Schema mit
(`/usr/lib/<arch>/calamares/modules/<name>/<name>.schema.yaml`). Die Konfiguration
muss dazu passen. Passt sie nicht, verwirft Calamares sie **still** und arbeitet
mit Vorgaben weiter -- im Protokoll steht dann nur eine beilaeufige Warnung.

Genau daran ist die RSOS-Installation zweimal gescheitert: `mount.conf` enthielt
`options: bind` statt `options: [ bind ]` und einen unbekannten Schluessel. Die
Folge war, dass `/dev`, `/proc` und `/sys` nie ins Zielsystem eingebunden wurden
-- und der Bootloader-Schritt brach ab mit

    grub-install: error: cannot find a device for /boot/grub (is /dev mounted?)
    -> Rueckgabewert 1

Dieses Skript prueft alle unsere Modulkonfigurationen gegen die Schemas und
meldet jede Abweichung mit Pfad.

Aufruf (im Container, mit dem gebauten System als Wurzel):

    docker run --rm -v rsos-build-work:/work -v "$PWD":/src:ro rsos-build:2.0 \\
      bash -c 'apt-get install -y -qq python3-jsonschema python3-yaml >/dev/null 2>&1
               python3 /src/scripts/calamares-configs-pruefen.py /work/chroot'

Rueckgabewert 0 = alles in Ordnung, 1 = mindestens eine Abweichung.
"""

import sys
from pathlib import Path

try:
    import yaml
    from jsonschema import Draft7Validator
except ImportError as fehler:
    raise SystemExit(
        f"Es fehlt eine Bibliothek: {fehler}\n"
        "Im Container nachinstallieren: apt-get install -y python3-jsonschema python3-yaml")

HIER = Path(__file__).resolve().parent.parent
UNSERE = HIER / "config/includes.chroot/etc/calamares/modules"

SUCHORTE = [
    "usr/lib/x86_64-linux-gnu/calamares/modules",
    "usr/lib/calamares/modules",
    "usr/share/calamares/modules",
]


def schema_finden(wurzel, name):
    for ort in SUCHORTE:
        pfad = wurzel / ort / name / f"{name}.schema.yaml"
        if pfad.is_file():
            return pfad
    return None


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    wurzel = Path(sys.argv[1])
    if not (wurzel / "etc").is_dir():
        raise SystemExit(f"Das sieht nicht nach einem Zielsystem aus: {wurzel}")

    geprueft = uebersprungen = fehler = 0

    for conf in sorted(UNSERE.glob("*.conf")):
        name = conf.stem
        schema = schema_finden(wurzel, name)
        if schema is None:
            print(f"–  {name}: kein Schema im System (uebersprungen)")
            uebersprungen += 1
            continue

        try:
            daten = yaml.safe_load(conf.read_text(encoding="utf-8"))
            regeln = yaml.safe_load(schema.read_text(encoding="utf-8"))
        except Exception as ausnahme:
            print(f"✗  {name}: nicht lesbar -- {ausnahme}")
            fehler += 1
            continue

        abweichungen = sorted(Draft7Validator(regeln).iter_errors(daten),
                              key=lambda e: list(e.path))
        if abweichungen:
            fehler += 1
            print(f"✗  {name}: {len(abweichungen)} Abweichung(en) vom Schema")
            for e in abweichungen:
                stelle = "/".join(str(t) for t in e.path) or "(Wurzel)"
                print(f"     {stelle}: {e.message}")
        else:
            print(f"✓  {name}")
            geprueft += 1

    print()
    print(f"{geprueft} in Ordnung, {fehler} mit Abweichungen, {uebersprungen} ohne Schema")
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())
