#!/usr/bin/env python3
"""ASCII-Bildmarke fuer fastfetch aus der echten Logoform erzeugen.

Statt ein Logo von Hand zu zeichnen, wird die Silhouette der Bildmarke
abgetastet und in Blockzeichen (Leerzeichen, obere/untere Halbbloecke, voller
Block) umgesetzt. Das ergibt zwei Bildzeilen pro Textzeile und damit eine
erkennbare, kompakte Wiedergabe der tatsaechlichen Form.

Aufruf:  python3 scripts/make-neofetch-logo.py [ausgabe.txt]
"""

import sys
from pathlib import Path

from PIL import Image

HIER = Path(__file__).resolve().parent.parent
QUELLE = HIER / "assets/brand/monogram_white.png"
ZIEL = HIER / "config/includes.chroot/etc/fastfetch/sti-ascii.txt"

# Zwei Ausgabeformate, weil sich die Programme unterscheiden:
#   fastfetch  versteht ANSI-Escapesequenzen im Bild
#   neofetch   erwartet Platzhalter der Form ${c1} und ersetzt sie selbst
#              (siehe get_distro_ascii/print_ascii im Skript)
ZIEL_NEOFETCH = HIER / "config/includes.chroot/usr/share/neofetch/ascii-rsos.txt"
NEOFETCH_FARBE = "${c1}"

# Breite in Textzeichen. Jedes Zeichen deckt 2 Bildzeilen ab.
ZEICHEN_BREITE = 64
# Schwellwert auf dem Alphakanal: ab hier gilt ein Bildpunkt als "Logo".
SCHWELLE = 110

# Markfarbe (Cyan) als ANSI-Truecolor-Escapesequenz.
CYAN = "\033[38;2;0;229;255m"
ENDE = "\033[0m"

BLOCK = {
    (0, 0): " ",
    (1, 0): "\u2580",   # obere Haelfte
    (0, 1): "\u2584",   # untere Haelfte
    (1, 1): "\u2588",   # voller Block
}


def silhhouette_lesen(pfad):
    """Deckende Bildpunkte als Wahrheitsmatrix zurueckgeben."""
    with Image.open(pfad) as bild:
        alpha = bild.convert("RGBA").split()[3]
    return alpha


def auf_breite_bringen(alpha, zeichen_breite):
    """Proportional verkleinern, sodass die Breite in Zeichen passt."""
    breite, hoehe = alpha.size
    px_pro_zeichen = breite / zeichen_breite
    neue_hoehe = hoehe / px_pro_zeichen
    # Ungerade Zeilenzahl aufrunden, damit beide Haelften belegt sind.
    if int(neue_hoehe) % 2:
        neue_hoehe += 1
    return alpha.resize((zeichen_breite, int(neue_hoehe)), Image.LANCZOS)


def in_blockzeichen(alpha):
    """Wahrheitsmatrix in Textzeilen aus Blockzeichen umsetzen."""
    daten = alpha.load()
    breite, hoehe = alpha.size
    zeilen = []
    for oben in range(0, hoehe - 1, 2):
        zeile = []
        for x in range(breite):
            o = daten[x, oben] >= SCHWELLE
            u = daten[x, oben + 1] >= SCHWELLE
            zeile.append(BLOCK[(int(o), int(u))])
        zeilen.append("".join(zeile))
    return [z.rstrip() for z in zeilen]


def main():
    quelle = Path(sys.argv[1]) if len(sys.argv) > 1 else QUELLE
    ziel = Path(sys.argv[2]) if len(sys.argv) > 2 else ZIEL

    if not quelle.exists():
        raise SystemExit(f"Quelldatei fehlt: {quelle}")

    alpha = silhhouette_lesen(quelle)
    klein = auf_breite_bringen(alpha, ZEICHEN_BREITE)
    zeilen = in_blockzeichen(klein)

    # Leerzeilen am Rand entfernen, damit das Logo buendig sitzt.
    while zeilen and not zeilen[0].strip():
        zeilen.pop(0)
    while zeilen and not zeilen[-1].strip():
        zeilen.pop()

    inhalt = "\n".join(f"{CYAN}{z}{ENDE}" if z.strip() else "" for z in zeilen)
    ziel.parent.mkdir(parents=True, exist_ok=True)
    ziel.write_text(inhalt + "\n", encoding="utf-8")
    print(f"geschrieben: {ziel}  (fastfetch, ANSI-Farben)")

    # Dieselbe Grafik fuer neofetch: jede Zeile bekommt den Platzhalter voran,
    # den neofetch selbst durch die Farbe ersetzt.
    neofetch = "\n".join(f"{NEOFETCH_FARBE}{z}" if z.strip() else "" for z in zeilen)
    ZIEL_NEOFETCH.parent.mkdir(parents=True, exist_ok=True)
    ZIEL_NEOFETCH.write_text(neofetch + "\n", encoding="utf-8")
    print(f"geschrieben: {ZIEL_NEOFETCH}  (neofetch, Platzhalter {NEOFETCH_FARBE})")

    print(f"{len(zeilen)} Zeilen, ZEICHEN_BREITE Zeichen breit".replace("ZEICHEN_BREITE", str(ZEICHEN_BREITE)))
    print()
    for z in zeilen:
        print(z)


if __name__ == "__main__":
    main()
