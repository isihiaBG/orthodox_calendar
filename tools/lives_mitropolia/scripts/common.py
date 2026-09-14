#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Общото за конвейера — пътища, теглене, нормализация на имена.

Втори извор за жития на български светии, след `tools/lives_bg/`
(pravoslavieto.com). Поводът: там ги няма св. цар Тервел, св. Райко-Йоан
Шуменски и още десетина, а сайтът на Софийска света митрополия ги има в
поредицата „Кръстният подвиг на българските светии".

⚠ Сайтът е WordPress с Elementor — съдържанието НЕ стои в `entry-content`
или друг говорещ клас, а е разпръснато из `elementor-widget-*` кутии.
Затова разчитането не търси контейнер, а взима всички `<p>` от страницата
и отсява по дължина (виж `03_apply.py`).
"""

from __future__ import annotations

import re
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / 'cache'
WORK = ROOT / 'work'
INPUT = ROOT / 'input'
PROJECT = ROOT.parents[1]
LIVES_DB = PROJECT / 'assets' / 'db' / 'lives.db'
CALENDAR_DB = PROJECT / 'assets' / 'db' / 'calendar_old.db'
SEED_DB = PROJECT / 'tools' / 'calendar_gen' / 'input' / 'db' / 'calendar_old.db'

BASE = 'https://mitropolia-sofia.org'
CATEGORY = f'{BASE}/category/biblioteka/bgsvetii/'

# ⚠ Сървърът отказва празен или съкратен User-Agent — с обикновено `curl`
# връща 0 байта. Затова се представяме като браузър.
UA = ('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36')

PAUSE = 1.0  # секунда между заявките — чужд сайт, не го натоварваме


def fetch(url: str, dest: Path, force: bool = False) -> bool:
    """Тегли адреса в [dest]. Връща True, ако е теглено сега."""
    if dest.exists() and not force and dest.stat().st_size > 5000:
        return False
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=40) as r:
        data = r.read()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    time.sleep(PAUSE)
    return True


# ── Нормализация на имена ────────────────────────────────────────────
# ⚠ Двата извора пишат едно и също име различно: „Св. преподобни Гавриил
# Лесновски (15.I) – житие и карта" срещу „Прп. Гавриил Лесновски († XI в.)".
# Затова сравнението е по МНОЖЕСТВО ЗНАЧЕЩИ ДУМИ, а не по низ.

_RANKS = {
    'свети', 'света', 'преп', 'преподобни', 'преподобна', 'преподобний',
    'мчк', 'мъченик', 'мъченица', 'мчца', 'свщмчк', 'свещеномъченик',
    'прпмчк', 'прпмчци', 'прпмчч', 'преподобномъченик', 'вмчца', 'вмч',
    'великомъченица', 'великомъченик', 'митр', 'митрополит', 'патр',
    'патриарх', 'археп', 'архиеп', 'архиепископ', 'еп', 'епископ',
    'български', 'българин', 'българска', 'цар', 'княз', 'благоверни',
    'благоверен', 'прав', 'праведни', 'равноап', 'равноапостолни',
    'свт', 'свв', 'жит', 'житие', 'карта', 'сведения', 'учениците',
}


def _fold(w: str) -> str:
    return w.lower().replace('ѝ', 'и').replace('й', 'и').replace('ъ', '')


# ⚠ Списъкът се СВИВА по същия начин, по който се свиват и думите от името.
# Иначе „български" в него никога не съвпада с „блгарски" от текста и
# титлите остават да участват в сравнението — тогава двама различни
# български светии си приличат само защото и двамата са българи.
_RANKS_FOLDED = {_fold(w) for w in _RANKS}


def name_key(s: str) -> set[str]:
    """Значещите думи на едно име — за сравнение между двата извора."""
    s = _fold(s)
    s = re.sub(r'\(.*?\)', ' ', s)          # (15.I), († 1802)
    s = re.sub(r'[–—-]', ' ', s)
    s = re.sub(r'[^а-я ]', ' ', s)
    return {w for w in s.split() if len(w) > 3 and w not in _RANKS_FOLDED}


def similarity(a: str, b: str) -> float:
    """Колко от ПО-КРАТКОТО име се съдържа в по-дългото.

    ⚠ Делителят е по-малкото множество, НЕ първото. Двата извора именуват
    с различна подробност: „Св. мчк княз Боян-Енравота" срещу „Мч. Боян,
    княз Български" — общата дума е една, но за краткото име това е
    всичко, което има. При деление на първото излизаше 50% и верни двойки
    падаха под прага.
    """
    ka, kb = name_key(a), name_key(b)
    if not ka or not kb:
        return 0.0
    return len(ka & kb) / min(len(ka), len(kb))
