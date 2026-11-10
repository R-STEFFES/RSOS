#!/usr/bin/env python3
"""Weltraum-Wandbilder fuer RSOS erzeugen.

Erzeugt vier Hintergrundbilder in den Markenfarben (Grund #0C0C0C, Akzent Cyan
#00E5FF, sparsam Orange #FF7A1A) und legt sie so ab, dass Plasma sie kennt:

    usr/share/backgrounds/rsos/weltraum/weltraum-N.png     die Bilder selbst
    usr/share/wallpapers/RSOS-Weltraum/                    Wandbildpaket fuer
        metadata.json, contents/images/, contents/screenshot.jpg

Das Vorschaubild schreibt Pillow als JPEG -- ImageMagick wird dafuer NICHT
gebraucht (es wurde auf Wunsch aus dem System entfernt).

Alles ist berechnet, kein Bildmaterial von aussen. Gleicher Zufallsstartwert ->
gleiches Bild.

Aufruf:  python3 scripts/make-wallpapers.py
"""

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HIER = Path(__file__).resolve().parent.parent
BILDER = HIER / "config/includes.chroot/usr/share/backgrounds/rsos/weltraum"
PAKET = HIER / "config/includes.chroot/usr/share/wallpapers/RSOS-Weltraum"

BREITE, HOEHE = 2560, 1440

SCHWARZ = (12, 12, 12)
CYAN = (0, 229, 255)
ORANGE = (255, 122, 26)

# Fester Startwert: derselbe Lauf liefert dasselbe Bild.
START = 20261110


