"""Таб „Богослужебни" → work/bogosluzhebni.json (като kanonnik.json, плюс
`book` и `grp` за двустепенното съдържание).

Изворите (input/newBooks/*.epub, azbyka.ru) са в старото кодиране Ucs:
    <p class="calibre6">        абзац
    <span class="kinovar">      червено (указание, буквица)
    <span class="slavicgray">   сиви препратки към страници/варианти — отпадат
    <b>                         получер вътре в заглавие — носи цвета около себе си
    <h2>                        заглавието на главата (руски граждански) — за превода

⚠ Декодира се САМО текстът между таговете — пуснат през ucs.decode, HTML-ът
се превръща в безсмислица („ⷯ/ѱⷬ҇…").
⚠ Заглавията са на руски → превод с DeepSeek (work/bogosl_titles_bg.json,
кеширан). Самият текст остава на цс.
"""
import html
import json
import os
import re
import sys
import zipfile
from html.parser import HTMLParser
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
import pdf_ucs  # noqa: E402
import ucs  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
W = ROOT / 'work'
IN = ROOT / 'input' / 'newBooks'
SRC = 'https://azbyka.ru/otechnik/Pravoslavnoe_Bogosluzhenie/'

MONTHS = ['януари', 'февруари', 'март', 'април', 'май', 'юни', 'юли', 'август',
          'септември', 'октомври', 'ноември', 'декември']
MINEI = ['01_Yanvar', '02_Fevral', '03_Mart', '04_Aprel', '05_May', '06_Iyun', '07_Iyul',
         '08_Avgust', '09_Sentyabr', '10_Oktyabr', '11_Noyabr', '12_Dekabr']

# (файл, ключ на книгата, бг име); редът е редът в таба и в плаващото копче.
BOOKS = [
    ('Chasoslov_na_tserkovno-slavyanskom_yazyike.epub', 'chasoslov', 'Часослов'),
    ('Oktoih.epub', 'oktoih', 'Октоих'),
] + [('Mineya_%s.epub' % m, 'minei', 'Минеи') for m in MINEI] + [
    ('Triod_postnaya.epub', 'triod_post', 'Триод постен'),
    ('Triod_tsvetnaya.epub', 'triod_tsvet', 'Триод цветен'),
    ('Slujebnik.epub', 'slujebnik', 'Служебник'),
    ('Tipikon.epub', 'tipikon', 'Типикон'),
]


