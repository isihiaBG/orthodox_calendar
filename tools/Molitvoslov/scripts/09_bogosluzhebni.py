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
import difflib
import unicodedata
from html.parser import HTMLParser
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
import pdf_ucs  # noqa: E402
import sluzhebnik_bg  # noqa: E402
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
            if self.stack.pop() == 'slavicgray' and 'slavicgray' not in self.stack:
                self._flush_gray()

    # ⚠ СИВИЯТ ШРИФТ (`slavicgray`) — дотук се изхвърляше ЦЯЛ, а в него има и
    # текст от печатната книга: „(А҆нато́лїевъ)" (стихирата е от св. Анатолий),
    # препратки към Писанието („(Мїх. є҃.)"), обикновени скоби от текста
    # („(Внеза́пꙋ)", „(Пѣ́снь степе́ней, р҃к)"). Изхвърлят се САМО бележките на
    # дигитализиращите на руски; останалото влиза като обикновен текст —
    # както е в печатната книга. „(комм.)" в Типикона също остава: той бележи
    # абзаците с особени случаи и Марковите глави (потребителят).
    EDITORIAL = ('Исправ', 'источник', 'оригинал', 'Словар', 'Служба', 'Опущен',
                 'Прим.', 'печата', 'По другим', 'племянника', 'так у',
                 'строка между', 'Текст сей')
    gray = None

    def _flush_gray(self):
        g, self.gray = self.gray or [], None
        raw = ''.join(r for r in g if isinstance(r, str))
        if any(w in raw for w in self.EDITORIAL) or self.cur is None:
            return
        self.cur.extend(x for x in g if not isinstance(x, str))

    def handle_data(self, data):
        if self.cur is None:
            return
        if 'slavicgray' in self.stack:
            t = re.sub(r'\s+', ' ', data)
            if self.gray is None:
                self.gray = []
            self.gray.append(t)                      # суров — за разпознаването
            dec = t if 'slavicgreek' in self.stack else ucs.decode(t)
            self.gray.append(('kinovar' in self.stack, dec, 'bold' in self.stack))
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


SLUJ_ONLINE = IN.parent / 'newBooks2' / 'sluzhebnik_azbyka_1896.html'


