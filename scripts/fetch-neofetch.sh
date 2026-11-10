#!/bin/sh
# neofetch ins Projekt holen und um die RSOS-Bildmarke ergaenzen.
#
# WARUM UEBERHAUPT VON HAND
# -------------------------
# Raphael will neofetch. In Debian 13 (trixie) gibt es das Paket nicht mehr:
# das Programm wurde 2024 eingestellt und aus dem Archiv entfernt
# ("apt-cache policy neofetch" liefert keinen Kandidaten). Das letzte
# Debian-Paket ist neofetch 7.1.0-4 aus Debian 12 (bookworm).
#
# Damit der Bau OHNE NETZ auskommt und trotzdem nachvollziehbar bleibt, wird
# das Programm hier EINMAL heruntergeladen, gegen eine feste Pruefsumme
# geprueft, um unsere Bildmarke ergaenzt und dann ins Projekt gelegt
# (config/includes.chroot/usr/bin/neofetch). Von da an liegt es im Repository
# und wird beim Bauen nur noch kopiert -- es kommt KEINE zusaetzliche
# Paketquelle ins Image.
#
# Aufruf:  sh scripts/fetch-neofetch.sh
set -eu

HIER=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ZIEL="$HIER/config/includes.chroot/usr/bin/neofetch"
KUNST="$HIER/config/includes.chroot/usr/share/neofetch/ascii-rsos.txt"

PAKET_URL="http://deb.debian.org/debian/pool/main/n/neofetch/neofetch_7.1.0-4_all.deb"
PAKET_SHA256="977499a6860467a709c68ec278bdce2c837a23ddc6fc5bd6039f5777757244aa"

ARBEIT=$(mktemp -d)
trap 'rm -rf "$ARBEIT"' EXIT

if [ ! -f "$KUNST" ]; then
	echo "Die Blockgrafik fehlt: $KUNST" >&2
	echo "Zuerst erzeugen:  python3 scripts/make-neofetch-logo.py" >&2
	exit 1
fi

echo "Lade $PAKET_URL"
curl -fsSL -o "$ARBEIT/neofetch.deb" "$PAKET_URL"

echo "$PAKET_SHA256  $ARBEIT/neofetch.deb" | sha256sum -c - >/dev/null 2>&1 || {
	echo "FEHLER: die Pruefsumme des Pakets stimmt nicht -- Abbruch." >&2
	exit 1
}
echo "Pruefsumme stimmt (neofetch 7.1.0-4 aus Debian 12)"

dpkg-deb -x "$ARBEIT/neofetch.deb" "$ARBEIT/entpackt"
QUELLE="$ARBEIT/entpackt/usr/bin/neofetch"
[ -f "$QUELLE" ] || { echo "FEHLER: neofetch nicht im Paket gefunden." >&2; exit 1; }

mkdir -p "$(dirname "$ZIEL")"

python3 - "$QUELLE" "$ZIEL" <<'PY'
import sys

quelle, ziel = sys.argv[1], sys.argv[2]
text = open(quelle, encoding="utf-8").read()

ANKER = '    case $(trim "$ascii_distro") in\n'
if ANKER not in text:
    raise SystemExit("Ankerpunkt nicht gefunden -- neofetch wurde veraendert?")

EIGENER_FALL = '''    case $(trim "$ascii_distro") in
        # --- RSOS ---------------------------------------------------------------
        # Von RSOS ergaenzt (scripts/fetch-neofetch.sh). "RSOS" ist der Name aus
        # NAME= in /etc/os-release; neofetch setzt ascii_distro daraus selbst,
        # deshalb greift dieser Fall ohne weitere Einstellung.
        #
        # Die Bildmarke liegt als Blockgrafik in
        # /usr/share/neofetch/ascii-rsos.txt und wird von
        # scripts/make-neofetch-logo.py aus der Silhouette der Marke erzeugt.
        # Die Platzhalter ${c1} und ${c2} fuellt neofetch weiter unten mit den
        # Farben aus set_colors.
        "RSOS"*)
            set_colors 6 7
            if [[ -r /usr/share/neofetch/ascii-rsos.txt ]]; then
                ascii_data="$(< /usr/share/neofetch/ascii-rsos.txt)"
            else
                ascii_data="  RSOS"
            fi
            ;;
'''

kopf = '''#!/usr/bin/env bash
#
# neofetch 7.1.0 -- unveraendert uebernommen aus dem Debian-Paket
# neofetch 7.1.0-4 (Debian 12 "bookworm"; Pruefsumme des Pakets siehe
# scripts/fetch-neofetch.sh). In Debian 13 gibt es das Programm nicht mehr.
#
# Einzige Aenderung von RSOS: in get_distro_ascii() steht ein zusaetzlicher
# Fall "RSOS", der die Bildmarke aus /usr/share/neofetch/ascii-rsos.txt laedt.
#
# Lizenz: Expat (MIT), siehe /usr/share/doc/neofetch/copyright
'''

text = text.replace(ANKER, EIGENER_FALL, 1)

# Eigene Kopfzeile vor die vorhandene Shebang-Zeile setzen.
if text.startswith("#!"):
    text = text.split("\n", 1)[1]
text = kopf + text

open(ziel, "w", encoding="utf-8").write(text)
print(f"geschrieben: {ziel}")
PY

chmod 755 "$ZIEL"
echo "Fertig: $ZIEL ($(wc -c <"$ZIEL") Bytes)"

grep -q '"RSOS"\*)' "$ZIEL" && echo "RSOS-Fall vorhanden" || {
	echo "FEHLER: der RSOS-Fall wurde nicht eingefuegt." >&2; exit 1; }

rm -f "$ARBEIT/neofetch.deb"
