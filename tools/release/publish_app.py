#!/usr/bin/env python3
"""Качва нова версия на приложението — актуализацията отвътре (lib/app_update.dart).

    python3 tools/release/publish_app.py 2193 [--dry-run]

1. APK-то от build/app/outputs/flutter-apk/app-release.apk → издание
   `app-latest` в GitHub, под име с номера на билда
   (`pravoslaven-kalendar-2193.apk`). ⚠ Име по билд, не едно и също: GitHub
   кешира ПРЕНАСОЧВАНЕТО по име с часове (виж CLAUDE.md, звукът) — със
   същото име телефонът би теглил старото APK.
2. docs/update.json — последният билд, адрес, размер, SHA-256 и „Какво
   ново" от assets/release_notes.json (вграден и в приложението). Чете го и приложението, и страницата
   за сваляне (docs/index.html). ⚠ Влиза в сила чак след commit + push
   (GitHub Pages), затова скриптът НЕ комитва сам — така първо се вижда.

⚠ Пазят се последните ДВЕ APK-та: човек, който тъкмо тегли предишното,
не бива да остане с прекъснат адрес.
⚠ Номерът се сверява с версията вътре в самото APK (aapt), ако aapt го
има — разминат ли се, приложението би предлагало вечно „нова версия".
"""
import argparse
import datetime
import gzip
import hashlib
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
APK = ROOT / 'build/app/outputs/flutter-apk/app-release.apk'
NEWS = ROOT / 'assets/release_notes.json'   # общият извор — виж „_“ в него
OUT = ROOT / 'docs/update.json'
API = 'https://api.github.com/repos/isihiaBG/orthodox_calendar'
TAG = 'app-latest'
KEEP = 2


def token():
    for line in (Path.home() / '.git-credentials').read_text().splitlines():
        if 'github.com' in line and '@' in line:
            return line.split('://', 1)[1].split('@', 1)[0].split(':', 1)[1]
    sys.exit('Няма ключ за GitHub в ~/.git-credentials')


def apk_version_code(path):
    aapt = shutil.which('aapt') or next(
        iter(sorted((Path.home() / 'Android/Sdk/build-tools').glob('*/aapt'))), None)
    if not aapt:
        return None
    out = subprocess.run([str(aapt), 'dump', 'badging', str(path)],
                         capture_output=True, text=True).stdout
    for tok in out.split():
        if tok.startswith("versionCode='"):
            return int(tok.split("'")[1])
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('build', type=int)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    if not APK.exists():
        sys.exit(f'Няма {APK}')
    vc = apk_version_code(APK)
    if vc is not None and vc != a.build:
        sys.exit(f'APK-то е билд {vc}, а е подадено {a.build}')
    data = APK.read_bytes()
    sha = hashlib.sha256(data).hexdigest()
    name = f'pravoslaven-kalendar-{a.build}.apk'
    news = json.loads(NEWS.read_text(encoding='utf-8'))['versions']
    if not any(n['build'] == a.build for n in news):
        sys.exit(f'В {NEWS.name} няма „Какво ново" за билд {a.build} — първо го напиши.')
    print(f'{name}: {len(data) / 1048576:.1f} MB, sha256 {sha[:12]}…, версия в APK: {vc}')
    if a.dry_run:
        return

    hd = {'Authorization': f'Bearer {token()}', 'Accept': 'application/vnd.github+json'}
    r = requests.get(f'{API}/releases/tags/{TAG}', headers=hd, timeout=60)
    if r.status_code == 404:
        r = requests.post(f'{API}/releases', headers=hd, timeout=60, json={
            'tag_name': TAG, 'target_commitish': 'main',
            'name': 'Православен календар — последна версия',
            'body': 'Оттук приложението се обновява само (lib/app_update.dart), а '
                    'страницата за сваляне сочи тук.\n⚠ Тагът не се сменя.'})
    r.raise_for_status()
    rel = r.json()
    assets = {x['name']: x for x in rel['assets']}

    up = rel['upload_url'].split('{')[0]

    def upload(fname, payload, ctype):
        if fname in assets:
            requests.delete(f'{API}/releases/assets/{assets.pop(fname)["id"]}',
                            headers=hd, timeout=60).raise_for_status()
        for attempt in range(4):
            try:
                r = requests.post(up, params={'name': fname}, data=payload, timeout=3600,
                                  headers={**hd, 'Content-Type': ctype})
                r.raise_for_status()
                break
            except requests.exceptions.ConnectionError:
                if attempt == 3:
                    raise
                time.sleep(15)
        u = r.json()['browser_download_url']
        print(f'  ↑ {u} ({len(payload) / 1048576:.1f} MB)')
        return u

    # Обикновеното APK — за страницата за сваляне и за билд 2193 (той не
    # познава свитото). Свитото (gzip, ~12% по-малко) — за обновяването от
    # приложението; то го разархивира, докато тегли.
    url = upload(name, data, 'application/vnd.android.package-archive')
    gz = gzip.compress(data, compresslevel=9, mtime=0)
    assert gzip.decompress(gz) == data
    gz_url = upload(name + '.gz', gz, 'application/gzip')

    for ext in ('.apk', '.apk.gz'):
        old = sorted((x for x in assets.values() if x['name'].endswith(ext)),
                     key=lambda x: x['created_at'], reverse=True)
        for x in old[KEEP - 1:]:
            requests.delete(f'{API}/releases/assets/{x["id"]}', headers=hd, timeout=60)
            print(f'  ✕ {x["name"]}')

    news = sorted(news, key=lambda n: n['build'], reverse=True)[:80]
    OUT.write_text(json.dumps({
        'build': a.build,
        'apk': url,
        'size': len(data),
        'sha256': sha,
        'apk_gz': gz_url,
        'gz_size': len(gz),
        'date': datetime.date.today().isoformat(),
        'news': news,
    }, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'→ {OUT.relative_to(ROOT)} — комитни и пушни, за да влезе в сила.')


if __name__ == '__main__':
    main()