class RedTransfer:
    """Червеното на Служебника — от ОНЛАЙН изданието на azbyka.ru.

    ⚠⚠ В .epub-а (book_1860, 2011) червено няма: 4 означения в 20 глави.
    Онлайн изданието „Служебник на церковнославянском языке (1896 г.)"
    (https://azbyka.ru/otechnik/Pravoslavnoe_Bogosluzhenie/sluzhebnik-na-tserkovnoslavjanskom-jazyke/,
    свалено в input/newBooks2/) е СЪЩАТА книга с `color-red` — 1788 откъса.
    ⚠ ТЕКСТЪТ остава този от .epub-а; оттам се взима САМО кое е червено:
    абзацът се търси в онлайн текста напред от последния намерен (с малко
    връщане назад), после се подравнява знак по знак. Сравнението е без
    надредни знаци, ѐ = е, ѹ = оу = у и т.н. Ненамереното остава черно и
    влиза в `self.missed` (за отчета). Литургиите на ап. Яков ги няма онлайн.
    Мерено: 2515 от 2642 абзаца намерени, ~20 от ненамерените са заглавия.
    """
    MAP = str.maketrans({'ᲂ': '', 'ꙋ': 'у', 'ѹ': 'у', 'ѡ': 'о', 'ѿ': 'от', 'ꙗ': 'я',
                         'ѧ': 'я', 'є': 'е', 'ѕ': 'з', 'і': 'и', 'ї': 'и', 'ѻ': 'о',
                         'ѳ': 'ф', 'ѵ': 'и', 'ꙁ': 'з', 'ѣ': 'е', 'ꙑ': 'ы', 'ѽ': 'о',
                         'ꙍ': 'о', 'ѯ': 'кс', 'ѱ': 'пс'})

    @classmethod
    def fold(cls, t):
        out, idx = [], []
        for i, ch0 in enumerate(t):
            ch = unicodedata.normalize('NFD', ch0)[0]
            if unicodedata.category(ch).startswith('M'):
                continue
            for cc in ch.lower().translate(cls.MAP):
                if cc.isalpha():
                    if cc == 'у' and out and out[-1] == 'о':      # „оу" = „у"
                        out.pop()
                        idx.pop()
                    out.append(cc)
                    idx.append(i)
        return ''.join(out), idx

    def __init__(self, path):
        t = path.read_text(encoding='utf-8')
        F, M = [], []
        for m in re.finditer(r'<p class="ponomar">(.*?)</p>', t, re.S):
            for mm in re.finditer(r'<span class="color-red">(.*?)</span>|([^<]+)', m.group(1), re.S):
                red = mm.group(1) is not None
                f, _ = self.fold(html.unescape(re.sub(r'<[^>]+>', '', mm.group(1) if red else mm.group(2))))
                F.append(f)
                M.extend([red] * len(f))
        self.F, self.M, self.cur, self.missed = ''.join(F), M, 0, []

    # ⚠ РЕЗЕРВНИ ПРАВИЛА — за абзаците без съответствие онлайн: заглавията
    # (там са в <h2>), редовете, които онлайн изданието съкращава („И҆
    # про́чее по чи́нꙋ"), и литургиите на ап. Яков, които ги няма онлайн.
    HEAD = re.compile(r'^(Послѣ́дованїе|Чи́нъ|Бж҃е́ственнаѧ слꙋ́жба|Ѹ҆ка́зъ|Ѿпꙋ́сты|'
                      r'во ст҃ы́х[ьъ] |быва́емыѧ|глаго́лемїи|сі́есть|во всю̀|начина́етсѧ)')
    INSTR = re.compile(r'^(Та́же|И҆ па́ки|Сщ҃е́нникъ|Свѧще́нникъ|І҆ере́й|Іере́й|Архїере́й|Дїа́конъ|Дїа́кони|Ли́къ|Лю́дїе|'
                       r'Чте́цъ|Возглаша́етъ|Возглаше́нїе|Возгла́съ|Мл҃тва|Моли́тва|'
                       r'И҆ пое́тсѧ|По |Прокі́менъ|Дрꙋгі́й|И҆ про́чее)')
    ROLE = re.compile(r'^((?:И҆ )?(?:Дїа́конъ|Дїа́кони|Ли́къ|Сщ҃е́нникъ|Свѧще́нникъ|І҆ере́й|Іере́й|'
                      r'Архїере́й|Лю́дїе|Чте́цъ|Возгла́съ|Возглаше́нїе|Дрꙋгі́й)(?:,? [^:]{0,40})?:)')

    def rules(self, runs3):
        text = ''.join(t for _, t, _ in runs3)
        s = text.strip()
        if len(s) <= 160 and (self.HEAD.match(s) or (s.endswith(':') and self.INSTR.match(s))):
            return [(True, t, b) for _, t, b in runs3]
        m = self.ROLE.match(text.lstrip())
        if not m:
            return runs3
        cut, out, pos = len(text) - len(text.lstrip()) + m.end(), [], 0
        for _, t, b in runs3:
            a, z = pos, pos + len(t)
            if z <= cut:
                out.append((True, t, b))
            elif a >= cut:
                out.append((False, t, b))
            else:
                out += [(True, t[:cut - a], b), (False, t[cut - a:], b)]
            pos = z
        return out

    def apply(self, runs3):
        text = ''.join(t for _, t, _ in runs3)
        f, idx = self.fold(text)
        if len(f) < 3:
            return self.rules(runs3)
        F, cur = self.F, self.cur
        seed, lo = f[:20], max(0, cur - 3000)
        pos = F.find(seed, lo, cur + 20000)
        if pos < 0 and len(f) >= 10:
            pos = F.find(seed[:10], lo, cur + 20000)
        if pos >= 0 and len(f) < 25 and pos - cur > 1500:
            pos = -1                      # къс абзац не мести показалеца далеч
        if pos < 0:
            self.missed.append(text.strip()[:80])
            return self.rules(runs3)
        win = F[pos:pos + int(len(f) * 1.3) + 20]
        sm = difflib.SequenceMatcher(None, f, win, autojunk=False)
        blocks = [bl for bl in sm.get_matching_blocks() if bl.size]
        if sum(bl.size for bl in blocks) < 0.8 * len(f):
            self.missed.append(text.strip()[:80])
            return self.rules(runs3)
        fm = [None] * len(f)
        for bl in blocks:
            for k in range(bl.size):
                fm[bl.a + k] = self.M[pos + bl.b + k]
        for k in range(len(fm)):                 # несъвпаднали — от съседа
            if fm[k] is None:
                fm[k] = fm[k - 1] if k else next((x for x in fm if x is not None), False)
        self.cur = pos + blocks[-1].b + blocks[-1].size
        # знак по знак: буквите по маската, останалото — като буквата преди
        cm, li = [], 0
        first = fm[0]
        for i in range(len(text)):
            while li < len(idx) and idx[li] < i:
                li += 1
            if li < len(idx) and idx[li] == i:
                cm.append(fm[li])
            else:
                cm.append(cm[-1] if cm else first)
        out, pos2 = [], 0
        for _, t, bld in runs3:
            seg_start = pos2
            for i in range(len(t)):
                r = cm[seg_start + i]
                if out and out[-1][0] == r and out[-1][2] == bld and i:
                    out[-1] = (r, out[-1][1] + t[i], bld)
                else:
                    out.append((r, t[i], bld))
            pos2 += len(t)
        return out


