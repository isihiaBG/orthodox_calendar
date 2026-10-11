#!/usr/bin/env python3
"""Четене на глас с ElevenLabs — беседа по беседа (11.10.2026).

Чете work/<книга>_marked.json (accent.py) и прави за всяка беседа:

    out/<книга>/<беседа>.mp3    звукът
    out/<книга>/<беседа>.json   изреченията с времената им — за маркирането
                                в приложението и за пускане от място в текста

и за всяка бележка под линия свой out/<книга>/noteN.mp3 (гласът на
разказвача), която приложението пуска след изречението с бележката — ако
бележките са включени.

    python3 eleven.py razgovori c13 notes        # само тези
    python3 eleven.py razgovori --all            # всички, докъдето стигнат кредитите

⚠ ВСЕКИ АБЗАЦ СЕ ПАЗИ (work/eleven_cache/) — повторно пускане не харчи нищо
за готовото, а спрялото продължава оттам, където е спряло. Преди всяка
платена заявка се пита колко кредита остават; не стигнат ли, скриптът спира.

Ключът е в ~/.config/elevenlabs.env (ELEVENLABS_API_KEY=…).
"""
import argparse
import base64
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent
WORK = HERE / 'work'
CACHE = WORK / 'eleven_cache'
OUT = HERE / 'out'
VOICES = json.loads((HERE / 'eleven_voices.json').read_text())
API = 'https://api.elevenlabs.io/v1'
MODEL = 'eleven_multilingual_v2'
RATE = 24000                       # pcm_24000: 16 бита, моно
CREDITS_PER_CHAR = 0.5             # измерено 0,44 (11.10.2026) — с резерв
# Абзацът се праща на части от по няколко изречения: в дълъг откъс гласът
# понякога забързва към края (чуто от потребителя, 11.10.2026). Текстът преди
# и след частта се подава за интонацията и НЕ се таксува (измерено).
MAX_CHARS = 500
ACUTE = '́'

# Паузите между абзаците, в секунди.
PAUSE = {'head': 1.1, 'para': 0.6, 'speaker': 0.85}


def key():
    for line in (Path.home() / '.config' / 'elevenlabs.env').read_text().splitlines():
        if line.startswith('ELEVENLABS_API_KEY='):
            return line.split('=', 1)[1].strip()
    sys.exit('Няма ELEVENLABS_API_KEY в ~/.config/elevenlabs.env')


def remaining(k):
    d = requests.get(f'{API}/user/subscription', headers={'xi-api-key': k}, timeout=60).json()
    return d['character_limit'] - d['character_count']


def settings(speaker):
    v = VOICES[speaker]
    return {'stability': v.get('stability', 0.5), 'similarity_boost': 0.75,
            'style': 0.0, 'use_speaker_boost': True, 'speed': v.get('speed', 1.0)}


def spoken(block):
    """Текстът за гласа и карта: позиция в block['text'] → позиция в него.

    'marked' е 'text' с ВМЪКНАТИ ударения; ⟦…⟧ (църковнославянското) не се
    изпращат."""
    text, marked = block['text'], block['marked']
    out, pos, j = [], [], 0
    for c in text:
        while marked[j] != c:              # вмъкнато ударение
            out.append(marked[j])
            j += 1
        pos.append(len(out))
        if c not in '⟦⟧':
            out.append(c)
        j += 1
    out.extend(marked[j:])
    pos.append(len(out))
    return ''.join(out), pos


def synth(k, speaker, text, budget, prev='', nxt=''):
    """Един абзац → (pcm байтове, начала и краища на знаците в секунди).
    Пази се на диска; от кеша не се плаща."""
    s = settings(speaker)
    h = hashlib.sha1(json.dumps([VOICES[speaker]['voice_id'], MODEL, s, text, prev, nxt],
                                ensure_ascii=False).encode()).hexdigest()[:20]
    pcm_p, al_p = CACHE / f'{h}.pcm', CACHE / f'{h}.json'
    if pcm_p.exists() and al_p.exists():
        al = json.loads(al_p.read_text())
        return pcm_p.read_bytes(), al
    need = len(text) * CREDITS_PER_CHAR
    left = remaining(k)
    if left - need < budget['reserve']:
        sys.exit(f'⚠ Спрях: остават {left} кредита, абзацът иска ~{need:.0f}, '
                 f'резервът е {budget["reserve"]}. Продължава се със същата команда.')
    for t in range(4):
        r = requests.post(f'{API}/text-to-speech/{VOICES[speaker]["voice_id"]}/with-timestamps',
                          params={'output_format': f'pcm_{RATE}'},
                          headers={'xi-api-key': k},
                          json={'text': text, 'model_id': MODEL, 'voice_settings': s,
                                'previous_text': prev[-1000:], 'next_text': nxt[:1000]},
                          timeout=600)
        if r.status_code == 200:
            break
        if r.status_code in (401, 402, 403) or 'quota' in r.text:
            sys.exit(f'⚠ ElevenLabs отказа ({r.status_code}): {r.text[:300]}')
        time.sleep(10 * (t + 1))
    else:
        sys.exit(f'⚠ ElevenLabs не отговаря: {r.status_code} {r.text[:300]}')
    d = r.json()
    a = d['alignment']
    al = {'chars': a['characters'], 'start': a['character_start_times_seconds'],
          'end': a['character_end_times_seconds']}
    CACHE.mkdir(parents=True, exist_ok=True)
    pcm_p.write_bytes(base64.b64decode(d['audio_base64']))
    al_p.write_text(json.dumps(al, ensure_ascii=False))
    budget['spent'] += len(text)
    return pcm_p.read_bytes(), al


