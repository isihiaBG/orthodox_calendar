#!/usr/bin/env python3
"""Пилот за четене на глас: едно житие от томовете → MP3 с гласове на Azure.

    python3 pilot.py                     # житието на прп. Никандър Псковски, двата гласа
    python3 pilot.py --voices Kalina     # само единия
    python3 pilot.py --stress-test       # кратък запис: дали гласът спазва ударение в текста
    python3 pilot.py --chars 3500        # само началото на житието

Думите, които гласът бърка, се поправят в stress.txt (прилага се винаги).

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

VOICES = {'Kalina': 'bg-BG-KalinaNeural', 'Borislav': 'bg-BG-BorislavNeural',
          # Многоезичен глас — чете български само в <lang xml:lang="bg-BG">.
          'Seraphina': 'de-DE-SeraphinaMultilingualNeural'}
BOOK = ROOT / 'assets/books/Жития на светиите - 09(сеп) - Димитрий Ростовски.epub'
CHAPTER = 'OEBPS/Text/index_split_824.xhtml'

LEXICON = Path(__file__).resolve().parent / 'stress.txt'
# Общ речник: словоформа → ударени варианти (прави се от речника на
# bgospodinov/bulgarian_dictionary, по „Речко", РБЕ и Мурдаров). Двузначните
# („гОспода"/„господА") НЕ се пипат — ударението там зависи от смисъла.
DICT = Path(__file__).resolve().parent / 'work' / 'stress_dict.tsv'
VOWELS = 'аеиоуъюяАЕИОУЪЮЯ'

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


def blocks(book=BOOK, chapter=CHAPTER):
    """(вид, текст) по реда на житието: 'head' за заглавия, 'text' за абзаци."""
    t = zipfile.ZipFile(book).read(chapter).decode()
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


def _doubled(w):
    """„житиЕ" → „житиее": удвоена ударената (главна) гласна, иначе малки букви.
    None, ако думата няма главна гласна (в израз — дума без промяна)."""
    caps = [i for i, c in enumerate(w) if c.isupper() and c in VOWELS]
    # Главната начална на собствено име не е ударение, ако има и друга.
    if len(caps) == 2 and caps[0] == 0:
        caps = caps[1:]
    if not caps:
        return None
    if len(caps) != 1:
        sys.exit(f'stress.txt: „{w}" — трябва най-много една главна гласна')
    i = caps[0]
    v = w[i].lower()
    return w[:i].lower() + v + v + w[i + 1:].lower()


def load_lexicon():
    """Ръчният речник: (израз в малки букви, изписване за гласа).

    Ред с една дума важи навсякъде; ред с няколко думи — само в този израз
    (за двузначни думи: „прОсти дрехи", но „простИ ми"). Ударената гласна е
    ГЛАВНА буква и се удвоява — гласът не слуша нито знака за ударение, нито
    фонетичния запис; удвоената гласна тегли ударението (проверено на слух
    с Калина, 10.10.2026). Изразите се прилагат ПРЕДИ отделните думи."""
    lex = {}
    for line in LEXICON.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' in line:
            # Точно изписване — когато ударението е вярно, но гласът бърка
            # буквите („блатиста = бла-тиста").
            k, v = (x.strip() for x in line.split('=', 1))
            lex[k.lower()] = v
            continue
        words = line.split()
        new = [_doubled(w) or w.lower() for w in words]
        if all(_doubled(w) is None for w in words):
            sys.exit(f'stress.txt: „{line}" — няма главна (ударена) гласна')
        lex[' '.join(w.lower() for w in words)] = ' '.join(new)
    return dict(sorted(lex.items(), key=lambda kv: -kv[0].count(' ')))


def load_dict(lex):
    """Общият речник, допълнен с ръчния; ръчният има предимство."""
    out = {}
    for line in DICT.read_text().splitlines():
        w, vs = line.split('\t')
        vs = vs.split('|')
        if len(vs) != 1 or sum(c in VOWELS for c in w) < 2:
            continue
        i = vs[0].index('`') - 1
        out[w] = w[:i + 1] + w[i] + w[i + 1:]
    out.update(lex)
    return out


def apply_lexicon(txt, lex):
    def keep_case(orig, new):
        return new[0].upper() + new[1:] if orig[0].isupper() else new
    for key, new in lex.items():
        if ' ' not in key:
            continue
        pat = r'\b' + r'\s+'.join(map(re.escape, key.split())) + r'\b'
        txt = re.sub(pat, lambda m: keep_case(m.group(0), new), txt, flags=re.I)

    def sub(m):
        word = m.group(0)
        new = lex.get(word.lower())
        return word if new is None or ' ' in word else keep_case(word, new)
    return re.sub(r'\w+', sub, txt)


def ssml(voice, parts):
    body = []
    for kind, txt in parts:
        body.append(html.escape(txt, quote=False))
        body.append(f'<break time="{PAUSE_HEAD if kind == "head" else PAUSE_PARA}"/>')
    return ('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
            'xml:lang="bg-BG">'
            f'<voice name="{voice}">{_lang_open(voice)}<prosody rate="{RATE}">{"".join(body)}'
            f'</prosody>{_lang_close(voice)}</voice></speak>')


def _lang_open(voice):
    return '<lang xml:lang="bg-BG">' if 'Multilingual' in voice else ''


def _lang_close(voice):
    return '</lang>' if 'Multilingual' in voice else ''


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
    ap.add_argument('--voices', nargs='+', default=['Kalina', 'Borislav'], choices=list(VOICES))
    ap.add_argument('--stress-test', action='store_true')
    ap.add_argument('--no-lexicon', dest='lexicon', action='store_false',
                    help='без stress.txt (по подразбиране се прилага)')
    ap.add_argument('--dict', action='store_true',
                    help='и общия речник (work/stress_dict.tsv) — ⚠ звучи по-зле, само за опити')
    ap.add_argument('--chars', type=int, help='само началото на житието, толкова знака')
    ap.add_argument('--month', type=int, help='друг том: номер на месеца (1–12)')
    ap.add_argument('--chapter', help='друга глава в тома, напр. Text/index_split_920.xhtml')
    ap.add_argument('--name', default='Никандър_Псковски', help='име на изходния файл')
    a = ap.parse_args()
    key, region = creds()
    OUT.mkdir(exist_ok=True)
    if a.stress_test:
        return stress_test(key, region, a.voices)
    book, chapter = BOOK, CHAPTER
    if a.month:
        book = next(ROOT.glob(f'assets/books/*- {a.month:02d}(*.epub'))
    if a.chapter:
        chapter = 'OEBPS/' + a.chapter if not a.chapter.startswith('OEBPS/') else a.chapter
    parts = blocks(book, chapter)
    if a.chars:
        cut, n = [], 0
        for p in parts:
            if n >= a.chars:
                break
            cut.append(p)
            n += len(p[1])
        parts = cut
    tag = ''
    if a.lexicon:
        lex = load_lexicon()
        if a.dict:
            lex = load_dict(lex)
        parts = [(k, apply_lexicon(t, lex)) for k, t in parts]
        tag = '_пълен_речник' if a.dict else ''
    if a.chars:
        tag = f'_откъс{tag}'
    print(f'{len(parts)} блока, {sum(len(t) for _, t in parts)} знака')
    for name in a.voices:
        with tempfile.TemporaryDirectory() as tmp:
            files = []
            for i, ch in enumerate(chunks(parts)):
                f = Path(tmp) / f'{i:03d}.mp3'
                synth(key, region, ssml(VOICES[name], ch), f)
                files.append(f)
                print(f'  {name}: част {i + 1}', flush=True)
            dest = OUT / f'{a.name}_{name}{tag}.mp3'
            concat(files, dest)
            print('→', dest)


if __name__ == '__main__':
    main()
