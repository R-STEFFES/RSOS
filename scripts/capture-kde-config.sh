#!/bin/sh
# RSOS 2.0 -- Plasma-Einstellungen von einem eingerichteten System abziehen.
#
# Plasma speichert sein Aussehen (Panel, Widgets, Farbschema, Hintergrund) in
# mehreren Dateien unter ~/.config. Die lassen sich nicht sinnvoll erfinden --
# sie muessen einmal von Hand eingestellt und dann hier abgeholt werden.
#
# Ablauf:
#   1. RSOS einmal bauen und in einer VM oder auf einem Testrechner starten.
#   2. Plasma so einstellen, wie es aussehen soll (Panel, Farbe, Wandbild).
#   3. Dieses Skript auf dem Testrechner ausfuehren.
#   4. Die entstandenen Dateien ins Repo legen und neu bauen.
#
#   ./scripts/capture-kde-config.sh [zielordner]

set -e

ZIEL="${1:-$(dirname "$0")/../config/includes.chroot/etc/skel/.config}"
QUELLE="${HOME}/.config"

mkdir -p "$ZIEL"

# Nur das, was Plasma wirklich fuer das Aussehen braucht.
for datei in \
	kdeglobals \
	kglobalshortcutsrc \
	plasma-org.kde.plasma.desktop-appletsrc \
	plasmashellrc \
	kwinrc \
	kwinrulesrc \
	kglobalshortcutsrc \
	baloofilerc \
	kscreenlockerrc \
	klauncherrc \
	kded5rc \
	plasma-localerc \
	; do
	if [ -e "$QUELLE/$datei" ]; then
		cp -v "$QUELLE/$datei" "$ZIEL/$datei"
	fi
done

# Farbschema, falls selbst angelegt
if [ -d "$QUELLE/color-schemes" ]; then
	mkdir -p "$ZIEL/color-schemes"
	cp -rv "$QUELLE/color-schemes/." "$ZIEL/color-schemes/"
fi

echo
echo "Abgezogen nach: $ZIEL"
echo "Jetzt pruefen: keine persoenlichen Pfade, keine Benutzernamen, keine"
echo "Zugangsdaten in den Dateien. Danach committen und neu bauen."