class RubricModel:
    """Червеното в Октоиха, научено от главите, които го имат.

    ⚠⚠ В .epub-а от azbyka.ru червеният шрифт (`kinovar`) СВЪРШВА насред
    книгата — от сряда на глас 4 до края, включително приложенията, няма
    нито едно означение (03.10.2026). HIP изданието от orthlib.ru също е без
    червено (OCR). Затова се учи от изрядната част (глас 1–3 и неделя–вторник
    на глас 4, 26 глави): Октоихът е строго успореден по гласове и
    указанията са едни и същи думи, различава се само номерът на гласа.

        FULL  — абзаци, изцяло червени            → целият абзац червен
        LAB   — червено начало до „:" / „," / „." → само етикетът червен
        общо  — кратък ред-указание (виж [generic]), САМО ако няма етикет

    Проверено: учено от глас 1–3, мерено на неделя–вторник на глас 4 — от
    787 абзаца 0 оцветени погрешно химни; разминават се ~17, почти все
    частично (по-къс етикет). Сравнението е без ударения, без надредни знаци
    и без пунктуацията вътре; гласът и поредните числа са заместители.
    """
    KW = re.compile(r'^(въ|во|на|по|таже|посемъ|ины|инъ|другій|канѡнъ|степенна|'
                    r'ѵпакои|вонми|аще)\b')

    @staticmethod
    def norm(t):
        t = pdf_ucs.bare(t).replace('҆', '').lower()
        t = re.sub(r'гласъ\s+[^\s:.,]+', 'гласъ #', t)
        t = re.sub(r'(?<![^\s])[а-ѳ]{1,2}-(мъ|ю|я|е)', '#-\\1', t)
        t = re.sub(r'[.,:;\[\]]', ' ', t)
        return re.sub(r'\s+', ' ', t).strip()

    def __init__(self, chs):
        self.full, self.lab = set(), set()
        for _, body in chs:
            if 'kinovar' not in body:
                continue
            p = ParaParser()
            p.feed(body)
            for runs3 in p.paras:
                runs = [(r, t) for r, t, _ in runs3]
                text = ''.join(t for _, t in runs).strip()
                if not text:
                    continue
                if all(r for r, t in runs if t.strip()):
                    self.full.add(self.norm(text))
                    continue
                lead = ''
                for r, t in runs:
                    if not r:
                        break
                    lead += t
                i = max(lead.rfind(':'), lead.rfind(','))
                if i >= 0 and len(pdf_ucs.bare(lead[:i]).strip()) > 1:
                    self.lab.add(self.norm(lead[:i + 1]))

    def generic(self, text):
        s = text.strip()
        n = self.norm(s)
        # „И҆́нъ канѡ́нъ прест҃ѣ́й бцⷣѣ [є҆го́же краестро́чїе: …]." — заглавие
        # на канон, колкото и дълго да е краестрочието.
        if len(s) <= 220 and re.match(r'^(инъ |другій )?канѡнъ\b', n):
            return True
        if len(s) > 140 or not self.KW.match(n):
            return False
        return s.endswith((':', ',')) or ' гласъ ' in ' ' + n + ' ' or \
            (s.endswith('.') and len(s) < 70)

    def only_black(self, runs3):
        return self.apply(runs3) if not any(r for r, t, _ in runs3 if t.strip()) else runs3

    def apply(self, runs3):
        """Абзацът без червено → със червено, по научените указания."""
        text = ''.join(t for _, t, _ in runs3)
        s = text.strip()
        if not s:
            return runs3
        if self.norm(s) in self.full:
            return [(True, t, b) for _, t, b in runs3]
        lead = len(text) - len(text.lstrip())
        best = 0
        for m in re.finditer(r'[:,.]', s[:160]):
            if self.norm(s[:m.end()]) in self.lab:
                best = m.end()
        if not best:
            if self.generic(s):
                return [(True, t, b) for _, t, b in runs3]
            return runs3
        cut, out, pos = lead + best, [], 0
        for _, t, b in runs3:
            a, z = pos, pos + len(t)
            if z <= cut:
                out.append((True, t, b))
            elif a >= cut:
                out.append((False, t, b))
            else:
                out.append((True, t[:cut - a], b))
                out.append((False, t[cut - a:], b))
            pos = z
        return out


