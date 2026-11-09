# RSOS 2.0 -- Bau-Container
#
# Kein root auf dem Wirtsrechner noetig, keine virtuelle Maschine: der Build
# laeuft in einem Debian-Container mit den offiziellen Werkzeugen. Das ist der
# reproduzierbarste Weg und der, den auch GitHub Actions nimmt.
#
#   docker build -t rsos-build scripts/container
#   docker run --rm -v "$PWD":/build -w /build rsos-build

FROM debian:trixie

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
        live-build \
        debootstrap \
        squashfs-tools \
        xorriso \
        isolinux \
        syslinux-common \
        syslinux-utils \
        grub-efi-amd64-bin \
        grub-pc-bin \
        mtools \
        dosfstools \
        gdisk \
        fdisk \
        parted \
        rsync \
        git \
        ca-certificates \
        gpg \
        gnupg \
        apt-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
CMD ["/bin/sh", "-c", "lb build"]
