#!/bin/sh
# RSOS 2.0 -- im Container bauen (kein root auf dem Wirt, keine VM)
#
#   ./scripts/container/build.sh            # frisch bauen
#   ./scripts/container/build.sh --keep     # Arbeitsvolume behalten (2. Lauf schneller)
#   ./scripts/container/build.sh --refresh  # Volume behalten, geaenderte Stufen neu laufen lassen
#   ./scripts/container/build.sh --frisch   # Chroot neu aufbauen, Paketcache behalten
#   ./scripts/container/build.sh --shell    # nur eine Shell im Container
#   ./scripts/container/build.sh --clean    # Arbeitsvolume wegwerfen
#
# --refresh ist der Weg, wenn sich Paketlisten, Includes oder Hooks geaendert
# haben: die Stufen, die davon abhaengen, laufen neu. Wirklich Zeit spart das
# nur nach einem ABGEBROCHENEN Bau -- nach einem erfolgreichen raeumt live-build
# seine Marker selbst weg. Der Paketcache bleibt in jedem Fall liegen, es wird
# also nichts erneut heruntergeladen.
#
# --frisch ist noetig, wenn PAKETE ENTFERNT wurden. live-build installiert nur,
# was in den Listen steht, und entfernt nichts -- ein --refresh haette die
# gestrichenen Pakete also im Image gelassen. --frisch wirft chroot/ und .build/
# weg und baut den Chroot neu; der Paketcache unter cache/ bleibt, deshalb
# kostet das nur wenige Minuten mehr als ein --refresh.
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
if [ "${1:-}" = "--keep" ] || [ "${1:-}" = "--refresh" ] || [ "${1:-}" = "--frisch" ]; then
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

# Eine Sperre aus einem abgebrochenen Lauf blockiert JEDEN weiteren Bau
# ("lb chroot_devpts already locked"): live-build legt fuer jede Stufe eine
# Datei .lock im Projektwurzelverzeichnis an und raeumt sie beim Abbruch nicht
# weg. Bei einem frischen Volume kann das nicht passieren, bei --keep und
# --refresh schon.
if [ "${1:-}" = "--keep" ] || [ "${1:-}" = "--refresh" ] || [ "${1:-}" = "--frisch" ]; then
	if [ -n "$("$ENGINE" run --rm -v "$VOL":/work "$IMAGE" /bin/sh -c 'ls /work/.lock 2>/dev/null')" ]; then
		echo "==> Sperre aus einem abgebrochenen Lauf entfernen (/work/.lock)"
		"$ENGINE" run --rm -v "$VOL":/work "$IMAGE" /bin/sh -c 'rm -f /work/.lock'
	fi
fi

# --frisch: Chroot und Marker wegwerfen, aber cache/ behalten. Noetig, wenn
# Pakete ENTFERNT wurden -- siehe oben in der Uebersicht.
if [ "${1:-}" = "--frisch" ]; then
	echo "==> Chroot und Marker wegwerfen (Paketcache bleibt)"
	"$ENGINE" run --rm --privileged -v "$VOL":/work "$IMAGE" /bin/sh -c '
		rm -rf /work/chroot /work/.build /work/.lock /work/binary /work/out
		rm -f /work/*.iso /work/build.log /work/*.log
		# Die Inhaltsliste ("contents") beschreibt den alten Chroot; bleibt sie
		# liegen, listet /live/filesystem.packages spaeter falsche Pakete.
		rm -f /work/cache/contents.*
		echo "Paketcache: $(find /work/cache -name "*.deb" 2>/dev/null | wc -l) Pakete"'
fi

# --refresh: die Stufen zuruecksetzen, die von geaenderten Paketlisten,
# Includes oder Hooks abhaengen. live-build merkt sich erledigte Stufen als
# Marker in .build/ und wuerde sie sonst ueberspringen -- die Aenderung kaeme
# nie im Image an. Der fertige Chroot bleibt dabei erhalten.
if [ "${1:-}" = "--refresh" ]; then
	echo "==> Geaenderte Stufen zuruecksetzen (Paketlisten, Includes, Hooks, Binary)"
	"$ENGINE" run --rm --privileged -v "$VOL":/work "$IMAGE" /bin/sh -c '
		cd /work/.build 2>/dev/null || exit 0
		# Die ganze Chroot-Stufe zuruecksetzen, nicht einzelne Schritte.
		# Grund: im Arbeitsvolume koennen Marker aus verschiedenen Laeufen
		# stehen (ein Schritt wurde neu gebaut, waehrend ein alter Marker
		# stehen blieb). Dann ueberspringt live-build Schritte, deren
		# Ergebnis gar nicht mehr da ist -- das hat nacheinander zu
		# drei Abbruechen gefuehrt:
		#   "grub-efi-amd64 Conflicts grub-pc"  (alte Paketliste)
		#   "lb chroot_devpts already locked"   (Sperre)
		#   "cp: cannot stat chroot/boot/vmlinuz-*"  (Kernel-Stufe uebersprungen)
		# Bootstrap und sein Cache bleiben stehen: der Teil ist teuer (2 GB
		# Download) und wird nicht durch Include-, Hook- oder Paketaenderungen
		# beeinflusst.
		rm -f chroot_* binary_*
		# live-build schreibt die Paketliste mit ">>" nach
		# chroot/root/packages.chroot und leert die Datei nie. Alte Eintraege
		# bleiben sonst stehen und werden mitinstalliert.
		rm -f /work/chroot/root/packages.chroot \
		      /work/chroot/root/packages.foreign-architectures
		echo "zurueckgesetzt: $(ls | tr "\n" " ")"'
fi

# Ueberbleibsel aus abgebrochenen Laeufen: eine alte Squashfs im Chroot wird
# sonst mit ins neue Abbild gepackt. Genau das ist passiert -- die ISO wuchs von
# 2,9 auf 5,1 GB, ohne dass ein Paket dazukam (in der Chroot lagen 2,2 GB
# filesystem.squashfs aus einem frueheren Lauf).
if [ -n "$("$ENGINE" run --rm -v "$VOL":/work "$IMAGE" /bin/sh -c 'ls /work/chroot/*.squashfs 2>/dev/null')" ]; then
	echo "==> Ueberbleibsel im Chroot entfernen (alte Squashfs)"
	"$ENGINE" run --rm -v "$VOL":/work "$IMAGE" /bin/sh -c 'rm -f /work/chroot/*.squashfs'
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

# Groessenkontrolle. Eine unerwartet grosse ISO heisst fast immer, dass
# Ueberbleibsel mitgepackt wurden -- bisher zweimal passiert (alte Squashfs in
# der Chroot). Lieber einmal zu viel nachsehen als eine kaputte ISO ausliefern.
for f in out/*.iso; do
	[ -e "$f" ] || continue
	MB=$(du -m "$f" | cut -f1)
	if [ "$MB" -gt 3500 ]; then
		echo >&2
		echo "WARNUNG: $(basename "$f") ist ${MB} MB gross, erwartet werden etwa 2900 MB." >&2
		echo "Nachsehen, was gross ist:" >&2
		echo "  $ENGINE run --rm -v $VOL:/work $IMAGE sh -c 'du -sh /work/chroot; find /work/chroot -xdev -size +100M -printf \"%s %p\\n\"'" >&2
	fi
done

# Zusaetzlich nach ~/Downloads -- dort liegen die anderen Testimages.
if [ -d "${HOME}/Downloads" ]; then
	for f in out/*.iso; do
		[ -e "$f" ] || continue
		cp -v "$f" "${HOME}/Downloads/"
	done
fi