# ⚠ РЕДОВЕ-УКАЗАНИЯ В ОКТОИХА — изцяло червени, във ВСИЧКИ гласове.
# Изворът и в изрядната си част ги дава само отчасти червени („Та́же," в
# червено, „Ны́нѣ ѿпꙋща́еши: Трист҃о́е…" в черно), а те са указание от край
# до край (указание на потребителя, 04.10.2026). Черно остава само онова,
# което се ЧЕТЕ: началото на подобника след „Подо́бенъ:" и стихът след
# „Сті́хъ:" в прокимена.
INSTR_START = re.compile(
    r'^(Та́же|Посе́мъ|Вхо́дъ|І҆ере́й|Степє́нна|Гдⷭ҇и поми́лꙋй, три́жды|'
    r'Сла́ва, и҆ ны́нѣ, бг҃оро́диченъ, не сѣдѧ́ще|По катава́сїи|По непоро́чныхъ)')
INSTR_MAX = 260


def _instr_html(plain):
    e = lambda t: html.escape(t, quote=False)
    red = lambda t: '<span class="rubric">%s</span>' % e(t) if t.strip() else e(t)
    i = plain.find('Подо́бенъ:')
    if i >= 0:
        j = i + len('Подо́бенъ:')
        return 'text', red(plain[:j]) + e(plain[j:])
    i = plain.find('Сті́хъ:')
    if i >= 0:
        j = i + len('Сті́хъ:')
        k = plain.find('Та́же', j)
        k = len(plain) if k < 0 else k
        return 'text', red(plain[:j]) + e(plain[j:k]) + red(plain[k:])
    return 'rubric', e(plain)


# ⚠ ПРИЛОЖЕНИЯТА В КРАЯ НА ОКТОИХА имат свои указания — моделът ги няма,
# защото в седмичните служби не се срещат (указание на потребителя,
# 04.10.2026). Цели червени редове и червени етикети отпред:
APP_FULL = re.compile(
    r'^(Ѹ҆́треннѧѧ стїхи́ра, гла́съ|Пѣ̑сни трⷪ҇чны\.|Е҆ѵⷢ҇лїе воскрⷭ҇но |Е҆ѵⷢ҇лїе ѿ |'
    r'А҆пⷭ҇лъ (?:къ|ѿ) |Свѣти́ленъ, гла́съ|Свѣти́льны подо́бнѣ|И҆ мл҃тва глаго́летсѧ|'
    r'И҆ ѿпꙋ́стъ, и҆ проще́нїе|А҆ллилꙋ́їа, три́жды|Прокі́мены, и҆ а҆по́стѡлы|'
    r'И҆ по ко́емждо стїсѣ̀)')
APP_LABEL = re.compile(
    r'^((?:Е҆ѯапостїла́рїй \S+?|Прича́стенъ|Крⷭ҇тобг҃оро́диченъ|Подо́бенъ|Подо́бны|'
    r'Дрꙋгі́й|Гла́съ \S+?|А҆ллилꙋ́їа, гла́съ \S+?|И҆ ѹ҆ме́ршымъ, гла́съ \S+?|'
    r'Въ понедѣ́льникъ(?: ѹ҆́бѡ)?|Во вто́рникъ|Въ сре́дꙋ(?: и҆ пѧто́къ)?|Въ четверто́къ|'
    r'Въ пѧто́къ|Въ сꙋббѡ́тꙋ|Во второ́мъ же|Въ пе́рвомъ ѹ҆́бѡ):)(\s)')


# ⚠ „Сподо́би гдⷭ҇и въ ве́черъ се́й:" насред червено указание е ЧЕРЕН текст
# с червена първа буква: това е началото на молитвата, която се чете от
# Часослова, и без това окото я прескача заедно с указанието около нея
# (указание на потребителя, 04.10.2026).
SPODOBI = re.compile(r'Сподо́би гдⷭ҇и(?:,? въ ве́черъ(?: се́й)?)?:?')


def _runs_of(b):
    """Блокът → [(червено, текст)] (rubric = изцяло червен)."""
    if b['kind'] == 'rubric':
        return [(True, html.unescape(b['html']))]
    out = []
    for m in re.finditer(r'<span class="rubric">(.*?)</span>|([^<]+)', b['html']):
        if m.group(1) is not None:
            out.append((True, html.unescape(m.group(1))))
        elif m.group(2):
            out.append((False, html.unescape(m.group(2))))
    return out


def _spodobi_black(b):
    runs = _runs_of(b)
    plain = ''.join(t for _, t in runs)
    m = SPODOBI.search(plain)
    if not m:
        return
    mask = []
    for r, t in runs:
        mask += [r] * len(t)
    for i in range(m.start() + 1, m.end()):
        mask[i] = False
    mask[m.start()] = True                     # червената буква
    parts, i = [], 0
    while i < len(plain):
        j = i
        while j < len(plain) and mask[j] == mask[i]:
            j += 1
        seg = html.escape(plain[i:j], quote=False)
        parts.append('<span class="rubric">%s</span>' % seg if mask[i] else seg)
        i = j
    b['kind'], b['html'] = 'text', ''.join(parts)


