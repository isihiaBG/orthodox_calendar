#!/usr/bin/env python3
"""Ударения за четене на глас с ElevenLabs.

ElevenLabs СПАЗВА знака за ударение (U+0301 след ударената гласна) —
проверено на слух от потребителя 10.10.2026: „резултатът е просто перфектен".
Затова тук ударенията се слагат НАВСЯКЪДЕ, в многосричните думи, по ред:

    1. accents.txt          ръчните (църковното произношение) — с предимство
    2. work/stress_dict.tsv  общият речник, ако думата е ЕДНОЗНАЧНА в него
    3. езиков модел          липсващите и двузначните, по смисъла на изречението
                             → отчет за преглед (work/<книга>_review.md)

    python3 accent.py razgovori              # без модела: колко остават
    python3 accent.py razgovori --llm        # и с модела
"""
import argparse
import hashlib
import html
import json
import re
import sys
import time
import unicodedata
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests

from pilot import expand_abbr

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
WORK = HERE / 'work'
ACCENTS = HERE / 'accents.txt'
DICT = WORK / 'stress_dict.tsv'
ACUTE = '́'
VOWELS = 'аеиоуъюяѝ'
WORD = re.compile(r'[А-Яа-яЍѝ]+')

BOOKS = {'razgovori': ROOT / 'assets/chitalnya/razgovori.epub'}
SPEAKERS = {'К': 'kalinik', 'Ц': 'tsetso', 'И': 'ivaylo'}


# ── разчитане на книгата ────────────────────────────────────────────────

def _plain(fragment):
    return html.unescape(re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', fragment))).strip()


def book_blocks(epub):
    """[(файл, [блок…])]; блок = {kind, speaker, text, cs}.

    Репликата продължава до следващия етикет „К:"/„Ц:"/„И:"; в началото на
    беседата говори разказвачът. Етикетът НЕ се чете — сменя се гласът.
    Църковнославянското (клас `cs`/`csq`) пази своите ударения и се бележи с
    ⟦…⟧, за да не го пипа речникът."""
    z = zipfile.ZipFile(epub)
    opf = next(n for n in z.namelist() if n.endswith('.opf'))
    o = z.read(opf).decode()
    man = dict(re.findall(r'<item id="([^"]+)" href="([^"]+)"', o))
    out = []
    for idref in re.findall(r'<itemref idref="([^"]+)"', o):
        name = str(Path(opf).parent / man[idref])
        t = z.read(name).decode()
        t = re.sub(r'<a [^>]*epub:type="noteref"[^>]*>.*?</a>', '', t, flags=re.S)
        t = re.sub(r'<sup[^>]*>.*?</sup>', '', t, flags=re.S)
        t = re.sub(r'<span class="cs">(.*?)</span>', lambda m: '⟦' + m.group(1) + '⟧', t, flags=re.S)
        speaker, blocks = 'narrator', []
        for m in re.finditer(r'<(p|h\d)(?: class="([^"]*)")?[^>]*>(.*?)</\1>', t, re.S):
            tag, cls, inner = m.group(1), m.group(2) or '', m.group(3)
            if any(c in cls for c in ('pagebreak', 'cover', 'titleorn', 'dedorn')):
                continue
            text = _plain(inner)
            if not text or not WORD.search(text):
                continue
            text = expand_abbr(text)
            if 'csq' in cls:
                text = '⟦' + text + '⟧'
            lab = re.match(r'^([КЦИ]):\s*', text)
            if lab:
                speaker = SPEAKERS[lab.group(1)]
                text = text[lab.end():]
            kind = 'head' if tag.startswith('h') else (cls.split()[0] if cls else 'text')
            blocks.append({'kind': kind, 'speaker': 'narrator' if kind == 'head' else speaker,
                           'text': text})
        if blocks:
            out.append((Path(name).stem, blocks))
    return out


# ── речниците ───────────────────────────────────────────────────────────

def _stress_index(w):
    """„житиЕ" → 5: мястото на главната гласна (начална главна на име не се
    брои, ако има и друга)."""
    caps = [i for i, c in enumerate(w) if c.isupper() and c.lower() in VOWELS]
    if len(caps) == 2 and caps[0] == 0:
        caps = caps[1:]
    if len(caps) != 1:
        sys.exit(f'accents.txt: „{w}" — трябва точно една главна (ударена) гласна')
    return caps[0]


def load_accents():
    """(думи: дума → индекс, изрази: [(regex, [индекс или None по дума])])."""
    words, phrases = {}, []
    for line in ACCENTS.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) == 1:
            words[line.lower()] = _stress_index(line)
            continue
        idx = [(_stress_index(p) if any(c.isupper() and c.lower() in VOWELS for c in p[1:])
                or (p[0].isupper() and p[0].lower() in VOWELS) else None) for p in parts]
        pat = re.compile(r'(?<![А-Яа-я])' + r'\s+'.join(map(re.escape, (p.lower() for p in parts)))
                         + r'(?![А-Яа-я])', re.I)
        phrases.append((pat, idx))
    return words, phrases


