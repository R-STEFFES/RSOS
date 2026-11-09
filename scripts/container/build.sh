#!/bin/sh
# RSOS 2.0 -- im Container bauen (kein root auf dem Wirt, keine VM)
#
#   ./scripts/container/build.sh            # frisch bauen
#   ./scripts/container/build.sh --keep     # Arbeitsvolume behalten (2. Lauf schneller)
#   ./scripts/container/build.sh --refresh  # Volume behalten, geaenderte Stufen neu laufen lassen
#   ./scripts/container/build.sh --shell    # nur eine Shell im Container
#   ./scripts/container/build.sh --clean    # Arbeitsvolume wegwerfen
#
# --refresh ist der Weg, wenn sich Paketlisten, Includes oder Hooks geaendert
# haben: das Arbeitsvolume mit dem fertigen Chroot bleibt liegen, aber die
# Stufen, die davon abhaengen, laufen neu -- statt 2 GB neu zu laden.
#
# Voraussetzung: docker mit laufendem Daemon. Bei Docker Desktop startet man ihn
# ohne root mit:  systemctl --user start docker-desktop
#
# WARUM IN EINEM VOLUME UND NICHT IM HEREINGEBUNDENEN PROJEKTORDNER
# -----------------------------------------------------------------
# Docker Desktop reicht Bind-Mounts aus dem Heimatverzeichnis ueber virtiofs
# herein; im Container erscheinen sie als Dateisystem "fakeowner". Dieses
# Dateisystem kann nicht alles, was debootstrap beim Auspacken der Pakete
# braucht -- der Bau bricht ab mit
#
#     E: Tried to extract package, but tar failed. Exit...
#
# Ein natives Docker-Volume liegt dagegen auf ext4 und funktioniert. Deshalb
# wird der Quellbaum ins Volume kopiert, dort gebaut und das Ergebnis wieder
# herausgeholt. Nachgemessen: debootstrap im Volume -> rc=0, im Bind-Mount ->
# Abbruch beim ersten Paket.
#
# WARUM --privileged
# ------------------
# live-build mountet im Chroot /proc, /sys und /dev und legt Geraetedateien an.
# Ohne CAP_SYS_ADMIN bricht der erste Chroot-Schritt ab. Der Container ist
# wegwerfbar und sieht nur das Arbeitsvolume und (lesend) den Projektordner.

set -e

cd "$(dirname "$0")/../.."
PROJECT="$(pwd)"
VOL=rsos-build-work
IMAGE=rsos-build:2.0

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	ENGINE=docker
elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
	ENGINE=podman
else
	echo "Weder docker (mit laufendem Daemon) noch podman verfuegbar." >&2
	echo "Docker Desktop starten:  systemctl --user start docker-desktop" >&2
	echo "Alternativen: scripts/build.sh (mit sudo) oder scripts/build-rootless.sh" >&2
	exit 1
fi

case "${1:-}" in
--clean)
	"$ENGINE" volume rm "$VOL" >/dev/null 2>&1 || true
	echo "Arbeitsvolume $VOL entfernt."
	exit 0
	;;
esac

echo "==> Container-Image bauen ($ENGINE)"
"$ENGINE" build -t "$IMAGE" scripts/container

# Version und Beiname in den Chroot spiegeln -- wie scripts/build.sh
printf '%s\n' "$(cat VERSION)"   > config/includes.chroot/etc/rsos-version
printf '%s\n' "$(cat CODENAME)" > config/includes.chroot/etc/rsos-codename

# Frischer Lauf: altes Arbeitsvolume wegwerfen, sonst schleppt der Bau Reste
# des letzten Versuchs mit. Mit --keep und --refresh bleibt es erhalten.
if [ "${1:-}" = "--keep" ] || [ "${1:-}" = "--refresh" ]; then
	[ -n "$("$ENGINE" volume ls -q -f "name=^${VOL}$")" ] || "$ENGINE" volume create "$VOL" >/dev/null
else
	"$ENGINE" volume rm "$VOL" >/dev/null 2>&1 || true
	"$ENGINE" volume create "$VOL" >/dev/null
fi

if [ "${1:-}" = "--shell" ]; then
	echo "==> Shell im Container -- Projektordner lesend unter /src, Arbeit unter /work"
	"$ENGINE" run --rm -it --privileged -v "$VOL":/work -v "$PROJECT":/src:ro \
		-w /work "$IMAGE" /bin/bash
	exit 0
fi

echo "==> Quellen ins Arbeitsvolume kopieren"
"$ENGINE" run --rm --privileged -v "$VOL":/work -v "$PROJECT":/src:ro \
	"$IMAGE" /bin/sh -c 'cp -a /src/. /work/ && rm -rf /work/.git'

# --refresh: die Stufen zuruecksetzen, die von geaenderten Paketlisten,
# Includes oder Hooks abhaengen. live-build merkt sich erledigte Stufen als
# Marker in .build/ und wuerde sie sonst ueberspringen -- die Aenderung kaeme
# nie im Image an. Der fertige Chroot bleibt dabei erhalten.
if [ "${1:-}" = "--refresh" ]; then
	echo "==> Geaenderte Stufen zuruecksetzen (Paketlisten, Includes, Hooks, Binary)"
	"$ENGINE" run --rm --privileged -v "$VOL":/work "$IMAGE" /bin/sh -c '
		cd /work/.build 2>/dev/null || exit 0
		rm -f chroot_package-lists.install chroot_package-lists.live \
		      chroot_install-packages.install chroot_install-packages.live \
		      chroot_includes_after_packages chroot_hooks
		rm -f binary_*
		echo "zurueckgesetzt: $(ls | tr "\n" " ")"'
fi

echo "==> Build im Volume -- das dauert 25 bis 45 Minuten"
if [ -n "${RSOS_SQUASHFS:-}" ]; then
	echo "    Squashfs-Kompression: ${RSOS_SQUASHFS} (Vorgabe waere xz)"
fi
rc=0
"$ENGINE" run --rm --privileged -e RSOS_SQUASHFS -v "$VOL":/work -w /work \
	"$IMAGE" /bin/bash -c 'export LC_ALL=C.UTF-8; lb build' || rc=$?

# Ergebnis heraus kopieren -- ueber eine tar-Pipeline, damit die Dateien auf dem
# Wirt dem angemeldeten Benutzer gehoeren und nicht root: im Container laeuft
# der Bau als root, ein direkter Bind-Mount wuerde root:root hinterlassen.
echo "==> Ergebnis heraus kopieren"
"$ENGINE" run --rm -v "$VOL":/work "$IMAGE" \
	/bin/sh -c 'cd /work && tar -cf - out' 2>/dev/null | tar -xf - -C "$PROJECT" || true
"$ENGINE" run --rm -v "$VOL":/work "$IMAGE" \
	/bin/sh -c 'cat /work/build.log' >"$PROJECT/build.log" 2>/dev/null || true

if [ "$rc" -ne 0 ]; then
	echo >&2
	echo "Build fehlgeschlagen (rc=$rc). Die letzten Zeilen von build.log:" >&2
	tail -25 "$PROJECT/build.log" >&2 2>/dev/null || true
	echo >&2
	echo "Volles Protokoll: ${PROJECT}/build.log" >&2
	echo "Zum Nachsehen: ${ENGINE} run --rm -it --privileged -v ${VOL}:/work -w /work ${IMAGE} /bin/bash" >&2
	exit "$rc"
fi

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