# ⚠ СЛУЖЕБНИКЪТ — изрази, червени навсякъде, където се срещнат (указание на
# потребителя, 04.10.2026). Сравнението е в NFD — ударението в извора е ту
# готова буква („ѝ"), ту отделен знак.
SLUJ_RED = [
    r'Та́же глаго́лемъ шестоѱа́лмїе, со всѧ́кимъ внима́нїемъ и҆ стра́хомъ бж҃їимъ, ꙗ҆́кѡ '
    r'самомꙋ̀ собесѣ́дꙋюще хрⷭ҇тꙋ̀ бг҃ꙋ на́шемꙋ неви́димѡ, и҆ молѧ́ще ѡ҆ грѣсѣ́хъ на́шихъ\. '
    r'По трїе́хъ же ѱалмѣ́хъ і҆ере́й глаго́летъ мл҃твы ѹ҆́трєннїѧ, стоѧ́й непокрове́нъ '
    r'пред̾ ст҃ы́ми две́рьми\.',
    r'Си́це въ ко́емждо проше́нїи два̀, и҆лѝ трѝ и҆́мени глаго́лати\.',
    r'А҆́ще под̾ митрополі́томъ, приглаго́летъ:',
    r'а҆́ще въ монастырѣ̀:', r'а҆́ще є҆́сть:', r'а҆́ще ли ѻ҆би́тель,',
    r'Та́же глаго́летъ:', r'Та́же, тропарѝ:', r'И҆ глаго́лемъ:', r'Возгла́съ:',
    r'Сла́ва:', r'И҆ ны́нѣ:', r'та́же,', r'и҆́мⷬ҇къ:?', r'\[', r'\]',
]
# В „Сла́ва, ст҃а́гѡ: И҆ ны́нѣ, бг҃оро́диченъ." червени са САМО „Сла́ва," и
# „И҆ ны́нѣ," — останалото е черно.
SLUJ_ONLY = re.compile(unicodedata.normalize(
    'NFD', r'(Сла́ва,)( ст҃а́гѡ: )(И҆ ны́нѣ,)( бг҃оро́диченъ\.)'))
SLUJ_RE = re.compile('|'.join(unicodedata.normalize('NFD', x) for x in SLUJ_RED))


def _nfd_map(t):
    out, idx = [], []
    for i, ch in enumerate(t):
        for c in unicodedata.normalize('NFD', ch):
            out.append(c)
            idx.append(i)
    return ''.join(out), idx


def _runs_html(plain, mask):
    parts, i = [], 0
    while i < len(plain):
        j = i
        while j < len(plain) and mask[j] == mask[i]:
            j += 1
        seg = html.escape(plain[i:j], quote=False)
        parts.append('<span class="rubric">%s</span>' % seg if mask[i] else seg)
        i = j
    return ''.join(parts)


SLUJ_INSTR_END = re.compile(
    r'(глаго́лѧ|глаго́летъ|гл҃етъ|гл҃ѧ|возглаша́етъ|си́це|мо́литсѧ)[^:]{0,15}:$')


def slujebnik_instructions(units):
    """Указанията към свещеника и дякона — изцяло червени.

    Онлайн изданието оцветява често само първата дума („Та́же покро́вцы ѹ҆́бѡ
    взе́мъ… глаго́лѧ:"), а в .epub-а някои са изцяло черни. Признакът е
    СТРУКТУРЕН: абзац, който свършва с „глаго́лѧ:"/„глаго́летъ:" и подобни, и
    е или изцяло черен, или с ЕДИН къс червен етикет отпред (потребителят,
    05.10.2026). Не важи за „Учително известие" — там е проза.
    """
    for u in units:
        for b in u['blocks']:
            if b['kind'] != 'text':
                continue
            h = b['html']
            m = re.match(r'^<span class="rubric">([^<]{1,25})</span>(.*)$', h, re.S)
            rest = m.group(2) if m else h
            if '<' in rest:
                continue
            # „Сщ҃е́нникъ та́йнѡ: Подо́бнѣ и҆ ча́шꙋ по ве́чери, глаго́лѧ:" — след
            # етикет „та́йнѡ:" иде САМАТА молитва, не указание
            if m and m.group(1).rstrip().endswith('та́йнѡ:'):
                continue
            plain = html.unescape(re.sub(r'<[^>]+>', '', h)).strip()
            if len(plain) > 40 and SLUJ_INSTR_END.search(plain):
                b['kind'] = 'rubric'
                b['html'] = html.escape(plain, quote=False)


