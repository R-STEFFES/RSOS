#!/bin/sh
# RSOS 2.0 -- Bauen ohne root und ohne VM (User-Namespace)
#
# Auf Rechnern, auf denen `sudo` nicht erlaubt ist: der ganze Bau laeuft in
# einem User-Namespace, in dem wir root *sind* -- chroot, mount und debootstrap
# funktionieren darin. Geprueft auf Debian 12 mit util-linux 2.38.
#
#   ./scripts/build-rootless.sh            # ISO bauen
#   ./scripts/build-rootless.sh --clean    # vorher aufraeumen
#
# Zwei Eigenheiten, die du kennen musst:
#
# 1. TAR_OPTIONS=--no-same-owner
#    Im User-Namespace sind nur gid 0 (und die eigene gid) abgebildet. Dateien
#    mit gid 42 (Gruppe "shadow", z.B. /usr/sbin/unix_chkpwd) lassen sich nicht
#    auf ihren Besitzer setzen; tar bricht dann mit "Das Argument ist
#    ungueltig" ab. Mit --no-same-owner laeuft die Extraktion durch, alle
#    Dateien gehoeren anschliessend root:root. Fuer ein Live-Image ist das
#    unkritisch, es aendert aber die Gruppen einiger setgid-Programme.
#    Wer das nicht will, nimmt scripts/build.sh mit sudo oder den Container.
#
# 2. Kein UID-Mapping ueber newuidmap
#    Auf diesem Rechner verweigert newuidmap das Schreiben von uid_map
#    ("Operation not permitted"). Deshalb wird nur der einfache
#    Single-UID-Modus von `unshare -Ur` benutzt -- kein --map-auto, kein
#    mmdebstrap --mode=unshare.

set -e

cd "$(dirname "$0")/.."
PROJECT="$(pwd)"
TC="$PROJECT/.toolchain"

# --- Werkzeuge holen, falls noch nicht da ----------------------------------
if [ ! -x "$TC/root/usr/bin/xorriso" ]; then
	echo "==> .toolchain fehlt, hole Werkzeuge"
	./scripts/toolchain.sh
fi

export PATH="$TC/root/usr/sbin:$TC/root/usr/bin:$PATH"
export LD_LIBRARY_PATH="$TC/root/usr/lib/x86_64-linux-gnu:$TC/root/usr/lib/x86_64-linux-gnu/jli:$TC/root/lib/x86_64-linux-gnu"
export DEBOOTSTRAP_DIR="$TC/root/usr/share/debootstrap"
export TAR_OPTIONS="--no-same-owner"

# --- Version spiegeln ------------------------------------------------------
printf '%s\n' "$(cat VERSION)"   > config/includes.chroot/etc/rsos-version
printf '%s\n' "$(cat CODENAME)" > config/includes.chroot/etc/rsos-codename

# --- Bauen -----------------------------------------------------------------
case "${1:-}" in
	--clean) lb clean ;;
	--purge) lb clean --purge ;;
esac

unshare -Urm --propagation private sh -c 'cd "'"$PROJECT"'" && lb build'

echo
echo "Fertig. ISO(s) in ${PROJECT}/out/"
