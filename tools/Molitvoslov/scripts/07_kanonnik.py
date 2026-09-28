"""Таб „Канонник" → work/kanonnik.json (в същия вид като akatisti.json).

    цс гр.  „Канонник или полный молитвослов" (.epub) — основата
    цс      „Три канона" от цс молитвослова (work/csl_units.json, раздел 4)
            — само за покаянния, молебния и Ангелския канон
    бг      pravoslavieto.com: Малкият параклис (= молебният канон) и
            Великият канон на св. Андрей Критски (само бг)

⚠ СДВОЯВАНЕТО Е ПО НОМЕР НА ПЕСЕНТА, не по ред: изворите се различават по
онова, което стои между песните (седални, кондаци, тропари). Всичко от
другия извор между песен N и N+1 отива при песен N; предхождащото песен 1
— при първата единица. Така нищо не се губи, а песните вървят една до друга.

⚠ Умилителният канон към Иисус Христос и благодарственият към Богородица
са в СЪЩИТЕ файлове като акатистите (в Канонника акатистът е вмъкнат след
6-та песен). Тук се взимат само песните на канона — акатистът е в своя таб.

⚠ В „Три канона" трите канона са ПРЕПЛЕТЕНИ песен по песен: „Пѣ́снь г҃"
(покаянният), „И҆́нъ, ко прест҃ѣ́й бцⷣѣ" (молебният), „И҆́нъ, а҆́гг҃лꙋ"
(Ангелският). Тук се разплитат.
"""
import importlib.util
import html
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = os.path.join(ROOT, 'work')
_spec = importlib.util.spec_from_file_location(
    'ak', os.path.join(os.path.dirname(__file__), '06_akatisti.py'))
ak = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ak)

KANONNIK_URL = ak.KANONNIK_URL
CSL_URL = 'https://azbyka.ru/molitvoslov/molitvoslov-cerkovnoslavjanskim-shriftom.html'
BG_URL = 'https://www.pravoslavieto.com/bogosluzhenie/kanoni/%s.htm'

# (id, файл в Канонник | None, бг заглавие, само песните?, цс роля, бг страница)
KANONS = [
    (201, 'index_split_018.xhtml', 'Канон покаен към Господ Иисус Христос', False, 'iisus', None),
    (202, 'index_split_011.xhtml', 'Канон умилителен към Господ Иисус Христос', True, None, None),
    (203, 'index_split_014.xhtml', 'Канон молебен към Пресвета Богородица (Малък параклис)',
     False, 'bogorodica', 'paraklis'),
    (204, 'index_split_013.xhtml', 'Канон благодарствен към Пресвета Богородица', True, None, None),
    (205, 'index_split_019.xhtml', 'Канон към Пресвета Богородица Одигитрия', False, None, None),
    (206, 'index_split_015.xhtml', 'Канон към Ангела пазител', False, 'angel', None),
    (207, 'index_split_023.xhtml', 'Канон към Света Троица (творение на св. Григорий Синаит)',
     False, None, None),
    (211, 'index_split_016.xhtml', 'Понеделник: служба на Архангелите и Ангелите', False, None, None),
    (212, 'index_split_017.xhtml', 'Вторник: служба на св. Йоан Предтеча', False, None, None),
    (213, 'index_split_022.xhtml', 'Сряда и петък: служба на Честния Кръст', False, None, None),
    (214, 'index_split_020.xhtml', 'Четвъртък: служба на светите апостоли', False, None, None),
    (215, 'index_split_024.xhtml', 'Събота: служба на всички светии', False, None, None),
    (216, 'index_split_025.xhtml', 'Събота: служба за починалите', False, None, None),
    (221, None, 'Великият покаен канон на св. Андрей Критски', False, None, 'sv_Andrey_Kritski'),
]

MARKS = re.compile('[̀-ͯ҃-҉ⷠ-ⷿ꙯-ꙿ]')
CS_DIGIT = {'а': 1, 'в': 2, 'г': 3, 'д': 4, 'є': 5, 'ѕ': 6, 'з': 7, 'и': 8, 'ѳ': 9}
BG_ORD = {'първа': 1, 'втора': 2, 'трета': 3, 'четвърта': 4, 'пета': 5, 'шеста': 6,
          'седма': 7, 'осма': 8, 'девета': 9}


def song_csr(title):
    m = re.match(r'Пе́?снь\s+(\d+)', (title or '').replace(ak.ACUTE, ''))
    return int(m.group(1)) if m else None


