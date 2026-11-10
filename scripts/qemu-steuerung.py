#!/usr/bin/env python3
"""Den Installer kopflos in QEMU bedienen: Bildschirmfoto, Klick, Tastendruck.

WARUM
-----
Raphael hat die ISO bisher jedes Mal selbst in einer VM getestet und die Fehler
gemeldet. Das laesst sich abkuerzen: QEMU laeuft ohne Bildschirm, ueber QMP
(QEMU Machine Protocol) lassen sich Bildschirmfotos holen und Maus/Tastatur
steuern. Damit kann die Installation vorab durchgesehen werden.

WARUM QMP UND NICHT DER MONITOR
-------------------------------
Der einfache Monitor kann nur Tasten senden. Fuer die Schaltflaechen des
Installers braucht es echte Mausklicks auf feste Koordinaten -- das geht nur mit
QMP (input-send-event) und einem ABSOLUTEN Zeigegeraet im Gast (-device
usb-tablet). Ohne das Geraet kommen relative Bewegungen an und die Klicks landen
daneben.

BENUTZUNG
---------
Zuerst QEMU starten (siehe docs/INSTALLER-TEST.md):

    qemu-system-x86_64 -enable-kvm -m 3072 -smp 2 \\
      -drive file=/tmp/rsos-qemu/testplatte.qcow2,if=ide,format=qcow2 \\
      -cdrom /tmp/rsos-qemu/test.iso -boot d \\
      -usb -device usb-tablet -display none -vnc :5 \\
      -qmp unix:/tmp/rsos-qemu/qmp,server,nowait -no-reboot

Dann:

    python3 scripts/qemu-steuerung.py bild  /tmp/schritt1.ppm
    python3 scripts/qemu-steuerung.py klick 999 695
    python3 scripts/qemu-steuerung.py tippen rsos
    python3 scripts/qemu-steuerung.py taste ret
    python3 scripts/qemu-steuerung.py taste alt f2

Das Bildschirmfoto ist ein PPM; mit Pillow nach PNG wandeln:

    python3 -c "from PIL import Image; Image.open('/tmp/schritt1.ppm').save('/tmp/schritt1.png')"

WICHTIG: QEMU und einen parallel laufenden Bau NICHT gleichzeitig betreiben --
der Swap des Wirts reicht nicht, die Docker-VM stirbt dann (siehe Skill
docker-desktop-builds).
"""

import json
import socket
import sys
import time

SOCK = "/tmp/rsos-qemu/qmp"
# Bildschirmgroesse des Gastes. Muss zu den Klickkoordinaten passen.
BREITE, HOEHE = 1280, 800


class Qemu:
    """Verbindung zum QMP-Socket."""

    def __init__(self, sock=SOCK):
        self.s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.s.settimeout(15)
        self.s.connect(sock)
        self.f = self.s.makefile("rwb")
        self.f.readline()                       # Begruessung des Servers
        self._sende({"execute": "qmp_capabilities"})

    def _sende(self, auftrag):
        self.f.write((json.dumps(auftrag) + "\n").encode())
        self.f.flush()
        while True:
            zeile = self.f.readline()
            if not zeile:
                return {}
            try:
                antwort = json.loads(zeile)
            except Exception:
                continue
            if "return" in antwort or "error" in antwort:
                return antwort

    def _ereignis(self, ereignisse):
        return self._sende({"execute": "input-send-event",
                            "arguments": {"events": ereignisse}})

    def klick(self, x, y):
        """Klick auf Bildschirmkoordinaten (0..BREITE, 0..HOEHE)."""
        self._ereignis([
            {"type": "abs", "data": {"axis": "x", "value": round(x / BREITE * 32767)}},
            {"type": "abs", "data": {"axis": "y", "value": round(y / HOEHE * 32767)}},
        ])
        time.sleep(0.25)
        self._ereignis([{"type": "btn", "data": {"down": True, "button": "left"}}])
        time.sleep(0.12)
        self._ereignis([{"type": "btn", "data": {"down": False, "button": "left"}}])
        time.sleep(0.4)

    def taste(self, *codes):
        """Tasten senden; mehrere Codes werden gemeinsam gedrueckt (z.B. alt, f2)."""
        self._sende({"execute": "send-key",
                     "arguments": {"keys": [{"type": "qcode", "data": c} for c in codes]}})
        time.sleep(0.4)

    def tippen(self, text):
        """Text tippen -- auch Grossbuchstaben und Sonderzeichen.

        Frueher wurden nur Kleinbuchstaben, Ziffern und der Bindestrich
        gesendet. Grossbuchstaben kamen dadurch GAR NICHT an: im Installer
        blieb das Feld "Vor- und Nachname" leer (der Cursor blinkte, es
        passierte nichts), und beim Tippen von Befehlen entstand
        Buchstabensalat. Was fehlt, wird jetzt ueber Shift gesendet.
        """
        # Zeichen, die ohne Shift auf einer eigenen Taste liegen
        direkt = {
            "/": "slash", ".": "dot", ",": "comma", "-": "minus",
            "=": "equal", ";": "semicolon", "'": "apostrophe",
            "[": "bracket_left", "]": "bracket_right", "\\": "backslash",
            "`": "grave_accent",
        }
        # Zeichen, die mit Shift getippt werden
        mit_shift = {
            "_": "minus", ":": "semicolon", '"': "apostrophe",
            "|": "backslash", ">": "dot", "<": "comma", "?": "slash",
            "+": "equal", "~": "grave_accent",
            "!": "1", "@": "2", "#": "3", "$": "4", "%": "5",
            "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
        }

        for zeichen in text:
            if zeichen == " ":
                tasten = ["spc"]
            elif zeichen in direkt:
                tasten = [direkt[zeichen]]
            elif zeichen in mit_shift:
                tasten = ["shift", mit_shift[zeichen]]
            elif zeichen.isalpha() and zeichen.isupper():
                tasten = ["shift", zeichen.lower()]
            else:
                tasten = [zeichen]          # Kleinbuchstaben und Ziffern

            self._sende({"execute": "send-key",
                         "arguments": {"keys": [{"type": "qcode", "data": c}
                                                for c in tasten]}})
            time.sleep(0.06)

    def bild(self, pfad):
        self._sende({"execute": "screendump", "arguments": {"filename": pfad}})
        time.sleep(1.2)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    q = Qemu()
    befehl = sys.argv[1]
    rest = sys.argv[2:]

    if befehl == "bild":
        q.bild(rest[0]); print("Bild:", rest[0])
    elif befehl == "klick":
        q.klick(int(rest[0]), int(rest[1])); print(f"geklickt auf {rest[0]},{rest[1]}")
    elif befehl == "tippen":
        q.tippen(rest[0]); print("getippt:", rest[0])
    elif befehl == "taste":
        q.taste(*rest); print("Tasten:", " ".join(rest))
    else:
        raise SystemExit(f"Unbekannter Befehl: {befehl}\n{__doc__}")


if __name__ == "__main__":
    main()
