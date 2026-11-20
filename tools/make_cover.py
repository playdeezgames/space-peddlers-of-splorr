#!/usr/bin/env python3
"""Draws assets/cover.png (630 by 500): the title in m6x11 on a starfield, next to the
game's own Short Range Chart frame (build/shots/05-warp.ppm, made by tools/make_shots.sh).
No original Space Trader art is used. Needs Pillow. Run from the repo root."""
import random
from PIL import Image, ImageDraw

NAVY, WHITE, ORANGE, YELLOW, GREY = (0x1D, 0x2B, 0x53), (255, 255, 255), (0xFF, 0xA3, 0x00), (0xFF, 0xEC, 0x27), (0xC2, 0xC3, 0xC7)
font = Image.open("assets/fonts/Fontm6x11.png").convert("L")
CW, CH = 10, 14

def glyph(c):
    i = ord(c) - 32
    g = font.crop(((i % 16) * CW, (i // 16) * CH, (i % 16) * CW + CW, (i // 16) * CH + CH))
    ink = [x for x in range(CW) for y in range(CH) if g.getpixel((x, y)) < 128]
    return g, (max(ink) + 2 if ink else 5)

def text(img, s, x, y, scale, col):
    for c in s:
        g, adv = glyph(c)
        for gy in range(CH):
            for gx in range(CW):
                if g.getpixel((gx, gy)) < 128:
                    img.paste(col, (x + gx * scale, y + gy * scale, x + (gx + 1) * scale, y + (gy + 1) * scale))
        x += adv * scale

def width(s, scale):
    return sum(glyph(c)[1] for c in s) * scale

cover = Image.new("RGB", (630, 500), NAVY)
d = ImageDraw.Draw(cover)
rnd = random.Random(1202)
for _ in range(260):
    x, y = rnd.randrange(630), rnd.randrange(500)
    s = rnd.choice((2, 2, 2, 4))
    d.rectangle((x, y, x + s - 1, y + s - 1), fill=rnd.choice((WHITE, GREY)))

chart = Image.open("build/shots/05-warp.ppm").convert("RGB")
cx, cy = 296, 160
d.rectangle((cx - 8, cy - 8, cx + 327, cy + 327), fill=(0x5F, 0x57, 0x4F))
cover.paste(chart, (cx, cy))

lines = [("SPACE", 5, ORANGE), ("PEDDLERS", 5, ORANGE), ("of SPLORR!!", 3, YELLOW)]
y = 24
for s, sc, col in lines:
    text(cover, s, 24, y, sc, col)
    y += 13 * sc
for i, s in enumerate(("Buy low,", "sell high,", "dodge the", "pirates.")):
    text(cover, s, 24, 250 + i * 30, 2, WHITE)
for i, s in enumerate(("A port of", "Space Trader", "by Pieter", "Spronck")):
    text(cover, s, 24, 384 + i * 26, 2, GREY)
cover.save("assets/cover.png", optimize=True)
print("assets/cover.png", cover.size)
