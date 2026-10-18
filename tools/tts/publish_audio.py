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
    <част>.opus    ЛЕКИЯТ вариант (18.10.2026, искане на автора): Opus 20 kbps,
                   около 3 пъти по-малък — приложението го тегли при избор
                   „Икономично" (по подразбиране). Прави се ТУК, от одобрения
                   MP3 — не от кеша на ElevenLabs: кешът може да е по-нов от
                   одобреното (c08), а звукът трябва да е СЪЩИЯТ. В регистъра:
                   `lq` (байтове) и `lv` (отпечатък) до `mp3`/`v`.
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
import re
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent
REPO = 'isihiaBG/orthodox_calendar'
API = f'https://api.github.com/repos/{REPO}'
INDEX_TAG = 'audio-index'
# Книга → пътят ѝ в приложението (ключът в регистъра).
ASSETS = {'razgovori': 'assets/chitalnya/razgovori.epub',
          # Житията от томовете — гласът Калина (azure_life.py), 13.10.2026.
          'zhitia10': 'assets/books/Жития на светиите - 10(окт) - Димитрий Ростовски.epub'}


def secret():
    """Ключът за шифроване — от lib/audio_secret.dart (не е в git)."""
    t = (HERE.parent.parent / 'lib' / 'audio_secret.dart').read_text()
    return re.search(r"kAudioSecret = '([^']+)'", t).group(1)


def keystream_xor(data, name):
    """⚠ „Куца" защита (решение на автора, 11.10.2026): XOR с поток от
    xorshift32, чието семе е FNV-1a на „ключ:име на файла". Огледално на
    `_xorStream` в lib/audiobook.dart — двете ТРЯБВА да дават едно и също."""
    h = 0x811C9DC5
    for b in (secret() + ':' + name).encode():
        h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
    st = h or 1
    out = bytearray(len(data))
    import numpy as np
    n = (len(data) + 3) // 4
    ks = np.empty(n, dtype=np.uint32)
    x = st
    for i in range(n):
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        ks[i] = x
    kb = ks.view(np.uint8)[:len(data)]
    return (np.frombuffer(data, dtype=np.uint8) ^ kb).tobytes()


LOW_KBPS = 20   # избрано на слух от автора (18.10.2026) — 16 също ставаше


def make_low(mp3):
    """`<част>.opus` до MP3-то — наново само ако липсва или е по-стар.
    ⚠ `-application voip` — настройката на Opus за глас (музиката в края е
    отделен плейър, в записите я няма)."""
    opus = mp3.with_suffix('.opus')
    if not opus.exists() or opus.stat().st_mtime < mp3.stat().st_mtime:
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(mp3), '-ac', '1',
                        '-c:a', 'libopus', '-b:a', f'{LOW_KBPS}k', '-application', 'voip',
                        str(opus)], check=True)
    return opus


def token():
    for line in (Path.home() / '.git-credentials').read_text().splitlines():
        if 'github.com' in line and '@' in line:
            return line.split('://', 1)[1].split('@', 1)[0].split(':', 1)[1]
    sys.exit('Няма ключ за GitHub в ~/.git-credentials')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--force', action='store_true', help='качва всичко наново')
    a = ap.parse_args()
    out = HERE / 'out' / a.book
    tag = f'{a.book}-audio-v1'

    parts = {}
    for js in sorted(out.glob('*.json')):
        mp3 = js.with_suffix('.mp3')
        if not mp3.exists():
            continue
        opus = make_low(mp3)
        h = hashlib.sha1(mp3.read_bytes() + js.read_bytes()).hexdigest()[:12]
        lv = hashlib.sha1(opus.read_bytes() + js.read_bytes()).hexdigest()[:12]
        parts[js.stem] = {'mp3': mp3.stat().st_size, 'json': js.stat().st_size, 'v': h,
                          'lq': opus.stat().st_size, 'lv': lv}
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
            m = requests.get(assets[f'{a.book}.json']['url'], timeout=60,   # виж update_index
                             headers={**hd, 'Accept': 'application/octet-stream'})
            if m.ok:
                old = m.json().get('parts', {})

    todo = [p for p, x in parts.items() if a.force or old.get(p, {}).get('v') != x['v']]
    todo_low = [p for p, x in parts.items() if a.force or old.get(p, {}).get('lv') != x['lv']]
    print(f'за качване: {len(todo)} — {", ".join(todo) or "нищо"}')
    print(f'лек вариант: {len(todo_low)} — {", ".join(todo_low) or "нищо"}')
    if a.dry_run:
        return

    def upload(name, data, ctype):
        # ⚠⚠ НОВОТО СЕ КАЧВА ПОД ВРЕМЕННО ИМЕ и чак после заменя старото.
        # Дотук старото се триеше ПРЕДИ качването — и докато 22-те MB се
        # качваха (минути), беседата я нямаше и свалянето в приложението
        # гърмеше (11.10.2026). Сега прозорецът е секунда.
        final, name = name, name + '.new'
        up = rel['upload_url'].split('{')[0]
        # ⚠ Големият файл (беседа 1, 22 MB) понякога прекъсва по средата —
        # опитва се пак, преди да се откаже.
        for attempt in range(4):
            try:
                r = requests.post(up, params={'name': name}, data=data, timeout=1800,
                                  headers={**hd, 'Content-Type': ctype})
                if r.status_code == 422:      # остатък от прекъснат опит
                    for x in requests.get(f'{API}/releases/{rel["id"]}/assets?per_page=100',
                                          headers=hd, timeout=60).json():
                        if x['name'] == name:
                            requests.delete(f'{API}/releases/assets/{x["id"]}', headers=hd,
                                            timeout=60)
                    continue
                r.raise_for_status()
                break
            except requests.exceptions.ConnectionError:
                if attempt == 3:
                    raise
                time.sleep(10)
        new_id = r.json()['id']
        if final in assets:
            requests.delete(f'{API}/releases/assets/{assets[final]["id"]}', headers=hd,
                            timeout=60).raise_for_status()
        requests.patch(f'{API}/releases/assets/{new_id}', headers=hd, timeout=60,
                       json={'name': final}).raise_for_status()
        name = final
        print(f'  ↑ {name} ({len(data) // 1024} KB)')

    # ⚠ Качват се ШИФРОВАНИ (`.mp3x`, `.jsonx`) — свален с браузъра, файлът
    # е безсмислен; приложението го дешифрира при сваляне.
    for p in todo:
        for ext in ('mp3', 'json'):
            name = f'{p}.{ext}x'
            upload(name, keystream_xor((out / f'{p}.{ext}').read_bytes(), name),
                   'application/octet-stream')
    for p in todo_low:
        name = f'{p}.opusx'
        upload(name, keystream_xor((out / f'{p}.opus').read_bytes(), name),
               'application/octet-stream')
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
        # ⚠⚠ ПРЕЗ API-то, не през `browser_download_url`: GitHub кешира
        # пренасочването по име с часове и второ пускане веднага след първо
        # четеше СТАРИЯ регистър — и го записваше обратно, затривайки току-що
        # вписаното (18.10.2026: леките варианти на „Разговори…" изчезнаха
        # при качването на житията).
        m = requests.get(assets['audio.json']['url'], timeout=60,
                         headers={**hd, 'Accept': 'application/octet-stream'})
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
