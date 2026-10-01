#!/usr/bin/env python3
"""Временни корици за „Читалня" → assets/chitalnya_covers/<код>.jpg

    python3 03_covers.py        # ПРЕДИ 02_build_epubs.py — той ги вгражда

⚠ Примерни, до истинските (потребителят ще ги подмени). Размерът е като на
томовете в „Месецослов" — 479×741 — тъй че пропорцията в Cover Flow е същата.
Подмяна: сложи свой .jpg със същото име и пусни наново 02_build_epubs.py.
"""
import random
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

PROJ = Path(__file__).resolve().parents[3]
FONTS = PROJ / 'assets' / 'fonts'
CROSS_SVG = PROJ / 'assets' / 'icons' / 'cross.svg'
SS = 3          # свръхдискретизация: рисува се три пъти по-едро и се смалява
OUT = PROJ / 'assets' / 'chitalnya_covers'
W, H = 479, 741
GOLD = (201, 168, 96)

BOOKS = [
    # код, заглавие (по редове), автор, цвят на подвързията
    ('debolsky', ['Дни', 'на богослужението'], 'Прот. Григорий Дебольски', (38, 62, 48)),
    ('zlatoust', ['Похвални слова', 'за светиите'], 'Свт. Йоан Златоуст', (92, 30, 32)),
    ('teofan', ['Мисли', 'за всеки ден', 'от годината'], 'Свт. Теофан Затворник', (28, 42, 72)),
    ('optina', ['Изречения', 'от Оптинските', 'старци'], 'Прпп. Оптински старци', (70, 48, 30)),
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


def cross_mask(height):
    """Православният кръст (assets/icons/cross.svg) като маска — през Inkscape.

    ⚠ PIL не чете SVG. Рисува се ЧЕРЕН на прозрачно и се ползва само алфата —
    цветът и релефът се слагат тук, за да са еднакви с рамката.
    """
    with tempfile.TemporaryDirectory() as d:
        png = Path(d) / 'c.png'
        subprocess.run(['inkscape', str(CROSS_SVG), '--export-type=png',
                        f'--export-filename={png}', f'--export-height={height}'],
                       check=True, capture_output=True)
        return Image.open(png).convert('RGBA').split()[3]


def emboss(base, mask, xy, color):
    """Позлатен отпечатък: тъмна вдлъбнатина отдолу-вдясно, светъл ръб
    отгоре-вляво, после самото злато — като щамповано в подвързията."""
    x, y = xy
    shadow = Image.new('RGBA', mask.size, (0, 0, 0, 0))
    shadow.putalpha(mask.point(lambda a: a * 0.55))
    shadow = shadow.filter(ImageFilter.GaussianBlur(2 * SS))
    base.alpha_composite(shadow, (x + 2 * SS, y + 3 * SS))
    light = Image.new('RGBA', mask.size, (255, 236, 190, 0))
    light.putalpha(mask.point(lambda a: a * 0.35))
    base.alpha_composite(light, (x - SS, y - SS))
    # Златото е с лек преход отгоре надолу — плоското изглежда като стикер.
    w, h = mask.size
    grad = Image.new('RGBA', (w, h))
    gp = grad.load()
    for yy in range(h):
        t = yy / max(1, h - 1)
        c = tuple(int(color[i] * (1.12 - 0.24 * t)) for i in range(3))
        c = tuple(min(255, v) for v in c)
        for xx in range(w):
            gp[xx, yy] = c + (255,)
    grad.putalpha(mask)
    base.alpha_composite(grad, (x, y))


def fit(d, lines, path, size, maxw):
    """Най-едрият кегел до `size`, при който ВСЕКИ ред се побира в рамката."""
    while size > 20:
        f = ImageFont.truetype(str(path), size)
        if all(d.textlength(t, font=f) <= maxw for t in lines):
            return f
        size -= 1
    return ImageFont.truetype(str(path), size)


def cover(code, lines, author, base):
    big = leather(base).resize((W * SS, H * SS), Image.LANCZOS).convert('RGBA')
    d = ImageDraw.Draw(big)
    # Двойна рамка.
    for m, wd in ((22, 3), (32, 1)):
        d.rectangle([m * SS, m * SS, (W - m) * SS, (H - m) * SS],
                    outline=GOLD, width=wd * SS)
    # Кръстът — по-едър от досегашния, в горната трета.
    cm = cross_mask(118 * SS)
    emboss(big, cm, ((W * SS - cm.width) // 2, 62 * SS), GOLD)
    # Заглавието — по-едро; кегелът се свива само ако ред не се побира.
    inner = (W - 2 * 48) * SS
    title = fit(d, lines, FONTS / 'Tamburin Modern.ttf', 60 * SS, inner)
    step = int(title.size * 1.28)
    block = step * (len(lines) - 1) + title.size
    y = int(370 * SS - block / 2)
    # ⚠ Сянката е на ОТДЕЛЕН слой и се смесва (alpha_composite). Нарисувана
    # направо с полупрозрачен цвят, ImageDraw ПОДМЕНЯ пикселите вместо да ги
    # смесва и буквите излизат с твърд черен контур.
    shade = Image.new('RGBA', big.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    y0 = y
    for ln in lines:
        w = d.textlength(ln, font=title)
        sd.text(((W * SS - w) / 2 + 2 * SS, y + 3 * SS), ln, font=title,
                fill=(0, 0, 0, 140))
        y += step
    big.alpha_composite(shade.filter(ImageFilter.GaussianBlur(2 * SS)))
    d = ImageDraw.Draw(big)
    y = y0
    for ln in lines:
        w = d.textlength(ln, font=title)
        d.text(((W * SS - w) / 2, y), ln, font=title, fill=GOLD + (255,))
        y += step
    # Орнаментална черта: по-къса от реда, с ромбче по средата.
    ly = y - step + title.size + 34 * SS
    cx = W * SS // 2
    d.line([cx - 78 * SS, ly, cx - 10 * SS, ly], fill=GOLD, width=2 * SS)
    d.line([cx + 10 * SS, ly, cx + 78 * SS, ly], fill=GOLD, width=2 * SS)
    r = 5 * SS
    d.polygon([(cx, ly - r), (cx + r, ly), (cx, ly + r), (cx - r, ly)], fill=GOLD)
    # Авторът — по-едър курсив над долния ръб на рамката.
    au = fit(d, [author], FONTS / 'CharisSIL-Italic.ttf', 30 * SS, inner)
    w = d.textlength(author, font=au)
    d.text(((W * SS - w) / 2, (H - 112) * SS), author, font=au, fill=(230, 214, 176))
    img = big.convert('RGB').resize((W, H), Image.LANCZOS)
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f'{code}.jpg', quality=90)
    print('  ', code, 'кегел', title.size // SS)


if __name__ == '__main__':
    for b in BOOKS:
        cover(*b)