def slujebnik_phrases(units):
    for u in units:
        for b in u['blocks']:
            if b['kind'] not in ('text', 'rubric'):
                continue
            runs = _runs_of(b)
            plain = ''.join(t for _, t in runs)
            mask = [r for r, t in runs for _ in t]
            nfd, idx = _nfd_map(plain)
            hit = False
            for m in SLUJ_ONLY.finditer(nfd):
                for g, red in ((1, True), (2, False), (3, True), (4, False)):
                    for k in range(m.start(g), m.end(g)):
                        mask[idx[k]] = red
                hit = True
            for m in SLUJ_RE.finditer(nfd):
                for k in range(m.start(), m.end()):
                    mask[idx[k]] = True
                hit = True
            if not hit:
                continue
            if all(mask):
                b['kind'], b['html'] = 'rubric', html.escape(plain, quote=False)
            else:
                b['kind'], b['html'] = 'text', _runs_html(plain, mask)


def oktoih_instructions(units, appendix=False):
    for ui, u in enumerate(units):
        # Заглавните редове в НАЧАЛОТО на приложение („Нача́ло воскре́сныхъ
        # є҆ѯапостїла̑рїй, и҆ ѹ҆́треннихъ…", „Трⷪ҇чны сїѧ̑ григо́рїѧ сїнаи́та,
        # пѣва́емы…") — до първия ред, който вече е съдържание.
        if appendix and ui == 0:
            for b in u['blocks']:
                plain = html.unescape(re.sub(r'<[^>]+>', '', b['html'])).strip()
                if b['kind'] == 'rubric':
                    continue
                if b['kind'] != 'text' or APP_LABEL.match(plain + ' ') or \
                        APP_FULL.match(plain) or len(plain) > 220 or \
                        b['html'].startswith('<span class="rubric">'):
                    break
                b['kind'], b['html'] = 'rubric', html.escape(plain, quote=False)
        for b in u['blocks']:
            if b['kind'] != 'text':
                continue
            plain = html.unescape(re.sub(r'<[^>]+>', '', b['html'])).strip()
            if appendix and len(plain) <= 160 and APP_FULL.match(plain):
                b['kind'], b['html'] = 'rubric', html.escape(plain, quote=False)
                continue
            if appendix and not b['html'].startswith('<span class="rubric">'):
                b['html'] = APP_LABEL.sub(r'<span class="rubric">\1</span>\2', b['html'], count=1)
            if len(plain) <= INSTR_MAX and INSTR_START.match(plain):
                b['kind'], b['html'] = _instr_html(plain)
                continue
            # „Гла́съ и҃, бг҃оро́диченъ:" — кратък ред-указание (не химн като
            # „Гла́съ тѝ прино́симъ разбо́йничь…").
            if len(plain) < 60 and re.match(r'^Гла́съ \S+?[,.:]', plain):
                b['kind'], b['html'] = 'rubric', html.escape(plain, quote=False)
                continue
            h = b['html']
            # „І҆рмо́съ то́йже." / „И҆́нъ. І҆рмо́съ:" в началото — етикет.
            h = re.sub(r'^((?:И҆́нъ\.? )?І҆рмо́съ(?: то́йже)?[.:])',
                       r'<span class="rubric">\1</span>', h)
            # „[Два́жды.]" в края на химна — указание.
            h = re.sub(r'(\[(?:Два́жды|Три́жды)\.?\])', r'<span class="rubric">\1</span>', h)
            # „И҆ ны́нѣ, то́йже." — „то́йже" е част от етикета.
            h = re.sub(r'<span class="rubric">((?:И҆ ны́нѣ|Сла́ва),)</span> (то́йже[.:,])',
                       r'<span class="rubric">\1 \2</span>', h)
            # Указания НАСРЕД реда, вън от червен откъс: „А҆нтїфѡ́нъ в҃:",
            # „Прокі́менъ, гла́съ ѕ҃:", „Сті́хъ:".
            parts = re.split(r'(<span class="rubric">.*?</span>)', h)
            for i in range(0, len(parts), 2):
                parts[i] = re.sub(
                    r'((?:А҆нтїфѡ́нъ \S+?|Прокі́менъ,? гла́съ \S+?|Сті́хъ(?: \S{1,3}?)?):)',
                    r'<span class="rubric">\1</span>', parts[i])
            b['html'] = ''.join(parts)
        for b in u['blocks']:
            if b['kind'] in ('text', 'rubric'):
                _spodobi_black(b)