def rauschen(breite, hoehe, grob, rng):
    """Weiches Wertrauschen: kleine Zufallstafel, weich vergroessert."""
    klein = rng.random((max(2, hoehe // grob), max(2, breite // grob)))
    bild = Image.fromarray((klein * 255).astype(np.uint8), mode="L")
    bild = bild.resize((breite, hoehe), Image.BICUBIC)
    return np.asarray(bild, dtype=np.float32) / 255.0


def nebel(breite, hoehe, rng, lagen=6, basis=380, schwelle=0.42):
    """Mehrstufiges Rauschen -- ergibt wolkenartige Strukturen."""
    summe = np.zeros((hoehe, breite), dtype=np.float32)
    gewicht = 1.0
    gesamt = 0.0
    for stufe in range(lagen):
        summe += gewicht * rauschen(breite, hoehe, max(8, basis // (2 ** stufe)), rng)
        gesamt += gewicht
        gewicht *= 0.55
    summe /= gesamt
    # Kontrast: nur die dichten Bereiche leuchten
    summe = np.clip((summe - schwelle) / (1.0 - schwelle), 0.0, 1.0)
    return summe ** 1.4


def sternfeld(breite, hoehe, rng, anzahl, helligkeit=1.0):
    """Sterne als Helligkeitsbild."""
    stern = Image.new("L", (breite, hoehe), 0)
    zeichnen = ImageDraw.Draw(stern)
    for _ in range(anzahl):
        x = rng.random() * breite
        y = rng.random() * hoehe
        r = 0.5 + 1.7 * rng.random() ** 3
        h = int((90 + 165 * rng.random() ** 1.6) * helligkeit)
        zeichnen.ellipse((x - r, y - r, x + r, y + r), fill=h)
    return np.asarray(stern.filter(ImageFilter.GaussianBlur(0.6)), dtype=np.float32) / 255.0


def farbverlauf(maske, von, nach):
    """Maske (0..1) auf einen Farbverlauf abbilden."""
    von = np.array(von, dtype=np.float32)
    nach = np.array(nach, dtype=np.float32)
    return von[None, None, :] + maske[:, :, None] * (nach - von)[None, None, :]


def scheibe(breite, hoehe, cx, cy, r):
    """Kreisfoermige Maske."""
    ebene = Image.new("L", (breite, hoehe), 0)
    ImageDraw.Draw(ebene).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return ebene


def weltraum_bild(nummer, rng):
    """Ein Wandbild bauen. Vier Varianten mit unterschiedlicher Stimmung."""
    breite, hoehe = BREITE, HOEHE

    # --- Grundflaeche ------------------------------------------------------
    grund = np.zeros((hoehe, breite, 3), dtype=np.float32)
    grund[:, :, :] = SCHWARZ

    # --- Nebel: grobe Form plus feine Struktur ----------------------------
    grob = nebel(breite, hoehe, rng, lagen=5, basis=820, schwelle=0.34)
    fein = nebel(breite, hoehe, rng, lagen=7, basis=240, schwelle=0.48)

    einstellungen = {
        1: ((8, 45, 90), CYAN, 1.45),          # blauer Nebel, Cyan-Kante
        2: ((26, 8, 62), (150, 70, 255), 1.25),  # violett
        3: ((0, 55, 80), (0, 210, 255), 1.35),   # tuerkis
        # Variante 4 ist die ruhige: fast schwarz, nur ein Hauch Nebel.
        # Orange bleibt hier der sparsame Gegenakzent (Markenvorgabe).
        4: ((4, 16, 34), (0, 150, 200), 0.38),
    }
    von, nach, staerke = einstellungen[nummer]

    grund += farbverlauf(grob, von, nach) * (grob ** 0.75)[:, :, None] * staerke
    grund += farbverlauf(fein, von, nach) * (fein * 0.55)[:, :, None]

    # --- Sterne ------------------------------------------------------------
    sterne = sternfeld(breite, hoehe, rng, 3200 if nummer != 4 else 1800)
    grund += sterne[:, :, None] * np.array((252, 252, 250), dtype=np.float32)[None, None, :]

    # Ein paar auffaellige Sterne mit Hof und Kreuzstrahl
    for _ in range(6):
        x, y = int(rng.random() * breite), int(rng.random() * hoehe)
        hof = scheibe(breite, hoehe, x, y, 3).filter(ImageFilter.GaussianBlur(9))
        grund += (np.asarray(hof, dtype=np.float32) / 255.0)[:, :, None] * \
            np.array(CYAN, dtype=np.float32)[None, None, :] * 0.85
        strahl = Image.new("L", (breite, hoehe), 0)
        d = ImageDraw.Draw(strahl)
        d.line((x - 26, y, x + 26, y), fill=170, width=1)
        d.line((x, y - 26, x, y + 26), fill=170, width=1)
        strahl = strahl.filter(ImageFilter.GaussianBlur(0.9))
        grund += (np.asarray(strahl, dtype=np.float32) / 255.0)[:, :, None] * \
            np.array((220, 245, 255), dtype=np.float32)[None, None, :]

    # --- Planet am unteren Rand (Variante 1 und 3) ------------------------
    if nummer in (1, 3):
        r = int(hoehe * (0.80 if nummer == 1 else 0.62))
        cx = int(breite * (0.82 if nummer == 1 else 0.18))
        cy = int(hoehe * 1.42)
        ebene = scheibe(breite, hoehe, cx, cy, r)
        kern = np.asarray(ebene, dtype=np.float32) / 255.0
        hof = np.asarray(ebene.filter(ImageFilter.GaussianBlur(70)), dtype=np.float32) / 255.0
        rand = np.asarray(ebene.filter(ImageFilter.GaussianBlur(4)), dtype=np.float32) / 255.0

        # Atmosphaere: weicher Cyan-Hof
        grund += np.clip(hof - kern * 0.85, 0, 1)[:, :, None] * \
            np.array(CYAN, dtype=np.float32)[None, None, :] * 1.5
        # heller Rand direkt an der Kante
        grund += np.clip(rand - kern, 0, 1)[:, :, None] * \
            np.array((215, 250, 255), dtype=np.float32)[None, None, :] * 1.7
        # Planetenkoerper: fast schwarz, verdeckt die Sterne dahinter
        grund *= (1.0 - kern * 0.97)[:, :, None]

    # --- Ruhige Variante: duenner Horizont mit Cyan-Saum ------------------
    if nummer == 4:
        kante = int(hoehe * 0.80)
        saum = Image.new("L", (breite, hoehe), 0)
        ImageDraw.Draw(saum).rectangle((0, kante, breite, kante + 3), fill=255)
        saum = saum.filter(ImageFilter.GaussianBlur(12))
        k = np.asarray(saum, dtype=np.float32) / 255.0
        grund += k[:, :, None] * np.array(CYAN, dtype=np.float32)[None, None, :] * 0.95
        unten = np.zeros((hoehe, breite), dtype=np.float32)
        unten[kante:, :] = 1.0
        grund *= (1.0 - unten * 0.6)[:, :, None]

    # --- Feiner diagonaler Lichtstreifen (Markenmotiv) --------------------
    strahl = Image.new("L", (breite, hoehe), 0)
    d = ImageDraw.Draw(strahl)
    versatz = int(breite * 0.42)
    d.polygon([(versatz, 0), (versatz + 5, 0),
               (versatz - hoehe + 5, hoehe), (versatz - hoehe, hoehe)], fill=255)
    strahl = strahl.filter(ImageFilter.GaussianBlur(26))
    s = np.asarray(strahl, dtype=np.float32) / 255.0
    grund += s[:, :, None] * np.array(CYAN, dtype=np.float32)[None, None, :] * 0.14

    # --- Sparsamer Gegenakzent in Orange ----------------------------------
    if nummer % 2 == 0:
        strich = Image.new("L", (breite, hoehe), 0)
        d = ImageDraw.Draw(strich)
        d.rectangle((int(breite * 0.76), int(hoehe * 0.085),
                     int(breite * 0.92), int(hoehe * 0.085) + 6), fill=255)
        strich = strich.filter(ImageFilter.GaussianBlur(1.4))
        o = np.asarray(strich, dtype=np.float32) / 255.0
        grund += o[:, :, None] * np.array(ORANGE, dtype=np.float32)[None, None, :] * 0.95

    # --- Vignette und Koernung gegen Streifenbildung ----------------------
    yy, xx = np.mgrid[0:hoehe, 0:breite]
    abstand = np.sqrt(((xx / breite - 0.5) * 2) ** 2 + ((yy / hoehe - 0.5) * 2) ** 2) / math.sqrt(2)
    grund *= (1.0 - 0.5 * abstand ** 2)[:, :, None]
    grund += rng.normal(0, 1.8, (hoehe, breite, 1)).astype(np.float32)

    return Image.fromarray(np.clip(grund, 0, 255).astype(np.uint8), mode="RGB")


def main():
    BILDER.mkdir(parents=True, exist_ok=True)
    (PAKET / "contents/images").mkdir(parents=True, exist_ok=True)

    namen = []
    for nummer in range(1, 5):
        rng = np.random.default_rng(START + nummer)
        bild = weltraum_bild(nummer, rng)
        ziel = BILDER / f"weltraum-{nummer}.png"
        bild.save(ziel)
        print(f"geschrieben: {ziel}  ({bild.width}x{bild.height})")
        namen.append(ziel.name)

    # Das erste Bild ist der Standard: zusaetzlich ins Wandbildpaket, damit
    # Plasma es in den Systemeinstellungen unter "Hintergrundbilder" anbietet.
    haupt = Image.open(BILDER / "weltraum-1.png")
    haupt.save(PAKET / "contents/images/weltraum-1.png")
    haupt.resize((640, 360), Image.LANCZOS).save(PAKET / "contents/screenshot.jpg", quality=88)

    (PAKET / "metadata.json").write_text(json.dumps({
        "KPlugin": {
            "Authors": [{"Name": "Steffes Industries"}],
            "Id": "RSOS-Weltraum",
            "License": "GPL-3.0",
            "Name": "RSOS Weltraum",
            "Name[de]": "RSOS Weltraum",
        }
    }, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"Wandbildpaket: {PAKET}")
    print(f"Bilder: {', '.join(namen)}")


if __name__ == "__main__":
    main()
