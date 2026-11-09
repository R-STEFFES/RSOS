#!/bin/sh
# RSOS 2.0 -- ISO auf dem eigenen Rechner bauen.
#
# Kein Docker, keine virtuelle Maschine: live-build legt das System in einen
# Ordner (chroot/), installiert dort die Pakete, packt das Ganze als Squashfs
# und schreibt daraus die ISO. Genau der Ablauf, den live-build seit Jahren
# mitbringt -- nur braucht der chroot-Schritt root.
#
#   ./scripts/build.sh              # ISO bauen
#   ./scripts/build.sh --clean      # vorher alles aufraeumen
#   ./scripts/build.sh --purge      # zusaetzlich den Paket-Cache leeren
#
# Ergebnis: RSOS-2.0-Janina-<datum>-amd64.hybrid.iso

set -e

cd "$(dirname "$0")/.."
PROJECT="$(pwd)"

# --- Vorbedingungen --------------------------------------------------------
fehlt=0
for t in lb debootstrap xorriso mksquashfs; do
	if ! command -v "$t" >/dev/null 2>&1; then
		echo "fehlt: $t" >&2
		fehlt=1
	fi
done
if [ "$fehlt" -eq 1 ]; then
	cat >&2 <<'EOF'

Erst die Werkzeuge installieren:

  sudo apt install live-build debootstrap squashfs-tools xorriso \
                   isolinux syslinux-common grub-efi-amd64-bin grub-pc-bin

EOF
	exit 1
fi

# --- Version in den Chroot spiegeln ---------------------------------------
printf '%s\n' "$(cat VERSION)"   > config/includes.chroot/etc/rsos-version
printf '%s\n' "$(cat CODENAME)" > config/includes.chroot/etc/rsos-codename

# --- Bauen -----------------------------------------------------------------
case "${1:-}" in
	--clean)  lb clean ;;
	--purge)  lb clean --purge ;;
esac

# lb build ruft auto/config, dann den Build, dann auto/clean auf.
sudo --preserve-env=HOME lb build

echo
echo "Fertig. ISO(s) in ${PROJECT}/out/"
ls -lh out/ 2>/dev/null || true

# Die ISO zusaetzlich nach ~/Downloads legen -- dort liegen die anderen
# Testimages, und von dort laesst sie sich direkt in der VM auswaehlen.
if [ -d "${HOME}/Downloads" ]; then
	for f in out/*.iso; do
		[ -e "$f" ] || continue
		cp -v "$f" "${HOME}/Downloads/"
	done
fi
