#!/bin/sh
# RSOS-Bildmarke (STI-Zeichen) als Vektor erzeugen.
#
# Warum ueberhaupt: von der Bildmarke gibt es nur Rasterdateien. Fuer
# Anwendungssymbole -- allen voran das Startzeichen des KDE-Anwendungsstarters
# -- wird ein SVG gebraucht, weil KDE die Farbe ueber "currentColor" an das
# jeweilige Farbschema anpasst. Ein PNG bliebe immer weiss und waere auf einem
# hellen Panel unsichtbar.
#
# Das Skript tastet die Silhouette ab und laesst potrace in einem Container die
# Umrisse nachziehen. potrace laeuft im Container, weil es auf dem Wirt nicht
# installiert ist.
#
# Aufruf:  sh scripts/make-logo-svg.sh
# Ergebnis: assets/brand/monogram_white.svg
set -eu

HIER=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
QUELLE="$HIER/assets/brand/monogram_white.png"
ZIEL="$HIER/assets/brand/monogram_white.svg"
BILD=rsos-build:2.0

if [ ! -f "$QUELLE" ]; then
	echo "Quelldatei fehlt: $QUELLE" >&2
	exit 1
fi

ARBEIT=$(mktemp -d)
trap 'rm -rf "$ARBEIT"' EXIT

# 1) Silhouette auf eine quadratische Flaeche setzen (Rand 8 %).
#    potrace verfolgt schwarze Bereiche, das Logo wird also schwarz auf weiss
#    gezeichnet. "point(...)" bildet den Alphakanal auf schwarz/weiss ab.
python3 - "$QUELLE" "$ARBEIT/silhouette.pbm" <<'PY'
import sys
from PIL import Image

quelle, ziel = sys.argv[1], sys.argv[2]
bild = Image.open(quelle).convert("RGBA")
alpha = bild.split()[3]

kasten = alpha.point(lambda v: 255 if v > 110 else 0).getbbox()
if kasten is None:
    raise SystemExit("Die Bildmarke ist leer -- Alphakanal pruefen.")

zeichen = bild.crop(kasten).convert("RGBA")
rand = int(max(zeichen.size) * 0.08)

flaeche = max(zeichen.size) + 2 * rand
blatt = Image.new("RGBA", (flaeche, flaeche), (0, 0, 0, 0))
blatt.alpha_composite(zeichen, ((flaeche - zeichen.width) // 2,
                                (flaeche - zeichen.height) // 2))

# Verkleinern: potrace arbeitet schneller und die Kurven werden ruhiger.
kante = 1400
blatt = blatt.resize((kante, kante), Image.LANCZOS)

schwarzweiss = blatt.split()[3].point(lambda v: 0 if v > 120 else 255, "L").convert("1")
schwarzweiss.save(ziel)
print(f"Silhouette: {kante}x{kante}, Marke {zeichen.width}x{zeichen.height} (Rand {rand})")
PY

# 2) Umrisse nachziehen (im Container).
docker run --rm -v "$ARBEIT":/arbeit "$BILD" bash -c '
set -eu
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq potrace >/dev/null 2>&1
potrace -s -o /arbeit/roh.svg -u 10 /arbeit/silhouette.pbm
echo "POTRACE-OK"' >"$ARBEIT/lauf.txt" 2>&1

grep -q "POTRACE-OK" "$ARBEIT/lauf.txt" || {
	echo "potrace ist gescheitert:" >&2
	cat "$ARBEIT/lauf.txt" >&2
	exit 1
}

# 3) Aufraeumen: DOCTYPE raus (KDE mag keine externe DTD), Einheiten ohne "pt",
#    Fuellung an das Farbschema binden, Hintergrund transparent halten.
python3 - "$ARBEIT/roh.svg" "$ZIEL" <<'PY'
import re
import sys

roh, ziel = sys.argv[1], sys.argv[2]
text = open(roh, encoding="utf-8").read()

# <svg ...> abschneiden: potrace stellt eine DOCTYPE mit externer DTD voran.
text = text[text.index("<svg"):]
text = text.replace(' width="1400.000000pt" height="1400.000000pt"', '')
text = text.replace('pt"', '"').replace('pt ', ' ')
text = text.replace(' fill="#000000"', '')

# Breeze-Konvention fuer Symbolzeichen: die Farbe kommt aus dem Farbschema.
text = text.replace("<path ", '<path style="fill:currentColor" ', 1)
text = re.sub(r'\n\s*\n', '\n', text)

kopf = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!-- RSOS-Bildmarke (STI-Zeichen), Vektor. Erzeugt von\n'
    '     scripts/make-logo-svg.sh aus assets/brand/monogram_white.png.\n'
    '     Die Fuellung ist currentColor, die Farbe kommt vom KDE-Farbschema.\n'
    '     Achtung: in XML-Kommentaren sind zwei Bindestriche hintereinander\n'
    '     verboten, deshalb steht hier kein Gedankenstrich. -->\n'
)
open(ziel, "w", encoding="utf-8").write(kopf + text)
print("SVG geschrieben:", ziel)
PY

grep -c "currentColor" "$ZIEL" >/dev/null
echo "Fertig: $ZIEL ($(wc -c <"$ZIEL") Bytes)"
