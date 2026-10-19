#!/usr/bin/env python3
"""Карта на светлината за кориците → assets/cover_light/book1.png

    python3 05_cover_light.py

Кориците НЕ се пипат: приложението прилага картата при показване, с шейдъра
shaders/cover_light.frag (lib/cover_light.dart) — така важи и за всяка бъдеща
корица. Изворът е маската tools/chitalnya/input/cover_mask1.png (рисувана от
потребителя, 19.10.2026; ⚠ input/ не е в git). Изборът на автора е
„гръбче ½ + Осветяване":

  1. рамката — маската има прозрачна ивица по краищата, която по ръба на
     корицата излизаше като тъмна черта; изрязва се (+2 px запас);
  2. гръбчето — лявата зона (светлата ивица и прегъвката, ~110 px от
     маската) се свива наполовина, останалото се разтяга леко;
  3. осветяване — маската се чете като карта на светлината СПРЯМО СРЕДАТА
     си: средата остава колкото е, ръбовете светват или тъмнеят, гръбчето
     носи топлия си оттенък (30%);
  4. затъмняването се отслабва (SHADOW) и всичко светва малко (LIFT).

Картата е коефициент за всеки цвят: корица × коефициент. В PNG-то е записан
коефициент / 2 (стига до ~1,31, тоест над 1 — изсветлява), шейдърът умножава
по 2. Размерът е на кориците (479×741); друга пропорция я разтяга.
"""
from pathlib import Path

import numpy as np
from PIL import Image

PROJ = Path(__file__).resolve().parents[3]
OUT = PROJ / 'assets' / 'cover_light' / 'book1.png'
SIZE = (479, 741)
MASK = PROJ / 'tools' / 'chitalnya' / 'input' / 'cover_mask1.png'

SPINE = 110        # лявата зона на маската (в пиксели на оригинала)
SPINE_SCALE = 0.5  # „гръбче ½"
TINT = 0.3         # колко от топлия оттенък на маската влиза
# 19.10.2026, след преглед на телефона: десният и долният ръб тъмнееха до
# ~0,55 (на места 0,17) и кориците изглеждаха тъмни. Изборът е между пробите
# C и D (artifact „Корици — по-светли“):
SHADOW = 0.4       # колко от затъмняването на маската остава (1 = цялото)
LIFT = 1.065       # обща светлина


def prepared_mask(size):
    m = np.array(Image.open(MASK).convert('RGBA')).astype(float)
    a = m[..., 3]
    # 1) рамката — докъдето маската още не е плътна
    rows = np.where(a[:, 200:800].mean(1) > 200)[0]
    cols = np.where(a[300:1300].mean(0) > 190)[0]
    if not len(rows) or not len(cols):
        raise SystemExit('маската няма плътна част — друг файл ли е?')
    m = m[rows[0] + 2:rows[-1] - 1, cols[0] + 2:cols[-1] - 1]
    # 2) гръбчето — стъпаловидно (линейно) преразпределение по x
    w = m.shape[1]
    xo = np.arange(w, dtype=float)
    nb = SPINE * SPINE_SCALE
    xs = np.where(xo < nb, xo / SPINE_SCALE,
                  SPINE + (xo - nb) * (w - 1 - SPINE) / (w - 1 - nb))
    i0 = np.floor(xs).astype(int).clip(0, w - 2)
    f = (xs - i0)[None, :, None]
    m = m[:, i0] * (1 - f) + m[:, i0 + 1] * f
    img = Image.fromarray(m.clip(0, 255).astype('uint8'), 'RGBA')
    m = np.array(img.resize(size, Image.LANCZOS)).astype(float) / 255
    return m[..., :3], m[..., 3:4]


def light_map(rgb, a):
    seen = 0.5 * (1 - a) + rgb * a          # маската върху неутрално сиво
    lum = seen.mean(2, keepdims=True)
    h, w = lum.shape[:2]
    ref = np.median(lum[h * 27 // 100:h * 73 // 100, w // 4:w * 3 // 4])
    tint = seen / np.maximum(lum, 1e-3)
    g = (lum / ref) * ((1 - TINT) + TINT * tint)
    # само тъмното се свива към 1; отблясъците остават
    l = g.mean(2, keepdims=True)
    nl = np.where(l < 1, 1 - (1 - l) * SHADOW, l)
    return g * (nl / np.maximum(l, 1e-3)) * LIFT


def main():
    g = light_map(*prepared_mask(SIZE))
    if g.max() >= 2:
        raise SystemExit(f'коефициентът стига {g.max():.2f} — не се побира в /2')
    OUT.parent.mkdir(exist_ok=True)
    Image.fromarray((g / 2 * 255 + .5).clip(0, 255).astype('uint8')).save(OUT, optimize=True)
    print(f'{OUT.relative_to(PROJ)}: {SIZE[0]}×{SIZE[1]}, коефициент '
          f'{g.min():.2f}…{g.max():.2f}, {OUT.stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
