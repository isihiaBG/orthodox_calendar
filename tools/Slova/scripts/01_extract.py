#!/usr/bin/env python3
"""Двете книги в input/ → work/units/*.json (за общия преводач).

    python3 01_extract.py

⚠ НИЩО НЕ ПИШЕ В БАЗИ и нищо не струва пари.

Книгите:
  • прп. Юстин (Попович), „Что такое святость и зачем православному
    христианину читать «Жития святых»" — ЕДНО слово (justin-01);
  • свт. Йоан Златоуст, „Похвалы святым" — беседите (zl-NN).

⚠⚠ ВСЕКИ БЛОК НОСИ ВИДА СИ В ОТДЕЛЕН СПИСЪК (`kinds`), успореден на
`blocks_ru`: title, titlenote, h, p, note. Преводачът превежда само
текста и връща същия брой редове; видът не зависи от това дали моделът е
запазил някакъв маркер в текста.

⚠ КНИГИТЕ СЕ ПАЗЯТ КАТО КНИГИ — редът (`order`) и частта в azbyka.ru
(`part`) остават, защото същият превод ще влезе и в „Читалня".

⚠ Бележките в книгите са връзки с текста в атрибута `title`:
  • `*N` (редакторски) стоят почти винаги на ЗАГЛАВИЕТО и казват кога и
    къде е произнесена беседата — стават ред под заглавието (titlenote);
  • цифровите стоят в текста — горен индекс там, текстът им накрая (note).
Библейските връзки (azbyka.ru/biblia) се свалят до текст и се връщат СЛЕД
превода с `свържи()` от lives_plus/scripts/05_bible_links.py.
"""
import html
import json
import re
import zipfile
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
ВХОД = КОРЕН / 'input'
РАБОТА = КОРЕН / 'work'

ИЗТОЧНИК_ЮСТИН = ('https://azbyka.ru/otechnik/Iustin_Popovich/'
                  'chto-takoe-svjatost-i-zachem-pravoslavnomu-khristianinu-'
                  'chitat-zhitija-svjatykh/')
ИЗТОЧНИК_ЗЛАТОУСТ = 'https://azbyka.ru/otechnik/Ioann_Zlatoust/svyatii/'

# ⚠ Четивата на Златоуст: файлове от книгата и част („Часть N") в azbyka.ru
# — там всяко слово или група слова за един светия е на своя страница, и
# потребителят поиска връзката да води към КОНКРЕТНОТО слово. Съпоставено
# по заглавията на страниците 1…21.
# ⚠ Словото за мц. Дросида (файл 012, част 6) НЕ е тук: потребителят го е
# превел сам — `tools/slova_bg/`.
ЗЛАТОУСТ = [
    ('zl-01', ['002'], 1),
    ('zl-02', ['004'], 2),
    ('zl-03', ['005'], 2),
    ('zl-04', ['006', '007'], 2),     # третата беседа + „Еще о маккавеях"
    ('zl-05', ['008'], 3),
    ('zl-06', ['009'], 4),
    ('zl-07', ['010', '011'], 5),     # заглавието на групата + текстът
    ('zl-08', ['013'], 7),
    ('zl-09', ['014'], 8),
    ('zl-10', ['015'], 9),
    ('zl-11', ['016'], 10),
    ('zl-12', ['017'], 11),
    ('zl-13', ['018'], 12),
    ('zl-14', ['019', '020'], 13),    # група „о Пелагии" + беседа първа
    ('zl-15', ['021'], 13),
    ('zl-16', ['022', '023'], 14),    # група „о Романе" + слово първо
    ('zl-17', ['024'], 14),
    ('zl-18', ['025'], 15),
    ('zl-19', ['026'], 16),
    ('zl-20', ['027'], 17),
    ('zl-21', ['028'], 18),
    ('zl-22', ['029', '030'], 19),    # „всем святым" + „Способы приготовления"
    ('zl-23', ['031'], 20),
    ('zl-24', ['032', '033'], 21),    # група „в память Васса" + беседата
]

СУПЕР = str.maketrans('0123456789', '⁰¹²³⁴⁵⁶⁷⁸⁹')
RE_NOTE = re.compile(
    r'<a [^>]*href="[^"]*#(?:foot)?note\d+"[^>]*title="([^"]*)"[^>]*>.*?</a>',
    re.S)
RE_BLOCK = re.compile(
    r'<(h[1-6]|div|p)\b([^>]*)>(.*?)</\1>', re.S)


def чист(s: str) -> str:
    return ' '.join(html.unescape(re.sub(r'<[^>]+>', ' ', s)).split()).strip()


def без_номер(t: str) -> str:
    """Заглавие без маркера на бележката („…Лукиане*1", „…Романе9.")."""
    t = re.sub(r'\*\d+', '', t)
    t = re.sub(r'(?<=[^\d\s])\d+\.?$', '', t)
    return t.strip(' .') + ('.' if t.strip().endswith('.') and False else '')