def chapter_units(body, model=None):
    p = ParaParser()
    p.feed(body)
    if model:
        p.paras = [model(r) if callable(model) else model.apply(r) for r in p.paras]
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
        # ⚠ „І҆рмо́съ:" на ОТДЕЛЕН ред → етикет пред текста на ирмоса под
        # него. Четецът смалява ирмоса само ако блокът му ПОЧВА с червен
        # етикет „…рмо́съ…" (`MolBlock.isIrmos`); отделен, етикетът оставяше
        # ирмоса с размера на тропарите (указание на потребителя, 04.10.2026).
        bl = u['blocks']
        k = 0
        while k < len(bl) - 1:
            lab = bl[k]['html']
            # ⚠ Буквицата (`<span>Ѿ</span>` отпред) НЕ пречи — без това 55
            # ирмоса в Минеите („И҆́нъ. І҆рмо́съ:" + буквица) оставаха едри.
            nxt = bl[k + 1]['html'] if k + 1 < len(bl) else ''
            lead = re.match(r'<span class="rubric">(.*?)</span>', nxt)
            if (bl[k]['kind'] == 'rubric' and len(lab) <= 80
                    and re.search(r'рмо́съ(?: то́йже|, гла́съ \S+)?[.:]?$', lab)
                    and bl[k + 1]['kind'] == 'text'
                    and (not lead or len(lead.group(1).strip()) <= 2)):
                bl[k + 1]['html'] = '<span class="rubric">%s</span> %s' % (
                    lab, bl[k + 1]['html'])
                del bl[k]
            k += 1
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
        for bad, good in SOURCE_FIXES:
            h = h.replace(bad, good)
        yield label, h[h.find('<body'):]


# ⚠ Поправки в самия HTML на извора — точно по низ, за да не пипат нищо друго.
# Великото повечерие: `<span class="kinovar">` пред „Могꙋ́щїи" не се затваря и
# червеното „изтичаше" до края на службата — „С нами Бог", Символът,
# молитвите („Нескве́рнаѧ…", „И҆ да́ждь на́мъ влⷣко…") излизаха като
# указания. Червена трябва да е само буквицата (както в съседните стихове).
# ⚠ Общо нулиране на таговете при всеки <p> НЕ става: в Типикона
# червеното нарочно минава през няколко незатворени абзаца (заглавията на
# главите) и там би станало черно.
# Полунощницата (края): буквицата „Г" е вложена като ОТДЕЛЕН абзац вътре в
# указанието, тъй че редът „Гдⷭ҇и и҆ влⷣко живота̀ моегѡ̀: и҆ покло́нъ є҆ди́нъ
# вели́кїй." излизаше като самотно „Г" и текст без буквица (потребителят).
SOURCE_FIXES = [
    ('<span class="kinovar">Могyщіи покарsйтесz:',
     '<span class="kinovar">М</span>огyщіи покарsйтесz:'),
    ('мlтву всю2: \n\n<p class="calibre6">Г</p></span>Dи и3 вLко животA моегw2:',
     'мlтву всю2:</span>\n\n</p><p class="calibre6"><span class="kinovar">Г</span>Dи и3 вLко животA моегw2:'),
]


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


