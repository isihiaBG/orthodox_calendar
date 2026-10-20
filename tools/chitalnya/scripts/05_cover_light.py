#!/usr/bin/env python3
"""Карта на светлината за кориците → assets/cover_light/book1.png

    python3 05_cover_light.py [ключ=стойност …]

Кориците НЕ се пипат: приложението прилага картата при показване, с шейдъра
shaders/cover_light.frag (lib/cover_light.dart) — така важи и за всяка бъдеща
корица. Шейдърът заобля и ъглите.

Изворът (21.10.2026) е снимка на истинска кожена корица от потребителя —
tools/chitalnya/input/cover_leather.png (⚠ input/ не е в git). Избран от
автора вариант „E2" (artifact „Разговори — отблизо"):

  1. само яркостта, изрязана ТОЧНО по ръба на кожата — тъмното поле около
     книгата на снимката изглеждаше като подрязана корица;
  2. петте рингчета на гръбчето — заменени с парче от гръбчето над тях;
  3. обемът е гладкото засенчване; детайлът по горния, долния и десния ръб
     нараства ПЛАВНО от нула (на `tex` навътре) до пълен на самия ръб.
     Детайлът е релеф (кантът, отблясъците — пази се) и зърно (кожата —
     остава `grainamt`, цяло само в най-външната ивица). Гръбчето с
     прегъвката вляво — както е;
  4. спрямо средата → коефициент; средата е точно 1 (неутрално);
     сянката × `shadow`, отблясъците — меко таване (`knee`);
  5. гръбчето свито (`spine_scale`), пропорцията 479×741 — разтяга се
     средата, ръбовете остават в мащаб;
  6. мека сянка 4 px по самия долен и десен ръб — да не изглеждат отрязани.

Картата е корица × коефициент; в PNG-то е коефициент / 2, шейдърът × 2.
Същата маска и като RGBA (бяло/черно с алфа = сила) — в work/.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

PROJ = Path(__file__).resolve().parents[3]
SRC = PROJ / 'tools' / 'chitalnya' / 'input' / 'cover_leather.png'
OUT = PROJ / 'assets' / 'cover_light' / 'book1.png'
RGBA = PROJ / 'tools' / 'chitalnya' / 'work' / 'cover_mask_leather_rgba.png'

P = dict(
    tex=0.14,      # детайлът стига до тук (дял от ширината)
    tex_pow=2.5,   # колко бавно нараства към ръба
    relief=5.0,    # над тази мярка (px) е релеф, под нея — зърно
    grainamt=0.2,  # колко зърно остава навътре от ръба
    rim=0.012,     # най-външната ивица, където зърното е пълно
    rim_w=4.0,     # мека сянка по долния и десния ръб: ширина (px на корицата)
    rim_d=0.32,    # … и дълбочина в края
    edge=0.08,     # до тук засенчването е пълно
    fade=0.18,     # до тук стига до неутрално
    grain=1.8,     # изглаждане в зоната на релефа (px) — само шумът
    center=30.0,
    spine=44,      # гръбчето в оригинала (без прегъвката)
    spine_scale=0.6,
    shadow=0.75,   # колко от затъмняването остава
    light=1.0,     # колко от изсветляването остава
    knee=0.9,      # меко таване на отблясъците: макс. добавка → knee
    W=958,
)
for kv in sys.argv[1:]:
    k, v = kv.split('=')
    P[k] = float(v)
W = int(P['W']); H = round(W * 741 / 479)

src = np.array(Image.open(SRC).convert('RGB')).astype(float)
L = src @ [0.299, 0.587, 0.114]
L = L[:1481, :1042].copy()   # точно по ръба на кожата — без тъмното поле около книгата
h, w = L.shape

# 1) рингчетата: всеки пояс се заменя с парче от гръбчето над него (същата
#    кожа, същият релеф), със слети краища — не с изглаждане
sp = int(P['spine'])
RINGS = [(262, 308), (468, 522), (664, 718), (876, 926), (1124, 1172)]
for a, b in RINGS:
    n = b - a; f = 10
    srcrows = L[a - n - 30:b - 30 + 2 * f, :sp + 4].copy()
    patch = srcrows[f:f + n]
    wgt = np.ones(n)
    wgt[:f] = np.linspace(0, 1, f); wgt[-f:] = np.linspace(1, 0, f)
    wgt = wgt[:, None]
    L[a:b, :sp + 4] = L[a:b, :sp + 4] * (1 - wgt) + patch * wgt

# 2) кожата: основа = гладкото засенчване; отгоре — детайлът (релеф, кант),
#    който по горния, долния и десния ръб нараства ПЛАВНО от нула навътре до
#    пълен на самия ръб. Гръбчето вляво с прегъвката остава както е.
yy, xx = np.mgrid[0:h, 0:w].astype(float)
dx = np.minimum(xx, w - 1 - xx); dy = np.minimum(yy, h - 1 - yy)
d = np.minimum(dx, dy) / w
def ss(x):
    x = np.clip(x, 0, 1); return x * x * (3 - 2 * x)
fine = gaussian_filter(L, P['grain'])
cen = gaussian_filter(L, P['center'])
d_trb = np.minimum(dy, w - 1 - xx) / w          # без левия ръб
amt = ss(1 - d_trb / P['tex']) ** P['tex_pow']
sp_end = sp + 18                                  # гръбчето + прегъвката
left = ss(1 - (xx - sp_end) / 40.0)               # 1 до прегъвката, после бързо 0
amt = np.maximum(amt, left)
# детайлът на две части: релеф (кантът, отблясъците — по-едрото) и зърно
# (кожата). Зърното е притъпено навсякъде освен в самата най-външна ивица.
rel = gaussian_filter(L, P['relief'])
edge = ss(1 - d_trb / P['rim'])
gk = P['grainamt'] + (1 - P['grainamt']) * edge
gk = np.maximum(gk, left)
low = cen + (rel - cen) * amt + (fine - rel) * amt * gk

# 3) спрямо средата → коефициент
ref = np.median(cen[h * 3 // 10:h * 7 // 10, w // 4:w * 3 // 4])
g = low / ref

# 4) неутрален център + сила на сянката/светлината (отблясъците — меко таване)
t = ss((d - P['edge']) / (P['fade'] - P['edge']))
g = 1 + (g - 1) * (1 - t)
up = (g - 1) * P['light']
up = up / (1 + up / P['knee'])
g = np.where(g < 1, 1 - (1 - g) * P['shadow'], 1 + up)

# 5) гръбчето по-тясно + пропорцията 479×741: ръбовете в мащаб, разтяга се средата
def axis_map(n_out, n_in, lo, hi, lo_scale):
    # мащаб: изход/вход на ръбовете = n_out_edge; използваме единичен мащаб f
    f = W / w                               # px изход за px вход по ширина
    lo_out = lo * f * lo_scale; hi_out = hi * f
    o = np.arange(n_out, dtype=float)
    mid_in = n_in - lo - hi; mid_out = n_out - lo_out - hi_out
    return np.where(o < lo_out, o / (f * lo_scale),
           np.where(o > n_out - hi_out, n_in - (n_out - o) / f,
                    lo + (o - lo_out) * mid_in / mid_out))
xs = axis_map(W, w, sp, 0, P['spine_scale'])
ys = axis_map(H, h, 250, 250, 1.0)
Y, X = np.meshgrid(ys, xs, indexing='ij')
G = map_coordinates(g, [Y, X], order=1, mode='nearest')

# 6) мека сянка по самия долен и десен ръб — да не изглеждат отрязани.
#    Ширината е в пиксели на корицата (479 широка), картата е W широка.
if P['rim_w'] > 0:
    k = W / 479
    yy2, xx2 = np.mgrid[0:H, 0:W].astype(float)
    def fall(dd):
        t = np.clip(1 - dd / (P['rim_w'] * k), 0, 1); return t * t
    r = np.maximum(fall(W - 1 - xx2), fall(H - 1 - yy2))
    G = G * (1 - P['rim_d'] * r)

if G.max() >= 2:
    raise SystemExit(f'коефициентът стига {G.max():.2f} — не се побира в /2')
OUT.parent.mkdir(exist_ok=True)
Image.fromarray((G / 2 * 255 + .5).clip(0, 255).astype('uint8')).convert('RGB').save(OUT, optimize=True)
# Същото като RGBA за наслагване в други програми: бяло, където светва,
# черно, където тъмнее; алфата е силата, в средата 0.
a = np.where(G < 1, 1 - G, np.minimum(G - 1, 1))
rgba = np.zeros((H, W, 4), 'uint8')
rgba[..., :3] = np.where(G[..., None] > 1, 255, 0)
rgba[..., 3] = (a * 255 + .5).clip(0, 255)
RGBA.parent.mkdir(exist_ok=True)
Image.fromarray(rgba, 'RGBA').save(RGBA, optimize=True)
print(f'{OUT.relative_to(PROJ)}: {W}×{H}, коефициент {G.min():.2f}…{G.max():.2f}, '
      f'център {G[H // 2, W // 2]:.3f}, {OUT.stat().st_size // 1024} KB')
print(f'{RGBA.relative_to(PROJ)} (RGBA)')
