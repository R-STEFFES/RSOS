#!/bin/sh
# RSOS 2.0 -- Standard-Wandbild beim ersten Anmelden setzen
#
# WARUM ES DIESES SKRIPT BRAUCHT
# ------------------------------
# Eigentlich sollte das Look-and-Feel-Paket den Standard-Hintergrund setzen:
# /usr/share/plasma/look-and-feel/org.kde.rsos.desktop/contents/defaults enthaelt
#     [Wallpaper]
#     Image=/usr/share/wallpapers/RSOS-Weltraum/contents/images/weltraum-1.png
# genau wie KDEs Breeze Dark dort "Image=Next" stehen hat.
#
# Im kopflosen QEMU-Test griff das aber nicht: Plasma wendet ein Look-and-Feel
# nur an, wenn die Konfiguration des Benutzers noch leer ist. RSOS legt
# ~/.config/kdeglobals schon mit an (dunkles Farbschema samt Farbwerten,
# Symbolthema) -- Plasma haelt den Benutzer damit fuer fertig eingerichtet und
# laesst das Paket liegen. Ergebnis: Es blieb bei KDEs lila Standardbild.
#
# Statt auf dieses Verhalten zu bauen, setzt dieses Skript das Bild einmal
# selbst. Danach merkt es sich das und fasst nichts mehr an -- waehlt der
# Benutzer spaeter ein anderes Bild, bleibt seine Wahl erhalten.

set -e

MARKE="${HOME}/.config/rsos-wandbild-gesetzt"
BILD=/usr/share/backgrounds/rsos/weltraum/weltraum-1.png

# Schon erledigt -> nichts tun (die Wahl des Benutzers nicht ueberschreiben)
[ -e "${MARKE}" ] && exit 0
[ -r "${BILD}" ] || exit 0

command -v plasma-apply-wallpaperimage >/dev/null 2>&1 || exit 0

# Plasma braucht einen Moment, bis die Arbeitsflaeche steht
sleep 3

if plasma-apply-wallpaperimage "${BILD}" >/dev/null 2>&1; then
	mkdir -p "$(dirname "${MARKE}")"
	touch "${MARKE}"
fi

exit 0
