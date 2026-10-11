#!/usr/bin/env python3
"""Качва звука на книга в GitHub — отделно издание, от което приложението го
сваля по беседи (11.10.2026, решение на автора).

    python3 publish_audio.py razgovori              # качва новото и промененото
    python3 publish_audio.py razgovori --dry-run    # само казва какво би качил

Изданието е `<книга>-audio-v1`. ⚠ ТАГЪТ НЕ СЕ СМЕНЯ — адресът е зашит в
приложението, също както при езиковите пакети на Библията.

В изданието за всяка готова част (беседа или бележка):
    <част>.mp3     звукът (64 kbps моно, както идва от ElevenLabs)
    <част>.json    изреченията: показан текст, начало и край в секунди
и един манифест `<книга>.json`:
    {"parts": {"c02": {"mp3": байтове, "json": байтове, "v": отпечатък}, …}}
По `v` приложението разбира, че беседа е генерирана наново и трябва да се
свали пак. Качват се само частите, чийто отпечатък се е сменил.

⚠⚠ ОБЩИЯТ РЕГИСТЪР (искане на автора): изданието `audio-index` носи
`audio.json` — всички озвучени книги наведнъж:
    {"books": {"<път до тома в assets>": {"release": "<таг>", "parts": {…}}}}
Приложението чете САМО него; манифестът на книгата е за този скрипт.
"""
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent
REPO = 'isihiaBG/orthodox_calendar'
API = f'https://api.github.com/repos/{REPO}'
INDEX_TAG = 'audio-index'
# Книга → пътят ѝ в приложението (ключът в регистъра).
ASSETS = {'razgovori': 'assets/chitalnya/razgovori.epub'}


def token():
    for line in (Path.home() / '.git-credentials').read_text().splitlines():
        if 'github.com' in line and '@' in line:
            return line.split('://', 1)[1].split('@', 1)[0].split(':', 1)[1]
    sys.exit('Няма ключ за GitHub в ~/.git-credentials')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    out = HERE / 'out' / a.book
    tag = f'{a.book}-audio-v1'

    parts = {}
    for js in sorted(out.glob('*.json')):
        mp3 = js.with_suffix('.mp3')
        if not mp3.exists():
            continue
        h = hashlib.sha1(mp3.read_bytes() + js.read_bytes()).hexdigest()[:12]
        parts[js.stem] = {'mp3': mp3.stat().st_size, 'json': js.stat().st_size, 'v': h}
    print(f'части: {len(parts)} — {", ".join(parts)}')

    hd = {'Authorization': f'Bearer {token()}', 'Accept': 'application/vnd.github+json'}
    r = requests.get(f'{API}/releases/tags/{tag}', headers=hd, timeout=60)
    if r.status_code == 404:
        if a.dry_run:
            print(f'изданието {tag} го няма — ще бъде създадено')
            rel, assets, old = None, {}, {}
        else:
            r = requests.post(f'{API}/releases', headers=hd, timeout=60, json={
                'tag_name': tag, 'name': f'Звукът на „{a.book}“',
                'body': 'Четене на глас (ElevenLabs). Приложението сваля оттук по беседи.\n'
                        '⚠ Тагът не се сменя — адресът е в приложението.'})
            r.raise_for_status()
            rel = r.json()
            assets, old = {}, {}
    else:
        r.raise_for_status()
        rel = r.json()
        assets = {x['name']: x for x in rel['assets']}
        old = {}
        if f'{a.book}.json' in assets:
            m = requests.get(assets[f'{a.book}.json']['browser_download_url'], timeout=60)
            if m.ok:
                old = m.json().get('parts', {})

    todo = [p for p, x in parts.items() if old.get(p, {}).get('v') != x['v']]
    print(f'за качване: {len(todo)} — {", ".join(todo) or "нищо"}')
    if a.dry_run:
        return

    def upload(name, data, ctype):
        if name in assets:
            requests.delete(f'{API}/releases/assets/{assets[name]["id"]}', headers=hd,
                            timeout=60).raise_for_status()
        up = rel['upload_url'].split('{')[0]
        r = requests.post(up, params={'name': name}, data=data, timeout=600,
                          headers={**hd, 'Content-Type': ctype})
        r.raise_for_status()
        print(f'  ↑ {name} ({len(data) // 1024} KB)')

    for p in todo:
        upload(f'{p}.mp3', (out / f'{p}.mp3').read_bytes(), 'audio/mpeg')
        upload(f'{p}.json', (out / f'{p}.json').read_bytes(), 'application/json')
    # Манифестът — ПОСЛЕДЕН: докато частите се качват, старият още сочи старото.
    upload(f'{a.book}.json', json.dumps({'parts': parts}, ensure_ascii=False).encode(),
           'application/json')
    update_index(hd, a.book, tag, parts)


def update_index(hd, book, tag, parts):
    """Вписва книгата в общия регистър (`audio-index/audio.json`)."""
    r = requests.get(f'{API}/releases/tags/{INDEX_TAG}', headers=hd, timeout=60)
    if r.status_code == 404:
        r = requests.post(f'{API}/releases', headers=hd, timeout=60, json={
            'tag_name': INDEX_TAG, 'name': 'Регистър на звука',
            'body': 'Кои книги и глави имат звук — приложението чете audio.json оттук.\n'
                    '⚠ Тагът не се сменя — адресът е в приложението.'})
    r.raise_for_status()
    rel = r.json()
    assets = {x['name']: x for x in rel['assets']}
    idx = {'books': {}}
    if 'audio.json' in assets:
        m = requests.get(assets['audio.json']['browser_download_url'], timeout=60)
        if m.ok:
            idx = m.json()
        requests.delete(f'{API}/releases/assets/{assets["audio.json"]["id"]}', headers=hd,
                        timeout=60).raise_for_status()
    idx['books'][ASSETS[book]] = {'release': tag, 'parts': parts}
    # Версията — по нея приложението разбира, че неговият регистър е стар.
    idx['version'] = int(time.time())
    up = rel['upload_url'].split('{')[0]
    requests.post(up, params={'name': 'audio.json'}, timeout=120,
                  data=json.dumps(idx, ensure_ascii=False).encode(),
                  headers={**hd, 'Content-Type': 'application/json'}).raise_for_status()
    print(f'  ↑ регистър: {len(idx["books"])} книги')


if __name__ == '__main__':
    main()
