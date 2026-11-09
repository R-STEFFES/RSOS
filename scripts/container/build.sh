#!/bin/sh
# RSOS 2.0 -- im Container bauen (kein root auf dem Wirt, keine VM)
#
#   ./scripts/container/build.sh          # bauen
#   ./scripts/container/build.sh --shell  # nur eine Shell im Container
#
# Voraussetzung: docker oder podman, laufender Daemon, Zugriff auf den Socket.

set -e

cd "$(dirname "$0")/../.."
PROJECT="$(pwd)"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	ENGINE=docker
elif command -v podman >/dev/null 2>&1; then
	ENGINE=podman
else
	echo "Weder docker (mit laufendem Daemon) noch podman verfuegbar." >&2
	echo "Alternativen: scripts/build.sh (mit sudo) oder scripts/build-rootless.sh" >&2
	exit 1
fi

IMAGE=rsos-build:2.0

echo "==> Container-Image bauen ($ENGINE)"
"$ENGINE" build -t "$IMAGE" scripts/container

if [ "${1:-}" = "--shell" ]; then
	"$ENGINE" run --rm -it -v "$PROJECT":/build -w /build "$IMAGE" /bin/bash
	exit 0
fi

echo "==> Build im Container"
"$ENGINE" run --rm -v "$PROJECT":/build -w /build "$IMAGE" /bin/sh -c 'lb build'

echo
echo "Fertig. ISO(s) in ${PROJECT}/out/"
ls -lh out/ 2>/dev/null || true
