#!/bin/sh
# RSOS 2.0 -- fertiges Abbild pruefen
#
#   ./scripts/pruefe-abbild.sh                      # neueste ISO in out/
#   ./scripts/pruefe-abbild.sh pfad/zur.iso
#
# WARUM
# -----
# Bisher ist jede ausgelieferte ISO vom Nutzer getestet worden, und jedes Mal
# fehlte etwas: falsches Logo, helle Schrift, fehlender Bootloader, doppelte
# Groesse. Ein gruener Skriptlauf sagt nur, dass der Bau nicht abgebrochen ist --
# nicht, dass das Richtige im Abbild steckt.
#
# Dieses Skript sieht in das Abbild HINEIN und prueft die Punkte, die schon
# einmal beanstandet wurden. Es laeuft im Container, weil dort die Werkzeuge
# liegen (unsquashfs, xorriso) und der Wirt sie nicht braucht.
#
# Rueckgabewert 0 = alles gefunden, 1 = mindestens ein Punkt fehlt.

set -e

cd "$(dirname "$0")/.."

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	ENGINE=docker
else
	echo "Docker (mit laufendem Daemon) wird gebraucht." >&2
	echo "Starten:  systemctl --user start docker-desktop" >&2
	exit 1
fi

ISO="${1:-$(ls -t out/*.iso 2>/dev/null | head -1)}"
[ -n "$ISO" ] || { echo "Keine ISO gefunden." >&2; exit 1; }
[ -f "$ISO" ] || { echo "Nicht gefunden: $ISO" >&2; exit 1; }
ISO="$(readlink -f "$ISO")"

echo "==> Pruefe $(basename "$ISO")"
echo "    Groesse: $(du -m "$ISO" | cut -f1) MB"
echo "    SHA512:  $(sha512sum "$ISO" | cut -c1-32)…"
echo

"$ENGINE" run --rm -v "$ISO":/iso:ro rsos-build:2.0 sh -c '
set -e
ISO=/iso

echo "--- Bootstruktur"
if xorriso -indev "$ISO" -report_el_torito as_mkisofs 2>/dev/null | grep -q "eltorito-alt-boot"; then
	echo "    ✓ BIOS und UEFI vorhanden"
else
	echo "    ✗ UEFI-Eintrag fehlt (eltorito-alt-boot)"
fi

mkdir -p /tmp/p && cd /tmp/p
xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs /tmp/p/fs 2>/dev/null

echo "--- Squashfs"
unsquashfs -s /tmp/p/fs 2>/dev/null | grep -i "^Compression" | sed "s/^/    /"

echo "--- Inhalt"
fehlt=0
pruefe() {          # pruefe <beschreibung> <pfad im Abbild> [muster]
	if [ -z "$3" ]; then
		if unsquashfs -cat /tmp/p/fs "$2" >/dev/null 2>&1; then
			echo "    ✓ $1"
		else
			echo "    ✗ $1 -- $2 fehlt"; fehlt=1
		fi
	elif unsquashfs -cat /tmp/p/fs "$2" 2>/dev/null | grep -q "$3"; then
		echo "    ✓ $1"
	else
		echo "    ✗ $1 -- Muster \"$3\" nicht in $2"; fehlt=1
	fi
}

pruefe_nicht() {    # pruefe_nicht <beschreibung> <pfad im Abbild> <muster>
	# Kommentarzeilen ausblenden. Die Datei erklaert in ihren Kommentaren
	# genau den Fehler, den diese Pruefung sucht ("sysfs: Unknown parameter
	# 'nodiscard'") -- eine Suche ueber den ganzen Text schlaegt deshalb
	# immer an und meldet falschen Alarm.
	if unsquashfs -cat /tmp/p/fs "$2" 2>/dev/null | grep -v '^[[:space:]]*#' | grep -q "$3"; then
		echo "    ✗ $1 -- \"$3\" steht in $2"; fehlt=1
	else
		echo "    ✓ $1"
	fi
}

pruefe "Systemversion im os-release"         usr/lib/os-release "RSOS"
pruefe "Beiname Janina"                      usr/lib/os-release "Janina"
pruefe "Standortvorgabe Europe/Berlin"       etc/calamares/modules/locale.conf "Berlin"
pruefe "mount.conf: /dev wird eingebunden"   etc/calamares/modules/mount.conf "device: /dev"
pruefe "mount.conf: /sys wird eingebunden"   etc/calamares/modules/mount.conf "mountPoint: /sys"
# "nodiscard" gehoert NICHT in die Vorgabe: sie gilt auch fuer proc und sys,
# und sysfs verweigert dann das Einhaengen. Eine Suche nach
# "options: [ defaults ]" waere zu unscharf -- die Zeile gibt es auch beim
# Eintrag fuer swap.
pruefe_nicht "mount.conf: kein nodiscard"    etc/calamares/modules/mount.conf "nodiscard"
pruefe "Qt folgt der KDE-Palette"            etc/environment "QT_QPA_PLATFORMTHEME=kde"
pruefe "Wandbild-Autostart vorhanden"        etc/xdg/autostart/rsos-wandbild.desktop
pruefe "Starter heisst RSOS"                 usr/share/applications/calamares-install-debian.desktop "RSOS"
pruefe "Marke als Vektor im Image"           usr/share/icons/hicolor/scalable/apps/sti-logo.svg
pruefe "Eigene Live-Benutzerbezeichnung"     etc/live/config.conf.d/rsos.conf "RSOS Live user"

echo "--- Dateien im Abbild"
# Achtung: unsquashfs -ll zeigt Pfade mit dem Praefix "squashfs-root/".
# Ein Muster wie " usr/bin/x$" greift deshalb nie und meldet falsche Fehlbefunde.
for f in usr/sbin/grub-install usr/sbin/gparted usr/bin/nano usr/bin/fastfetch \
         usr/bin/neofetch usr/share/icons/RSOS/index.theme; do
	if unsquashfs -ll /tmp/p/fs 2>/dev/null | grep -q "squashfs-root/$f$"; then
		echo "    ✓ $f"
	else
		echo "    ✗ $f fehlt"; fehlt=1
	fi
done

echo "--- Pakete"
unsquashfs -cat /tmp/p/fs var/lib/dpkg/status 2>/dev/null > /tmp/p/status
echo "    $(grep -c "^Package: " /tmp/p/status) Pakete"
for p in libreoffice-writer thunderbird kdenlive gimp inkscape xterm \
         audacious transmission-gtk bleachbit filezilla remmina soundconverter; do
	if grep -q "^Package: ${p}$" /tmp/p/status; then
		echo "    ✗ gestrichenes Paket wieder da: $p"; fehlt=1
	fi
done

echo
if [ "$fehlt" = 0 ]; then echo "ERGEBNIS: alles gefunden ✓"; else echo "ERGEBNIS: es fehlt etwas ✗"; fi
exit $fehlt'
