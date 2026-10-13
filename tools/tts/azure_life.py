#!/usr/bin/env python3
"""Житие от тома — с гласа Калина (Azure), ИЗРЕЧЕНИЕ ПО ИЗРЕЧЕНИЕ (13.10.2026).

    python3 azure_life.py zhitia10 OEBPS/Text/index_split_920.xhtml

Звукът е като в пилота (pilot.py — същият глас, темпо, речник stress.txt и
разгъване на съкращенията), но всяко изречение е отделна заявка, тъй че
началото и краят му в общия запис се ЗНАЯТ — приложението осветява
изречението и пуска от маркирано място. Изходът е във формата на беседите
(out/<книга>/<част>.mp3 + .json), а `publish_audio.py <книга>` го качва.

⚠ Показаният текст е буквално този от тома (с номерата на бележките —
екранът ги показва), а текстът за гласа е без тях. Църковнославянското
(`data-prayer="csl"`) не се чете — като в пилота.
⚠ Azure, безплатната квота (0,5 млн. знака на месец) — не ElevenLabs.
"""
import html, json, re, subprocess, sys, time, zipfile
from pathlib import Path
import requests
import pilot as P
from accent import split_sentences

BOOKS = {'zhitia10': P.ROOT / 'assets/books/Жития на светиите - 10(окт) - Димитрий Ростовски.epub'}
RATE = 24000
GAP = {'sent': 0.30, 'text': 0.70, 'head': 1.00}
NOTE = re.compile(r'(\d+)')


def blocks(book, chapter):
    t = zipfile.ZipFile(book).read(chapter).decode()
    t = t[t.find('<body'):]
    t = re.sub(r'<a [^>]*note(\d+)[^>]*>.*?</a>', lambda m: '' + m.group(1) + '', t, flags=re.S)
    out = []
    for m in re.finditer(r'<(h\d|p|div)([^>]*)>(.*?)</\1>', t, re.S):
        tag, attrs, inner = m.groups()
        if 'data-prayer="csl"' in attrs:
            continue
        txt = html.unescape(re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', re.sub(r'<br\s*/?>', ' ', inner)))).strip()
        if not txt or not re.search(r'[А-Яа-я]', txt):
            continue
        head = tag.startswith('h') or 'data-prayer="head"' in attrs or len(out) < 2
        out.append(('head' if head else 'text', txt))
    return out


def synth_pcm(key, region, text):
    doc = ('<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="bg-BG">'
           f'<voice name="{P.VOICES["Kalina"]}"><prosody rate="{P.RATE}">'
           f'{html.escape(text, quote=False)}</prosody></voice></speak>')
    for t in range(5):
        r = requests.post(f'https://{region}.tts.speech.microsoft.com/cognitiveservices/v1',
                          headers={'Ocp-Apim-Subscription-Key': key,
                                   'Content-Type': 'application/ssml+xml',
                                   'X-Microsoft-OutputFormat': 'raw-24khz-16bit-mono-pcm',
                                   'User-Agent': 'orthodox-calendar-tts'},
                          data=doc.encode('utf-8'), timeout=120)
        if r.status_code == 200:
            return r.content
        if r.status_code == 429:
            time.sleep(15 * (t + 1))
            continue
        sys.exit(f'Azure отказа: HTTP {r.status_code} {r.text[:200]}')
    sys.exit('Azure: твърде много заявки')


def trim(pcm):
    """Тишината в началото и края на изречението — паузите ги слагаме ние."""
    import array
    a = array.array('h', pcm)
    th = 300
    s = next((i for i, v in enumerate(a) if abs(v) > th), 0)
    e = next((i for i in range(len(a) - 1, -1, -1) if abs(a[i]) > th), len(a) - 1)
    s = max(s - int(0.02 * RATE), 0)
    e = min(e + int(0.06 * RATE), len(a))
    return a[s:e].tobytes()


def main():
    book, chapter = sys.argv[1], sys.argv[2]
    part = Path(chapter).stem
    key, region = P.creds()
    lex = P.load_lexicon()
    out = Path(__file__).resolve().parent / 'out' / book
    out.mkdir(parents=True, exist_ok=True)
    cache = Path(__file__).resolve().parent / 'work' / 'azure_cache'
    cache.mkdir(parents=True, exist_ok=True)
    pcm, sents, paras = bytearray(), [], []
    bl = blocks(BOOKS[book], chapter)
    chars = 0
    for pi, (kind, txt) in enumerate(bl):
        paras.append({'k': kind, 'v': 'kalina'})
        for si, piece in enumerate(split_sentences(txt)):
            shown = NOTE.sub(r'\1', piece).strip()
            spoken = NOTE.sub('', piece).strip()
            spoken = re.sub(r'^Превод:\s*', '', spoken)
            spoken = P.apply_lexicon(P.expand_abbr(spoken), lex)
            if not re.search(r'[А-Яа-я]', spoken):
                continue
            import hashlib
            h = hashlib.sha1(spoken.encode()).hexdigest()[:16]
            f = cache / f'{h}.pcm'
            if not f.exists():
                f.write_bytes(trim(synth_pcm(key, region, spoken)))
                chars += len(spoken)
                time.sleep(3.2)      # безплатната квота: 20 заявки в минута
            if sents:
                gap = GAP['sent'] if si else GAP[paras[-2]['k'] if len(paras) > 1 and si == 0 else 'text']
                pcm += bytes(int(gap * RATE) * 2)
            t0 = len(pcm) / 2 / RATE
            pcm += f.read_bytes()
            sents.append({'t': round(t0, 3), 'e': round(len(pcm) / 2 / RATE, 3), 'p': pi, 's': shown,
                          'n': [int(n) for n in NOTE.findall(piece)]})
            print(f'  {len(sents)}: {shown[:60]}', flush=True)
    pcm += bytes(int(0.5 * RATE) * 2)
    dur = len(pcm) / 2 / RATE
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(RATE), '-ac', '1', '-i', '-',
                    '-c:a', 'libmp3lame', '-b:a', '64k', str(out / f'{part}.mp3')], input=bytes(pcm), check=True)
    (out / f'{part}.json').write_text(json.dumps({'file': part, 'duration': round(dur, 3), 'paras': paras,
                                                   'sents': sents}, ensure_ascii=False))
    print(f'{part}: {dur / 60:.1f} мин, {len(sents)} изречения, изпратени знаци: {chars}')


if __name__ == '__main__':
    main()
