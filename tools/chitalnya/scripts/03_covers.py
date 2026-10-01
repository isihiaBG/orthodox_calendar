#!/usr/bin/env python3
"""Временни корици за „Читалня" → assets/chitalnya_covers/<код>.jpg

    python3 03_covers.py        # ПРЕДИ 02_build_epubs.py — той ги вгражда

⚠ Примерни, до истинските (потребителят ще ги подмени). Размерът е като на
томовете в „Месецослов" — 479×741 — тъй че пропорцията в Cover Flow е същата.
Подмяна: сложи свой .jpg със същото име и пусни наново 02_build_epubs.py.
"""
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

PROJ = Path(__file__).resolve().parents[3]
FONTS = PROJ / 'assets' / 'fonts'
OUT = PROJ / 'assets' / 'chitalnya_covers'
W, H = 479, 741
GOLD = (201, 168, 96)

BOOKS = [
    # код, заглавие (по редове), автор, цвят на подвързията
    ('debolsky', ['Дни', 'на богослужението'], 'Прот. Григорий Дебольски', (38, 62, 48)),
    ('zlatoust', ['Похвални слова', 'за светиите'], 'Свт. Йоан Златоуст', (92, 30, 32)),
    ('teofan', ['Мисли', 'за всеки ден', 'от годината'], 'Свт. Теофан Затворник', (28, 42, 72)),
    ('optina', ['Мисли', 'на Оптинските', 'старци'], 'Прпп. Оптински старци', (70, 48, 30)),
]


def leather(base):
    """Подвързия: основният цвят с едва доловима зърнистост и тъмни ъгли."""
    rnd = random.Random(sum(base))
    img = Image.new('RGB', (W, H), base)
    px = img.load()
    for y in range(H):
        for x in range(W):
            n = rnd.randint(-9, 9)
            dx, dy = (x - W / 2) / (W / 2), (y - H / 2) / (H / 2)
            v = 1 - 0.35 * min(1, (dx * dx + dy * dy) / 2)
            px[x, y] = tuple(max(0, min(255, int(c * v) + n)) for c in base)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def centered(d, y, text, font, fill):
    w = d.textlength(text, font=font)
    d.text(((W - w) / 2, y), text, font=font, fill=fill)


def cover(code, lines, author, base):
    img = leather(base)
    d = ImageDraw.Draw(img)
    # Двойна рамка.
    for m, wd in ((22, 3), (32, 1)):
        d.rectangle([m, m, W - m, H - m], outline=GOLD, width=wd)
    # Кръстче горе.
    cx, cy = W // 2, 120
    d.line([cx, cy - 34, cx, cy + 34], fill=GOLD, width=5)
    d.line([cx - 20, cy - 14, cx + 20, cy - 14], fill=GOLD, width=5)
    d.line([cx - 14, cy + 16, cx + 14, cy + 8], fill=GOLD, width=4)
    title = ImageFont.truetype(str(FONTS / 'Tamburin Modern.ttf'), 46)
    y = 260 - 28 * (len(lines) - 2)
    for ln in lines:
        centered(d, y, ln, title, GOLD)
        y += 62
    # Орнаментална черта и авторът.
    d.line([W / 2 - 70, y + 24, W / 2 + 70, y + 24], fill=GOLD, width=2)
    au = ImageFont.truetype(str(FONTS / 'CharisSIL-Italic.ttf'), 24)
    centered(d, H - 130, author, au, (226, 210, 170))
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f'{code}.jpg', quality=88)
    print('  ', code)


if __name__ == '__main__':
    for b in BOOKS:
        cover(*b)