def split_morning_prayers(out):
    """Началото на Часослова → СВОЙ раздел „Молитви след ставане".

    ⚠ В извора то е част от Полунощницата: „ЧАСОСЛО́ВЪ", изданието,
    посвещението и последованието след ставане от сън, и чак тогава
    „Нача́ло полꙋ́нощницы". (Указание на потребителя, 03.10.2026.)
      • новият раздел е БЕЗ горно заглавие (`notitle`) — „ЧАСОСЛО́ВЪ" е
        заглавие на самия текст: това е началото на книгата;
      • Полунощницата започва с „Нача́ло полꙋ́нощницы".
    ⚠ Номерът е 1000 — свободен (номерацията почва от 1001). Така номерата
    на всички останали раздели не се местят и отметките остават верни.
    ⚠ Вътрешните препратки сочат Полунощницата по ИМЕ и ТЕКСТ, тъй че не се
    пипат (броят им се проверява в [fix_small_compline]).
    """
    i = next(k for k, s in enumerate(out)
             if s['book'] == 'Часослов' and s['title_bg'] == 'Полунощница')
    sec = out[i]
    if len(sec['units']) != 1:
        sys.exit('⚠ Полунощница: очаквана една единица, има %d' % len(sec['units']))
    u = sec['units'][0]
    plain = lambda b: html.unescape(re.sub(r'<[^>]+>', '', b['html'])).strip()
    k = next((j for j, b in enumerate(u['csl'])
              if plain(b).startswith('Нача́ло полꙋ́нощницы')), None)
    if k is None or plain(u['csl'][0]) != 'ЧАСОСЛО́ВЪ':
        sys.exit('⚠ Полунощница: не е намерено „ЧАСОСЛО́ВЪ"/„Нача́ло полꙋ́нощницы"')
    head = {'n': 0, 'title_csl': None, 'title_bg': None,
            'title_cs': plain(u['csl'][0]),
            'csr': [], 'bg': [], 'csl': u['csl'][1:k], 'sources': []}
    u['csl'] = u['csl'][k:]
    out.insert(i, {**{x: sec[x] for x in sec if x != 'units'},
                   'sec': 1000, 'title_bg': 'Молитви след ставане',
                   'notitle': True, 'units': [head]})


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
                # Краят на Малкото повечерие → краят на Великото, на
                # отпуста (указание на потребителя). Препратката е насред
                # червено указание в обикновен абзац — span-ът се разделя,
                # а връзката носи класа, за да остане винена.
                # ⚠ По израз, не по низ: надредните знаци в извора са
                # разложени („и"+U+0300), а не „ѝ".
                h2 = re.sub(
                    r'(въ )(конц\S+ вел\S+ повеч\S+?)\.</span>',
                    r'\1</span><a href="mol:Часослов/Велико повечерие'
                    r'#И҆ а҆́бїе сщ҃е́нникъ возглаша́етъ" class="rubric">'
                    r'\2</a><span class="rubric">.</span>', h2)
                # Краят на Великото повечерие („И҆ прѡ́чаѧ, ꙗ҆́коже предпи́сано
                # въ полꙋ́нощницѣ") → ектенията в Полунощницата (потребителят).
                h2 = re.sub(
                    r'(предпи\S* въ полꙋ\S*нощницѣ)\.$',
                    r'<a href="mol:Часослов/Полунощница'
                    r'#Помо́лимсѧ ѡ҆ вели́комъ господи́нѣ и҆ ѻ҆тцѣ̀">\1</a>.', h2)
                if h2 != h:
                    b['html'] = h2
                    links += 1
    if links != 4:
        sys.exit('⚠ Часослов: очаквани 4 вътрешни препратки, намерени %d' % links)
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
        chs = list(chapters(IN / fname))
        # ⚠ Октоихът: от сряда на глас 4 нататък изворът е БЕЗ червено —
        # учи се от главите, които го имат (виж [RubricModel]).
        model = RubricModel(chs) if book == 'oktoih' else None
        # ⚠ Служебникът: в .epub-а няма червено — то се пренася от онлайн
        # изданието на azbyka.ru (виж [RedTransfer]).
        if book == 'slujebnik':
            model = RedTransfer(SLUJ_ONLINE)
            bg_log = []
        for label, body in chs:
            # ⚠ „Без червено" = под 20 означения: петъкът на глас 6 има ЕДНО
            # и с проверка „няма нито едно" оставаше цял ден черен.
            if book == 'slujebnik':
                fix = model.apply
            else:
                fix = model.apply if model and body.count('kinovar') < 20 else None
                # В изрядните глави — само на абзаци БЕЗ НИТО ЕДНО червено:
                # изворът и там е изпускал по някой ред („Бг҃оро́диченъ:Ли́къ…").
                if model and not fix:
                    fix = model.only_black
            us = chapter_units(body, fix)
            if book == 'oktoih':
                oktoih_instructions(us, appendix=not label.startswith('Глас'))
            if book == 'slujebnik':
                slujebnik_phrases(us)
                if 'учительное' not in label:   # то е проза, не служба
                    slujebnik_instructions(us)
                # ⚠ етикетите са РУСКИТЕ от .epub-а („Литургия апостола Иакова",
                # „Известие учительное"), не българските заглавия
                if 'Иакова' not in label:   # литургиите на ап. Яков са друго издание
                    sluzhebnik_bg.apply(us, bg_log)
            raw.append((fname, book, bname, label, us))
        if book == 'slujebnik':
            (W / 'sluzhebnik_bg_log.txt').write_text(
                '\n'.join('%s\t%s' % x for x in bg_log), encoding='utf-8')
            (W / 'sluzhebnik_red_missed.txt').write_text('\n'.join(model.missed), encoding='utf-8')
            print('Служебник: червеното от онлайн изданието; без съответствие %d абзаца'
                  ' → work/sluzhebnik_red_missed.txt' % len(model.missed))
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
    split_morning_prayers(out)
    fix_small_compline(out)
    expand_page_refs(out)
    (W / 'bogosluzhebni.json').write_text(json.dumps(out, ensure_ascii=False, indent=1),
                                          encoding='utf-8')
    n_bl = sum(len(u['csl']) for s in out for u in s['units'])
    print('→ work/bogosluzhebni.json: %d раздела, %d блока' % (len(out), n_bl))


if __name__ == '__main__':
    main()