def load_dict():
    d = {}
    for line in DICT.read_text().splitlines():
        w, vs = line.split('\t')
        vs = {v.index('`') - 1 for v in vs.split('|')}
        d[w] = vs
    return d


def vowel_count(w):
    return sum(c in VOWELS for c in w.lower())


def put(word, i):
    return word[:i + 1] + ACUTE + word[i + 1:]


# ── ударения в един текст ──────────────────────────────────────────────

def mark(text, accents, dic, llm=None):
    """→ (текст с ударения, нерешени [(начало, дума, двузначна)]).

    `llm` — {начало_на_думата: индекс} от модела за ТОЗИ текст."""
    words, phrases = accents
    fixed = {}                        # начало на дума → индекс от израз
    for pat, idx in phrases:
        for m in pat.finditer(text):
            pos = m.start()
            for w, i in zip(WORD.finditer(m.group(0)), idx):
                if i is not None:
                    fixed[pos + w.start()] = i
    out, last, pending = [], 0, []
    protected = [(m.start(), m.end()) for m in re.finditer(r'⟦.*?⟧', text, re.S)]
    for m in WORD.finditer(text):
        s, w = m.start(), m.group(0)
        if any(a <= s < b for a, b in protected) or vowel_count(w) < 2:
            continue
        if text[m.end():m.end() + 1] in (ACUTE, '̀'):
            continue                  # вече с ударение
        low = w.lower()
        if s in fixed:
            i = fixed[s]
        elif low in words:
            i = words[low]
        elif llm and s in llm:
            i = llm[s]
        elif len(dic.get(low, ())) == 1:
            i = next(iter(dic[low]))
        else:
            pending.append((s, w, low in dic))
            continue
        out.append(text[last:s] + put(w, i))
        last = m.end()
    out.append(text[last:])
    return ''.join(out), pending


# ── езиковият модел ─────────────────────────────────────────────────────

ENV = [ROOT / 'tools' / 'azbyka.ru' / '.env']
API = 'https://api.deepseek.com/chat/completions'
MODEL = 'deepseek-v4-pro'
PROMPT = """Ти си филолог, специалист по българско книжовно произношение и по православна църковна лексика.

Получаваш абзаци от православна книга на български. Някои думи са оградени така: ⟨3|думата⟩, където 3 е номерът на думата.

За ВСЯКА оградена дума посочи къде пада ударението в ТОВА изречение (по смисъла — напр. „гОспода" е Бог в винителен, „господА" са господата; „прОсти" е прилагателно, „простИ" е повелително).
Църковните имена и думи се ударяват по църковната традиция в България (свети → светИ, Господи → ГОсподи).

Отговори САМО с JSON обект: номер → думата с малки букви, а ударената гласна — ГЛАВНА.
Пример: {"1": "житиЕ", "2": "гОспода", "3": "започнАл"}"""


def api_key():
    for p in ENV:
        if p.exists():
            for line in p.read_text().splitlines():
                if line.strip().startswith('DEEPSEEK_API_KEY='):
                    return line.split('=', 1)[1].strip()
    sys.exit('Няма DEEPSEEK_API_KEY')


def ask(key, batch, tries=4):
    """batch: [(id_на_блока, текст, [(начало, дума)])] → {id: {начало: индекс}}."""
    lines, refs, n = [], {}, 0
    for bid, text, pend in batch:
        parts, last = [], 0
        for s, w in pend:
            n += 1
            refs[str(n)] = (bid, s, w)
            parts.append(text[last:s] + f'⟨{n}|{w}⟩')
            last = s + len(w)
        parts.append(text[last:])
        lines.append(''.join(parts))
    payload = {'model': MODEL, 'temperature': 0.2, 'stream': False,
               'response_format': {'type': 'json_object'},
               'messages': [{'role': 'system', 'content': PROMPT},
                            {'role': 'user', 'content': '\n\n'.join(lines)}]}
    for t in range(tries):
        try:
            r = requests.post(API, json=payload, timeout=600,
                              headers={'Authorization': f'Bearer {key}'})
            if r.status_code == 402 or 'Insufficient Balance' in r.text:
                sys.exit('⚠ Изчерпан баланс в DeepSeek.')
            r.raise_for_status()
            ans = json.loads(r.json()['choices'][0]['message']['content'])
            break
        except (requests.RequestException, ValueError, KeyError):
            time.sleep(5 * (t + 1))
    else:
        return {}
    res = {}
    for k, (bid, s, w) in refs.items():
        v = str(ans.get(k, ''))
        caps = [i for i, c in enumerate(v) if c.isupper() and c.lower() in VOWELS]
        if v.lower() != w.lower() or len(caps) != 1:
            continue                  # отговорът не е същата дума — пропуска се
        res.setdefault(bid, {})[s] = caps[0]
    return res


