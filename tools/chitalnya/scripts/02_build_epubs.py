#!/usr/bin/env python3
"""„Читалня" — четирите книги като .epub → assets/chitalnya/*.epub

    python3 01_titles.py        # заглавията (кеш, превежда само новото)
    python3 02_build_epubs.py   # → assets/chitalnya/
    python3 03_covers.py        # → assets/chitalnya_covers/

⚠⚠ ТЕКСТОВЕТЕ НЕ СЕ ПРЕВЕЖДАТ ТУК — взимат се готови от базите, от които
ги показват дневният изглед и словата. Книгата е само друга подредба на
същото: цялото четиво, в реда на оригинала.

⚠ ФОРМАТЪТ Е .epub, за да ги чете СЪЩИЯТ четец като „Месецослов"
(book_reader.dart) — със съдържание, търсене, отметки, цитати и PDF, без нов
код. По същия път ще минават и книгите за сваляне.

Подредбата — както в оригинала (указание на потребителя):
  • Дебольски — по дялове („Постни дни", „Страстна седмица"…), в реда на книгата;
  • Златоуст — 24-те беседи в реда на книгата;
  • Теофан — плосък списък в реда на книгата (от Нова година);
  • Оптинските старци — ВСИЧКИ 796 сентенции, по темите на „Симфонията".
"""
import html
import json
import re
import sqlite3
import uuid
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJ = ROOT.parents[1]
DB = PROJ / 'assets' / 'db'
OUT = PROJ / 'assets' / 'chitalnya'
COVERS = PROJ / 'assets' / 'chitalnya_covers'
TITLES = json.loads((ROOT / 'work' / 'titles.json').read_text(encoding='utf-8'))

E = lambda s: html.escape(s, quote=False)


def xhtml(title, body):
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
            '<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>'
            f'<title>{E(title)}</title></head><body>{body}</body></html>')


def source_line(url, label='azbyka.ru'):
    # Същият вид като предговора на прп. Юстин в томовете: `data-role`
    # го прави `<p class="source">` в _normalize (book_reader.dart).
    return (f'<div class="paragraph" data-role="source">Източник: '
            f'<a href="{E(url)}">{E(label)}</a></div>')


class Book:
    """Един .epub: глави (с вложени точки в съдържанието) и бележки."""

    def __init__(self, code, title, author, collapsible=False):
        self.code, self.title, self.author = code, title, author
        # Съдържанието със сгънати групи — виж EpubBook.collapsibleToc.
        self.collapsible = collapsible
        self.files = []      # (име, xhtml)
        self.extras = {}     # 'Images/x.webp' → байтове (орнаменти)
        self.toc = []        # [(заглавие, файл, [деца])]

    def add(self, name, title, body):
        self.files.append((name, xhtml(title, body)))
        return name

    def write(self):
        OUT.mkdir(parents=True, exist_ok=True)
        cover = COVERS / f'{self.code}.jpg'
        path = OUT / f'{self.code}.epub'
        uid = str(uuid.uuid5(uuid.NAMESPACE_URL, 'chitalnya/' + self.code))
        manifest = ''.join(
            f'<item id="f{i}" href="Text/{n}" media-type="application/xhtml+xml"/>'
            for i, (n, _) in enumerate(self.files))
        manifest += ''.join(
            f'<item id="x{i}" href="{n}" media-type="image/webp"/>'
            for i, n in enumerate(self.extras))
        if cover.exists():
            manifest += '<item id="cover" href="Images/cover.jpg" media-type="image/jpeg"/>'
        spine = ''.join(f'<itemref idref="f{i}"/>' for i in range(len(self.files)))
        opf = ('<?xml version="1.0" encoding="utf-8"?>'
               '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">'
               '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
               f'<dc:title>{E(self.title)}</dc:title><dc:creator>{E(self.author)}</dc:creator>'
               f'<dc:language>bg</dc:language><dc:identifier id="uid">{uid}</dc:identifier>'
               + ('<meta name="cover" content="cover"/>' if cover.exists() else '')
               + ('<meta name="toc-collapsible" content="true"/>' if self.collapsible else '') +
               f'</metadata><manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
               f'{manifest}</manifest><spine toc="ncx">{spine}</spine></package>')
        order = [0]

        def nav(entries):
            out = []
            for title, f, kids in entries:
                order[0] += 1
                out.append(f'<navPoint id="n{order[0]}" playOrder="{order[0]}">'
                           f'<navLabel><text>{E(title)}</text></navLabel>'
                           f'<content src="Text/{f}"/>{nav(kids)}</navPoint>')
            return ''.join(out)

        ncx = ('<?xml version="1.0" encoding="utf-8"?>'
               '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
               f'<head><meta name="dtb:uid" content="{uid}"/></head>'
               f'<docTitle><text>{E(self.title)}</text></docTitle>'
               f'<navMap>{nav(self.toc)}</navMap></ncx>')
        with zipfile.ZipFile(path, 'w') as z:
            z.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
            z.writestr('META-INF/container.xml',
                       '<?xml version="1.0"?><container version="1.0" '
                       'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                       '<rootfiles><rootfile full-path="OEBPS/content.opf" '
                       'media-type="application/oebps-package+xml"/></rootfiles></container>',
                       compress_type=zipfile.ZIP_DEFLATED)
            z.writestr('OEBPS/content.opf', opf, compress_type=zipfile.ZIP_DEFLATED)
            z.writestr('OEBPS/toc.ncx', ncx, compress_type=zipfile.ZIP_DEFLATED)
            for n, x in self.files:
                z.writestr(f'OEBPS/Text/{n}', x, compress_type=zipfile.ZIP_DEFLATED)
            if cover.exists():
                z.write(cover, 'OEBPS/Images/cover.jpg', compress_type=zipfile.ZIP_STORED)
            for name, data in self.extras.items():
                z.writestr(f'OEBPS/{name}', data, compress_type=zipfile.ZIP_STORED)
        n = len(self.files) - 1
        print(f'  {path.name}: {n} глави, {path.stat().st_size // 1024} KB')

    def titlepage(self, subtitle):
        img = ('<p class="centernote"><img src="../Images/cover.jpg" alt=""/></p>'
               if (COVERS / f'{self.code}.jpg').exists() else '')
        body = (f'{img}<h1>{E(self.title)}</h1>'
                f'<p class="centernote">{E(self.author)}</p>'
                + (f'<p class="centernote">{E(subtitle)}</p>' if subtitle else ''))
        self.toc.append((self.title, self.add('title.xhtml', self.title, body), []))


