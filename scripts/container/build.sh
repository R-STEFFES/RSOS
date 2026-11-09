#!/bin/sh
# RSOS 2.0 -- im Container bauen (kein root auf dem Wirt, keine VM)
#
#   ./scripts/container/build.sh          # bauen
#   ./scripts/container/build.sh --shell  # nur eine Shell im Container
#
# Voraussetzung: docker oder podman mit laufendem Daemon, Zugriff auf den Socket.
#
# Hinweis --privileged: live-build mountet im Chroot /proc, /sys und /dev und
# legt dort Geraetedateien an. Ein normaler Container darf das nicht (kein
# CAP_SYS_ADMIN), der Bau bricht dann beim ersten Chroot-Schritt ab. Deshalb
# laeuft der Build-Container privilegiert -- er ist wegwerfbar und hat keinen
# Zugriff auf etwas anderes als den hereingebundenen Projektordner.

set -e

cd "$(dirname "$0")/../.."
PROJECT="$(pwd)"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	ENGINE=docker
elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
	ENGINE=podman
else
	echo "Weder docker (mit laufendem Daemon) noch podman verfuegbar." >&2
	echo "Alternativen: scripts/build.sh (mit sudo) oder scripts/build-rootless.sh" >&2
	exit 1
fi

IMAGE=rsos-build:2.0

echo "==> Container-Image bauen ($ENGINE)"
"$ENGINE" build -t "$IMAGE" scripts/container

# Version und Beiname in den Chroot spiegeln -- wie scripts/build.sh
printf '%s\n' "$(cat VERSION)"   > config/includes.chroot/etc/rsos-version
printf '%s\n' "$(cat CODENAME)" > config/includes.chroot/etc/rsos-codename

if [ "${1:-}" = "--shell" ]; then
	"$ENGINE" run --rm -it --privileged -v "$PROJECT":/build -w /build \
		"$IMAGE" /bin/bash
	exit 0
fi

echo "==> Build im Container"
"$ENGINE" run --rm --privileged -v "$PROJECT":/build -w /build \
	"$IMAGE" /bin/sh -c 'lb build'

echo
echo "Fertig. ISO(s) in ${PROJECT}/out/"
ls -lh out/ 2>/dev/null || true

# Zusaetzlich nach ~/Downloads -- dort liegen die anderen Testimages.
if [ -d "${HOME}/Downloads" ]; then
	for f in out/*.iso; do
		[ -e "$f" ] || continue
		cp -v "$f" "${HOME}/Downloads/"
	done
fi
