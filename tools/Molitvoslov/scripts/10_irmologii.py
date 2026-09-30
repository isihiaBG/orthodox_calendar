#!/usr/bin/env python3
"""Ирмологий → work/irmologii.json — последната от богослужебните книги.

    python3 10_irmologii.py        # после 05_build_db.py

⚠ ИЗВОРЪТ Е HIP (orthlib.ru), НЕ .epub-ът. Книгата я има и като .epub от
azbyka.ru, но там е с ГРАЖДАНСКИ шрифт, а всички останали богослужебни книги
са с църковнославянски — затова се предпочита HIP (решение на потребителя).
Преобразуването е в `hip.py`. Архивът `input/newBooks2/irmologij.rar` се
разархивира в `work/irmologij_hip/` при всяко пускане.

⚠ ЧЕРВЕНОТО НЕ Е ОТБЕЛЯЗАНО В ИЗВОРА (няма `%<`). Указанията се познават по
вид — с ограниченията на всяко гадаене:
  • „Пѣ́снь а҃." (и „Гла́съ а҃." в богородичните/степенните) → нова молитва;
  • „[Въ ржⷭ҇тво̀ хрⷭ҇то́во:]" в началото или вътре в реда → червен етикет;
  • кратък ред, завършващ на „:" → червен ред;
  • ред, започващ с указателна дума (Та́же, Посе́мъ, Вѣ́домо…) → червен;
  • „Сті́хъ:", „Сла́ва:", „И҆ ны́нѣ:", „Пе́рвый ли́къ:"… в началото → етикет.
Не се превежда (решение на потребителя); заглавията в съдържанието са на
български, написани тук на ръка.
"""
import html
import json
import re
import subprocess
import sys
from pathlib import Path

import hip

ROOT = Path(__file__).resolve().parents[1]
W = ROOT / 'work'
RAR = ROOT / 'input' / 'newBooks2' / 'irmologij.rar'
HIPDIR = W / 'irmologij_hip'
SRC = 'http://orthlib.ru'
BOOK = 'Ирмологий'
FIRST_ID = 2001        # богослужебните книги са 1001…; тук — отделен обхват

TITLES = {
    '01glas': 'Ирмоси на глас 1', '02glas': 'Ирмоси на глас 2', '03glas': 'Ирмоси на глас 3',
    '04glas': 'Ирмоси на глас 4', '05glas': 'Ирмоси на глас 5', '06glas': 'Ирмоси на глас 6',
    '07glas': 'Ирмоси на глас 7', '08glas': 'Ирмоси на глас 8',
    '09predrojd': 'Ирмоси в предпразненството на Рождество Христово',
    '10predkres': 'Ирмоси в предпразненството на Светите Богоявления',
    '11liturgia': 'Последование на църковните песнопения на Божествената литургия',
    '12prezhdeosv': 'Ако е Великата Четиридесетница',
    '13bgrvoskr': 'Богородични възкресни на осемте гласа',
    '14bgrvsednev': 'Богородични на осемте гласа, когато е Слава на светия в Минея',
    '15stepen': 'Степенни на осемте гласа',
    '16pesnvsedn': 'На утренята след шестопсалмието',
    '17pesnprazd': 'Библейски песни – празнични',
    '18pesnpost': 'Библейски песни през Светата Четиридесетница',
    '19neporochned': 'Възкресни тропари след Непорочните в неделя, глас 5',
    '20prokother': 'Възкресни прокимени',
    '21neporochsub': 'Тропари след Непорочните в събота, глас 5',
    '22paskha': 'Канон в Светата Неделя на Пасха и в цялата Светла седмица',
    '23izbrpsalm': 'Избрани псалми',
    '24pripev': 'Припеви на 9-ата песен на Господските и Богородичните празници',
}

# ⚠ Файлът 16 носи ТРИ отделни неща едно след друго — делят се по шевовете в
# самия текст, всяко става свой раздел (искане на потребителя, 30.09.2026):
# абзацът, който ПОЧВА така, е първият на новия раздел.
SPLITS = {
    '16pesnvsedn': [('Вѣ́домо бꙋ́ди, ꙗ҆́кѡ въ трⷪ҇чныхъ', 'Троични песни'),
                    ('Та́же стїхосло́вїе Ѱалти́ра', 'Библейски песни – всекидневни')],
}

