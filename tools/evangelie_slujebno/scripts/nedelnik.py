#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Зареждане на отпечатаните „Неделници" — с приложена ерата.

⚠⚠ `input/nedelnik.csv` е ПРЕПИС НА ИЗВОРА и не се поправя. Известните грешки
в самите календарчета стоят в `input/nedelnik_errata.csv`. Така при бъдещ трети
„Неделник" се вижда дали и той носи същата грешка, или е чист.
"""
import csv
from pathlib import Path

ВХОД = Path(__file__).resolve().parents[1] / 'input'


def зареди(с_ерата=True):
    редове = list(csv.DictReader(
        open(ВХОД / 'nedelnik.csv', encoding='utf-8'), delimiter='|'))
    if not с_ерата:
        return редове, []
    ерата = []
    for ред in open(ВХОД / 'nedelnik_errata.csv', encoding='utf-8'):
        ред = ред.strip()
        if not ред or ред.startswith('#'):
            continue
        г, md, кол, печат, вярно, бележка = ред.split('|', 5)
        ерата.append((г, md, кол, печат, вярно, бележка))
    for r in редове:
        for г, md, кол, печат, вярно, _ in ерата:
            if r['year'] == г and r['md'] == md and r[кол] == печат:
                r[кол] = вярно
                r.setdefault('_поправено', []).append(кол)
    return редове, ерата
