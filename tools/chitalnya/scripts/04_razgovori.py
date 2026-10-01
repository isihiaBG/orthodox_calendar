#!/usr/bin/env python3
"""„Разговори за Божествения промисъл…" (.docx на потребителя) → .epub за
„Читалня" → assets/chitalnya/razgovori.epub (+ корица).

    python3 04_razgovori.py

⚠ Изворът е .docx-ът в input/ (не в git). PDF-ът до него е ОБРАЗЕЦ за вида —
по него се сверява, че подредбата е като в оригинала.

Стиловете на книгата → класовете на четеца (reader_styles.dart):
    Heading2 (заглавие на беседа)   нова глава, <h1>
    subHeading („(разговор с …)")  <p class="centernote"> получер курсив
    „Цитат" (a)                     <p class="epigraph">
    „Цитат_ЦС" (a0), Hirmos Ucs     разчетен през ucs.decode, червен
    ListParagraph                   <p class="item">• …
    No Spacing (вътрешни заглавия)  <p class="grouphead">
    „Посвещение" (a1)               <p class="centernote">
    „Супер заглавие" (a2)           <h1> на заглавната страница
    QuoteChar/Emphasis/…            <i>
    бележки под линия               noteN.xhtml (изскачащ панел)
    картинки                        <img data-w="дял от реда"> — ширината
                                    от оригинала (виж BookImageExtension)
⚠ Плаващите картинки и текстовите кутии са ДВОЙНИ в .docx (mc:Choice и
mc:Fallback) — взима се само първият вариант.
"""
import html
import io
import re
import sys
import zipfile
from pathlib import Path

import xml.etree.ElementTree as ET

from PIL import Image, ImageFile

# ⚠ image21.png е с повредена контролна сума в цветовия профил (iCCP) —
# самата картинка е цяла; без това Pillow отказва да я отвори.
ImageFile.LOAD_TRUNCATED_IMAGES = True

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / 'Molitvoslov' / 'scripts'))
import ucs  # noqa: E402

ROOT = HERE.parent
PROJ = ROOT.parents[1]
SRC = next((ROOT / 'input').glob('*.docx'))
OUT = PROJ / 'assets' / 'chitalnya' / 'razgovori.epub'
COVER = PROJ / 'assets' / 'chitalnya_covers' / 'razgovori.jpg'
TEXT_W_CM = 16.5        # широчината на реда в оригинала (A4 с полета)

W_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS = {'w': W_NS, 'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
      'a': 'http://schemas.openxmlformats.org/drawingml/2006/main', 'r': R_NS}
w = lambda t: '{%s}%s' % (W_NS, t)
WPG = 'http://schemas.microsoft.com/office/word/2010/wordprocessingGroup'
PIC = 'http://schemas.openxmlformats.org/drawingml/2006/picture'

E = lambda s: html.escape(s, quote=False)


def xhtml(title, body):
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
            '<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>'
            f'<title>{E(title)}</title></head><body>{body}</body></html>')