def song_csl(title):
    t = MARKS.sub('', title or '')
    m = re.search(r'Пснь\s+(\S)', t) or re.search(r'Пѣснь\s+(\S)', t)
    return CS_DIGIT.get(m.group(1)) if m else None


def song_bg(text):
    m = re.search(r'Пe?е?сен\s+(\w+)', text.replace('e', 'е'))
    return BG_ORD.get(m.group(1).lower()) if m else None


def csl_canons():
    """„Три канона" (цс) → {роля: [(песен | None, заглавие, блокове)]}."""
    sec = [x for x in json.load(open(os.path.join(W, 'csl_units.json'), encoding='utf-8'))
           if x['sec'] == 4][0]
    out = {'iisus': [], 'bogorodica': [], 'angel': []}
    song = None
    for u in sec['units']:
        t = u['title'] or ''
        n = song_csl(t)
        if n:
            song = n
        if t.startswith('Канѡ́нъ покаѧ́нный') or re.match(r'Пѣ́снь', t):
            role = 'iisus'
        elif 'прест҃ѣ́й бцⷣѣ' in t and (t.startswith('И҆́нъ') or t.startswith('Конда́къ')):
            role = 'bogorodica'
        elif 'а҆́гг҃л' in t:
            role = 'angel'
        elif 'і҆и҃с' in t and (t.startswith('Конда́къ') or t.startswith('Сѣда́ленъ')):
            role = 'iisus'
        else:
            continue
        if song is None:
            continue
        out[role].append((song if (t.startswith('И҆́нъ') or n or t.startswith('Канѡ́нъ'))
                          else song, t, u['blocks']))
    return out


BG_START = {'paraklis': 'След Благословен Бог наш', 'sv_Andrey_Kritski': None}
RE_BG_ITEM = re.compile(r'<(h[2-4]|p)\b[^>]*>(.*?)(?=<p\b|<h[2-6]\b|<div\b|</body|$)',
                        re.S | re.I)


def _bg_html(inner):
    """Абзац от страницата → html: курсивът („Ирмос:", „Слава:") става
    винено указание, <br> остава (стихотворният превод е ред по ред)."""
    inner = re.sub(r'<br\s*/?>', '\x00', inner, flags=re.I)
    inner = re.sub(r'<i>(.*?)</i>', '\x01\\1\x02', inner, flags=re.S | re.I)
    t = html.unescape(re.sub(r'<[^>]+>', '', inner)).replace('\xa0', ' ')
    t = re.sub(r'[ \t\r\n]+', ' ', t).strip()
    t = re.sub(r' ?\x00 ?', '\x00', t).strip('\x00 ')
    t = re.sub(r'\x00{2,}', '\x00\x00', t)
    t = html.escape(t, quote=False)
    t = re.sub(r'\x01\s*(.*?)\s*\x02\s*', lambda m: ('<span class="rubric">%s</span> ' % m.group(1))
               if m.group(1) else '', t)
    t = re.sub(r'(^|\x00)0, ', r'\1О, ', t)
    return t.replace('\x00', '<br>').strip()


def bg_segments(page):
    """Бг страница (канон) → {песен: блокове}; 0 = всичко преди песен 1."""
    raw = open(os.path.join(ROOT, 'cache', 'bg', page + '.htm'), 'rb').read()
    t = raw.decode('utf-8', 'replace')
    t = re.search(r'<body[^>]*>(.*)</body>', t, re.S | re.I).group(1)
    start = BG_START.get(page.split('__')[-1])
    started = False
    segs, cur = {0: []}, 0
    for m in RE_BG_ITEM.finditer(t):
        tag, inner = m.group(1).lower(), m.group(2)
        plain = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', inner))).strip()
        if not started:
            if (start and start in plain) or (tag != 'p' and song_bg(plain)):
                started = True
            else:
                continue
        if plain.startswith('Виж също') or plain.startswith('www.Pravoslavieto'):
            break
        if not plain:
            continue
        if tag != 'p':
            n = song_bg(plain)
            if n:
                cur = n
                segs.setdefault(cur, [])
                continue
            segs.setdefault(cur, []).append({'kind': 'rubric', 'html': html.escape(plain, quote=False)})
            continue
        segs.setdefault(cur, []).append({'kind': 'text', 'html': _bg_html(inner)})
    return segs


CSL_KINDS = [('Конда́къ', 'Кондак'), ('Сѣда́ленъ', 'Седален'), ('Мл҃тва', 'Молитва')]


