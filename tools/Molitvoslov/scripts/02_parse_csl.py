"""Цс молитвословът (work/csl_book.html, от 01) → раздели и отделни молитви.

    → work/csl_units.json
      [ { "sec": 1, "title": "Мл҃твы ѹ҆́трєннїѧ.",
          "units": [ { "n": 0, "title": null | "Мл҃тва мытарѧ̀:",
                       "blocks": [ {"kind": "text"|"rubric", "html": "…"} ] } ] } ]

ЕДИНИЦАТА Е МОЛИТВАТА (<h3>). Текстът преди първото <h3> на раздела влиза в
единица без заглавие (n = 0) — там стоят уводните указания („Воспрѧнꙋ́въ без̾
лѣ́ности…").

⚠ Разделите се познават по котвата <a name="N"/> в <h2>, а НЕ по самото <h2>:
„Канѡ́нъ, гла́съ в҃." е <h2> без котва и е ЧАСТ от последованието към
причастие. Тук той става заглавие на единица, както всяко <h3>.

⚠ Абзац, който е ИЗЦЯЛО указание (само <span class="rubric">), е блок
„rubric"; указание насред текста остава вътре в „text" като span — така
четецът го рисува винено на място, без да се губи редът на думите.
"""
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'work', 'csl_book.html')
OUT = os.path.join(ROOT, 'work', 'csl_units.json')

RE_ITEM = re.compile(r'<(h2|h3|p)\b[^>]*>(.*?)</\1>', re.S)
RE_ANCHOR = re.compile(r'<a name="(\d+)"\s*/>')
RE_ONLY_RUBRIC = re.compile(r'^\s*<span class="rubric">((?:(?!<span).)*?)</span>\s*$', re.S)