class Doc:
    def __init__(self):
        self.z = zipfile.ZipFile(SRC)
        rels = self.z.read('word/_rels/document.xml.rels').decode()
        self.rels = dict(re.findall(r'Id="([^"]+)"[^>]*?Target="([^"]+)"', rels))
        fn = ET.fromstring(self.z.read('word/footnotes.xml'))
        self.fnotes = {}
        for f in fn.findall('w:footnote', NS):
            self.fnotes[f.get(w('id'))] = ' '.join(
                self.runs(p) for p in f.findall('w:p', NS)).strip()
        self.images = {}     # media/… → име в .epub
        self.ornaments = set()  # едноцветните — оцветяват се според темата
        self.notes = []      # (номер, html)
        self.note_of = {}

    # ── знакови части ──────────────────────────────────────────────
    def runs(self, p):
        """Текстът на абзаца (без картинките и кутиите) → html."""
        out = []
        st = p.find('w:pPr/w:pStyle', NS)
        # ⚠ В „Цитат_ЦС" (a0) шрифтът Ucs идва от СТИЛА НА АБЗАЦА, не от
        # самия текст — проверката само по текста го пропускаше и цитатът
        # излизаше неразчетен („Покаsніz tвeрзи…", докладвано).
        cs = st is not None and st.get(w('val')) == 'a0'
        for ch in p:
            if ch.tag == w('r'):
                out.append(self.run(ch, cs))
            elif ch.tag == w('hyperlink'):
                href = self.rels.get(ch.get('{%s}id' % R_NS), '')
                inner = ''.join(self.run(r, cs) for r in ch.findall('w:r', NS))
                out.append(f'<a href="{E(href)}">{inner}</a>' if href.startswith('http')
                           else inner)
            elif ch.tag in (w('ins'), w('smartTag'), w('fldSimple')):
                out.append(''.join(self.run(r, cs) for r in ch.iter(w('r'))))
        s = ''.join(out)
        # Съседни еднакви тагове се слепват („<i>а</i><i>б</i>" → „<i>аб</i>").
        for t in ('i', 'b', 'span class="rubric"', 'span class="cs"'):
            close = t.split()[0]
            s = s.replace(f'</{close}><{t}>', '')
        # Цс откъс: ВОДЕЩАТА буква червена, останалото мастилено (както в
        # богослужебните книги) — и в цели цитати, и вмъкнат в изречение.
        return re.sub(
            r'(<span class="cs">[„"«(\s]*)([^\W\d_][\u0300-\u036f\u0483-\u0489\u2de0-\u2dff\ua66f-\ua67f]*)',
            r'\1<span class="rubric">\2</span>', s)

    def run(self, r, para_cs=False):
        rpr = r.find('w:rPr', NS)
        def has(tag):
            e = rpr.find(f'w:{tag}', NS) if rpr is not None else None
            return e is not None and e.get(w('val'), 'true') not in ('0', 'false')
        fn = r.find('w:footnoteReference', NS)
        if fn is not None:
            return self.note(fn.get(w('id')))
        parts = []
        for ch in r:
            if ch.tag == w('t'):
                parts.append(ch.text or '')
            elif ch.tag == w('tab'):
                parts.append(' ')
            elif ch.tag == w('br') and ch.get(w('type')) != 'page':
                parts.append('\n')
        t = ''.join(parts)
        if not t:
            return ''
        font = rpr.find('w:rFonts', NS) if rpr is not None else None
        fname = (font.get(w('ascii')) or '') if font is not None else ''
        rst = rpr.find('w:rStyle', NS) if rpr is not None else None
        # Църковнославянско е: шрифт Ucs на текста, знаков стил „Цитат_ЦС"
        # (Char0), или абзац „Цитат_ЦС", без текстът да сменя шрифта на друг
        # (препратката „(Иов 40:14)" е с Cambria).
        rsv = rst.get(w('val')) if rst is not None else ''
        # ⚠ Знаковият стил QuoteChar носи СВОЙ шрифт (Cambria) — така е
        # набрана препратката „(Иов 40:14)" вътре в цс цитат.
        cs = 'Ucs' in fname or rsv == 'Char0' \
            or (para_cs and not fname and not has('i')
                and rsv not in ('QuoteChar', 'IntenseEmphasis', 'Emphasis', 'Hyperlink'))
        if cs:
            t = ucs.decode(t)
        t = E(t).replace('\n', '<br/>')
        if cs:
            t = f'<span class="cs">{t}</span>'
        ital = has('i') or (rst is not None and rst.get(w('val')) in
                            ('QuoteChar', 'IntenseEmphasis', 'Emphasis'))
        col = rpr.find('w:color', NS) if rpr is not None else None
        red = (col is not None and col.get(w('val')) in ('EE0000', 'FF0000', 'C00000')
               and not cs)
        if ital:
            t = f'<i>{t}</i>'
        if has('b'):
            t = f'<b>{t}</b>'
        if red:
            t = f'<span class="rubric">{t}</span>'
        return t

    def note(self, fid):
        if fid not in self.note_of:
            n = len(self.notes) + 1
            self.note_of[fid] = n
            self.notes.append((n, self.fnotes.get(fid, '')))
        n = self.note_of[fid]
        return f'<a href="note{n}.xhtml#note{n}"><sup>{n}</sup></a>'

    # ── картинки ───────────────────────────────────────────────────
    @staticmethod
    def is_ornament(im):
        """Едноцветна прозрачна графика (орнамент) — четецът я оцветява
        според темата (`data-tint`), иначе в тъмна тема кафявото се губи."""
        if im.mode != 'RGBA':
            return False
        px = [p for p in im.resize((120, max(1, 120 * im.height // im.width))).getdata()
              if p[3] > 128]
        if len(px) < 20:
            return False
        lum = [0.3 * r + 0.59 * g + 0.11 * b for r, g, b, _ in px]
        mean = sum(lum) / len(lum)
        sd = (sum((v - mean) ** 2 for v in lum) / len(lum)) ** 0.5
        return sd < 28

    def image(self, rid, cx_emu, src_rect=None):
        target = self.rels.get(rid)
        if not target or not target.startswith('media/') or target.endswith('.wdp'):
            return ''
        if src_rect is not None:
            key = target + '#' + ','.join(src_rect.get(k, '0') for k in 'ltrb')
        else:
            key = target
        if key not in self.images:
            data = self.z.read('word/' + target)
            try:
                im = Image.open(io.BytesIO(data))
            except Exception:
                print('  ⚠ непознат формат, пропуснат:', target)
                return ''
            # Снимките се свиват (до 1400 px), но орнаментите с прозрачност
            # остават PNG — фонът им иначе почернява.
            # Прозрачност се пази само ако я има НАИСТИНА — иконите-снимки
            # идват като RGBA с напълно плътна алфа и PNG ги прави тежки.
            alpha = False
            if im.mode in ('RGBA', 'LA', 'P') or 'transparency' in im.info:
                a = im.convert('RGBA').getchannel('A')
                alpha = a.getextrema()[0] < 250
            im = self.crop(im, src_rect)
            if max(im.size) > 1400:
                im.thumbnail((1400, 1400))
            if self.is_ornament(im.convert('RGBA') if im.mode in ('RGBA', 'LA', 'P') else im):
                self.ornaments.add(key)
            buf = io.BytesIO()
            stem = Path(target).stem + ('' if key == target else
                                        '_' + str(abs(hash(key)) % 10000))
            if alpha:
                # WebP пази прозрачността и е в пъти по-лек от PNG (Flutter
                # го чете); орнаментите се пазят без загуба.
                name = stem + '.webp'
                small = max(im.size) < 600
                im.save(buf, 'WEBP', lossless=small, quality=86, method=6)
            else:
                name = stem + '.jpg'
                im.convert('RGB').save(buf, 'JPEG', quality=84)
            self.images[key] = (name, buf.getvalue())
        name = self.images[key][0]
        frac = min(1.0, (cx_emu / 360000) / TEXT_W_CM) if cx_emu else 1.0
        tint = ' data-tint="1"' if key in self.ornaments else ''
        return (f'<p class="centernote"><img src="../Images/{name}" data-w="{frac:.2f}"'
                f'{tint} alt=""/></p>')

    @staticmethod
    def crop(im, src_rect):
        """`a:srcRect` — Word показва само част от картинката (l/t/r/b в
        стохилядни от размера). ⚠ Без него орнаментите излизаха дребни и
        разхвърляни: ползваха се целите файлове с прозрачните им полета."""
        if src_rect is None:
            return im
        f = lambda k: int(src_rect.get(k, '0')) / 100000
        W_, H_ = im.size
        box = (round(W_ * f('l')), round(H_ * f('t')),
               round(W_ * (1 - f('r'))), round(H_ * (1 - f('b'))))
        return im.crop(box) if box[2] > box[0] and box[3] > box[1] else im

    def group(self, g, cx):
        """Група картинки (орнаментът от три части, двойката илюстрации)
        → ЕДНА картинка, сглобена по координатите от Word.

        ⚠ Поотделно частите губят мястото си едни спрямо други — излизаха
        разхвърляни и непълни (докладвано от потребителя). Завъртане на 180°
        (rot="10800000") се прави и на всяка част, и на цялата група.
        """
        A = NS['a']
        gx = g.find('{%s}grpSpPr/{%s}xfrm' % (WPG, A))
        ch_off = gx.find('{%s}chOff' % A).attrib
        ch_ext = gx.find('{%s}chExt' % A).attrib
        ox, oy = int(ch_off['x']), int(ch_off['y'])
        W_, H_ = int(ch_ext['cx']), int(ch_ext['cy'])
        PX = 1400 / W_                      # широчината на сглобеното
        canvas = Image.new('RGBA', (1400, max(1, round(H_ * PX))), (0, 0, 0, 0))
        for pic in g.iter('{%s}pic' % PIC):
            blip = pic.find('.//{%s}blip' % A)
            x = pic.find('.//{%s}xfrm' % A)
            if blip is None or x is None:
                continue
            target = self.rels.get(blip.get('{%s}embed' % R_NS), '')
            try:
                im = Image.open(io.BytesIO(self.z.read('word/' + target))).convert('RGBA')
            except Exception:
                continue
            im = self.crop(im, pic.find('.//{%s}srcRect' % A))
            off, ext = x.find('{%s}off' % A).attrib, x.find('{%s}ext' % A).attrib
            w_ = max(1, round(int(ext['cx']) * PX))
            h_ = max(1, round(int(ext['cy']) * PX))
            im = im.resize((w_, h_), Image.LANCZOS)
            if x.get('flipH') == '1':
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            if x.get('flipV') == '1':
                im = im.transpose(Image.FLIP_TOP_BOTTOM)
            rot = int(x.get('rot', '0')) / 60000
            if rot:
                im = im.rotate(-rot, expand=False)
            canvas.alpha_composite(im, (round((int(off['x']) - ox) * PX),
                                        round((int(off['y']) - oy) * PX)))
        grot = int(gx.get('rot', '0')) / 60000
        if grot:
            canvas = canvas.rotate(-grot, expand=False)
        canvas = canvas.crop(canvas.getbbox() or (0, 0, 1, 1))
        self.groups = getattr(self, 'groups', 0) + 1
        name = f'group{self.groups}.webp'
        buf = io.BytesIO()
        canvas.save(buf, 'WEBP', quality=88, method=6)
        self.images[f'group{self.groups}'] = (name, buf.getvalue())
        frac = min(1.0, (cx / 360000) / TEXT_W_CM) if cx else 1.0
        tint = ' data-tint="1"' if self.is_ornament(canvas) else ''
        return (f'<p class="centernote"><img src="../Images/{name}" data-w="{frac:.2f}"'
                f'{tint} alt=""/></p>')

    def drawings(self, p):
        """Картинките и текстовите кутии в абзаца — в реда, в който стоят."""
        out = []
        for d in p.iter(w('drawing')):
            g = d.find('.//{%s}wgp' % WPG)
            if g is not None:
                ext = d.find('.//wp:extent', NS)
                out.append(self.group(g, int(ext.get('cx')) if ext is not None else 0))
                continue
            box = d.find('.//w:txbxContent', NS)
            if box is not None:
                lines = [self.runs(x) for x in box.findall('w:p', NS)]
                lines = [x for x in lines if x.strip()]
                if lines:
                    out.append('<p class="boxtext">' + '<br/>'.join(lines) + '</p>')
                continue
            ext = d.find('.//wp:extent', NS)
            cx = int(ext.get('cx')) if ext is not None else 0
            seen = set()
            src_rect = d.find('.//{%s}srcRect' % NS['a'])
            for blip in d.iter('{%s}blip' % NS['a']):
                rid = blip.get('{%s}embed' % R_NS)
                if rid and rid not in seen:
                    seen.add(rid)
                    out.append(self.image(rid, cx, src_rect))
        return [x for x in out if x]


def main():
    doc = Doc()
    d = doc.z.read('word/document.xml').decode()
    d = re.sub(r'<mc:Fallback>.*?</mc:Fallback>', '', d, flags=re.S)
    root = ET.fromstring(d.encode())
    paras = root.find('w:body', NS).findall('w:p', NS)

    chapters = [['Заглавна страница', []]]
    title_lines = []
    for p in paras:
        ppr = p.find('w:pPr', NS)
        st = ppr.find('w:pStyle', NS) if ppr is not None else None
        st = st.get(w('val')) if st is not None else ''
        jc = ppr.find('w:jc', NS) if ppr is not None else None
        jc = jc.get(w('val')) if jc is not None else ''
        text = doc.runs(p).strip()
        # ⚠ NBSP → интервал: „+ + +" е разделено с непрекъсваеми интервали
        # и иначе не се разпознаваше като кръстчета.
        plain = re.sub(r'<[^>]+>', '', text).replace('\xa0', ' ')
        if st == 'TOC2' or plain.strip() == 'Съдържание':
            continue                 # съдържанието го прави четецът
        cur = chapters[-1][1]
        # Картинките и кутиите — преди текста на същия абзац (така стоят
        # и в оригинала: котвата е в началото на реда).
        cur.extend(doc.drawings(p))
        if not text:
            continue
        if st == 'Heading2':
            chapters.append([html.unescape(plain), [f'<h1>{E(html.unescape(plain))}</h1>']])
        elif st == 'subHeading':
            cur.append(f'<p class="centernote"><b>{re.sub(r"</?i>", "", text)}</b></p>')
        elif st == 'a2':
            if plain.strip('+ ') == '':
                # „+ + +" — кръстчетата са в Tamburin, като в оригинала;
                # <h3> е стилът, който четецът рисува с него.
                cur.append(f'<h3>{plain.strip()}</h3>')
            else:
                title_lines.append(text)
                if len(title_lines) == 4:
                    cur.append('<h1>' + '<br/>'.join(title_lines) + '</h1>')
        elif st == 'a1':
            # Посвещението: курсив, двустранно подравнено, с цвета на текста;
            # „От автора" — вдясно.
            cls = 'dedicationright' if jc == 'right' else 'dedication'
            cur.append(f'<p class="{cls}">{text}</p>')
        elif st == 'a':
            # Цитатите са в КУРСИВ, както в книгата (указание на автора).
            cur.append(f'<p class="epigraph"><i>{re.sub(r"</?i>", "", text)}</i></p>')
        elif st == 'a0':
            # Цс цитат: ВОДЕЩАТА буква червена, останалото мастилено (както в
            # богослужебните книги) — указание на автора.
            cur.append(f'<p class="csq">{text}</p>')
        elif st == 'ListParagraph':
            cur.append(f'<p class="item">• {text}</p>')
        elif st == 'NoSpacing':
            cur.append(f'<p class="grouphead">{re.sub(r"</?b>", "", text)}</p>')
        elif jc == 'center' or (len(chapters) == 1):
            cur.append(f'<p class="centernote">{text}</p>')
        else:
            cur.append(f'<p>{text}</p>')

    # ── Заглавната страница: въздух преди иконата ──────────────────
    # Иначе „с.Якимово, Видинска епархия" и иконата „Всецарица" се четат
    # като едно (указание на автора).
    tp = chapters[0][1]
    for k, x in enumerate(tp):
        if '<img ' in x and k > 0 and 'Якимово' in tp[k - 1]:
            tp.insert(k, '<p class="gaptop">&#160;</p>')
            break

    # ── Надписите към илюстрациите ─────────────────────────────────
    # Текстова кутия ДО картинка е надпис към нея: по-дребен шрифт и ПОД
    # нея (в книгата някои са отвесни и в подредбата излизаха преди нея —
    # указание на автора). Кутия без картинка до себе си (анекдотът в „За
    # Каруля") остава рамкиран откъс.
    img = lambda x: '<img ' in x
    for _, parts in chapters:
        i = 0
        while i < len(parts):
            if parts[i].startswith('<p class="boxtext">'):
                cap = parts[i].replace('class="boxtext"', 'class="figcaption"')
                cap = re.sub(r'</?i>', '', cap)
                # Надписът е КРАТЪК; анекдотът в „За Каруля" стои в същия абзац
                # като снимката, но е самостоятелен откъс.
                if len(re.sub(r'<[^>]+>', '', cap)) > 180:
                    parts[i] = parts[i].replace('class="boxtext"', 'class="epigraph"')
                    i += 1
                    continue
                # ⚠ Първо ПРЕДИШНАТА картинка: подписът под иконата
                # „Всецарица" иначе се закачаше за следващия орнамент.
                if i > 0 and img(parts[i - 1]):
                    parts[i] = cap
                elif i + 1 < len(parts) and img(parts[i + 1]):
                    parts[i], parts[i + 1] = parts[i + 1], cap
                    i += 2
                    continue
                else:
                    parts[i] = parts[i].replace('class="boxtext"', 'class="epigraph"')
            i += 1

    # ── PDF: целият оригинал и всяка беседа, изрязана от него ──────
    # ⚠ Страницата, на която почва беседата, се НАМИРА по заглавието ѝ в
    # самия PDF, а не се смята по номерата от съдържанието — така
    # отместването от заглавните страници не може да се сбърка.
    import pymupdf as fitz
    pdf_src = next((ROOT / 'input').glob('*.pdf'))
    src = fitz.open(pdf_src)
    norm = lambda t: re.sub(r'[^0-9a-zа-яѝ]', '', t.lower())
    page_text = [norm(pg.get_text()) for pg in src]
    # Търси се СЛЕД страницата със съдържанието — там стоят всички
    # заглавия и първото съвпадение щеше да е тя.
    at = next(i for i, t in enumerate(page_text) if 'съдържание' in t) + 1
    starts = []
    for title, _ in chapters[1:]:
        key = norm(title)[:28]
        while at < len(page_text) and key not in page_text[at]:
            at += 1
        if at == len(page_text):
            sys.exit(f'⚠ в PDF-а няма заглавие „{title}"')
        starts.append(at)
        at += 1
    last = len(src) - 2          # без задната корица
    # ⚠ ОТДЕЛНИТЕ БЕСЕДИ НЕ СЕ ПАЗЯТ КАТО ЦЕЛИ PDF-И (те носеха по копие от
    # шрифтовете — 8 MB). Пази се само „опашка" — допълнение към края на
    # оригинала (incremental update), което казва „страниците са само
    # тези". Оригинал + опашка = валиден PDF само с беседата (сверено с
    # poppler и Ghostscript). Опашката е няколко KB; долепя я приложението
    # (EpubBook.chapterPdf), без да разчита нищо в PDF-а.
    import tempfile
    orig = pdf_src.read_bytes()
    pdfs = {'book.pdf': orig}
    for k, a in enumerate(starts):
        b = (starts[k + 1] - 1) if k + 1 < len(starts) else last
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td) / 'x.pdf'
            tmp.write_bytes(orig)
            part = fitz.open(tmp)
            part.select(list(range(a, b + 1)))
            part.save(tmp, incremental=True, encryption=fitz.PDF_ENCRYPT_KEEP)
            part.close()
            full = tmp.read_bytes()
        if full[:len(orig)] != orig:
            sys.exit('⚠ опашката не е чисто допълнение към оригинала')
        pdfs[f'c{k + 1:02d}.tail'] = full[len(orig):]
        print(f'  c{k + 1:02d}: стр. {a + 1}–{b + 1} (опашка {len(full) - len(orig)} B)')

    # ── .epub ──────────────────────────────────────────────────────
    files, toc = [], []
    for i, (title, parts) in enumerate(chapters):
        name = 'title.xhtml' if i == 0 else f'c{i:02d}.xhtml'
        files.append((name, xhtml(title, ''.join(parts))))
        toc.append((title if i else 'Разговори за Божествения промисъл', name))
    for n, t in doc.notes:
        files.append((f'note{n}.xhtml', xhtml(str(n), f'<h1 id="note{n}">{n}</h1><p>{t}</p>')))

    import uuid
    uid = str(uuid.uuid5(uuid.NAMESPACE_URL, 'chitalnya/razgovori'))
    man = ''.join(f'<item id="f{i}" href="Text/{n}" media-type="application/xhtml+xml"/>'
                  for i, (n, _) in enumerate(files))
    for k, (n, _) in enumerate(doc.images.values()):
        mt = {'png': 'image/png', 'webp': 'image/webp'}.get(n.rsplit('.', 1)[1], 'image/jpeg')
        man += f'<item id="i{k}" href="Images/{n}" media-type="{mt}"/>'
    spine = ''.join(f'<itemref idref="f{i}"/>' for i in range(len(chapters)))
    opf = ('<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" '
           'version="2.0" unique-identifier="uid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
           '<dc:title>Разговори за Божествения промисъл, последните времена и вътрешния духовен живот</dc:title>'
           f'<dc:language>bg</dc:language><dc:identifier id="uid">{uid}</dc:identifier>'
           # Без буквица — абзаците почват с „К:", „И: ВЪПРОС –" (автора).
           '<meta name="no-dropcap" content="true"/></metadata>'
           f'<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>{man}</manifest>'
           f'<spine toc="ncx">{spine}</spine></package>')
    nav = ''.join(f'<navPoint id="n{i}" playOrder="{i + 1}"><navLabel><text>{E(t)}</text></navLabel>'
                  f'<content src="Text/{n}"/></navPoint>' for i, (t, n) in enumerate(toc))
    ncx = ('<?xml version="1.0" encoding="utf-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" '
           f'version="2005-1"><head><meta name="dtb:uid" content="{uid}"/></head>'
           f'<docTitle><text>Разговори</text></docTitle><navMap>{nav}</navMap></ncx>')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, 'w') as z:
        z.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        z.writestr('META-INF/container.xml',
                   '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                   '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>'
                   '</rootfiles></container>', compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OEBPS/content.opf', opf, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr('OEBPS/toc.ncx', ncx, compress_type=zipfile.ZIP_DEFLATED)
        for n, x in files:
            z.writestr(f'OEBPS/Text/{n}', x, compress_type=zipfile.ZIP_DEFLATED)
        for n, data in doc.images.values():
            z.writestr(f'OEBPS/Images/{n}', data, compress_type=zipfile.ZIP_STORED)
        # ⚠ PDF-ите стоят ИЗВЪН манифеста: те не са част от четивото, а
        # само се споделят (book_reader.dart ги търси по името на главата).
        for n, data in pdfs.items():
            z.writestr(f'OEBPS/pdf/{n}', data, compress_type=zipfile.ZIP_STORED)
    # Корицата — предната корица на книгата (image1), с пропорцията на
    # останалите (479×741): изрязва се по средата, не се разтяга.
    front = Image.open(io.BytesIO(doc.z.read('word/media/image1.jpg'))).convert('RGB')
    W, H = 479, 741
    s = max(W / front.width, H / front.height)
    front = front.resize((round(front.width * s), round(front.height * s)), Image.LANCZOS)
    l, t = (front.width - W) // 2, (front.height - H) // 2
    front.crop((l, t, l + W, t + H)).save(COVER, quality=90)
    print(f'{OUT.name}: {len(chapters) - 1} беседи, {len(doc.notes)} бележки, '
          f'{len(doc.images)} картинки, {OUT.stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