def _unit_by_word(units, word):
    for u in units:
        if (u['title_csl'] or '').replace(ak.ACUTE, '').startswith(word):
            return u
    return None


def attach(units, segs, lang):
    """Сегментите по песни → поле `lang` на единиците (по номер на песента)."""
    by_song = {}
    for u in units:
        n = song_csr(u['title_csl'])
        if n and n not in by_song:
            by_song[n] = u
    for n, blocks in segs.items():
        if isinstance(n, str):
            target = _unit_by_word(units, n)
        else:
            target = by_song.get(n) if n else (units[0] if units else None)
        if target is None:
            # Песен, каквато основата няма — нова единица накрая.
            target = {'title_csl': None, 'title_bg': None, 'csr': [], 'bg': [], 'csl': [],
                      'sources': []}
            units.append(target)
        target.setdefault(lang, [])
        target[lang] = target[lang] + blocks
        if lang == 'bg' and isinstance(n, int) and n:
            target['title_bg'] = 'Песен %d' % n


# ─── Канонникът на цс (PDF, „Вертоград", кодиране Ucs) ─────────────────────
# ⚠ Номерата са ОТПЕЧАТАНИТЕ страници от съдържанието на книгата; индексът
# в PDF-а е с единица по-малко (стр. 4 е индекс 3 — измерено).
import pdf_ucs  # noqa: E402

PDF = os.path.join(ROOT, 'input', 'newBooks', '20_Канонник ЦС.pdf')
PDF_SOURCE = 'Канонник, изд. „Вертоград“ (2012)'

# Разделите на книгата: първа страница → какво се прави с тях.
#   ('attach', sid)        цс шрифт към наш раздел (само съвпадащите единици)
#   ('new', sid, заглавие) нов раздел само на цс
#   None                   пропуска се (вече имаме цс, или е акатист)
# ⚠ „songs" = само песните и кондака/икоса към канона; акатистът, вмъкнат
# след 6-та песен, отпада (той е в таб „Акатисти").
PDF_TOC = [
    (4, ('new', 231, 'Канон към Света Троица (творение на Митрофан)')),
    (19, ('attach', 202, 'songs')),
    (53, None),                               # покаен — цс вече има
    (66, ('new', 232, 'Канон на Пасха')),
    (83, ('new', 233, 'Канон на Рождество Христово')),
    (99, ('new', 234, 'Канон към Честния и Животворящ Кръст')),
    (117, 'great'),                           # Великият канон — отделно
    (318, None),                              # молебен — цс вече има
    (334, ('attach', 204, 'songs')),
    (366, ('new', 235, 'Канон на Рождество Богородично')),
    (386, ('new', 236, 'Канон на Покрова на Пресвета Богородица')),
    (401, ('new', 237, 'Канон пред иконата на Божията Майка „Утоли моите скърби“')),
    (419, ('new', 238, 'Канон пред иконата на Божията Майка „Скоропослушница“')),
    (434, ('new', 239, 'Канон пред иконата на Божията Майка „Троеручица“')),
    (456, ('attach', 211, 'all')),
    (471, ('new', 251, 'Канон към св. архистратиг Михаил')),
    (489, ('new', 252, 'Канон към св. архангел Гавриил')),
    (505, None),                              # Ангел пазител — цс вече има
    (518, ('attach', 212, 'all')),
    (535, ('new', 253, 'Канон към свт. Николай Чудотворец', 'songs')),
    (580, ('new', 254, 'Канон към свт. Спиридон Тримитунтски')),
    (598, ('new', 255, 'Канон към свщмч. Киприан и мц. Иустина')),
    (613, ('new', 256, 'Канон към вмч. Пантелеймон Лечител')),
    (630, ('new', 257, 'Канон към мч. Трифон')),
    (644, ('new', 258, 'Канон към прп. Сергий Радонежки')),
    (668, ('new', 259, 'Канон към прп. Александър Свирски')),
    (686, ('new', 260, 'Канон към прп. Серафим Саровски')),
    (705, ('new', 261, 'Канон към св. прав. Йоан Кронщадски')),
    (720, ('new', 262, 'Канон към прп. Мария Египетска')),
    (735, ('new', 263, 'Канон към св. Петър и Феврония Муромски')),
    (750, ('new', 264, 'Канон към св. прав. Анна, майка на Пресвета Богородица')),
    (765, None),                              # акатистите — има ги
]
PDF_END = 764            # последната страница преди акатистите