RE_SONG = re.compile(r'^(Пѣ́снь\s+\S+?)[.:]?(?:\s+(?:[Іі]҆рмо́съ):?\s*(.*))?$')
# „Пѣ̑сни трⷪ҇чны. Гла́съ а҃." — при троичните гласът носи и името на песните.
RE_GLAS = re.compile(r'^(?:Пѣ̑сни трⷪ҇чны\.\s+)?(Гла́съ\s+\S+?)[.:](?:\s+(.*))?$')
# ⚠ „Пое́мъ" САМО с „и҆̀хъ" (указанието в Богородичните): голото „Пое́мъ гдⷭ҇еви,
# сла́внѡ бо просла́висѧ…" е СТИХ от Изход 15 и оцветен червен лъже.
# (Бележка на потребителя, 30.09.2026.)
STARTERS = ('Та́же', 'Посе́мъ', 'Вѣ́домо', 'Подоба́етъ', 'Пое́тсѧ', 'И҆ а҆́бїе', 'И҆ про́чее',
            'А҆́ще же', 'Въ недѣ́лю ѹ҆́бѡ', 'По возгла́сѣ', 'По пе́рвомъ', 'И҆ по чи́нꙋ', 'Кі́йждо',
            'Нача́ло', 'И҆ начина́етъ', 'Глаго́лемъ же', 'Пое́мъ и҆̀хъ', 'На є҆ди́номъ',
            'Въ недѣ́лю же')
# Указания, които са червени ЦЕЛИ, каквато и дължина да имат — катавасията,
# поклонът, „глаголи ирмос/тропар" и т.н. (посочени от потребителя).
FULL_RED = ('Глаго́ли і҆рмо́съ', 'Глаго́ли тропа́рь', 'Седма́ѧ же', 'И҆ покло́нъ', 'Покло́нъ',
            'И҆ тропа́рь', 'И҆ катава́сїа', 'Катава́сїа', 'И҆ по і҆рмосѣ̀')
# Указание, СЛЕД което следва текст за пеене: червен е само етикетът.
LEAD_LABELS = ('Та́же глаго́лемъ:', 'Въ понедѣ́льникъ ѹ҆́бѡ къ пе́рвомꙋ:', 'Во вто́рникъ же:',
               'Въ сре́дꙋ и҆ пѧто́къ:', 'Въ четверто́къ:',
               'Во второ́е на Сла́ва: глаго́лати внегда̀ въ конца́хъ',
               'Въ тре́тїе же на И҆ ны́нѣ: въ конца́хъ глаго́лати:')
LABEL = re.compile(r'^((?:Сті́хъ(?:\s+\S+)?|Сла́ва|И҆ ны́нѣ|Сла́ва,? и҆ ны́нѣ|Прокі́менъ[^:]{0,15}|'
                   r'Тропа́рь|Бг҃оро́диченъ|Пе́рвый ли́къ[^:]{0,15}|Вторы́й ли́къ[^:]{0,15}|'
                   r'Ли́къ|І҆рмо́съ|И҆ і҆рмо́съ|Начина́й|На \S{1,6}):)\s+(\S.*)$')
TITLE_PAGE = ('І҆РМОЛО́ГЇЙ', 'съ бг҃омъ ст҃ы́мъ', 'ѡ҆бдержа́й всѧ̑')


def red(t):
    return '<span class="rubric">%s</span>' % t


def brackets(h):
    """„[…]" — червен етикет, без скобите."""
    return re.sub(r'\[([^\[\]]+)\]', lambda m: red(m.group(1)), h)