def tr(ru):
    t = re.sub(r'\*\d+', '', ru or '').strip()
    return TITLES.get(t, t)


def debolsky():
    # ⚠ Не „…на Православната Католическа Източна Църква" (буквално по
    # оригинала) — „католическа" смущава българския читател (потребителят).
    b = Book('debolsky', 'Дни на богослужението в Православната Църква',
             'Прот. Григорий Дебольски')
    b.titlepage('Пояснения за дните на богослужението през годината')
    con = sqlite3.connect(DB / 'lives_plus.db')
    part, kids = None, None
    for id_, part_bg, title, body, src in con.execute(
            'SELECT id, part_bg, title_bg, body, source FROM dni ORDER BY ord'):
        # Само ПЪРВОТО <h3> (заглавието на главата) става <h1>; вътрешните
        # подзаглавия си остават <h3>.
        body = re.sub(r'^\s*<h3>(.*?)</h3>', r'<h1>\1</h1>', body, count=1, flags=re.S)
        if not body.lstrip().startswith('<h1>'):
            body = f'<h1>{E(title)}</h1>' + body
        f = b.add(f'{id_}.xhtml', title, body + (source_line(src) if src else ''))
        if part_bg != part:
            part, kids = part_bg, []
            b.toc.append((part_bg, f, kids))
        kids.append((title, f, []))
    b.write()


def zlatoust():
    b = Book('zlatoust', 'Похвални слова за светиите', 'Свт. Йоан Златоуст')
    b.titlepage('Беседи за мъченици, светители и праведници')
    con = sqlite3.connect(DB / 'lives_plus.db')
    # ⚠ И словото за вмц. Дросида (`zlat`) — преведено отделно от автора на
    # приложението (tools/slova_bg/), затова е друга „книга" в базата. В
    # оригинала то е № 6 (azbyka.ru/…/svyatii/6) и застава там — подредбата
    # е по номера на страницата в azbyka, после по id.
    rows = con.execute("SELECT id, title_bg, body, source FROM slova "
                       "WHERE book IN ('zl-svyatii', 'zlat')").fetchall()

    def num(r):
        m = re.search(r'svyatii/(\d+)', r[3] or '')
        return int(m.group(1)) if m else 999

    rows.sort(key=lambda r: (num(r), r[0]))
    notes = []
    for id_, title, body, src in rows:
        # Бележките на словата идват като `note://N` с текста в `title` —
        # четецът на книги ги иска като отделни файлове (както Теофан).
        def note(m):
            notes.append(html.unescape(m.group(1)))
            n = len(notes)
            return f'<a href="note{n}.xhtml#note{n}">'

        body = re.sub(r'<a href="note://[^"]*" title="([^"]*)">', note, body)
        body = re.sub(r'^<h3>', '<h1>', body)
        body = re.sub(r'^(<h1>.*?)</h3>', r'\1</h1>', body, flags=re.S)
        if not body.startswith('<h1>'):
            body = f'<h1>{E(title)}</h1>' + body
        f = b.add(f'{id_}.xhtml', title, body + (source_line(src) if src else ''))
        b.toc.append((title, f, []))
    for n, t in enumerate(notes, 1):
        b.files.append((f'note{n}.xhtml',
                        xhtml(str(n), f'<h1 id="note{n}">{n}</h1><p>{E(t)}</p>')))
    b.write()