GREAT_DAYS = [
    ('Въ понедѣльникъ', 241, 'Великият покаен канон — понеделник от първата седмица'),
    ('Во вторникъ', 242, 'Великият покаен канон — вторник от първата седмица'),
    ('Въ средꙋ', 243, 'Великият покаен канон — сряда от първата седмица'),
    ('Въ четвертокъ', 244, 'Великият покаен канон — четвъртък от първата седмица'),
]


def csr_key_units(units, title_of):
    """Ключове като при PDF-а: ('song', N) или (вид, след песен N, пореден)."""
    keys, last, cnt = {}, 0, {}
    for u in units:
        t = (title_of(u) or '').replace(ak.ACUTE, '')
        m = re.match(r'(?:Пе?снь|Песен)\s+(\d+)', t)
        kind = None
        if m:
            last = int(m.group(1))
            keys[('song', last)] = u
            continue
        for k, w in (('kondak', 'Кондак'), ('ikos', 'Икос'), ('sedalen', 'Седален'),
                     ('prayer', 'Молитва')):
            if t.startswith(w):
                kind = k
        if kind:
            cnt[(kind, last)] = cnt.get((kind, last), 0) + 1
            keys[(kind, last, cnt[(kind, last)])] = u
    return keys


def csl_unit(pu):
    return {'title_csl': None, 'title_bg': None, 'title_cs': pu['title'],
            'csr': [], 'bg': [], 'csl': pu['blocks'], 'sources': []}


def merge_pdf(units, pdf_units, title_of, insert_unmatched):
    """Цс от PDF-а към готовите единици, по ключ. Несъвпадналите се вмъкват
    СЛЕД последната съвпаднала (при Великия канон) или отпадат."""
    keys = csr_key_units(units, title_of)
    hit = miss = 0
    after = None
    for pu in pdf_units:
        k = tuple(pu['key'])
        if k[0] == 'intro':
            continue
        u = keys.get(k)
        if u is not None:
            u['csl'] = pu['blocks']
            after = u
            hit += 1
        elif insert_unmatched:
            new = csl_unit(pu)
            units.insert(units.index(after) + 1 if after else 0, new)
            after = new
            miss += 1
        else:
            miss += 1
    return hit, miss


def only_songs(pdf_units):
    """Акатистът е вмъкнат след 6-та песен — той не е част от канона."""
    return [u for u in pdf_units if u['key'][0] in ('intro', 'song', 'prayer', 'sedalen')]


def pdf_sections():
    """→ (attach: {sid: (pdf_units, mode)}, new: [раздел], great: pdf_units)."""
    doc = pdf_ucs.open_doc(PDF)
    starts = [p for p, _ in PDF_TOC] + [PDF_END + 2]
    attach, new, great_full = {}, [], None
    for (page, act), nxt in zip(PDF_TOC, starts[1:]):
        if act is None:
            continue
        ls = pdf_ucs.lines(doc, page - 1, nxt - 2)
        title_cs = ' '.join(''.join(t for _, t in r[4]).strip() for r in ls
                            if r[2] and r[3] and r[0] == page - 1)
        if act == 'great':
            # ⚠ Четирите дни идват от ПАРАЛЕЛНОТО издание (цс | бг), не
            # оттук — тук се взима само целият канон от 5-та седмица.
            great_full, _ = great_canon(ls)
            new.extend(great_days_parallel())
            continue
        pu = pdf_ucs.units(ls)
        if act[0] == 'attach':
            attach[act[1]] = only_songs(pu) if act[2] == 'songs' else pu
        else:
            if len(act) > 3 and act[3] == 'songs':
                pu = only_songs(pu)
            new.append(pdf_new_section(act[1], act[2], title_cs, pu))
    return attach, new, great_full


def great_canon(ls):
    """Великият канон: четирите дни от 1-ва седмица + целият (5-та седмица)."""
    bare = lambda r: pdf_ucs.bare(''.join(t for _, t in r[4])).replace('҆', '')
    heads = [i for i, r in enumerate(ls) if r[2] and r[3]]
    day_at = []
    for word, sid, tbg in GREAT_DAYS:
        i = next(i for i in heads if bare(ls[i]).startswith(word)
                 and not any(i == d for d, *_ in day_at))
        day_at.append((i, sid, tbg))
    fifth = next(i for i in heads if 'пѧтыѧ' in bare(ls[i + 1]) or 'пѧтыѧ' in bare(ls[i]))
    days = []
    for n, (i, sid, tbg) in enumerate(day_at):
        end = day_at[n + 1][0] if n + 1 < len(day_at) else fifth
        days.append((sid, tbg, ls[i:end]))
    full_at = next(i for i, r in enumerate(ls) if i > fifth and r[3]
                   and bare(r).startswith('Канѡнъ великїй'))
    return pdf_ucs.units(ls[full_at:]), days


