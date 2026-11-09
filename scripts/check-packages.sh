#!/bin/sh
# RSOS 2.0 -- Alle Paketnamen gegen den echten Debian-Index pruefen.
#
# Faengt Tippfehler und inzwischen entfernte Pakete, bevor der Bau 20 Minuten
# spaeter im Chroot abbricht. Prueft main, contrib, non-free und
# non-free-firmware von trixie.
#
#   ./scripts/check-packages.sh

set -e

cd "$(dirname "$0")/.."
PROJECT="$(pwd)"
DISTRO="${DISTRO:-trixie}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
ARCH="${ARCH:-amd64}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Indizes von ${DISTRO} holen"
for area in main contrib non-free non-free-firmware; do
	curl -sfL -o "$TMP/$area.xz" "$MIRROR/dists/$DISTRO/$area/binary-$ARCH/Packages.xz" \
		|| echo "  (kein Index fuer $area)" >&2
done

xzcat "$TMP"/*.xz 2>/dev/null | sed -n 's/^Package: //p' | sort -u > "$TMP/bekannt.txt"
echo "  $(wc -l < "$TMP/bekannt.txt") Pakete im Index"

grep -hvE '^[[:space:]]*(#|$)' "$PROJECT"/config/package-lists/*.list.* \
	| tr ' ' '\n' | tr -d '\r' | sed 's/[[:space:]]//g' | grep -v '^$' \
	| sort -u > "$TMP/gewuenscht.txt"
echo "  $(wc -l < "$TMP/gewuenscht.txt") Pakete in unseren Listen"

FEHLT="$(comm -23 "$TMP/gewuenscht.txt" "$TMP/bekannt.txt")"

if [ -n "$FEHLT" ]; then
	echo
	echo "NICHT IN ${DISTRO} GEFUNDEN:" >&2
	printf '  %s\n' $FEHLT >&2
	echo >&2
	echo "Diese Namen in config/package-lists/ korrigieren oder streichen." >&2
	exit 1
fi

echo
echo "Alle Paketnamen sind in ${DISTRO} vorhanden."
