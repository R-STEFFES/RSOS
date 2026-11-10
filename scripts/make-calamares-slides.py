#!/usr/bin/env python3
"""Neue Bilder fuer die Calamares-Diashow erzeugen.

Die vier Slides tragen jetzt die richtige Wortmarke und deutsche Sprueche.
Aufbau je Bild:

    oben links    kleine Wortmarke mit duennem Cyan-Strich darueber
    Mitte         der Spruch, gross und fett, ein Wort in Cyan
    darunter      ein Satz in Normalschrift
    unten links   "RSOS 2.0 Janina"
    rechts        die Bildmarke als sehr blasses Wasserzeichen

Der Grund ist ein Ausschnitt aus dem passenden Weltraum-Wandbild, abgedunkelt.
Dadurch gehoeren Installer und Schreibtisch sichtbar zusammen. Erzeugt werden
die Wandbilder von scripts/make-wallpapers.py -- das muss also vorher laufen.

Schrift: Libre Franklin (Markenvorgabe), Black fuer die Sprueche.
Farben:  Grund #0C0C0C, Weiss #FAFAF8, Cyan #00E5FF

Aufruf:  python3 scripts/make-calamares-slides.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

HIER = Path(__file__).resolve().parent.parent
BRANDING = HIER / "config/includes.chroot/etc/calamares/branding/rsos"
WELTRAUM = HIER / "config/includes.chroot/usr/share/backgrounds/rsos/weltraum"
WORTMARKE = HIER / "assets/brand/wordmark_white.png"
BILDMARKE = HIER / "assets/brand/monogram_white.png"

SCHRIFT = "/usr/share/fonts/Libre_Franklin/LibreFranklin-VariableFont_wght.ttf"
SCHRIFT_KURSIV = "/usr/share/fonts/Libre_Franklin/LibreFranklin-Italic-VariableFont_wght.ttf"

BREITE, HOEHE = 1920, 1200

SCHWARZ = (12, 12, 12)
WEISS = (250, 250, 248)
CYAN = (0, 229, 255)
GRAU = (168, 172, 178)

# Die Sprueche. Jede Zeile ist eine Folge von (Text, Farbe).
SLIDES = [
    {
        "zeilen": [
            [("Freiheit fängt", WEISS)],
            [("beim ", WEISS), ("System", CYAN), (" an.", WEISS)],
        ],
        "zusatz": "Debian im Kern. Steffes in der Handschrift.",
        "bild": "weltraum-1.png",
    },
    {
        "zeilen": [
            [("Schlank.", WEISS)],
            [("Schnell. ", WEISS), ("Sauber.", CYAN)],
        ],
        "zusatz": "Kein Ballast. Nur das, was du wirklich brauchst.",
        "bild": "weltraum-2.png",
    },
    {
        "zeilen": [
            [("Wir setzen die", WEISS)],
            [("Standards", CYAN), (" von morgen.", WEISS)],
        ],
        "zusatz": "Steffes Industries — Systeme, die man versteht.",
        "bild": "weltraum-3.png",
    },
    {
        "zeilen": [
            [("Dein System.", WEISS)],
            [("Deine ", WEISS), ("Regeln.", CYAN)],
        ],
        "zusatz": "Freie Quellen. Keine Konten. Keine Werbung.",
        "bild": "weltraum-4.png",
    },
]


def schrift(groesse, gewicht="Regular", kursiv=False):
    """Libre Franklin in der gewuenschten Strichstaerke laden."""
    pfad = SCHRIFT_KURSIV if kursiv else SCHRIFT
    f = ImageFont.truetype(pfad, groesse)
    try:
        f.set_variation_by_name(gewicht)
    except Exception:
        # Variable Schriften sind nicht ueberall verfuegbar -- dann bleibt es
        # bei der Standardstaerke, das Bild entsteht trotzdem.
        pass
    return f


def grundflaeche(bildname):
    """Abgedunkelter Ausschnitt aus dem passenden Wandbild."""
    quelle = Image.open(WELTRAUM / bildname).convert("RGB")
    # Auf das Slide-Format bringen, mittig beschnitten
    vr = max(BREITE / quelle.width, HOEHE / quelle.height)
    neu = quelle.resize((round(quelle.width * vr), round(quelle.height * vr)), Image.LANCZOS)
    links = (neu.width - BREITE) // 2
    oben = (neu.height - HOEHE) // 2
    flaeche = neu.crop((links, oben, links + BREITE, oben + HOEHE)).convert("RGB")

    # Abdunkeln, damit die Schrift sicher lesbar bleibt
    flaeche = Image.blend(flaeche, Image.new("RGB", (BREITE, HOEHE), SCHWARZ), 0.55)
    return flaeche


def wasserzeichen(flaeche):
    """Bildmarke rechts als sehr blasses Wasserzeichen."""
    marke = Image.open(BILDMARKE).convert("RGBA")
    zielbreite = int(BREITE * 0.52)
    marke = marke.resize((zielbreite, round(marke.height * zielbreite / marke.width)),
                         Image.LANCZOS)
    # Deckkraft stark zuruecknehmen
    alpha = marke.split()[3].point(lambda v: int(v * 0.09))
    marke.putalpha(alpha)
    x = BREITE - marke.width + int(BREITE * 0.04)
    y = (HOEHE - marke.height) // 2
    flaeche.alpha_composite(marke, (x, y)) if flaeche.mode == "RGBA" else \
        flaeche.paste(marke, (x, y), marke)


def zeile_zeichnen(zeichnen, x, y, teile, schr):
    """Eine Zeile aus farbigen Teilen setzen. Gibt die Breite zurueck."""
    for text, farbe in teile:
        zeichnen.text((x, y), text, font=schr, fill=farbe)
        x += zeichnen.textlength(text, font=schr)
    return x


def slide_bauen(nummer, angaben):
    flaeche = grundflaeche(angaben["bild"]).convert("RGBA")
    wasserzeichen(flaeche)

    zeichnen = ImageDraw.Draw(flaeche)

    # --- Wortmarke oben links ---------------------------------------------
    wortmarke = Image.open(WORTMARKE).convert("RGBA")
    zielbreite = 400
    wortmarke = wortmarke.resize((zielbreite, round(wortmarke.height * zielbreite / wortmarke.width)),
                                 Image.LANCZOS)
    x0, y0 = 130, 128
    zeichnen.rectangle((x0, y0 - 28, x0 + 118, y0 - 23), fill=CYAN)
    flaeche.alpha_composite(wortmarke, (x0, y0))

    # --- Spruch ------------------------------------------------------------
    gross = schrift(112, "Black")
    y = 430
    for teile in angaben["zeilen"]:
        zeile_zeichnen(zeichnen, x0, y, teile, gross)
        y += 132

    # --- Trennstrich und Zusatz -------------------------------------------
    y += 26
    zeichnen.rectangle((x0, y, x0 + 120, y + 3), fill=CYAN)
    zusatz = schrift(38, "Medium")
    zeichnen.text((x0, y + 34), angaben["zusatz"], font=zusatz, fill=GRAU)

    # --- Kennung unten links ----------------------------------------------
    klein = schrift(30, "Bold")
    zeichnen.text((x0, HOEHE - 118), "RSOS 2.0 JANINA", font=klein, fill=CYAN)
    fein = schrift(26, "Regular")
    zeichnen.text((x0, HOEHE - 76), "steffes.industries", font=fein, fill=(110, 116, 122))

    ziel = BRANDING / f"slide{nummer}.png"
    flaeche.convert("RGB").save(ziel)
    print(f"geschrieben: {ziel}  ({BREITE}x{HOEHE})")


def main():
    fehlend = [s["bild"] for s in SLIDES if not (WELTRAUM / s["bild"]).exists()]
    if fehlend:
        raise SystemExit(
            "Es fehlen Wandbilder: " + ", ".join(fehlend) +
            "\nZuerst ausfuehren:  python3 scripts/make-wallpapers.py")

    for nummer, angaben in enumerate(SLIDES, start=1):
        slide_bauen(nummer, angaben)


if __name__ == "__main__":
    main()