class ParaParser(HTMLParser):
    """<p> → [(червено?, текст)], с декодиран Ucs."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.paras, self.cur, self.stack = [], None, []

    def handle_starttag(self, tag, attrs):
        cls = dict(attrs).get('class', '') or ''
        if tag == 'p':
            self.cur = []
        elif tag == 'br' and self.cur is not None:
            self.cur.append((False, ' '))
        if tag in ('span', 'b', 'i', 'a', 'em', 'strong'):
            self.stack.append('bold' if tag == 'b' else cls)

    def handle_endtag(self, tag):
        if tag == 'p' and self.cur is not None:
            self.paras.append(self.cur)
            self.cur = None
        elif tag in ('span', 'b', 'i', 'a', 'em', 'strong') and self.stack:
            self.stack.pop()

    def handle_data(self, data):
        if self.cur is None or 'slavicgray' in self.stack:
            return
        t = re.sub(r'\s+', ' ', data)
        if t:
            # ⚠ Третото поле: получер (Октоихът бележи заглавията така, не с
            # червено) — само за разпознаване на заглавие, не за цвета.
            # ⚠ Номерата на страниците („зри стр. 229") са АРАБСКИ ЦИФРИ в
            # отделен шрифт (`slavicgreek`); минати през ucs.decode, те стават
            # надредни знаци и не се четат. Остават както са (потребителят).
            dec = t if 'slavicgreek' in self.stack else ucs.decode(t)
            self.cur.append(('kinovar' in self.stack, dec, 'bold' in self.stack))


RE_UNIT = re.compile(r'^(?:(?:Въ?|Во|На)\s.{0,60}(?:вечер|ѹтр|утр|лїтꙋрг|повечер|полꙋнощ|часѣ|часъ)'
                     r'|(?:Гласъ \S+ )?Пѣснь\s|Канѡнъ|Послѣдованїе|Чинъ|Часъ\s)')


def chapter_units(body):
    p = ParaParser()
    p.feed(body)
    units = [{'title': None, 'blocks': []}]
    for runs3 in p.paras:
        runs = [(r, t) for r, t, _ in runs3]
        text = ''.join(t for _, t in runs).strip()
        if not text:
            continue
        red = all(r for r, t in runs if t.strip())
        bold = all(r or b for r, t, b in runs3 if t.strip())
        h = pdf_ucs.runs_html(runs)
        plain = re.sub(r'<[^>]+>', '', h).strip()
        b = pdf_ucs.bare(plain).replace('҆', '')
        if (red or bold) and len(b) <= 90 and RE_UNIT.match(b):
            if units[-1]['title'] and not units[-1]['blocks']:
                # Две заглавия едно след друго — второто е указание към първото.
                units[-1]['blocks'].append({'kind': 'rubric', 'html': html.escape(plain, quote=False)})
            else:
                # „Пѣ́снь а҃. І҆рмо́съ:" — етикетът на ирмоса отива пред ТЕКСТА му,
                # както навсякъде другаде в молитвослова, не в заглавието.
                m = re.match(r'^(.*?Пѣ́снь\s+\S+?\.?)\s+(І҆рмо́съ):?$', plain)
                if m:
                    units.append({'title': m.group(1).rstrip('.'), 'blocks': [],
                                  'label': m.group(2) + ':'})
                else:
                    units.append({'title': plain.rstrip(':,.'), 'blocks': []})
            continue
        if red or bold and not any(r for r, _ in runs):
            if bold and not red:
                units[-1]['blocks'].append({'kind': 'rubric', 'html': html.escape(plain, quote=False)})
                continue
        if red:
            units[-1]['blocks'].append({'kind': 'rubric', 'html': html.escape(plain, quote=False)})
            continue
        lab = units[-1].pop('label', None)
        if lab:
            h = '<span class="rubric">%s</span> %s' % (lab, h)
        kind = 'refrain' if re.match(r'<span class="rubric">Припѣ́въ', h) else 'text'
        units[-1]['blocks'].append({'kind': kind, 'html': h})
    for u in units:
        u.pop('label', None)
    return [u for u in units if u['blocks'] or u['title']]


def chapters(path):
    """Главите по РЕДА НА КНИГАТА (spine), не по toc.ncx.

    ⚠ Съдържанието на някои книги е НЕПЪЛНО: в Октоиха свършва на глас 7, а
    глас 8 и десет приложения са в книгата; в Типикона липсват гл. 49–62, в
    две Минеи — по едно приложение. Затова се обхожда spine-ът, а заглавието
    се взима от съдържанието, ако го има там, инак от <h2>.
    """
    z = zipfile.ZipFile(path)
    ncx = next(n for n in z.namelist() if n.endswith('.ncx'))
    base = os.path.dirname(ncx)
    t = z.read(ncx).decode('utf-8')
    labels = {}
    for label, src in re.findall(r'<navLabel>\s*<text>(.*?)</text>.*?<content src="([^"]+)"', t, re.S):
        labels.setdefault(src.split('#')[0], html.unescape(label).strip())
    opf = next(n for n in z.namelist() if n.endswith('.opf'))
    o = z.read(opf).decode('utf-8')
    items = dict(re.findall(r'<item\b[^>]*?id="([^"]+)"[^>]*?href="([^"]+)"', o))
    items.update({i: h for h, i in re.findall(r'<item\b[^>]*?href="([^"]+)"[^>]*?id="([^"]+)"', o)})
    for idref in re.findall(r'<itemref\b[^>]*idref="([^"]+)"', o):
        href = items.get(idref, '')
        if not href.endswith('html'):
            continue
        name = os.path.join(os.path.dirname(opf), href) if os.path.dirname(opf) else href
        h = z.read(name).decode('utf-8', 'replace')
        m = re.search(r'<h2[^>]*>(.*?)</h2>', h, re.S)
        label = labels.get(href) or (html.unescape(re.sub(r'<[^>]+>', '', m.group(1))).strip()
                                     if m else '')
        # „Глас 8-йВоскресенье" — в заглавията от <h2> интервалът липсва.
        label = re.sub(r'(\d-й)(?=[А-Я])', r'\1. ', re.sub(r'\s+', ' ', label)).strip()
        if not label or 'первоисточник' in label or label.startswith('Полное оглавление'):
            continue
        yield label, h[h.find('<body'):]


def translate_titles(titles):
    cache = W / 'bogosl_titles_bg.json'
    done = json.loads(cache.read_text(encoding='utf-8')) if cache.exists() else {}
    missing = [x for x in dict.fromkeys(titles) if x not in done]
    if missing:
        import importlib.util
        spec = importlib.util.spec_from_file_location(
            'tr', ROOT.parent / 'lives_plus' / 'scripts' / '02_translate_deepseek.py')
        tr = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(tr)
        tr.ПРОМПТ = PROMPT
        k = tr.ключ()
        rep = {'повиквания': 0, 'вход': 0, 'изход': 0}
        for i in range(0, len(missing), 40):
            part = missing[i:i + 40]
            out = tr.преведи(k, part, '', rep)
            for ru, bg in zip(part, out):
                done[ru] = bg.strip()
            cache.write_text(json.dumps(done, ensure_ascii=False, indent=1), encoding='utf-8')
            print('  заглавия %d/%d' % (i + len(part), len(missing)), flush=True)
    return done


PROMPT = """Ти си опитен преводач на православна богослужебна литература от руски на български.