PARALLEL = os.path.join(ROOT, 'input', 'newBooks', 'Velik_kanon_Andrei Kritski.pdf')
PARALLEL_BG = 'http://bulgarian-orthodox-church.org/rr/liturg/tripesnvp-01-vkanon.pdf'
PARALLEL_CS = 'Велик канон, фондация „Свети Седмочисленици“ (2013)'


def great_days_parallel():
    """Великият канон по дни — цс и бг от паралелното издание (2013)."""
    out = []
    for (word, sid, tbg), day in zip(GREAT_DAYS, pdf_ucs.parallel(PARALLEL)):
        units = [{'title_csl': None, 'title_bg': u['title_bg'], 'title_cs': u['title_cs'],
                  'csr': [], 'bg': u['bg'], 'csl': u['csl'],
                  'sources': [PARALLEL_BG] if u['bg'] else []}
                 for u in day['units']]
        out.append({'sec': sid, 'tab': 'kanonnik', 'title_bg': tbg,
                    'title_csl': day['title_cs'], 'csr_source': None,
                    'csl_source': PARALLEL_CS, 'units': units})
    return out


_TR = str.maketrans({'ѡ': 'о', 'ѻ': 'о', 'ꙋ': 'у', 'ѹ': 'у', 'ѧ': 'я', 'ꙗ': 'я', 'ѣ': 'е',
                     'є': 'е', 'і': 'и', 'ї': 'и', 'ѵ': 'и', 'ѳ': 'ф', 'ѕ': 'з', 'ъ': None,
                     'ь': None, 'й': 'и', 'ы': 'и'})


def fold_cs(h):
    """За сравнение между ДВЕ издания: без етикетите, надредните знаци и
    правописните варианти (ѡ/о, ꙋ/у…) — те се разминават между книгите."""
    h = re.sub(r'<span class="rubric">.*?</span>', '', h)
    h = re.sub(r'<[^>]+>', '', h)
    t = pdf_ucs.bare(h).replace('҆', '').lower()
    t = t.replace('ѿ', 'от').replace('ѯ', 'кс').replace('ѱ', 'пс').replace('ѽ', 'от')
    return re.sub(r'[\W\d_]', '', t.translate(_TR))[:50]


def great_full_bg(pdf_units):
    """Целият Велик канон с бг превод, взет от четирите дни по съвпадение на
    цс текста. ⚠ Добавките в четвъртък на 5-та седмица (канонът към
    апостолите, припевите към св. Андрей, блаженствата) ги няма в дните —
    остават само на цс."""
    import difflib
    tr = {}
    for day in pdf_ucs.parallel(PARALLEL):
        for u in day['units']:
            if len(u['csl']) != len(u['bg']):
                continue
            for a, b in zip(u['csl'], u['bg']):
                f = fold_cs(a['html'])
                if f:
                    tr.setdefault(f, b)
    keys = list(tr)
    units, hit, tot = [], 0, 0
    for pu in pdf_units:
        bg = []
        for b in pu['blocks']:
            if b['kind'] == 'rubric':
                continue
            tot += 1
            f = fold_cs(b['html'])
            k = f if f in tr else next(iter(difflib.get_close_matches(f, keys, 1, 0.8)), None)
            if k:
                bg.append(tr[k])
                hit += 1
        n = pdf_ucs.song_no(pu['title']) if pu['title'] else None
        tb = ('Песен %d' % n if n else
              {'kondak': 'Кондак, глас 6', 'sedalen': 'Седален, глас 8'}.get(pu['key'][0]))
        units.append({'title_csl': None, 'title_bg': tb,
                      'title_cs': pu['title'], 'csr': [], 'bg': bg, 'csl': pu['blocks'],
                      'sources': [PARALLEL_BG] if bg else []})
    print('     Велик канон (цял): бг за %d от %d тропара' % (hit, tot))
    return units


def pdf_new_section(sid, title_bg, title_cs, pdf_units):
    units = [csl_unit(u) for u in pdf_units]
    return {'sec': sid, 'tab': 'kanonnik', 'title_bg': title_bg, 'title_csl': title_cs or None,
            'csr_source': None, 'csl_source': PDF_SOURCE, 'units': units}


