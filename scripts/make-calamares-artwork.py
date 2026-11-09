#!/usr/bin/env python3
"""RSOS -- Calamares-Hintergrundbild im aktuellen Markenstil erzeugen.

Erzeugt 1920x1080 nach den Markenvorgaben (siehe fundus/marke.md):

    Grund    #0C0C0C  (Schwarz)
    Akzent   #00E5FF  (Cyan, Hauptakzent)
    Wortmarke weiss, aus fundus/logo/logo_white.png

Tron-Look: dunkler Grund, Cyan als Hauptakzent, sparsam. Die Wortmarke sitzt
mittig, der Speed-Slash zieht als duenne Cyan-Linie dahinter durch -- mit einer
Luecke dort, wo die Wortmarke steht, sonst wirkt es wie Durchstreichen.

Aufruf:

    python3 scripts/make-calamares-artwork.py

Schreibt `wallpaper.png` nach config/includes.chroot/... -- das ist die einzige
massgebliche Fassung und landet beim Bauen im Image. (Eine zweite Kopie unter
assets/calamares-branding/ gab es frueher; sie lief auseinander und wurde
entfernt, damit niemand die falsche Datei bearbeitet.)
"""

import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# --- Markenvorgaben -------------------------------------------------------
SCHWARZ = (12, 12, 12)          # #0C0C0C
CYAN = (0, 229, 255)            # #00E5FF

BREITE, HOEHE = 1920, 1080
WORTMARKE_BREITE = 820
UNTERZEILE = "RSOS 2.0"
UNTERZEILE_GROESSE = 34
SPERRUNG = 16

# Der Slash laeuft von links unten nach rechts oben
SLASH = [(-100, 900), (BREITE + 100, 250)]

ZUFALL = random.Random(20261109)  # fester Startwert: gleiches Bild bei jedem Lauf

HIER = os.path.dirname(os.path.abspath(__file__))
PROJEKT = os.path.dirname(HIER)
LOGO = os.path.expanduser("~/Schreibtisch/Videos/fundus/logo/logo_white.png")
SCHRIFT = "/usr/share/fonts/Libre_Franklin/static/LibreFranklin-ExtraBold.ttf"

ZIELE = [
    os.path.join(PROJEKT, "config/includes.chroot/etc/calamares/branding/rsos/wallpaper.png"),
]


def facettengrund():
    """Dunkler Grund mit kaum sichtbaren Facetten (Tron-Look)."""
    bild = Image.new("RGB", (BREITE, HOEHE), SCHWARZ)
    zeichnen = ImageDraw.Draw(bild)

    for _ in range(90):
        cx = ZUFALL.randint(-200, BREITE + 200)
        cy = ZUFALL.randint(-200, HOEHE + 200)
        seiten = ZUFALL.randint(3, 5)
        radius = ZUFALL.randint(180, 620)
        ecken = []
        for i in range(seiten):
            winkel = (2 * math.pi / seiten) * i + ZUFALL.uniform(-0.5, 0.5)
            ecken.append((cx + radius * math.cos(winkel),
                          cy + radius * math.sin(winkel)))
        stufe = ZUFALL.randint(0, 7)   # nur wenige Stufen ueber dem Grund
        zeichnen.polygon(ecken, fill=(SCHWARZ[0] + stufe, SCHWARZ[1] + stufe, SCHWARZ[2] + stufe))

    return bild.filter(ImageFilter.GaussianBlur(28))


def wortmarke_geometrie():
    """Wohin die Wortmarke kommt -- einmal berechnet, zweimal gebraucht."""
    marke = Image.open(LOGO).convert("RGBA")
    marke = marke.crop(marke.split()[3].getbbox())
    hoehe = round(WORTMARKE_BREITE * marke.height / marke.width)
    marke = marke.resize((WORTMARKE_BREITE, hoehe), Image.LANCZOS)

    x = (BREITE - WORTMARKE_BREITE) // 2
    y = (HOEHE - hoehe) // 2 - 30
    return marke, (x, y, x + WORTMARKE_BREITE, y + hoehe)


def speed_slash(bild, freihalten):
    """Cyan-Linie mit weichem Schein -- mit Luecke um die Wortmarke herum."""
    schein = Image.new("RGB", (BREITE, HOEHE), (0, 0, 0))
    ImageDraw.Draw(schein).line(SLASH, fill=(0, 70, 82), width=26)
    schein = schein.filter(ImageFilter.GaussianBlur(34))
    ImageDraw.Draw(schein).line(SLASH, fill=CYAN, width=3)

    # Freizone: Wortmarke plus Unterzeile plus Rand, weich auslaufend
    x1, y1, x2, y2 = freihalten
    rand = 60
    maske = Image.new("L", (BREITE, HOEHE), 255)
    ImageDraw.Draw(maske).rectangle(
        [x1 - rand, y1 - 50, x2 + rand, y2 + 105], fill=0)
    maske = maske.filter(ImageFilter.GaussianBlur(26))

    faktor = (np.asarray(maske, dtype="int16") / 255.0)[..., None]
    slash = (np.asarray(schein, dtype="int16") * faktor).astype("int16")
    grund = np.asarray(bild, dtype="int16")
    return Image.fromarray(np.clip(grund + slash, 0, 255).astype("uint8"))


def wortmarke(bild, marke, kasten):
    """Weisse Wortmarke mittig, darunter die Unterzeile in Cyan."""
    x1, y1, _, y2 = kasten
    bild.paste(marke, (x1, y1), marke)

    if not os.path.exists(SCHRIFT):
        return bild

    schrift = ImageFont.truetype(SCHRIFT, UNTERZEILE_GROESSE)
    breiten = [schrift.getbbox(z)[2] - schrift.getbbox(z)[0] for z in UNTERZEILE]
    gesamt = sum(breiten) + SPERRUNG * (len(UNTERZEILE) - 1)

    zeichnen = ImageDraw.Draw(bild)
    cx = (BREITE - gesamt) // 2
    cy = y2 + 58
    for zeichen, breite in zip(UNTERZEILE, breiten):
        zeichnen.text((cx, cy), zeichen, font=schrift, fill=CYAN)
        cx += breite + SPERRUNG

    return bild


def main():
    if not os.path.exists(LOGO):
        raise SystemExit(f"Wortmarke fehlt: {LOGO}")

    marke, kasten = wortmarke_geometrie()

    bild = facettengrund()
    bild = speed_slash(bild, kasten)
    bild = wortmarke(bild, marke, kasten)

    for ziel in ZIELE:
        os.makedirs(os.path.dirname(ziel), exist_ok=True)
        bild.save(ziel, "PNG", optimize=True)
        print(f"geschrieben: {ziel}  ({os.path.getsize(ziel) // 1024} KB)")


if __name__ == "__main__":
    main()