def units_of(paras):
    units = [{'title': None, 'blocks': []}]
    for p in paras:
        plain = re.sub(r'<[^>]+>', '', html.unescape(p))
        if 'Библиотека' in plain or plain.startswith(TITLE_PAGE):
            continue
        m = RE_SONG.match(plain)
        if m and len(plain) < 200:
            units.append({'title': m.group(1), 'blocks': []})
            if m.group(2):
                units[-1]['blocks'].append({'kind': 'text', 'html': brackets(
                    '%s %s' % (red('І҆рмо́съ:'), html.escape(m.group(2), quote=False)))})
            continue
        m = RE_GLAS.match(plain)
        if m and len(plain) < 60:
            units.append({'title': m.group(1), 'blocks': []})
            if m.group(2):
                units[-1]['blocks'].append({'kind': 'text', 'html': brackets(
                    html.escape(m.group(2), quote=False))})
            continue
        lead = next((l for l in LEAD_LABELS if plain.startswith(l)), None)
        if lead:
            units[-1]['blocks'].append({'kind': 'text', 'html': brackets('%s %s' % (
                red(html.escape(lead, quote=False)),
                html.escape(plain[len(lead):].strip(), quote=False)))})
            continue
        if plain.startswith(FULL_RED):
            units[-1]['blocks'].append({'kind': 'rubric', 'html': html.escape(plain, quote=False)})
            continue
        whole = re.fullmatch(r'\[([^\[\]]+)\]', plain)
        if whole or (len(plain) < 150 and plain.endswith(':') and not plain.startswith('['))\
                or (plain.startswith(STARTERS) and len(plain) < 400):
            units[-1]['blocks'].append({'kind': 'rubric', 'html': html.escape(
                whole.group(1) if whole else plain, quote=False)})
            continue
        m = LABEL.match(plain)
        if m:
            h = '%s %s' % (red(html.escape(m.group(1), quote=False)),
                           html.escape(m.group(2), quote=False))
        else:
            h = html.escape(plain, quote=False)
        units[-1]['blocks'].append({'kind': 'text', 'html': brackets(h)})
    return [u for u in units if u['blocks']]


def main():
    HIPDIR.mkdir(parents=True, exist_ok=True)
    subprocess.run(['unrar', 'x', '-o+', '-inul', str(RAR), str(HIPDIR) + '/'], check=True)
    out = []
    sid = FIRST_ID
    for key in TITLES:
        f = HIPDIR / (key + '.hip')
        if not f.exists():
            sys.exit('⚠ липсва %s' % f.name)
        unknown = set()
        paras = hip.convert(f.read_bytes().decode('cp1251'), unknown)
        if unknown:
            print('  ⚠ %s: непознати означения %s' % (f.name, sorted(unknown)))
        parts = [(TITLES[key], paras)]
        for start, title in SPLITS.get(key, []):
            rest = parts[-1][1]
            plain = [re.sub(r'<[^>]+>', '', html.unescape(p)) for p in rest]
            at = next((j for j, t in enumerate(plain) if t.startswith(start)), None)
            if at is None:
                sys.exit('⚠ %s: няма шев „%s"' % (f.name, start))
            parts[-1] = (parts[-1][0], rest[:at])
            parts.append((title, rest[at:]))
        for title, ps in parts:
            us = units_of(ps)
            out.append({'sec': sid, 'tab': 'bogosluzhebni', 'book': BOOK, 'grp': None,
                        'title_bg': title, 'title_csl': None, 'csr_source': None,
                        'csl_source': SRC,
                        'units': [{'n': k, 'title_csl': u['title'], 'title_bg': None,
                                   'title_cs': None, 'csl': u['blocks'], 'csr': [], 'bg': [],
                                   'sources': []}
                                  for k, u in enumerate(us)]})
            sid += 1
    (W / 'irmologii.json').write_text(json.dumps(out, ensure_ascii=False, indent=1),
                                      encoding='utf-8')
    n = sum(len(u['csl']) for s in out for u in s['units'])
    r = sum(1 for s in out for u in s['units'] for b in u['csl'] if b['kind'] == 'rubric')
    print('→ work/irmologii.json: %d глави, %d молитви, %d блока (%d червени реда)' % (
        len(out), sum(len(s['units']) for s in out), n, r))


if __name__ == '__main__':
    main()
