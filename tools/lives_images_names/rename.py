#!/usr/bin/env python3
"""Четими имена на илюстрациите в assets/lives_images/ (автора, 27.10.2026).

    python3 tools/lives_images_names/rename.py [--dry-run]

КОНВЕНЦИЯТА
    <слъг>_<NN>.<разш>          sv-paraskeva-petka_01.png
    statia-<слъг>_<NN>.<разш>   statia-ikonografiya-pashi-descensus_03.jpg

    слъгът — този от lives.db (texts.slug / articles.slug), за да се намира
             житието по името на файла и обратно (само „.html" отпада и
             „_" става „-");
    NN     — редът на появяване в житието/статията (01, 02 …);
    споделена снимка (в няколко жития) — ЕДИН файл, кръстен на първото по
             азбучен ред житие (житията преди статиите).

Имената СЕ ИЗВЕЖДАТ от базата при всяко пускане — затова скриптът е
идемпотентен и кръщава сам и картинки, добавени по-късно.

⚠ Пипа САМО assets/: файловете и препратките в lives.db (texts.life,
articles.body). Конвейерите (lives_bg, lives_extra, paskha …) НЕ се пускат
и изворите им НЕ се пипат — по решение на автора, защото след тях има ръчни
поправки направо в assets/. Те още пишат старите имена.
⚠⚠ Затова, ако някога се пусне конвейер, който пише в lives.db или в
assets/lives_images/, СЛЕД него (и след tools/optimize_lives_images.py)
пускай ТОЗИ скрипт: names.csv помни всяко старо име → новото, така че
препратка към старо име, чийто файл вече е преименуван, се оправя, а
наново изтегленото копие под старото име се маха (ако е същото по md5).

Резервно копие (lives.db + папката) — в ~/orthodox_calendar_backups/,
извън хранилището и извън assets/.
"""
import argparse
import collections
import csv
import datetime
import hashlib
import os
import re
import shutil
import sqlite3
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMG = ROOT / 'assets/lives_images'
DB = ROOT / 'assets/db/lives.db'
NAMES = Path(__file__).with_name('names.csv')
BACKUPS = Path.home() / 'orthodox_calendar_backups'

# Адресът на картинка в html-а на житията — пълният път (виж lives_image.dart).
REF = re.compile(r'(assets/lives_images/)([^"\'\s)>]+)')
SOURCES = [('texts', 'life', ''), ('articles', 'body', 'statia-')]


def md5(p):
    return hashlib.md5(p.read_bytes()).hexdigest()


def load_history():
    h = {}
    if NAMES.exists():
        with NAMES.open(newline='', encoding='utf-8') as f:
            for r in csv.DictReader(f):
                h[r['old']] = r['new']
    return h