def char_time(al, i, end=False):
    """Времето на i-тия знак от изпратения текст. Ако подравняването е с друга
    дължина (не би трябвало), се смята пропорционално."""
    n = len(al['chars'])
    if n == 0:
        return 0.0
    i = min(max(i, 0), n - 1)
    return (al['end'] if end else al['start'])[i]


def silence(sec):
    return b'\0\0' * int(RATE * sec)


def chunks_of(block):
    """Абзац над MAX_CHARS се праща на части по изречения."""
    sp, pos = spoken(block)
    parts, cur = [], None
    for st, en, shown, notes in block['sents']:
        a, b = pos[st], pos[en]
        if cur and b - cur[0] > MAX_CHARS:
            parts.append(cur)
            cur = None
        if cur is None:
            cur = [a, b, []]
        cur[1] = b
        cur[2].append((a, b, shown, notes))
    if cur:
        parts.append(cur)
    return [(sp[a:b], a, items) for a, b, items in parts]


def render(k, book, name, blocks, budget):
    """Една беседа → mp3 + json."""
    pcm, sents, t, prev = bytearray(), [], 0.0, None
    paras = []
    for pi, bl in enumerate(blocks):
        paras.append({'k': bl['kind'], 'v': bl['speaker']})
        if prev is not None:
            gap = PAUSE['head'] if 'head' in (prev['kind'], bl['kind']) else \
                PAUSE['speaker'] if prev['speaker'] != bl['speaker'] else PAUSE['para']
            pcm += silence(gap)
            t += gap
        parts = chunks_of(bl)
        for ci, (text, base, items) in enumerate(parts):
            prev_t = ' '.join(p[0] for p in parts[:ci])
            next_t = ' '.join(p[0] for p in parts[ci + 1:])
            audio, al = synth(k, bl['speaker'], text, budget, prev_t, next_t)
            if len(al['chars']) != len(text):
                print(f'  ⚠ подравняването е {len(al["chars"])} знака, текстът {len(text)}')
            for a, b, shown, notes in items:
                sents.append({'t': round(t + char_time(al, a - base), 3),
                              'e': round(t + char_time(al, b - base - 1, end=True), 3),
                              'p': pi, 's': shown, **({'n': notes} if notes else {})})
            pcm += audio
            t += len(audio) / 2 / RATE
        prev = bl
    dest = OUT / book
    dest.mkdir(parents=True, exist_ok=True)
    mp3 = dest / f'{name}.mp3'
    # CBR — точното пускане от място в mp3 иска постоянна побитова скорост.
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(RATE), '-ac', '1',
                    '-i', '-', '-c:a', 'libmp3lame', '-b:a', '64k', str(mp3)],
                   input=bytes(pcm), check=True)
    (dest / f'{name}.json').write_text(json.dumps(
        {'file': name, 'duration': round(t, 3), 'paras': paras, 'sents': sents}, ensure_ascii=False, indent=0))
    print(f'  {name}: {t / 60:.1f} мин, {len(sents)} изречения, {mp3.stat().st_size // 1024} KB')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book')
    ap.add_argument('parts', nargs='*', help='c13, notes, …')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--reserve', type=int, default=2000,
                    help='кредити, които НЕ се харчат (по подразбиране 2000)')
    a = ap.parse_args()
    chapters = json.loads((WORK / f'{a.book}_marked.json').read_text())
    want = [c['file'] for c in chapters] if a.all else a.parts
    k = key()
    budget = {'reserve': a.reserve, 'spent': 0}
    print(f'кредити преди: {remaining(k)}')
    for c in chapters:
        if c['file'] not in want:
            continue
        if c['file'] == 'notes':
            for bl in c['blocks']:
                render(k, a.book, f'note{bl["note"]}', [bl], budget)
        else:
            render(k, a.book, c['file'], c['blocks'], budget)
    print(f'изпратени знаци: {budget["spent"]}; кредити след: {remaining(k)}')


if __name__ == '__main__':
    main()
