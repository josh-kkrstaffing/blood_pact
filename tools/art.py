#!/usr/bin/env python3
"""Draws the Blind Tiger games art from scratch and writes it to Media/ as TGA.

Everything here is drawn by this script: shapes, colours, and letters and suit
marks set in the DejaVu fonts (free to use). The one outside picture is the
tiger mark, which is the addon's own logo. Nothing comes from the game or from
anyone else's art. Run it from the repo root:  python3 tools/art.py
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "Media"
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SYMBOLS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

GOLD = (212, 168, 60)
GOLD_HI = (246, 214, 120)
GOLD_LO = (140, 100, 30)
INK = (18, 16, 14)
CREAM = (246, 240, 224)
RED = (176, 28, 36)
BLACK = (22, 22, 26)
GREEN = (22, 110, 60)


def font(path, size):
    return ImageFont.truetype(path, size)


def save(img, name):
    """32-bit TGA, not compressed, the form the game client reads."""
    assert img.mode == "RGBA"
    for side in img.size:
        assert side & (side - 1) == 0, "sides must be powers of two"
    img.save(os.path.join(OUT, name + ".tga"), compression=None)
    img.save(os.path.join("/tmp", "bt_" + name + ".png"))


def centred(draw, xy, text, fnt, fill, **kw):
    box = draw.textbbox((0, 0), text, font=fnt, stroke_width=kw.get("stroke_width", 0))
    w, h = box[2] - box[0], box[3] - box[1]
    draw.text((xy[0] - w / 2 - box[0], xy[1] - h / 2 - box[1]), text, font=fnt, fill=fill, **kw)


def round_mark(mark, size):
    """The tiger mark cut to a circle, so its square corners never show."""
    m = mark.resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    m.putalpha(Image.composite(m.split()[3], Image.new("L", (size, size), 0), mask))
    return m


# ---------------------------------------------------------------- the cards
CW, CH = 72, 102          # one card in the sheet
S = 4                     # drawn this many times bigger, then shrunk, for smooth edges
RANKS = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
SUITS = ["♠", "♥", "♦", "♣"]      # spade, heart, diamond, club: the addon's order


def card_face(rank, suit_i):
    img = Image.new("RGBA", (CW * S, CH * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    colour = RED if suit_i in (1, 2) else BLACK
    suit = SUITS[suit_i]
    d.rounded_rectangle([S, S, CW * S - S - 1, CH * S - S - 1], radius=7 * S, fill=CREAM, outline=(60, 50, 40), width=S)
    rank_font = font(SERIF, (22 if rank == "10" else 26) * S)
    centred(d, (16 * S, 17 * S), rank, rank_font, colour)
    centred(d, (16 * S, 38 * S), suit, font(SYMBOLS, 18 * S), colour)
    if rank in ("J", "Q", "K"):
        d.rounded_rectangle([30 * S, 30 * S, 64 * S, 92 * S], radius=4 * S, outline=GOLD_LO, width=S, fill=(238, 228, 200))
        centred(d, (47 * S, 52 * S), rank, font(SERIF, 34 * S), colour)
        centred(d, (47 * S, 78 * S), suit, font(SYMBOLS, 20 * S), colour)
    else:
        centred(d, (44 * S, 64 * S), suit, font(SYMBOLS, (58 if rank == "A" else 44) * S), colour)
    return img.resize((CW, CH), Image.LANCZOS)


def card_back(mark):
    img = Image.new("RGBA", (CW * S, CH * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S, S, CW * S - S - 1, CH * S - S - 1], radius=7 * S, fill=INK, outline=GOLD, width=2 * S)
    inner = Image.new("RGBA", img.size, (0, 0, 0, 0))
    di = ImageDraw.Draw(inner)
    step = 9 * S
    for k in range(-CH * S, CW * S + CH * S, step):
        di.line([(k, 0), (k + CH * S, CH * S)], fill=GOLD_LO + (150,), width=S // 2)
        di.line([(k, CH * S), (k + CH * S, 0)], fill=GOLD_LO + (150,), width=S // 2)
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([7 * S, 7 * S, CW * S - 7 * S, CH * S - 7 * S], radius=4 * S, fill=255)
    img.paste(inner, (0, 0), Image.composite(inner.split()[3], Image.new("L", img.size, 0), mask))
    d.rounded_rectangle([7 * S, 7 * S, CW * S - 7 * S, CH * S - 7 * S], radius=4 * S, outline=GOLD_LO, width=S)
    r = 21 * S
    cx, cy = CW * S // 2, CH * S // 2
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=INK, outline=GOLD, width=S)
    img.alpha_composite(round_mark(mark, 40 * S), (cx - 20 * S, cy - 20 * S))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=GOLD, width=S)
    return img.resize((CW, CH), Image.LANCZOS)


def cards(mark):
    sheet = Image.new("RGBA", (1024, 512), (0, 0, 0, 0))
    for s in range(4):
        for r, rank in enumerate(RANKS):
            sheet.alpha_composite(card_face(rank, s), (r * CW, s * CH))
    sheet.alpha_composite(card_back(mark), (13 * CW, 0))
    save(sheet, "cards")


# ---------------------------------------------------------------- the wheel
# The American wheel, clockwise from the single zero.
WHEEL = ["0", "28", "9", "26", "30", "11", "7", "20", "32", "17", "5", "22", "34", "15", "3", "24", "36", "13", "1",
         "00", "27", "10", "25", "29", "12", "8", "19", "31", "18", "6", "21", "33", "16", "4", "23", "35", "14", "2"]
REDS = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}


def wheel():
    n = 1024
    c = n // 2
    R = c - 8
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    def disc(frac, fill, outline=None, width=0):
        r = R * frac
        d.ellipse([c - r, c - r, c + r, c + r], fill=fill, outline=outline, width=width)

    disc(1.0, GOLD_LO)
    disc(0.985, GOLD)
    disc(0.955, GOLD_HI)
    disc(0.94, GOLD_LO)
    step = 360.0 / len(WHEEL)
    for ring, shade in ((0.925, 1.0), (0.64, 0.72)):
        r = R * ring
        for i, name in enumerate(WHEEL):
            base = GREEN if name in ("0", "00") else RED if int(name) in REDS else BLACK
            fill = tuple(int(v * shade) for v in base)
            a = i * step - 90
            d.pieslice([c - r, c - r, c + r, c + r], a - step / 2, a + step / 2, fill=fill)
        for i in range(len(WHEEL)):
            a = math.radians(i * step - 90 + step / 2)
            d.line([(c, c), (c + r * math.cos(a), c + r * math.sin(a))], fill=GOLD, width=3)
        d.ellipse([c - r, c - r, c + r, c + r], outline=GOLD, width=4)
    disc(0.46, (34, 26, 18), GOLD, 5)
    for k in range(8):
        a = math.radians(k * 45)
        d.line([(c, c), (c + R * 0.44 * math.cos(a), c + R * 0.44 * math.sin(a))], fill=GOLD_LO, width=7)
    disc(0.17, GOLD_LO)
    disc(0.15, GOLD)
    disc(0.09, GOLD_HI)
    disc(0.05, GOLD_LO)
    num_font = font(SANS, 40)
    for i, name in enumerate(WHEEL):
        tile = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
        centred(ImageDraw.Draw(tile), (48, 48), name, num_font, (250, 246, 236))
        tile = tile.rotate(-i * step, resample=Image.BICUBIC)
        a = math.radians(i * step)
        x, y = c + R * 0.79 * math.sin(a), c - R * 0.79 * math.cos(a)
        img.alpha_composite(tile, (int(x - 48), int(y - 48)))
    save(img.resize((512, 512), Image.LANCZOS), "wheel")


def ball():
    n = 128
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([14, 18, 118, 122], fill=(0, 0, 0, 90))
    d.ellipse([10, 10, 114, 114], fill=(236, 236, 232), outline=(120, 120, 120), width=4)
    d.ellipse([30, 26, 66, 58], fill=(255, 255, 255))
    save(img.filter(ImageFilter.GaussianBlur(1.2)).resize((32, 32), Image.LANCZOS), "ball")


# ---------------------------------------------------------------- the reels
SYM = 128


def sym_canvas():
    img = Image.new("RGBA", (SYM * S, SYM * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def sym_seven():
    img, d = sym_canvas()
    f = font(SERIF, 118 * S)
    centred(d, (64 * S, 62 * S), "7", f, RED, stroke_width=5 * S, stroke_fill=GOLD)
    return img


def sym_bar():
    img, d = sym_canvas()
    d.rounded_rectangle([8 * S, 36 * S, 120 * S, 92 * S], radius=10 * S, fill=INK, outline=GOLD, width=5 * S)
    d.rounded_rectangle([16 * S, 44 * S, 112 * S, 84 * S], radius=5 * S, outline=GOLD_LO, width=S)
    centred(d, (64 * S, 64 * S), "BAR", font(SERIF, 34 * S), GOLD_HI)
    return img


def sym_bell():
    img, d = sym_canvas()
    d.ellipse([54 * S, 10 * S, 74 * S, 30 * S], outline=GOLD_LO, width=5 * S)
    d.ellipse([30 * S, 22 * S, 98 * S, 100 * S], fill=GOLD)
    d.polygon([(30 * S, 62 * S), (98 * S, 62 * S), (116 * S, 98 * S), (12 * S, 98 * S)], fill=GOLD)
    d.rounded_rectangle([10 * S, 92 * S, 118 * S, 106 * S], radius=7 * S, fill=GOLD_LO)
    d.ellipse([52 * S, 100 * S, 76 * S, 122 * S], fill=GOLD_LO)
    d.ellipse([42 * S, 34 * S, 58 * S, 72 * S], fill=GOLD_HI)
    return img


def sym_cherry():
    img, d = sym_canvas()
    stem = (60, 110, 40)
    d.arc([20 * S, 14 * S, 110 * S, 150 * S], 200, 275, fill=stem, width=5 * S)
    d.arc([40 * S, 14 * S, 150 * S, 170 * S], 195, 262, fill=stem, width=5 * S)
    d.ellipse([74 * S, 8 * S, 112 * S, 30 * S], fill=(70, 140, 50))
    for cx, cy in ((40, 86), (86, 92)):
        d.ellipse([(cx - 28) * S, (cy - 28) * S, (cx + 28) * S, (cy + 28) * S], fill=RED, outline=(110, 14, 20), width=2 * S)
        d.ellipse([(cx - 16) * S, (cy - 18) * S, (cx - 4) * S, (cy - 6) * S], fill=(240, 130, 130))
    return img


def sym_lemon():
    img, d = sym_canvas()
    body = (240, 208, 50)
    d.polygon([(4 * S, 64 * S), (26 * S, 50 * S), (26 * S, 78 * S)], fill=body)
    d.polygon([(124 * S, 64 * S), (102 * S, 50 * S), (102 * S, 78 * S)], fill=body)
    d.ellipse([16 * S, 28 * S, 112 * S, 100 * S], fill=body, outline=(170, 140, 20), width=2 * S)
    d.ellipse([34 * S, 40 * S, 64 * S, 58 * S], fill=(252, 238, 150))
    return img.rotate(20, resample=Image.BICUBIC)


def sym_tiger(mark):
    img, d = sym_canvas()
    d.ellipse([4 * S, 4 * S, 124 * S, 124 * S], fill=INK, outline=GOLD, width=5 * S)
    img.alpha_composite(round_mark(mark, 114 * S), (7 * S, 7 * S))
    d.ellipse([4 * S, 4 * S, 124 * S, 124 * S], outline=GOLD, width=5 * S)
    return img


def reels(mark):
    # In the order the addon lists them: Tiger, Seven, Bar, Bell, Cherry, Lemon.
    sheet = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    art = [sym_tiger(mark), sym_seven(), sym_bar(), sym_bell(), sym_cherry(), sym_lemon()]
    for i, img in enumerate(art):
        sheet.alpha_composite(img.resize((SYM, SYM), Image.LANCZOS), ((i % 4) * SYM, (i // 4) * SYM))
    save(sheet, "reels")


# ---------------------------------------------------------------- felt and chip
def felt():
    w, h = 512, 256
    rnd = random.Random(7)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dx, dy = (x - w / 2) / (w / 2), (y - h / 2) / (h / 2)
            v = 1.0 - 0.45 * min(1.0, dx * dx * 0.7 + dy * dy * 0.9)
            g = rnd.uniform(-5, 5)
            px[x, y] = (int(10 * v + g / 3), int((78 * v) + g), int(46 * v + g / 2), 255)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([5, 5, w - 6, h - 6], radius=12, outline=GOLD_LO, width=2)
    save(img, "felt")


def chip():
    n = 64 * S
    c = n // 2
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = c - 2 * S
    d.ellipse([c - r, c - r, c + r, c + r], fill=(235, 235, 235), outline=(70, 70, 70), width=2 * S)
    for k in range(8):
        a = k * 45
        d.pieslice([c - r + 2 * S, c - r + 2 * S, c + r - 2 * S, c + r - 2 * S], a - 9, a + 9, fill=(70, 70, 70))
    r2 = int(r * 0.70)
    d.ellipse([c - r2, c - r2, c + r2, c + r2], fill=(250, 250, 250), outline=(90, 90, 90), width=2 * S)
    r3 = int(r * 0.50)
    d.ellipse([c - r3, c - r3, c + r3, c + r3], outline=(150, 150, 150), width=S)
    save(img.resize((64, 64), Image.LANCZOS), "chip")


def main():
    mark = Image.open(os.path.join(OUT, "mark.tga")).convert("RGBA")
    cards(mark)
    wheel()
    ball()
    reels(mark)
    felt()
    chip()


if __name__ == "__main__":
    main()