def clean(s: str) -> str:
    s = RE_ANCHOR.sub('', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


def plain(s: str) -> str:
    return re.sub(r'<[^>]+>', '', s).strip()


# ───────────────── деленето на слетите абзаци ─────────────────
#
# ⚠ Книгата слива в ЕДИН абзац самостоятелни молитви („Молитвами святых…
# Слава Тебе… Царю небесный… Святый Боже… [Трижды.]") и така указанието
# „[Трижды.]" изглежда, че важи за целия абзац, а важи само за последната.
# Същото в канона: припевите и тропарите са един абзац. (Докладвано от
# потребителя, 28.09.2026.) Делим по ПРИЗНАК, не по място.

MARKS = '[\u0300-\u036f\u0483-\u0489\u2de0-\u2dff\ua66f-\ua67f]*'
RE_MARK = re.compile(MARKS)


def loose(s):
    """Израз, който хваща низа с КАКВИТО И ДА Е надредни знаци."""
    base = RE_MARK.sub('', s)
    return ''.join(re.escape(ch) + (MARKS if ch != ' ' else '') for ch in base)


# Начала на самостоятелни молитви: пред тях — нов ред, ако стоят след
# края на изречение.
INCIPITS = [   # дословно от книгата; надредните знаци не са задължителни
    'Сла́ва тебѣ̀ бж҃е', 'Цр҃ю̀ нбⷭ҇ный', 'Ст҃ы́й бж҃е', 'Сла́ва ѻ҆ц҃ꙋ̀',
    'И҆ ны́нѣ и҆ при́снѡ', 'Прест҃а́ѧ трⷪ҇це', 'Ѻ҆́ч҃е на́шъ',
    'Прїиди́те, поклони́мсѧ', 'Чⷭ҇тнѣ́йшꙋю херꙋві̑мъ', 'Досто́йно є҆́сть',
    'Млⷭ҇рдїѧ двє́ри', 'Мл҃твами ст҃ы́хъ', 'Гдⷭ҇и, поми́лꙋй.',
    'Гдⷭ҇и, поми́лꙋй на́съ, на тѧ́', 'Мнѣ́ же є҆́же прилѣплѧ́тисѧ',
]
RE_INCIPIT = re.compile('(?<=[.;!] )(?:' + '|'.join(loose(i) for i in INCIPITS) + ')')
# „Слава… Духу." НЕ се откъсва от „И ныне…" подир нея — това е едно славословие.
RE_NYNE = re.compile(loose('И҆ ны́нѣ'))
RE_AMIN = re.compile(loose('А҆ми́нь') + r'\. (?!<span)')
# Указание-брой или указание-изречение, след което идва текст.
RE_AFTER_RUBRIC = re.compile(r'(?:\]|\.)</span> (?=[^<\s])')
# Етикети, с които започва нов ред.
RE_LABEL_SPAN = re.compile(r' (?=<span class="rubric">(?:' + '|'.join(loose(x) for x in [
    'Припѣ́въ', 'Сла́ва ѻ҆ц҃ꙋ̀', 'Сла́ва:', 'Бг҃оро́диченъ', 'Сті́хъ', 'І҆рмо́съ',
    'І҆́косъ', 'Прест҃а́ѧ бцⷣе', 'И҆ па́ки:']) + '))')
# „Слава… Духу." пред тропар — тропарът на нов ред (като при глас 6).
RE_SLAVA_END = re.compile(loose('дх҃ꙋ') + r'\. (?!' + loose('И҆ ны́нѣ') + ')')
RE_PRIPEV = re.compile(r'^<span class="rubric">' + loose('Припѣ́въ') + r'[^<]*</span>\s*')


def split_points(html):
    pts = set()
    for m in RE_LABEL_SPAN.finditer(html):
        pts.add(m.end())
    for m in RE_AFTER_RUBRIC.finditer(html):
        pts.add(m.end())
    for m in RE_AMIN.finditer(html):
        pts.add(m.end())
    for m in RE_SLAVA_END.finditer(html):
        pts.add(m.end())
    for m in RE_INCIPIT.finditer(html):
        # И ныне веднага след „Духу." остава при Слава — едно славословие.
        before = RE_MARK.sub('', plain(html[:m.start()])).rstrip()
        if RE_NYNE.match(html, m.start()) and before.endswith('дхꙋ.'):
            continue
        pts.add(m.start())
    return sorted(p for p in pts if 0 < p < len(html))


def in_tag(html, i):
    return html.rfind('<', 0, i) > html.rfind('>', 0, i)


def split_block(html):
    """Един слят абзац → няколко блока (текст / указание / припев)."""
    out, prev = [], 0
    for p in split_points(html) + [len(html)]:
        if in_tag(html, p):
            continue
        piece = html[prev:p].strip()
        prev = p
        if piece and plain(piece):
            out.extend(split_refrain(piece))
    return out


def split_refrain(piece):
    """„Припев: <припев>. <тропар>" → припевът отделно (по-дребен), тропарът
    на нов ред, БЕЗ етикет (указание на потребителя)."""
    m = RE_PRIPEV.match(piece)
    if not m:
        r = RE_ONLY_RUBRIC.match(piece)
        if r:
            return [{'kind': 'rubric', 'html': r.group(1).strip()}]
        return [{'kind': 'text', 'html': piece}]
    rest = piece[m.end():]
    end = re.search(r'[.!] (?=\S)', plain(rest) and rest)
    if not end:
        return [{'kind': 'refrain', 'html': piece}]
    ref = piece[:m.end() + end.end()].strip()
    trop = rest[end.end():].strip()
    out = [{'kind': 'refrain', 'html': ref}]
    if trop:
        out.extend(split_refrain(trop))
    return out


def main():
    src = open(SRC, encoding='utf-8').read()
    sections, sec, unit = [], None, None

    for m in RE_ITEM.finditer(src):
        tag, inner = m.group(1), m.group(2)
        anchor = RE_ANCHOR.search(inner)
        if tag == 'h2' and anchor:
            sec = {'sec': int(anchor.group(1)), 'title': plain(clean(inner)),
                   'units': []}
            sections.append(sec)
            unit = None
            continue
        if sec is None:
            continue                      # съдържанието най-отгоре
        if tag in ('h2', 'h3'):
            unit = {'n': len(sec['units']) + 1 if sec['units'] or unit else 1,
                    'title': plain(clean(inner)), 'blocks': []}
            sec['units'].append(unit)
            continue
        body = clean(inner)
        if not plain(body):
            continue
        if unit is None:                  # уводът преди първото заглавие
            unit = {'n': 0, 'title': None, 'blocks': []}
            sec['units'].append(unit)
        unit['blocks'].extend(split_block(body))

    # номерата наново, за да са поредни и без дупки
    for s in sections:
        k = 0
        for u in s['units']:
            if u['title'] is None:
                u['n'] = 0
            else:
                k += 1
                u['n'] = k

    json.dump(sections, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('→', OUT)
    for s in sections:
        nb = sum(len(u['blocks']) for u in s['units'])
        print('  %2d  %3d молитви  %4d блока  %s' % (s['sec'], len(s['units']), nb, s['title'][:60]))


if __name__ == '__main__':
    main()
