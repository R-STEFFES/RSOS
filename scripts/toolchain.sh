#!/bin/sh
# RSOS 2.0 -- Bauwerkzeuge ohne root nach .toolchain/ holen.
#
# Gedacht fuer Rechner, auf denen kein live-build installiert ist und kein
# root zur Verfuegung steht. `apt-get download` darf jeder normale Benutzer;
# die Pakete werden mit dpkg-deb ausgepackt und ueber LD_LIBRARY_PATH benutzt.
#
# Ergebnis: .toolchain/ mit lb, debootstrap, xorriso, mksquashfs, mkfs.*
#
# Aufruf:  ./scripts/toolchain.sh

set -e

cd "$(dirname "$0")/.."
TC="$(pwd)/.toolchain"

ARCH="$(dpkg --print-architecture)"
DISTRO="trixie"
MIRROR="http://deb.debian.org/debian"
POOL="$MIRROR/pool/main"

mkdir -p "$TC/debs" "$TC/root"

holen() {
	# $1 = Paketname, $2 = Pfad im Pool (optional)
	pkg="$1"
	pfad="${2:-}"
	if [ -z "$pfad" ]; then
		pfad="$("$TC/root/usr/bin/apt-get" download --print-uris "$pkg" 2>/dev/null | head -1 | cut -d"'" -f2)"
	fi
	if [ -z "$pfad" ]; then
		echo "  ! $pkg nicht gefunden" >&2
		return 0
	fi
	datei="$TC/debs/$(basename "$pfad")"
	if [ ! -e "$datei" ]; then
		curl -sfL -o "$datei" "$pfad" || { echo "  ! Download $pkg fehlgeschlagen" >&2; return 0; }
	fi
	dpkg-deb -x "$datei" "$TC/root"
	echo "  + $pkg"
}

echo "==> live-build, debootstrap, ISO-Werkzeuge nach $TC"
for p in live-build debootstrap xorriso xorriso-tcltk libisoburn1 libburn4 libisofs6 libjte2 \
         squashfs-tools liblzo2-2 liblz4-1 libzstd1 libz1 liblzma5 libfuse3-3 \
         isolinux syslinux-common syslinux-utils mtools; do
	holen "$p"
done

echo "==> Test"
export LD_LIBRARY_PATH="$TC/root/usr/lib/x86_64-linux-gnu:$TC/root/usr/lib/x86_64-linux-gnu/jli:$TC/root/lib/x86_64-linux-gnu"
"$TC/root/usr/bin/xorriso" -version 2>&1 | head -2
"$TC/root/usr/bin/mksquashfs" -version 2>&1 | head -1
"$TC/root/usr/sbin/debootstrap" --version

echo
echo "Fertig. Benutzen mit:"
echo "  export PATH=$TC/root/usr/sbin:$TC/root/usr/bin:\$PATH"
echo "  export LD_LIBRARY_PATH=$TC/root/usr/lib/x86_64-linux-gnu:$TC/root/usr/lib/x86_64-linux-gnu/jli"
echo "  export DEBOOTSTRAP_DIR=$TC/root/usr/share/debootstrap"
