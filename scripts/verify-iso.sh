#!/bin/sh
# RSOS 2.0 -- ISO pruefen, ohne sie zu mounten und ohne root.
#
# Prueft: Dateisystem lesbar, Kernel/Initramfs/Squashfs vorhanden,
# BIOS- und EFI-Booteintrag gesetzt, Squashfs enthaelt ein benutzbares System.
#
#   ./scripts/verify-iso.sh out/rsos-2.0-....iso

set -e

ISO="${1:-}"
if [ -z "$ISO" ] || [ ! -e "$ISO" ]; then
	echo "Aufruf: $0 <iso-datei>" >&2
	exit 2
fi

fehler=0
pruef() {
	if [ "$2" = "0" ]; then
		printf '  [ok]   %s\n' "$1"
	else
		printf '  [FEHLT] %s\n' "$1"
		fehler=$((fehler + 1))
	fi
}

echo "==> $ISO ($(du -h "$ISO" | cut -f1))"

echo "==> Inhalt"
INHALT="$(xorriso -indev "$ISO" -find / -type f 2>/dev/null || true)"
for datei in /live/vmlinuz /live/initrd.img /live/filesystem.squashfs; do
	echo "$INHALT" | grep -qx "$datei"
	pruef "$datei" $?
done

echo "==> Booteintraege"
TORITO="$(xorriso -indev "$ISO" -report_el_torito as_mkisofs 2>/dev/null || true)"
echo "$TORITO" | grep -qi "eltorito"
pruef "El-Torito (BIOS)" $?
if echo "$TORITO" | grep -qi "efi"; then
	pruef "EFI-Bootimage" 0
else
	pruef "EFI-Bootimage" 1
fi

echo "==> Squashfs"
if command -v unsquashfs >/dev/null 2>&1; then
	xorriso -osirrox on -indev "$ISO" -extract /live/filesystem.squashfs \
		/tmp/rsos-pruef.squashfs 2>/dev/null || true
	if [ -e /tmp/rsos-pruef.squashfs ]; then
		LISTE="$(unsquashfs -l /tmp/rsos-pruef.squashfs 2>/dev/null || true)"
		for d in /etc/os-release /usr/bin/plasmashell /usr/bin/sddm /usr/lib/calamares; do
			echo "$LISTE" | grep -qx "squashfs-root$d"
			pruef "Systemdatei $d" $?
		done
		rm -f /tmp/rsos-pruef.squashfs
	fi
else
	echo "  (unsquashfs fehlt, Squashfs-Pruefung uebersprungen)"
fi

echo
if [ "$fehler" -eq 0 ]; then
	echo "ISO sieht vollstaendig aus."
else
	echo "$fehler Pruefung(en) fehlgeschlagen." >&2
	exit 1
fi