# ── главното ────────────────────────────────────────────────────────────

def bid_of(text):
    return hashlib.sha1(text.encode()).hexdigest()[:16]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('book', choices=list(BOOKS))
    ap.add_argument('--llm', action='store_true')
    ap.add_argument('--workers', type=int, default=4)
    a = ap.parse_args()
    accents, dic = load_accents(), load_dict()
    chapters = book_blocks(BOOKS[a.book])
    cache_p = WORK / f'{a.book}_llm.json'
    cache = json.loads(cache_p.read_text()) if cache_p.exists() else {}
    llm = {bid: {int(s): i for s, i in v.items()} for bid, v in cache.items()}

    def pass_():
        todo, total, words = [], 0, 0
        for _, blocks in chapters:
            for b in blocks:
                bid = bid_of(b['text'])
                b['marked'], pend = mark(b['text'], accents, dic, llm.get(bid))
                words += sum(1 for m in WORD.finditer(b['text']) if vowel_count(m.group(0)) > 1)
                total += len(pend)
                if pend and bid not in llm:
                    todo.append((bid, b['text'], [(s, w) for s, w, _ in pend]))
        return todo, total, words

    todo, total, words = pass_()
    print(f'многосрични думи: {words}; нерешени: {total} ({total / max(words, 1):.0%}); '
          f'абзаци за модела: {len(todo)}')
    if a.llm and todo:
        key = api_key()
        batches, cur, size = [], [], 0
        for item in todo:
            if cur and size + len(item[1]) > 3000:
                batches.append(cur)
                cur, size = [], 0
            cur.append(item)
            size += len(item[1])
        if cur:
            batches.append(cur)
        print(f'заявки към модела: {len(batches)}')
        done = 0
        with ThreadPoolExecutor(a.workers) as ex:
            for res in ex.map(lambda b: ask(key, b), batches):
                for bid, v in res.items():
                    llm.setdefault(bid, {}).update(v)
                    cache[bid] = {str(s): i for s, i in llm[bid].items()}
                cache_p.write_text(json.dumps(cache, ensure_ascii=False))
                done += 1
                print(f'  {done}/{len(batches)}', flush=True)
        todo, total, words = pass_()
        print(f'след модела нерешени: {total}')
    (WORK / f'{a.book}_marked.json').write_text(json.dumps(
        [{'file': f, 'blocks': bl} for f, bl in chapters], ensure_ascii=False, indent=1))
    report(a.book, chapters, accents, dic, llm)


def report(book, chapters, accents, dic, llm):
    """Думите, решени от модела, и нерешените — за преглед от човек."""
    words, _ = accents
    seen = {}
    for _, blocks in chapters:
        for b in blocks:
            text, bid = b['text'], bid_of(b['text'])
            for s, i in (llm.get(bid) or {}).items():
                w = WORD.match(text, s)
                if not w:
                    continue
                w = w.group(0)
                key = w.lower()[:i] + w.lower()[i].upper() + w.lower()[i + 1:]
                amb = len(dic.get(w.lower(), ())) > 1
                e = seen.setdefault(key, {'n': 0, 'amb': amb, 'ex': text[max(0, s - 40):s + 40]})
                e['n'] += 1
            for s, w, amb in mark(text, accents, dic, llm.get(bid))[1]:
                e = seen.setdefault('? ' + w.lower(), {'n': 0, 'amb': amb, 'ex': text[max(0, s - 40):s + 40]})
                e['n'] += 1
    lines = ['# Ударения за преглед', '',
             'Решени от езиковия модел (липсват в речника или са двузначни). '
             'Ударената гласна е главна. Грешните — в accents.txt с вярното ударение.', '']
    for k, e in sorted(seen.items(), key=lambda kv: (-kv[1]['n'], kv[0])):
        tag = ' (двузначна)' if e['amb'] else ''
        lines.append(f'- **{k}** ×{e["n"]}{tag} — …{e["ex"]}…')
    (WORK / f'{book}_review.md').write_text('\n'.join(lines) + '\n')
    print(f'отчет: {WORK / f"{book}_review.md"} ({len(seen)} думи)')


if __name__ == '__main__':
    main()
