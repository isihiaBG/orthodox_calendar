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


def main():
    csl = csl_canons()
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
                    'csl_source': CSL_URL if csl_role else None, 'units': units})
        print('  %d  единици %3d  (цс гр. %3d · цс %3d · бг %3d)  %s' % (
            sid, len(units), sum(1 for u in units if u['csr']),
            sum(1 for u in units if u.get('csl')), sum(1 for u in units if u['bg']), title_bg))
    json.dump(out, open(os.path.join(W, 'kanonnik.json'), 'w', encoding='utf-8'),
              ensure_ascii=False, indent=1)
    print('→ work/kanonnik.json')


if __name__ == '__main__':
    main()