def разчети(html_s: str, бележки: list, заглавие_бел: list, първи: bool):
    """Файлът → [(вид, текст)]. Бележките се трупат в списъците отвън."""
    out = []
    тяло = html_s.split('<body', 1)[-1]
    for m in RE_BLOCK.finditer(тяло):
        таг, атр, съдържание = m.group(1), m.group(2), m.group(3)
        if таг == 'div' and 'paragraph' not in атр:
            continue
        заглавен = таг.startswith('h')

        def бележка(mm):
            текст = html.unescape(mm.group(1)).strip()
            if not текст:
                return ''
            if заглавен:
                заглавие_бел.append(текст)
                return ''
            бележки.append(текст)
            return str(len(бележки)).translate(СУПЕР)

        t = RE_NOTE.sub(бележка, съдържание)
        t = чист(t)
        if not t:
            continue
        if заглавен:
            t = без_номер(t)
            out.append(('title' if (първи and not out) else 'h', t))
        else:
            out.append(('p', t))
    return out


def юстин(z) -> dict:
    s = z.read('index_split_001.xhtml').decode('utf-8', 'replace')
    бел, заг_бел = [], []
    блокове = разчети(s, бел, заг_бел, True)
    # Заглавието в книгата е „Преподобный Иустин (Попович) <br> Что такое…";
    # за четивото стига самото заглавие, авторът е в `author`.
    вид, заг = блокове[0]
    заг = re.sub(r'^Преподобный Иустин \(Попович\)\s*', '', заг)
    блокове[0] = ('title', заг)
    return сглоби('justin-01', 1, None, блокове, бел, заг_бел,
                  ИЗТОЧНИК_ЮСТИН, 'Прп. Юстин (Попович) Челийски')


def сглоби(id_, ред, част, блокове, бел, заг_бел, източник, автор) -> dict:
    kinds, texts = [], []
    for вид, t in блокове:
        kinds.append(вид)
        texts.append(t)
        if вид == 'title':
            for b in заг_бел:
                kinds.append('titlenote')
                texts.append(b)
    for i, b in enumerate(бел, 1):
        kinds.append('note')
        texts.append(f'{i}. {b}')
    return {
        'id': id_, 'order': ред, 'part': част, 'author': автор,
        'title_ru': texts[kinds.index('title')], 'source': източник,
        'kinds': kinds, 'blocks_ru': texts,
        'chars': sum(len(t) for t in texts),
    }


def златоуст(z) -> list[dict]:
    out = []
    for ред, (id_, файлове, част) in enumerate(ЗЛАТОУСТ, 1):
        бел, заг_бел, блокове = [], [], []
        for k, f in enumerate(файлове):
            s = z.read(f'index_split_{f}.xhtml').decode('utf-8', 'replace')
            блокове += разчети(s, бел, заг_бел, k == 0)
        out.append(сглоби(id_, ред, част, блокове, бел, заг_бел,
                          f'{ИЗТОЧНИК_ЗЛАТОУСТ}{част}', 'Свт. Йоан Златоуст'))
    return out


# ⚠⚠ ДЪЛГИТЕ ЧЕТИВА СЕ ДЕЛЯТ ЗА ПРЕВОДА. Преводачът върви успоредно по
# ДЯЛОВЕ, а парчетата вътре в един дял — едно след друго (второто получава
# заглавието за контекст). Словото за Вавила (113 000 знака) иначе държи
# целия превод часове сам. Частите се сливат обратно при сглобяването, по
# реда на номера си; делението е по граница на абзац.
ДЯЛ_МАКС = 16000


def раздели(u: dict) -> list[dict]:
    if u['chars'] <= ДЯЛ_МАКС:
        return [u]
    части, от, събрано = [], 0, 0
    for i, t in enumerate(u['blocks_ru']):
        събрано += len(t)
        if събрано >= ДЯЛ_МАКС and i + 1 < len(u['blocks_ru']):
            части.append((от, i + 1))
            от, събрано = i + 1, 0
    части.append((от, len(u['blocks_ru'])))
    return [{**u, 'id': f'{u["id"]}-{k:02d}', 'parent': u['id'],
             'kinds': u['kinds'][a:b], 'blocks_ru': u['blocks_ru'][a:b],
             'chars': sum(len(t) for t in u['blocks_ru'][a:b])}
            for k, (a, b) in enumerate(части, 1)]


def main() -> int:
    (РАБОТА / 'units').mkdir(parents=True, exist_ok=True)
    книги = {f.name: f for f in ВХОД.glob('*.epub')}
    ю = next(v for k, v in книги.items() if 'Иустин' in k)
    з = next(v for k, v in книги.items() if 'Златоуст' in k)
    units = [юстин(zipfile.ZipFile(ю))] + златоуст(zipfile.ZipFile(з))
    # ⚠ Пълните четива (с реда, частта и източника) — за сглобяването.
    (РАБОТА / 'readings.json').write_text(
        json.dumps(units, ensure_ascii=False, indent=1), encoding='utf-8')
    for u in units:
        # ⚠ Пазач: всяко четиво има заглавие и поне един абзац.
        assert u['kinds'].count('title') == 1, u['id']
        assert 'p' in u['kinds'], u['id']
        for част in раздели(u):
            (РАБОТА / 'units' / f'{част["id"]}.json').write_text(
                json.dumps(част, ensure_ascii=False, indent=1), encoding='utf-8')
        print(f'{u["id"]:10} {u["chars"]:7}  бел. {u["kinds"].count("note"):2}'
              f'+{u["kinds"].count("titlenote")}  {u["title_ru"][:70]}')
    print(f'общо: {len(units)} четива, {sum(u["chars"] for u in units):,} знака')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