def resolve(name, history):
    """Старо име → последното му име (вериги old→mid→new)."""
    seen = set()
    while name in history and name not in seen:
        seen.add(name)
        name = history[name]
    return name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    history = load_history()
    con = sqlite3.connect(DB)

    # 1) Препратките, по ред на появяване. Препратка към старо име, чийто
    #    файл вече е преименуван (конвейерът е писал наново) → текущото име.
    owners = collections.defaultdict(list)       # файл → [(вид, слъг)]
    order = collections.defaultdict(list)        # (вид, слъг) → [файл] по ред
    fixed_refs = {}
    for kind, (tbl, col, prefix) in enumerate(SOURCES):
        for slug, body in con.execute(
                f'SELECT slug, {col} FROM {tbl} WHERE {col} LIKE ?', ('%lives_images/%',)):
            for m in REF.finditer(body):
                name = m.group(2)
                if not (IMG / name).exists():
                    cur = resolve(name, history)
                    if cur != name and (IMG / cur).exists():
                        fixed_refs[name] = cur
                        name = cur
                    else:
                        sys.exit(f'⚠ {tbl}:{slug} сочи липсващ файл {name} — '
                                 'спирам, нищо не е пипнато')
                key = (kind, slug)
                if key not in owners[name]:
                    owners[name].append(key)
                if name not in order[key]:
                    order[key].append(name)

    # 2) Новото име: собственикът е първият по (вид, слъг); номерът — редът
    #    сред НЕГОВИТЕ картинки.
    target = {}
    for key in sorted(order):
        kind, slug = key
        n = 0
        for name in order[key]:
            if min(owners[name]) != key:
                continue
            n += 1
            ext = Path(name).suffix.lower().replace('.jpeg', '.jpg')
            # Слъговете на някои статии носят „.html" или „_" — в името на
            # файла: само малки латински букви, цифри и тирета.
            stem = re.sub(r'[^a-z0-9-]+', '-', slug.lower().removesuffix('.html')).strip('-')
            target[name] = f'{SOURCES[kind][2]}{stem}_{n:02d}{ext}'
    if len(set(target.values())) != len(target):
        sys.exit('⚠ две картинки получават едно име — спирам')

    renames = {o: n for o, n in target.items() if o != n}
    refmap = {**{o: target.get(c, c) for o, c in fixed_refs.items()}, **renames}

    # Неизползвани: копие под старо име на вече преименуван файл → за триене.
    used = set(target)
    stale, orphans = [], []
    for p in sorted(IMG.iterdir()):
        if p.name in used or p.name in target.values():
            continue
        cur = target.get(resolve(p.name, history), resolve(p.name, history))
        if cur != p.name and (IMG / cur).exists() and md5(p) == md5(IMG / cur):
            stale.append(p.name)
        else:
            orphans.append(p.name)

    print(f'картинки в базата: {len(target)}; за преименуване: {len(renames)}; '
          f'препратки към стари имена: {len(fixed_refs)}; '
          f'стари копия за триене: {len(stale)}')
    for o, n in sorted(renames.items(), key=lambda x: x[1]):
        print(f'  {o}  →  {n}')
    for s in stale:
        print(f'  ✕ {s} (старо копие)')
    for s in orphans:
        print(f'  ⚠ неизползван, оставен: {s}')
    if a.dry_run or not (refmap or stale):
        return

    # 3) Резервно копие — извън assets/ и извън хранилището.
    BACKUPS.mkdir(exist_ok=True)
    ts = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    shutil.copy2(DB, BACKUPS / f'lives.db.bak-{ts}')
    with tarfile.open(BACKUPS / f'lives_images_{ts}.tar', 'w') as t:
        t.add(IMG, arcname='lives_images')
    print(f'резервно копие: {BACKUPS}/lives.db.bak-{ts}, lives_images_{ts}.tar')

    # 4) Файловете — на два хода (през временно име), за да не се застъпят
    #    при размяна на номера.
    tmp = {o: f'.renaming-{i}{Path(o).suffix}' for i, o in enumerate(renames)}
    for o, t in tmp.items():
        (IMG / o).rename(IMG / t)
    for o, t in tmp.items():
        (IMG / t).rename(IMG / renames[o])
    for s in stale:
        (IMG / s).unlink()

    # 5) Препратките — точно по името, не с подниз.
    def sub(m):
        return m.group(1) + refmap.get(m.group(2), m.group(2))
    for tbl, col, _ in SOURCES:
        rows = con.execute(
            f'SELECT slug, {col} FROM {tbl} WHERE {col} LIKE ?', ('%lives_images/%',)).fetchall()
        for slug, body in rows:
            nb = REF.sub(sub, body)
            if nb != body:
                con.execute(f'UPDATE {tbl} SET {col}=? WHERE slug=?', (nb, slug))
    con.commit()

    # 6) Историята — всяко старо име, завинаги.
    new_hist = {**history, **renames}
    with NAMES.open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=['old', 'new'])
        w.writeheader()
        for o in sorted(new_hist):
            w.writerow({'old': o, 'new': new_hist[o]})

    # 7) Сверка: всяка препратка има файл.
    missing = []
    for tbl, col, _ in SOURCES:
        for slug, body in con.execute(f'SELECT slug, {col} FROM {tbl}'):
            for m in REF.finditer(body or ''):
                if not (IMG / m.group(2)).exists():
                    missing.append(f'{tbl}:{slug} → {m.group(2)}')
    if missing:
        sys.exit('⚠ ЛИПСВАЩИ след преименуването:\n  ' + '\n  '.join(missing))
    print('готово; всяка препратка има файл')


if __name__ == '__main__':
    main()