Превеждаш ЗАГЛАВИЯ на служби от богослужебните книги (Минеи, Октоих, Триоди, Часослов, Служебник, Типикон).

Правила:
1. Утвърден български църковен стил: „Обрезание Господне“, „Св. пророк Малахия“, „Преподобни Сава Освещени“.
2. Имената — в утвърдените български форми („Йоан“, не „Иоанн“; „Теодор“, не „Феодор“; „Атанасий“, не „Афанасий“; „Тимотей“; „Евтимий“).
3. Датата отпред остава, с български месец: „2 января: …“ → „2 януари: …“.
4. „Глас 1-й. Воскресенье“ → „Глас 1. Неделя“; дните: понеделник, вторник, сряда, четвъртък, петък, събота.
5. „Неделя о мытаре и фарисее“ → „Неделя на митаря и фарисея“; „седмица“ остава „седмица“.
6. Не добавяй нищо, не съкращавай, без точка накрая.

Входът е номериран списък, по едно заглавие на ред. Отговори със същите номера, същия ред и същия брой редове.
"""


# Кратките имена, които потребителят иска в съдържанието (Часослов).
TITLE_OVERRIDES = {
    'Последование на утренята': 'Утреня',
    'Последование на вечернята': 'Вечерня',
}


def grp_of(book, label, fname):
    if book == 'minei':
        m = MINEI.index(re.search(r'Mineya_(\d\d_\w+)\.epub', fname).group(1))
        return 'Миней за %s' % MONTHS[m]
    if book == 'oktoih':
        m = re.match(r'Глас (\d)', label)
        # Ексапостилариите, утринните евангелия и т.н. след 8-те гласа.
        return 'Глас %s' % m.group(1) if m else 'Приложения'
    return None


# ⚠ МАЛКОТО ПОВЕЧЕРИЕ: Пс. 101 → Пс. 142. Нашият Часослов е от редакцията,
# която след Пс. 69 дава Пс. 101 („Гдⷭ҇и, ѹ҆слы́ши моли́твꙋ мою̀, и҆ во́пль
# мо́й…"); далеч по-разпространената (и ползваната у нас) дава Пс. 142
# („Гдⷭ҇и, ѹ҆слы́ши моли́твꙋ мою̀, внꙋшѝ моле́нїе моѐ…"). Двата започват
# еднакво — затова разпознаването е по ПРОДЪЛЖЕНИЕТО. Текстът на Пс. 142 се
# взима от bible.db (цс), без надписанието. (Решение на потребителя.)
PS101_HEAD = 'Гдⷭ҇и, ѹ҆слы́ши моли́твꙋ мою̀, и҆ во́пль мо́й'
BIBLE_DB = Path(__file__).resolve().parents[3] / 'assets' / 'db' / 'bible.db'


def ps142_csl():
    import sqlite3
    con = sqlite3.connect(BIBLE_DB)
    vs = [t for (t,) in con.execute(
        "SELECT text FROM verses WHERE lang='utfcs' AND book='Ps' AND chapter=142 "
        "AND verse <> '0' ORDER BY ord")]
    con.close()
    # bible.db пише „ᲂу" (U+1C82+у), Часословът — „ѹ"; да не се смесват.
    return ' '.join(vs).replace('\u1c82у', 'ѹ')


def fix_small_compline(out):
    n = 0
    for s in out:
        if s['book'] != 'Часослов' or s['title_bg'] != 'Малко повечерие':
            continue
        for u in s['units']:
            for b in u['csl']:
                if b['html'].startswith(PS101_HEAD):
                    b['html'] = ps142_csl()
                    n += 1
    if n != 1:
        sys.exit('⚠ Малкото повечерие: Пс. 101 намерен %d пъти (очаквано 1)' % n)


# ⚠ ВЪТРЕШНИТЕ ПРЕПРАТКИ В ЧАСОСЛОВА („Вѣ́рꙋю во є҆ди́наго бг҃а: (стр. …)").
# В извора номерът на страницата е бил в друг шрифт и се разчита като
# безсмислени надредни знаци; истински връзки там няма. Вместо да се
# правят активни (връщането от тях би било сложно), препратката се ЗАМЕНЯ с
# пълния текст, намерен другаде в Часослова по началото си. Решение на
# потребителя — дублирането струва няколко KB. Пет места, всичките в края
# на Малкото повечерие; ненамерено начало СПИРА скрипта.
def _fold(h):
    import unicodedata
    t = re.sub(r'<[^>]+>', '', h)
    t = ''.join(c for c in unicodedata.normalize('NFD', t) if not unicodedata.combining(c))
    return re.sub(r'[^\w]', '', t).lower()


def expand_page_refs(out):
    chas = [b for s in out if s['book'] == 'Часослов' for u in s['units'] for b in u['csl']]
    n = 0
    for b in chas:
        if '(стр.' not in b['html']:
            continue
        inc = _fold(b['html'].split('<span class="rubric">(стр.')[0])
        full = next((c for c in chas if c is not b and '(стр.' not in c['html']
                     and _fold(c['html']).startswith(inc)), None)
        if full is None:
            sys.exit('⚠ Часослов: препратката „%s…" няма пълен текст' % inc[:30])
        b['html'], b['kind'] = full['html'], full['kind']
        n += 1
    print('Часослов: %d препратки заменени с пълния текст' % n)
    expand_vespers_psalms(out)
    # ⚠ ВЪТРЕШНИ ПРЕПРАТКИ → ПАНЕЛ ОТДОЛУ (`showRefSheet` в
    # molitvoslov_reader.dart; идея на потребителя). Адресът е по ИМЕ и по
    # ТЕКСТ, не по номер — номерата на разделите се разместват. Само там,
    # където целта е еднозначна:
    #   • 17-а катизма в Полунощницата → разделът „Катизма 17";
    #   • „начални молитвословия" в Малкото повечерие → Полунощницата, отворена
    #     на „Сла́ва тебѣ̀ бж҃е на́шъ" (не в самото начало, където са
    #     молитвите след ставане от сън — указание на потребителя).
    links = 0
    for s in out:
        if s['book'] != 'Часослов':
            continue
        for u in s['units']:
            for b in u['csl']:
                h = b['html']
                h2 = re.sub(r'(каѳі́сма з҃і \(зр\S* стр\. \d+\))',
                            r'<a href="mol:Часослов/Катизма 17">\1</a>', h)
                h2 = re.sub(r'(зр\S* въ нача́лѣ полꙋ́нощницы)',
                            r'<a href="mol:Часослов/Полунощница#Сла́ва тебѣ̀ бж҃е на́шъ">\1</a>', h2)
                if h2 != h:
                    b['html'] = h2
                    links += 1
    if links != 2:
        sys.exit('⚠ Часослов: очаквани 2 вътрешни препратки, намерени %d' % links)
    # Малкото повечерие: „…зрѝ въ нача́лѣ полꙋ́нощницы по всѧ̑ дни̑. стр. 7" —
    # указание към началото на друга служба; номерът на печатната страница
    # тук нищо не казва и се маха (потребителят). В Полунощницата
    # „(зрѝ стр. 229)" към 17-а катизма остава, вече четимо.
    for s in out:
        if s['book'] == 'Часослов' and s['title_bg'] == 'Малко повечерие':
            for u in s['units']:
                for b in u['csl']:
                    b['html'] = re.sub(r'(по всѧ̑ дни̑\.)\s*стр\.\s*\d+', r'\1', b['html'])


def _psalm(ch):
    import sqlite3
    con = sqlite3.connect(BIBLE_DB)
    # ⚠ Без надписанието („Ѱало́мъ дв҃дꙋ, внегда̀…") — в службата то не се
    # чете. При Пс. 33 то е стих 1, не 0 — затова по таблицата `headings`.
    vs = [t for (t,) in con.execute(
        "SELECT text FROM verses v WHERE lang='utfcs' AND book='Ps' AND chapter=? "
        "AND NOT EXISTS (SELECT 1 FROM headings h WHERE h.book='Ps' AND h.chapter=v.chapter "
        "AND h.verse=v.verse) ORDER BY ord", (ch,))]
    con.close()
    return html.escape(' '.join(vs).replace('\u1c82у', 'ѹ'), quote=False)


def expand_vespers_psalms(out):
    """Вечернята през Великия пост: „Та́же, ѱало́мъ л҃г: Бл҃гословлю̀ гдⷭ҇а…
    Стр. 125, и҆ ѱало́мъ рм҃д: Вознесꙋ́ тѧ, бж҃е мо́й:" — само началата на
    Пс. 33 и Пс. 144 с препратка към страница. Заменят се с целите псалми от
    bible.db (решение на потребителя). Препратката към 17-а катизма в
    Полунощницата НЕ се разгъва — тя е цяла катизма (пак решение на
    потребителя). Ненамерено място СПИРА скрипта."""
    for s in out:
        if s['book'] != 'Часослов':
            continue
        for u in s['units']:
            bl = u['csl']
            for i, b in enumerate(bl):
                h = b['html']
                if 'ѱало́мъ л҃г:' in h and 'ѱало́мъ рм҃д:' in h:
                    rest = h.split('Вознесꙋ́ тѧ, бж҃е мо́й:', 1)[1].lstrip()
                    bl[i:i + 1] = [
                        {'kind': 'rubric', 'html': 'Та́же, ѱало́мъ л҃г:'},
                        {'kind': 'text', 'html': _psalm(33)},
                        {'kind': 'rubric', 'html': 'И҆ ѱало́мъ рм҃д:'},
                        {'kind': 'text', 'html': _psalm(144)},
                        {'kind': 'text', 'html': rest},
                    ]
                    print('Часослов: Пс. 33 и Пс. 144 вмъкнати във Вечернята')
                    return
    sys.exit('⚠ Часослов: не е намерено мястото с Пс. 33 и Пс. 144')


def main():
    raw = []
    for fname, book, bname in BOOKS:
        for label, body in chapters(IN / fname):
            raw.append((fname, book, bname, label, chapter_units(body)))
    titles = translate_titles([r[3] for r in raw])
    out, sid = [], 1000
    for fname, book, bname, label, units in raw:
        sid += 1
        tbg = titles.get(label, label).strip().rstrip('.')
        tbg = TITLE_OVERRIDES.get(tbg, tbg)
        if book == 'oktoih':
            tbg = re.sub(r'^Глас \d+\.?\s*', '', tbg) or tbg
        us = [{'n': i, 'title_csl': None, 'title_bg': None, 'title_cs': u['title'],
               'csr': [], 'bg': [], 'csl': u['blocks'], 'sources': []}
              for i, u in enumerate(units)]
        out.append({'sec': sid, 'tab': 'bogosluzhebni', 'book': bname,
                    'grp': grp_of(book, label, fname), 'title_bg': tbg, 'title_csl': None,
                    'csr_source': None, 'csl_source': SRC, 'units': us})
    fix_small_compline(out)
    expand_page_refs(out)
    (W / 'bogosluzhebni.json').write_text(json.dumps(out, ensure_ascii=False, indent=1),
                                          encoding='utf-8')
    n_bl = sum(len(u['csl']) for s in out for u in s['units'])
    print('→ work/bogosluzhebni.json: %d раздела, %d блока' % (len(out), n_bl))


if __name__ == '__main__':
    main()
