#!/usr/bin/env python3
"""Разчита .odt на СОБСТВЕН превод в готово HTML за четеца.

    python3 01_parse_odt.py                 # всички папки в input/
    python3 01_parse_odt.py --slug sv-…     # само една

Изход: work/<слъг>.json  →  подава се на 02_apply.py

⚠⚠ ИСТИНСКО РАЗЧИТАНЕ НА XML, не регекс. Телата на бележките под линия са
ВЛОЖЕНИ `<text:p>` вътре в абзаца; прост израз „от <text:p> до </text:p>"
реже блока на грешно място и лепи текста на бележката в самия разказ.
Първият ми опит направи точно това.

⚠ Курсивът е СТИЛ, не таг. ODF го държи в `<style:style style:family="text">`
и го прилага през `<text:span text:style-name="T3">`; кои имена значат
курсив се чете от самия документ, не се гадае по номер.
"""
import argparse, json, os, re, sys, zipfile
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INPUT = os.path.join(ROOT, 'input')
WORK = os.path.join(ROOT, 'work')
# Библейската база — от нея идват съкращенията на книгите.
ROOT_БАЗА = Path(os.path.dirname(os.path.dirname(ROOT))) / 'assets' / 'db' / 'bible.db'

NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}
T = '{%s}' % NS['text']
S = '{%s}' % NS['style']
FO = '{%s}' % NS['fo']

# Редът, с който свършва документът — адресът на оригинала. Той НЕ влиза в
# тялото: четецът го изписва сам накрая през `_sourceHtml()`.
RE_SOURCE = re.compile(r'^\s*Източник:\s*(\S+)', re.I)
# Орнаментът между текста и реда с източника — няма какво да дели, щом
# редът се изнася в своя колона.
RE_ORNAMENT = re.compile(r'^[\s❈✻✽*·—–-]+$')

# ⚠⚠ БИБЛЕЙСКИТЕ ПРЕПРАТКИ СТАВАТ ВРЪЗКИ, които се отварят ВЪТРЕ в
# приложението, успоредно на български и църковнославянски (`bg~utfcs`) —
# утвърденото за целия проект.
#
# ⚠ Съкращенията се вземат от САМАТА библейска база (`books.bg_abbr`), не се
# изброяват тук. Изключенията са само там, където словото пише различно от
# базата — тях ги няма как да се изведат и стоят изрично.
РАЗЛИЧНИ = {'лк': 'Lk', 'прит': 'Prov', 'евр': 'Hebr', 'иак': 'Jac',
            'мт': 'Mt', 'мк': 'Mk', 'ин': 'Jn', 'деян': 'Act'}
RE_РЕФ = re.compile(
    r'\((\d?\s?[А-Яа-я][А-Яа-я]{1,10})\.\s*(\d+)[:,]\s*(\d+(?:[\-–]\d+)?'
    r'(?:\s*,\s*\d+(?:[\-–]\d+)?)*)\)')


def _съкращения():
    """съкращение (свито) → код на книгата, от самата база."""
    import sqlite3
    п = ROOT_БАЗА
    карта = dict(РАЗЛИЧНИ)
    if п.exists():
        c = sqlite3.connect(п)
        for код, съкр in c.execute(
                "SELECT code, bg_abbr FROM books WHERE bg_abbr IS NOT NULL"):
            карта.setdefault(re.sub(r'[\s.]', '', съкр).lower(), код)
        c.close()
    return карта


_СЪКР = None


def библейски_връзки(s: str) -> str:
    global _СЪКР
    if _СЪКР is None:
        _СЪКР = _съкращения()

    def _вр(m):
        съкр = re.sub(r'\s', '', m.group(1)).lower()
        код = _СЪКР.get(съкр)
        if not код:
            return m.group(0)
        стихове = re.sub(r'\s*', '', m.group(3)).replace('–', '-')
        адрес = ('https://azbyka.ru/biblia/?%s.%s:%s&amp;bg~utfcs'
                 % (код, m.group(2), стихове))
        # ⚠ Точката след съкращението се пази — „Сир. 7:39", не „Сир 7:39".
        return '(<a href="%s">%s. %s:%s</a>)' % (
            адрес, m.group(1).strip(), m.group(2), стихове)

    return RE_РЕФ.sub(_вр, s)


def italic_styles(root):
    """Имената на знаковите стилове, които РЕАЛНО значат курсив."""
    out = set()
    for st in root.iter(S + 'style'):
        if st.get(S + 'family') != 'text':
            continue
        for props in st.iter(S + 'text-properties'):
            if props.get(FO + 'font-style') == 'italic':
                out.add(st.get(S + 'name'))
    return out