RE_WEEKDAY = re.compile(r'^(Понеделник|Вторник|Сряда|Четвъртък|Петък|Събота)\b')


def teofan():
    b = Book('teofan', 'Мисли за всеки ден от годината', 'Свт. Теофан Затворник',
             collapsible=True)
    b.titlepage('По църковните четива от Словото Божие')
    con = sqlite3.connect(DB / 'teofan.db')
    notes = dict(con.execute('SELECT key, body FROM notes'))
    used = {}
    for id_, title_ru, body in con.execute(
            'SELECT id, src_title_ru, body FROM thoughts ORDER BY id'):
        title = tr(title_ru)

        def note(m):
            k = m.group(1)
            n = used.setdefault(k, len(used) + 1)
            return f'<a href="note{n}.xhtml#note{n}"><sup>{E(k)}</sup></a>'

        body = re.sub(r'<a href="teofan-note://([^"]+)">\s*<sup[^>]*>[^<]*</sup>\s*</a>',
                      note, body)
        f = b.add(f't{id_:03d}.xhtml', title, f'<h1>{E(title)}</h1>{body}')
        # ⚠ Делниците отиват ПОД предходната неделя или празник — иначе
        # съдържанието е безкрайна редица „Вторник, Сряда, Четвъртък…"
        # (потребителят). Групите се показват сгънати (`toc-collapsible`).
        if RE_WEEKDAY.match(title) and len(b.toc) > 1:
            b.toc[-1][2].append((title, f, []))
        else:
            b.toc.append((title, f, []))
    # Бележките — отделни файлове, извън съдържанието (както в томовете).
    for k, n in used.items():
        b.files.append((f'note{n}.xhtml', xhtml(k, f'<h1 id="note{n}">{E(k)}</h1>'
                                                 f'<p>{notes.get(k, "")}</p>')))
    b.write()


def divider_webp():
    """Разделителят между сентенциите — в стила на кориците: две тънки
    черти, които изтъняват към краищата, и ромбче в средата. Прозрачен фон,
    тъмно злато; в тъмна тема четецът го оцветява (`data-tint`)."""
    import io
    from PIL import Image, ImageDraw
    SS, W, H = 4, 640, 56
    im = Image.new('RGBA', (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    col = (122, 100, 64)
    cy, cx = H * SS // 2, W * SS // 2
    gap, half = 34 * SS, 286 * SS
    for side in (-1, 1):
        # Черта, която изтънява навън: поредица отсечки с намаляваща дебелина.
        steps = 60
        for k in range(steps):
            a = gap + (half - gap) * k / steps
            b = gap + (half - gap) * (k + 1) / steps
            wdt = max(1, round(4.5 * SS * (1 - k / steps) + 1.3 * SS))
            d.line([(cx + side * a, cy), (cx + side * b, cy)], fill=col + (255,), width=wdt)
        # точица на края
        ex = cx + side * (half + 8 * SS)
        d.ellipse([ex - 4 * SS, cy - 4 * SS, ex + 4 * SS, cy + 4 * SS], fill=col + (255,))
    r = 14 * SS
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=col + (255,))
    r2 = 6 * SS
    d.polygon([(cx, cy - r2), (cx + r2, cy), (cx, cy + r2), (cx - r2, cy)], fill=(0, 0, 0, 0))
    im = im.resize((W, H), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, 'WEBP', lossless=True)
    return buf.getvalue()


DIVIDER = ('<p class="saydivider"><img src="../Images/divider.webp" data-w="0.62" '
           'data-tint="1" alt=""/></p>')


def optina():
    b = Book('optina', 'Изречения от Оптинските старци', 'Прпп. Оптински старци')
    b.titlepage('По темите на „Симфония по творенията на преподобните Оптински старци"')
    con = sqlite3.connect(DB / 'optina.db')
    rows = con.execute('SELECT src_id, src_topic_ru, body FROM sayings').fetchall()
    rows.sort(key=lambda r: r[0])           # v1-002-01 — том, тема, номер
    topics = []
    for src_id, topic_ru, body in rows:
        if not topics or topics[-1][0] != topic_ru:
            topics.append((topic_ru, []))
        topics[-1][1].append(body)
    b.extras['Images/divider.webp'] = divider_webp()
    for i, (topic_ru, bodies) in enumerate(topics, 1):
        title = tr(topic_ru)
        # Подписът на стареца — `saysource` (вдясно, плътно под текста), а
        # между сентенциите — орнамент; иначе името се четеше и към
        # следващата мисъл (указание на потребителя).
        parts = [x.replace('<p class="source">', '<p class="saysource">') for x in bodies]
        f = b.add(f'o{i:03d}.xhtml', title,
                  f'<h1>{E(title)}</h1>' + DIVIDER.join(parts))
        b.toc.append((title, f, []))
    b.write()


if __name__ == '__main__':
    debolsky()
    zlatoust()
    teofan()
    optina()