# Редът в таба: каноните към Господ и празниците, Богородица, безплътните
# сили, светиите, седмичните служби, накрая Великият канон с дните му.
ORDER = [201, 202, 231, 207, 232, 233, 234, 203, 204, 205, 235, 236, 237, 238, 239,
         206, 251, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264,
         211, 212, 213, 214, 215, 216, 221, 241, 242, 243, 244]


def order(secs):
    pos = {sid: i for i, sid in enumerate(ORDER)}
    return sorted(secs, key=lambda x: pos.get(x['sec'], 999))


def main():
    csl = csl_canons()
    pdf_attach, pdf_new, pdf_great = pdf_sections()
    out = []
    for sid, kfile, title_bg, songs_only, csl_role, bg_page in KANONS:
        units = []
        if kfile:
            for u in ak.parse_kanonnik(kfile):
                t = u['title'] or ''
                if songs_only and not song_csr(t) and not t.replace(ak.ACUTE, '').startswith('Канон'):
                    # Акатистът и молитвите му — в таб „Акатисти".
                    continue
                units.append({'title_csl': t or None, 'title_bg': None, 'csr': u['blocks'],
                              'bg': [], 'csl': [], 'sources': []})
        if csl_role:
            segs = {}
            for song, t, blocks in csl[csl_role]:
                # ⚠ Кондакът, седалът и молитвата отиват при СВОЯТА единица
                # (ако основата я има отделно) — инак вдясно излизат два пъти.
                key = song
                for cs_word, key_word in CSL_KINDS:
                    if t.startswith(cs_word) and _unit_by_word(units, key_word):
                        key = key_word
                segs.setdefault(key, []).extend(blocks)
            attach(units, segs, 'csl')
        if bg_page:
            segs = bg_segments('bogosluzhenie__kanoni__' + bg_page)
            if units:
                attach(units, segs, 'bg')
                for u in units:
                    if u['bg']:
                        u['sources'] = [BG_URL % bg_page]
            else:
                # Само бг (Великият канон): единица на песен.
                for n in sorted(segs):
                    if segs[n]:
                        units.append({'title_csl': None,
                                      'title_bg': 'Песен %d' % n if n else None,
                                      'csr': [], 'bg': segs[n], 'csl': [],
                                      'sources': [BG_URL % bg_page]})
        pdf_src = None
        if sid in pdf_attach:
            h, m = merge_pdf(units, pdf_attach[sid], lambda u: u['title_csl'], False)
            print('     цс от PDF: %d съвпаднали, %d отпаднали' % (h, m))
            pdf_src = PDF_SOURCE
        if sid == 221 and pdf_great:
            # ⚠ Целият канон: цс от Канонника (службата в четвъртък на 5-та
            # седмица), бг — ПРЕВОДЪТ ОТ ЧЕТИРИТЕ ДНИ, тропар по тропар.
            # Стихотворното преразказване от pravoslavieto.com отпада.
            units = great_full_bg(pdf_great)
            pdf_src = PARALLEL_CS + '; ' + PDF_SOURCE
        for i, u in enumerate(units):
            u['n'] = i
        title_csl = None
        if kfile:
            import zipfile
            z = zipfile.ZipFile(ak.KANONNIK)
            h = re.search(r'<h2[^>]*>(.*?)</h2>', z.read(kfile).decode('utf-8'), re.S)
            title_csl = ak.plain(h.group(1)) if h else None
        out.append({'sec': sid, 'tab': 'kanonnik', 'title_bg': title_bg, 'title_csl': title_csl,
                    'csr_source': KANONNIK_URL if kfile else None,
                    'csl_source': CSL_URL if csl_role else pdf_src, 'units': units})
        print('  %d  единици %3d  (цс гр. %3d · цс %3d · бг %3d)  %s' % (
            sid, len(units), sum(1 for u in units if u['csr']),
            sum(1 for u in units if u.get('csl')), sum(1 for u in units if u['bg']), title_bg))
    for sec in pdf_new:
        for i, u in enumerate(sec['units']):
            u['n'] = i
        out.append(sec)
        print('  %d  единици %3d  (цс %d · бг %d)  %s' % (
            sec['sec'], len(sec['units']), sum(1 for u in sec['units'] if u['csl']),
            sum(1 for u in sec['units'] if u['bg']), sec['title_bg']))
    out = order(out)
    json.dump(out, open(os.path.join(W, 'kanonnik.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('→ work/kanonnik.json')


if __name__ == '__main__':
    main()
