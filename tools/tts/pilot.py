#!/usr/bin/env python3
"""Пилот за четене на глас: едно житие от томовете → MP3 с гласове на Azure.

    python3 pilot.py                     # житието на прп. Никандър Псковски, двата гласа
    python3 pilot.py --voices Kalina     # само единия
    python3 pilot.py --stress-test       # кратък запис: дали гласът спазва ударение в текста

Ключът се чете от ~/.config/azure_speech.env (AZURE_SPEECH_KEY,
AZURE_SPEECH_REGION) и НИКЪДЕ не се изписва. Изходът — в tools/tts/out/.

⚠ Църковнославянският текст на тропара и кондака се ПРОПУСКА (в тома е с
`data-prayer="csl"`): българският глас би го изговорил като български. Четат
се заглавието и преводът.
⚠ Бележките под линия не се четат — номерът им би се изговорил насред
изречението.
"""
import argparse
import html
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / 'out'
ENV = Path.home() / '.config' / 'azure_speech.env'

VOICES = {'Kalina': 'bg-BG-KalinaNeural', 'Borislav': 'bg-BG-BorislavNeural'}
BOOK = ROOT / 'assets/books/Жития на светиите - 09(сеп) - Димитрий Ростовски.epub'
CHAPTER = 'OEBPS/Text/index_split_824.xhtml'

CHUNK = 2800          # знака на заявка — далеч под 10-те минути звук на заявка
RATE = '-6%'          # малко по-бавно от подразбиращото — четене, не новини
PAUSE_PARA = '650ms'
PAUSE_HEAD = '1000ms'


def creds():
    if not ENV.exists():
        sys.exit(f'Няма {ENV} — виж инструкцията в разговора.')
    env = dict(re.findall(r'^\s*(\w+)\s*=\s*(\S+)', ENV.read_text(), re.M))
    key, region = env.get('AZURE_SPEECH_KEY'), env.get('AZURE_SPEECH_REGION')
    if not key or not region:
        sys.exit(f'В {ENV} липсва AZURE_SPEECH_KEY или AZURE_SPEECH_REGION.')
    return key, region


def blocks():
    """(вид, текст) по реда на житието: 'head' за заглавия, 'text' за абзаци."""
    t = zipfile.ZipFile(BOOK).read(CHAPTER).decode()
    t = re.sub(r'<a [^>]*note\d+[^>]*>.*?</a>', '', t, flags=re.S)
    out = []
    for m in re.finditer(r'<(h\d|p|div)([^>]*)>(.*?)</\1>', t, re.S):
        tag, attrs, inner = m.groups()
        if 'data-prayer="csl"' in attrs:
            continue
        txt = html.unescape(re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', inner))).strip()
        if not txt:
            continue
        txt = re.sub(r'^Превод:\s*', '', txt)
        # Заглавие: самото заглавие, редът с паметта (първите два) и „Тропар, глас…".
        head = tag.startswith('h') or 'data-prayer="head"' in attrs or len(out) < 2
        out.append(('head' if head else 'text', txt))
    return out


def ssml(voice, parts):
    body = []
    for kind, txt in parts:
        body.append(html.escape(txt, quote=False))
        body.append(f'<break time="{PAUSE_HEAD if kind == "head" else PAUSE_PARA}"/>')
    return ('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
            'xml:lang="bg-BG">'
            f'<voice name="{voice}"><prosody rate="{RATE}">{"".join(body)}'
            '</prosody></voice></speak>')


def chunks(parts):
    cur, size = [], 0
    for p in parts:
        if cur and size + len(p[1]) > CHUNK:
            yield cur
            cur, size = [], 0
        cur.append(p)
        size += len(p[1])
    if cur:
        yield cur


def synth(key, region, doc, dest):
    r = requests.post(
        f'https://{region}.tts.speech.microsoft.com/cognitiveservices/v1',
        headers={'Ocp-Apim-Subscription-Key': key,
                 'Content-Type': 'application/ssml+xml',
                 'X-Microsoft-OutputFormat': 'audio-24khz-96kbitrate-mono-mp3',
                 'User-Agent': 'orthodox-calendar-tts-pilot'},
        data=doc.encode('utf-8'), timeout=180)
    if r.status_code != 200:
        sys.exit(f'Azure отказа: HTTP {r.status_code} {r.text[:200]}')
    dest.write_bytes(r.content)


def concat(files, dest):
    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False) as lst:
        for f in files:
            lst.write(f"file '{f}'\n")
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0',
                    '-i', lst.name, '-c', 'copy', str(dest)], check=True)
    os.unlink(lst.name)


def stress_test(key, region, voice_names):
    # Едно и също изречение по три начина: голо, с ударение в текста (U+0301)
    # и с изричното произношение в SSML. Слуша се кое гласът спазва.
    s = [
        ('Голо:', 'Свети Иоаникий Велики и свети Пахомий. Тя има пара. Платих с пара.'),
        ('С ударение в текста:', 'Свети Иоани́кий Вели́ки и свети Пахо́мий. Тя има па́ра. Платих с пара́.'),
    ]
    for name in voice_names:
        voice = VOICES[name]
        parts = []
        for label, txt in s:
            parts += [('head', label), ('text', txt)]
        dest = OUT / f'ударения_{name}.mp3'
        synth(key, region, ssml(voice, parts), dest)
        print('→', dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--voices', nargs='+', default=list(VOICES), choices=list(VOICES))
    ap.add_argument('--stress-test', action='store_true')
    a = ap.parse_args()
    key, region = creds()
    OUT.mkdir(exist_ok=True)
    if a.stress_test:
        return stress_test(key, region, a.voices)
    parts = blocks()
    print(f'{len(parts)} блока, {sum(len(t) for _, t in parts)} знака')
    for name in a.voices:
        with tempfile.TemporaryDirectory() as tmp:
            files = []
            for i, ch in enumerate(chunks(parts)):
                f = Path(tmp) / f'{i:03d}.mp3'
                synth(key, region, ssml(VOICES[name], ch), f)
                files.append(f)
                print(f'  {name}: част {i + 1}', flush=True)
            dest = OUT / f'Никандър_Псковски_{name}.mp3'
            concat(files, dest)
            print('→', dest)


if __name__ == '__main__':
    main()