def esc(s):
    return (s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;'))


def inline(node, ital, notes, in_italic=False):
    """Съдържанието на един абзац → HTML. Връща (html, гол_текст)."""
    html, plain = [], []

    def text(s):
        if s:
            html.append(esc(s))
            plain.append(s)

    text(node.text)
    for ch in node:
        tag = ch.tag
        if tag == T + 'span':
            it = in_italic or ch.get(T + 'style-name') in ital
            h, p = inline(ch, ital, notes, it)
            # ⚠ Курсивът се затваря на ниво SPAN, не на ниво знак — инак
            # вложените спанове раждат <em><em>…
            if it and not in_italic and p.strip():
                html.append('<em>%s</em>' % h)
            else:
                html.append(h)
            plain.append(p)
        elif tag == T + 'note':
            n = ch.find(T + 'note-citation')
            body = ch.find(T + 'note-body')
            num = (n.text or '').strip() if n is not None else str(len(notes) + 1)
            txt = ' '.join(''.join(p.itertext()).strip()
                           for p in (body.iter(T + 'p') if body is not None else []))
            notes.append((num, txt.strip()))
            # ⚠ Горният индекс се рисува от ReaderSupExtension — същият
            # механизъм като номерата на бележки в томовете.
            # ⚠ Номерът е ВРЪЗКА („note://1"), не гол горен индекс: четецът
            # я поема и показва бележката в изскачащ панел отдолу — както в
            # четеца на книги. Гол `<sup>` се вижда, но не прави нищо.
            #
            # ⚠⚠ И `title` С ТЕКСТА НА БЕЛЕЖКАТА — заради PDF-а. Там панел
            # няма: бележките се ПЕЧАТАТ накрая, а текстът им се чете именно
            # от този атрибут. Без него номерът в PDF-а сочеше котва, която
            # не съществува, и самата бележка липсваше изцяло.
            # ⚠ Четецът го подминава — той взима текста от базата.
            html.append('<sup><a href="note://%s" title="%s">%s</a></sup>'
                        % (esc(num), esc(txt.replace('"', '”')), esc(num)))
        elif tag == T + 's':
            text(' ' * int(ch.get(T + 'c', 1)))
        elif tag == T + 'tab':
            text(' ')
        elif tag == T + 'line-break':
            html.append('<br/>')
        elif tag == T + 'a':
            h, p = inline(ch, ital, notes, in_italic)
            href = ch.get('{http://www.w3.org/1999/xlink}href', '')
            html.append('<a href="%s">%s</a>' % (esc(href), h) if href else h)
            plain.append(p)
        else:
            h, p = inline(ch, ital, notes, in_italic)
            html.append(h)
            plain.append(p)
        text(ch.tail)
    return ''.join(html), ''.join(plain)


def parse(path):
    with zipfile.ZipFile(path) as z:
        root = ET.fromstring(z.read('content.xml'))
    ital = italic_styles(root)
    body = root.find('office:body/office:text', NS)

    blocks = []          # (вид, html, гол текст)
    notes = []

    # ⚠ Абзаците НЕ са преки деца на <office:text> — този документ ги държи
    # във <text:section>. Оттам обхождането е рекурсивно.
    #
    # ⚠⚠ И НЕ ВЛИЗА В <text:note>: тялото на бележката е също <text:p> и,
    # взето за самостоятелен абзац, се явява втори път насред разказа.
    def walk(el):
        for ch in el:
            if ch.tag == T + 'note':
                continue
            if ch.tag in (T + 'p', T + 'h'):
                html, plain = inline(ch, ital, notes)
                blocks.append(
                    ('h' if ch.tag == T + 'h' else 'p', html, plain.strip()))
            else:
                walk(ch)

    walk(body)

    title, source, out = None, '', []
    for i, (kind, html, plain) in enumerate(blocks):
        if not plain:
            continue
        m = RE_SOURCE.match(plain)
        if m:
            source = m.group(1)
            continue
        if RE_ORNAMENT.match(plain):
            continue
        if title is None and kind == 'h':
            # ⚠ Заглавието НЕ влиза в тялото — четецът го изписва сам от
            # `title_bg`. Бележката, закачена за него, обаче остава.
            # ⚠ `title_bg` е ГОЛ ТЕКСТ — четецът го подава като `lifeTitle`.
            # Пренасянето на ред от документа („…Дросида,⏎и относно…") тук е
            # оформление и става интервал; оставено, `<br/>` се изписва
            # буквално в лентата.
            # ⚠ ТЪРПЕЛИВ към други атрибути: тагът вече носи и `title`
            # (заради PDF-а), а закованото „\">" спираше да съвпада —
            # показалецът към заглавието изчезваше мълчаливо.
            m_note = re.search(r'<sup><a [^>]*href="note://([^"]+)"', html)
            if m_note:
                out.append(('titlenote', m_note.group(1)))
            title = re.sub(r'<sup>.*?</sup>', '', html)
            title = re.sub(r'<br\s*/?>', ' ', title)
            title = re.sub(r'<[^>]+>', '', title)
            title = re.sub(r'\s+', ' ', title).strip()
            # ⚠ Бележката, закачена за ЗАГЛАВИЕТО, няма къде да си остави
            # номера: заглавието не минава през HTML. Самата бележка обаче
            # се изписва накрая заедно с останалите — губи се само
            # показалецът, не текстът.
            continue
        out.append(('body', html))
    return title, source, out, notes


def build_html(blocks, notes):
    """⚠ Класовете идват от reader_styles.dart — не измисляй нови."""
    parts = []
    body_seen = 0
    # ⚠ Бележката, закачена за ЗАГЛАВИЕТО, няма къде да си остави номера:
    # заглавието не минава през HTML (`title_bg` е гол текст). Затова
    # показалецът ѝ се долепя за приписката ПОД заглавието — тя стои точно
    # там, където би стоял номерът, и обяснява обстоятелствата на цялото
    # слово. Без това бележката съществуваше, но нищо не водеше до нея.
    бележка_на_заглавието = next(
        (h for k, h in blocks if k == 'titlenote'), None)
    for kind, html in blocks:
        if kind == 'titlenote':
            continue
        body_seen += 1
        if body_seen == 1:
            # „(св. Йоан Златоуст. Похвални слова за светиите)" — приписка
            # под заглавието, не начало на разказа.
            _txt = next((t for n, t in notes
                         if str(n) == str(бележка_на_заглавието)), '')
            показалец = ('<sup><a href="note://%s" title="%s">%s</a></sup>'
                         % (esc(бележка_на_заглавието),
                            esc(_txt.replace('"', '”')),
                            esc(бележка_на_заглавието))
                         if бележка_на_заглавието else '')
            parts.append('<p class="centernote">%s%s</p>' % (html, показалец))
        elif body_seen == 2:
            # Синопсисът — за какво се говори в словото.
            #
            # ⚠ Уводният ред стои ОТДЕЛНО, над него: той е наше обръщение
            # към читателя, не част от самото резюме.
            #
            # ⚠ Целият синопсис е в КУРСИВ — `epigraph` е приглушен и с
            # отстъп, но не наклонен; курсивът идва от `<em>`.
            # ⚠ Уводният ред е ЧАСТ ОТ СЪЩИЯ абзац, не подзаглавие над
            # него: „…ще намерите: Посещение на крайградския храм…".
            # Отделен, той се четеше като заглавие на раздел.
            parts.append('<p class="intro">%s %s</p>'
                         % ('В това Боговдъхновено слово ще намерите:', html))
        else:
            # ⚠⚠ ПЪРВИЯТ РАЗКАЗВАТЕЛЕН АБЗАЦ ОСТАВА БЕЗ НОМЕРА НА ДЯЛА.
            # Словото е разделено на дялове („1.", „2." …) и номерът стои
            # долепен за първата дума. На този абзац обаче пада БУКВИЦАТА —
            # тъй че инициалът би излязъл ЦИФРАТА „1", а не първата буква
            # на разказа. Останалите номера си остават по местата.
            # (Забелязано от потребителя, 18.09.2026.)
            if body_seen == 3:
                html = re.sub(r'^\s*\d+\.\s*', '', html)
            # ⚠⚠ ГОЛ <p>, БЕЗ class="paragraph" — инак НЯМА БУКВИЦА.
            # `splitDropCap` (drop_cap.dart) търси буквално `<p>…</p>`, тъй
            # че всеки клас я отменя. Мерено: стоте слова по свт. Димитрий
            # Ростовски са `class="paragraph"` и затова нито едно от тях не
            # получава инициал. Класът няма собствен стил в
            # reader_styles.dart — рисува се по тага, — тъй че голият <p>
            # изглежда точно същото и само връща буквицата.
            parts.append('<p>%s</p>' % библейски_връзки(html))
    # ⚠ Бележките НЕ се изписват вече най-долу: те живеят в своя таблица и
    # изскачат при тап върху номера. Оставени долу, същият текст стоеше два
    # пъти.
    _ = notes
    html = '\n'.join(parts)
    # ⚠ ODF реже курсива на няколко спана, щом вътре смени нещо незначещо
    # (езикова маркировка например), тъй че един цитат излиза като
    # <em>„</em><em>Н</em><em>е знаете ли…</em>. Изглежда еднакво, но
    # насича текста без нужда — слепва се.
    while '</em><em>' in html:
        html = html.replace('</em><em>', '')
    return html


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--slug')
    a = ap.parse_args()
    os.makedirs(WORK, exist_ok=True)
    slugs = [a.slug] if a.slug else sorted(
        d for d in os.listdir(INPUT) if os.path.isdir(os.path.join(INPUT, d)))
    for slug in slugs:
        d = os.path.join(INPUT, slug)
        odt = [f for f in sorted(os.listdir(d)) if f.lower().endswith('.odt')]
        if not odt:
            print('⚠ %s: няма .odt — пропускам' % slug); continue
        title, source, blocks, notes = parse(os.path.join(d, odt[0]))
        html = build_html(blocks, notes)
        rec = {
            'slug': slug, 'title_bg': title, 'source': source,
            'body': html, 'chars': len(re.sub(r'<[^>]+>', '', html)),
            'notes': [{'n': n, 'text': t} for n, t in notes],
            'file': odt[0],
        }
        with open(os.path.join(WORK, slug + '.json'), 'w', encoding='utf-8') as f:
            json.dump(rec, f, ensure_ascii=False, indent=1)
        print('%s: „%s" — %d знака, %d бележки, източник %s'
              % (slug, title, rec['chars'], len(rec['notes']), source or '(няма)'))


if __name__ == '__main__':
    main()
