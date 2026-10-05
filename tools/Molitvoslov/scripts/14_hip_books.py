#!/usr/bin/env python3
"""Миней празничен, Миней общ и Псалтир с последования (HIP, orthlib.ru) →
work/hip_books.json.

    python3 14_hip_books.py        # после 05_build_db.py

Изворите са в input/newBooks2/ (pm.rar, obschminea/*.rar, sp.rar) и се
разархивират в work/ при всяко пускане. Преобразуването е в `hip.py`.

Двата минея влизат в книгата „Минеи" като групи СЛЕД месеците, а
Псалтирът с последования — като своя книга най-отдолу (решение на потребителя,
05.10.2026).

⚠⚠ ЧЕРВЕНОТО. Общият миней го носи сам (`%<…%>`). Празничният и
Псалтирът с последования — НЕ (нито един знак). Там то се ПРЕНАСЯ ПО СЪДЪРЖАНИЕ
от вече оцветените цс текстове в molitvoslov.db (месечните Минеи носят
същите празнични служби, Часословът и Канонникът — молитвите и
последованията): абзацът се търси по началото си, подравнява се знак по знак
и маската се копира — текстът остава от HIP. Ненамереното минава през
правилата от Ирмология (`rules`). Отчет: work/hip_books_report.txt.
⚠ Затова РЕДЪТ: базата трябва да е сглобена ПРЕДИ това пускане — справката
се чете от нея (само разделите под 5000, т.е. без тези книги).
"""
import difflib
import html
import json
import re
import sqlite3
import subprocess
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

import hip

ROOT = Path(__file__).resolve().parents[1]
W = ROOT / 'work'
IN = ROOT / 'input' / 'newBooks2'
DB = ROOT.parents[1] / 'assets' / 'db' / 'molitvoslov.db'
SRC = {'pm': 'http://www.orthlib.ru/worship/mineya/#pm',
       'om': 'http://www.orthlib.ru/worship/obschminea/',
       'sp': 'http://www.orthlib.ru/worship/sledpsalt/'}

# ───────────────────────────── заглавията ─────────────────────────────

PM = [  # файл → заглавие (по реда на църковната година)
    ('sep/01indict', '1 септември: Начало на индикта – църковната нова година'),
    ('sep/08rogdestvo', '8 септември: Рождество на Пресвета Богородица'),
    ('sep/14vozdv', '14 септември: Въздвижение на Честния и Животворящ Кръст'),
    ('sep/25serg', '25 септември: Преподобни Сергий Радонежки'),
    ('sep/26john', '26 септември: Преставление на св. апостол и евангелист Йоан Богослов'),
    ('oct/01pokr', '1 октомври: Покров на Пресвета Богородица'),
    ('oct/05stmosk', '5 октомври: Светителите московски Петър, Алексий, Йона и Филип'),
    ('oct/22kazan', '22 октомври: Казанска икона на Божията Майка'),
    ('oct/26dimsol', '26 октомври: Св. великомъченик Димитрий Мироточиви'),
    ('nov/08michail', '8 ноември: Събор на св. архистратиг Михаил и на всички безплътни сили'),
    ('nov/21vved', '21 ноември: Въведение на Пресвета Богородица в храма'),
    ('dec/06nicola', '6 декември: Св. Николай Мирликийски Чудотворец'),
    ('dec/praot', 'Неделя на светите праотци'),
    ('dec/svotec', 'Неделя на светите отци'),
    ('dec/24predprazd', '24 декември: Предпразненство на Рождество Христово'),
    ('dec/navech', 'Царските часове в навечерието на Рождество Христово'),
    ('dec/25christm', '25 декември: Рождество Христово'),
    ('dec/nedpor', 'Неделя след Рождество Христово'),
    ('jan/01obrez', '1 януари: Обрезание Господне'),
    ('jan/05prkg', '5 януари: Предпразненство на Богоявление'),
    ('jan/05chkg', 'Царските часове в навечерието на Богоявление'),
    ('jan/06bogoyav', '6 януари: Свето Богоявление'),
    ('jan/30trehsv', '30 януари: Събор на трима светители'),
    ('feb/02sr', '2 февруари: Сретение Господне'),
    ('mar/25blgv', '25 март: Благовещение на Пресвета Богородица'),
    ('apr/23geor', '23 април: Св. великомъченик Георгий Победоносец'),
    ('may/09nicola', '9 май: Пренасяне на мощите на св. Николай Чудотворец'),
    ('may/11mefkir', '11 май: Св. равноапостолни Методий и Кирил, учители славянски'),
    ('may/21konsel', '21 май: Св. равноапостолни цар Константин и царица Елена'),
    ('jun/24john', '24 юни: Рождество на св. Йоан Кръстител'),
    ('jun/29petr_pavel', '29 юни: Св. първовърховни апостоли Петър и Павел'),
    ('jul/10antoniy', '10 юли: Преподобни Антоний Печерски'),
    ('jul/15vladimir', '15 юли: Св. равноапостолен княз Владимир'),
    ('jul/20ilia', '20 юли: Св. пророк Илия'),
    ('jul/22magdalina', '22 юли: Св. равноапостолна Мария Магдалина'),
    ('aug/01krest', '1 август: Изнасяне на Честния и Животворящ Кръст'),
    ('aug/06preobr', '6 август: Преображение Господне'),
    ('aug/15uspen', '15 август: Успение на Пресвета Богородица'),
    ('aug/16spastr', '16 август: Пренасяне на Неръкотворния образ Христов'),
    ('aug/29usekn', '29 август: Отсичане на главата на св. Йоан Кръстител'),
    ('aug/30alexnevsk', '30 август: Пренасяне на мощите на св. Александър Невски'),
    ('parem', 'Паримии на празниците'),
]

OM = [  # глава → заглавие (по съдържанието на книгата)
    ('iz', 'Кратко указание за службите'),
    ('01', 'Обща служба на Господските празници, предпразненства и попразненства'),
    ('02', 'Служба на Богородичните празници'),
    ('03', 'Служба на Честния и Животворящ Кръст'),
    ('04', 'Служба на светите ангели'),
    ('05', 'Служба на св. Йоан Предтеча'),
    ('06', 'Служба на светите отци'),
    ('07', 'Обща служба на пророк'),
    ('08', 'Служба на апостол'),
    ('09', 'Служба на апостоли'),
    ('10', 'Служба на светител'),
    ('11', 'Служба на светители'),
    ('12', 'Служба на преподобен'),
    ('13', 'Служба на преподобни'),
    ('14', 'Служба на мъченик'),
    ('15', 'Служба на мъченици'),
    ('16', 'Служба на свещеномъченик'),
    ('17', 'Служба на свещеномъченици'),
    ('18', 'Служба на преподобномъченик'),
    ('19', 'Служба на преподобномъченици'),
    ('20', 'Служба на мъченица'),
    ('21', 'Служба на мъченици (жени)'),
    ('22', 'Служба на преподобна жена'),
    ('23', 'Служба на преподобни жени'),
    ('24', 'Служба на преподобномъченица'),
    ('25', 'Служба на свещеноизповедник и преподобноизповедник'),
    ('26', 'Служба на безсребреници и чудотворци'),
    ('27', 'Служба на юродиви заради Христа'),
    ('28', 'Възкресна служба на глас 6'),
    ('29', 'Обща служба за всеки ден'),
    ('30', 'Богородични на „Господи, воззвах“ и на стиховните, възкресни на осемте гласа'),
    ('31', 'Отпустителни тропари, кондаци и светилни от Триода'),
    ('32', 'Отпустителни възкресни тропари на Октоиха, с богородичните, ипакоите и кондаците'),
    ('33', 'Възкресни тропари след Непорочните в неделите на цялата година'),
    ('34', 'Заупокойни тропари след Непорочните в събота'),
    ('35', 'Богородични отпустителни за цялата година'),
    ('36', 'Отпустителни тропари за цялата седмица'),
    ('37', 'За знаците на Господските, Богородичните и светийските празници'),
    ('38', 'Месецослов за цялата година'),
    ('39', 'Общи паримии на всеки светия'),
    ('40', 'Общи прокимени, апостоли, алилуиари, евангелия и причастни на светиите'),
    ('41', 'Общи апостоли и евангелия на всеки светия'),
]

SP = [
    ('01ps', None),        # Псалтирът — дели се по-долу на катизми
    ('02ishod', 'Последование при изход на душата от тялото'),
    ('03slad', 'Служба с акатист на Сладчайшия Иисус'),
    ('04ob', 'Обща служба за всеки ден на Господа нашего Иисуса Христа'),
    ('05akaf_bogor', 'Служба с акатист на Пресвета Богородица'),
    ('06k_bogor', 'Молебен канон на Пресвета Богородица'),
    ('07k_ang1', 'Канон на Ангела Пазител'),
    ('08k_ang2', 'Молебен канон на Ангела Пазител (друг)'),
    ('09k_arhang', 'Стихири и канон на безплътните сили – в понеделник'),
    ('10k_prdt', 'Стихири и канон на св. Йоан Предтеча – във вторник'),
    ('11k_odig', 'Стихири и канон на Пресвета Богородица Одигитрия – в сряда'),
    ('12k_nicap', 'Стихири и канони на апостолите и на св. Николай – в четвъртък'),
    ('13k_krest', 'Стихири и канон на Честния Кръст – в петък'),
    ('14k_cv', 'Стихири и канон на всички светии – в събота'),
    ('15m_utr', 'Утринни молитви'),
    ('16m_vech', 'Молитви преди сън'),
    ('17ko_prich', 'Последование за Светото Причастие'),
    ('18po_prich', 'Молитви след Светото Причастие'),
]
NUM = ['', 'първа', 'втора', 'трета', 'четвърта', 'пета', 'шеста', 'седма', 'осма',
       'девета', 'десета', 'единадесета', 'дванадесета', 'тринадесета', 'четиринадесета',
       'петнадесета', 'шестнадесета', 'седемнадесета', 'осемнадесета', 'деветнадесета',
       'двадесета']

# ───────────────────────────── сгъването ─────────────────────────────

MAP = str.maketrans({'ᲂ': '', 'ꙋ': 'у', 'ѹ': 'у', 'ѡ': 'о', 'ѿ': 'от', 'ꙗ': 'я',
                     'ѧ': 'я', 'є': 'е', 'ѕ': 'з', 'і': 'и', 'ї': 'и', 'ѻ': 'о',
                     'ѳ': 'ф', 'ѵ': 'и', 'ꙁ': 'з', 'ѣ': 'е', 'ꙑ': 'ы', 'ѽ': 'о',
                     'ꙍ': 'о', 'ѯ': 'кс', 'ѱ': 'пс'})


def fold(t):
    """Като `RedTransfer.fold` в 09_bogosluzhebni.py: без надредни, ѐ = е,
    ѹ = оу = у. Връща сгънатото и индекса на всяка негова буква в `t`."""
    out, idx = [], []
    for i, ch0 in enumerate(t):
        ch = unicodedata.normalize('NFD', ch0)[0]
        if unicodedata.category(ch).startswith('M'):
            continue
        for cc in ch.lower().translate(MAP):
            if cc.isalpha():
                if cc == 'у' and out and out[-1] == 'о':
                    out.pop()
                    idx.pop()
                out.append(cc)
                idx.append(i)
    return ''.join(out), idx


def runs_of(h):
    """html на блок → [(червено, текст)]."""
    out = []
    for m in re.finditer(r'<span class="rubric">(.*?)</span>|([^<]+)|<[^>]+>', h, re.S):
        if m.group(1) is not None:
            out.append((True, html.unescape(re.sub(r'<[^>]+>', '', m.group(1)))))
        elif m.group(2) is not None:
            out.append((False, html.unescape(m.group(2))))
    return out


def html_of(runs):
    out = []
    for red, t in runs:
        if not t:
            continue
        e = html.escape(t, quote=False)
        if red and out and out[-1][0]:
            out[-1] = (True, out[-1][1] + e)
        elif not red and out and not out[-1][0]:
            out[-1] = (False, out[-1][1] + e)
        else:
            out.append((red, e))
    return ''.join('<span class="rubric">%s</span>' % e if r else e for r, e in out)


# ───────────────────────────── справката ─────────────────────────────

class Reference:
    """Оцветените цс блокове от базата — един общ низ `G` с маска `M`, и индекс
    по НАЧАЛОТО на всеки блок (първите 12 сгънати букви — и на целия блок, и
    на текста след водещия червен етикет: в HIP етикетът ту е отделен ред,
    ту не е).

    ⚠ Кандидатите са най-много 25, НАЙ-БЛИЗКИТЕ до предишното намерено място:
    общи начала („Сла́ва ѻ҆ц҃ꙋ̀…") дават хиляди, а службата обикновено върви
    подред и в справката. Пробват се по първите 200 знака; пълното
    подравняване е само за победителя.
    """
    K = 12

    def __init__(self):
        db = sqlite3.connect(DB)
        G, M = [], []
        self.idx = defaultdict(list)
        pos = 0
        for kind, h in db.execute(
                "SELECT kind, html FROM blocks WHERE lang='csl' AND section_id < 5000 "
                "ORDER BY section_id, n, ord"):
            f, m = [], []
            for red, t in runs_of(h):
                ff, _ = fold(t)
                f.append(ff)
                m.extend([red or kind == 'rubric'] * len(ff))
            f = ''.join(f)
            if len(f) < 6:
                continue
            self.idx[f[:self.K]].append(pos)
            j = next((i for i, x in enumerate(m) if not x), 0)
            if 0 < j < len(f) - self.K:
                self.idx[f[j:j + self.K]].append(pos + j)
            G.append(f)
            M.extend(m)
            pos += len(f)
        self.G, self.M, self.last = ''.join(G), M, 0

    def mask(self, f):
        """Маската за сгънатия текст `f`, или None."""
        head = f[:200]
        best = None
        for off in (0, 12, 30):
            cands = self.idx.get(f[off:off + self.K])
            if not cands:
                continue
            cands = sorted(cands, key=lambda p: abs(p - self.last))[:25]
            for p in cands:
                start = max(0, p - off)
                win = self.G[start:start + len(head) + 40]
                sm = difflib.SequenceMatcher(None, head, win, autojunk=False)
                got = sum(b.size for b in sm.get_matching_blocks())
                if got >= 0.85 * len(head) and (best is None or got > best[0]):
                    best = (got, start)
            if best:
                break
        if not best:
            return None
        start = best[1]
        win = self.G[start:start + int(len(f) * 1.3) + 20]
        sm = difflib.SequenceMatcher(None, f, win, autojunk=False)
        bl = [b for b in sm.get_matching_blocks() if b.size]
        if sum(b.size for b in bl) < 0.85 * len(f):
            return None
        fm = [None] * len(f)
        for b in bl:
            for k in range(b.size):
                fm[b.a + k] = self.M[start + b.b + k]
        for k in range(len(fm)):
            if fm[k] is None:
                fm[k] = fm[k - 1] if k else next((x for x in fm if x is not None), False)
        self.last = start + bl[-1].b + bl[-1].size
        return fm


# ───────────────────────────── правилата ─────────────────────────────

STARTERS = ('Та́же', 'стїхологисꙋ́емъ', 'Стїхологисꙋ́емъ', 'Посе́мъ', 'Вѣ́домо', 'Подоба́етъ', 'Пое́тсѧ', 'И҆ а҆́бїе', 'И҆ про́чее',
            'А҆́ще', 'По возгла́сѣ', 'По пе́рвомъ', 'И҆ по чи́нꙋ', 'Нача́ло', 'И҆ начина́етъ',
            'На ма́лѣй вече́рни', 'На вели́цѣй вече́рни', 'На ве́лицѣй вече́рни', 'На ѹ҆́трени',
            'На лїтꙋргі́и', 'На стїхо́внѣ', 'На хвали́тєхъ', 'На лїті́и', 'На Гдⷭ҇и воззва́хъ',
            'Въ ве́черъ', 'По а҃-мъ стїхосло́вїи', 'По в҃-мъ стїхосло́вїи', 'По полѵеле́и',
            'По г҃-й пѣ́сни', 'По ѕ҃-й пѣ́сни', 'Канѡ́нъ', 'Пѣ́снь', 'Гла́съ', 'Ѱало́мъ',
            'Каѳі́сма', 'Мл҃тва', 'Тропарѝ', 'Посе́мъ', 'Сла́ва, и҆ ны́нѣ', 'Творе́нїе',
            'И҆ ѿпꙋ́стъ', 'Ѿпꙋ́стъ', 'Сѣда́ленъ', 'Свѣти́ленъ')
LABEL = re.compile(r'^((?:Сті́хъ(?:\s+\S+)?|Сла́ва|И҆ ны́нѣ|Сла́ва,? и҆ ны́нѣ|Прокі́менъ[^:]{0,20}|'
                   r'Тропа́рь[^:]{0,20}|Конда́къ[^:]{0,20}|І҆́косъ|Ї҆́косъ|Бг҃оро́диченъ|'
                   r'Крⷭ҇тобг҃оро́диченъ|Подо́бенъ|І҆рмо́съ|Сѣда́ленъ[^:]{0,20}|Свѣти́ленъ|'
                   r'Мл҃тва[^:]{0,20}|Ли́къ|Сщ҃е́нникъ|І҆ере́й|Дїа́конъ|Припѣ́въ|Трⷪ҇ченъ):)\s+(\S.*)$',
                   re.S)


RE_VERSE = re.compile(r'^[а-ѵ][҃-҇̀-ͯ]*'
                      r'(?:[а-ѵ][҃-҇̀-ͯ]*){0,3}\. ')
# Заглавие на псалом: без номер на стих отпред, с номера на псалма накрая
# („Ѱало́мъ дв҃дꙋ, в҃", „Въ коне́цъ, ѱало́мъ дв҃дꙋ, і҃.").
RE_PSALM = re.compile(r'^(?![а-ѵ]\S{0,6}\. ).{0,200}[,.]\s*[а-ѵ]\S{0,6}҃\S{0,3}\.?$')


def rules(plain):
    """Червеното по вид — за абзаците без съответствие в справката."""
    s = plain.strip()
    # ⚠ Номериран стих („в҃. Но въ зако́нѣ…") е ТЕКСТ, макар да свършва с
    # „:" — иначе половин Псалтир излиза червен.
    if RE_VERSE.match(s):
        return [(False, s)]
    if re.fullmatch(r'\[[^\[\]]+\]', s) or (len(s) < 150 and s.endswith(':')) \
            or (s.startswith(STARTERS) and len(s) < 300 and not LABEL.match(s)) \
            or (len(s) < 60 and re.match(r'^(Пѣ́снь|Гла́съ|Ѱало́мъ|Каѳі́сма)\b', s)):
        return [(True, s)]
    m = LABEL.match(s)
    out = [(True, m.group(1) + ' '), (False, m.group(2))] if m else [(False, s)]
    # „[…]" насред реда — червено
    res = []
    for red, t in out:
        if red:
            res.append((red, t))
            continue
        pos = 0
        for mm in re.finditer(r'\[[^\[\]]+\]', t):
            res += [(False, t[pos:mm.start()]), (True, mm.group())]
            pos = mm.end()
        res.append((False, t[pos:]))
    return res


def colour(plain, ref, stats):
    f, idx = fold(plain)
    fm = ref.mask(f) if len(f) >= 14 else None
    if fm is None:
        stats['rules'] += 1
        return rules(plain)
    # ⚠ Справката понякога носи същия текст БЕЗ червено („На ма́лѣй
    # вече́рни…" в някой ден на месечния Миней) — тогава решават правилата.
    if not any(fm):
        r = rules(plain)
        if any(red for red, _ in r):
            stats['rules'] += 1
            return r
    stats['ref'] += 1
    cm, li = [], 0
    for i in range(len(plain)):
        while li < len(idx) and idx[li] < i:
            li += 1
        cm.append(fm[li] if li < len(idx) and idx[li] == i else (cm[-1] if cm else fm[0]))
    out = []
    for ch, r in zip(plain, cm):
        if out and out[-1][0] == r:
            out[-1] = (r, out[-1][1] + ch)
        else:
            out.append((r, ch))
    return out


# ───────────────────────────── деленето ─────────────────────────────

SKIP = ('Библиотека святоотеческой', 'orthlib', 'OCR')
RE_SONG = re.compile(r'^Пѣ́снь\s+\S+?[.:]?$')


def paragraphs(path):
    unknown = set()
    ps = hip.convert(path.read_bytes().decode('cp1251'), unknown)
    if unknown:
        print('  ⚠ %s: непознати означения %s' % (path.name, sorted(unknown)))
    out = []
    for p in ps:
        plain = re.sub(r'<[^>]+>', '', html.unescape(p)).strip()
        if not plain or any(x in plain for x in SKIP) or re.fullmatch(r'\(л\.[^)]*\)', plain):
            continue
        out.append((p, plain))
    return out


def blocks_of(paras, ref, stats, own_red):
    """[(html, plain)] → блокове; червеното от извора или пренесено."""
    out = []
    for h, plain in paras:
        if own_red:
            runs = [(r, re.sub(r'\s+', ' ', t)) for r, t in runs_of(h)]
            if not any(r for r, _ in runs):
                runs = rules(plain)
        else:
            runs = colour(re.sub(r'\s+', ' ', plain), ref, stats)
        txt = ''.join(t for _, t in runs).strip()
        if not txt:
            continue
        if all(r or not t.strip() for r, t in runs):
            out.append({'kind': 'rubric', 'html': html.escape(txt, quote=False)})
        else:
            out.append({'kind': 'text', 'html': html_of(runs).strip()})
    return out


def units_of(blocks):
    """Нова молитва при всяка песен на канона — като в месечните Минеи."""
    units = [{'title': None, 'blocks': []}]
    for b in blocks:
        plain = html.unescape(re.sub(r'<[^>]+>', '', b['html']))
        if RE_SONG.match(plain):
            units.append({'title': plain.rstrip('.:'), 'blocks': []})
            continue
        units[-1]['blocks'].append(b)
    return [u for u in units if u['blocks']]


def units_by(blocks, head):
    """Нова молитва при всяко заглавие на псалом (`RE_PSALM`) — то става
    заглавие на молитвата."""
    units = [{'title': None, 'blocks': []}]
    for b in blocks:
        plain = html.unescape(re.sub(r'<[^>]+>', '', b['html'])).strip()
        low = plain.lower()
        if RE_PSALM.match(plain) and ('ѱало́м' in low or 'пѣ́снь' in low or len(plain) < 60):
            units.append({'title': plain.rstrip('.:'), 'blocks': []})
            continue
        units[-1]['blocks'].append(b)
    return [u for u in units if u['blocks']]


def section(sid, book, grp, title, units, src):
    return {'sec': sid, 'tab': 'bogosluzhebni', 'book': book, 'grp': grp,
            'title_bg': title, 'title_csl': None, 'csr_source': None, 'csl_source': src,
            'units': [{'n': k, 'title_csl': u['title'], 'title_bg': None, 'title_cs': None,
                       'csl': u['blocks'], 'csr': [], 'bg': [], 'sources': []}
                      for k, u in enumerate(units)]}


def unrar(rar, dest):
    dest.mkdir(parents=True, exist_ok=True)
    subprocess.run(['unrar', 'x', '-o+', '-inul', str(rar), str(dest) + '/'], check=True)


def main():
    unrar(IN / 'pm.rar', W / 'pm_hip')
    unrar(IN / 'sp.rar', W / 'sp_hip')
    for r in sorted((IN / 'obschminea').glob('*.rar')):
        unrar(r, W / 'om_hip')
    ref = Reference()
    print('справка: %d знака' % len(ref.G))
    out, report = [], []

    stats = defaultdict(int)
    for k, (f, title) in enumerate(PM):
        p = W / 'pm_hip' / 'mineaprazdn' / (f + '.hip')
        if not p.exists():
            sys.exit('⚠ липсва ' + str(p))
        out.append(section(5001 + k, 'Минеи', 'Миней празничен', title,
                           units_of(blocks_of(paragraphs(p), ref, stats, False)), SRC['pm']))
    report.append('Миней празничен: пренесено %(ref)d, по правила %(rules)d' % stats)

    for k, (f, title) in enumerate(OM):
        p = W / 'om_hip' / (f + '.hip')
        if not p.exists():
            sys.exit('⚠ липсва ' + str(p))
        out.append(section(5101 + k, 'Минеи', 'Миней общ', title,
                           units_of(blocks_of(paragraphs(p), ref, None, True)), SRC['om']))

    stats = defaultdict(int)
    sid = 5201
    for f, title in SP:
        p = W / 'sp_hip' / 'sledpsalt' / (f + '.hip')
        if not p.exists():
            sys.exit('⚠ липсва ' + str(p))
        bl = blocks_of(paragraphs(p), ref, stats, False)
        if title:
            out.append(section(sid, 'Псалтир с последования', None, title, units_of(bl), SRC['sp']))
            sid += 1
            continue
        # Псалтирът: начало / 20 катизми / тропарите и молитвите / уставът
        plain = [html.unescape(re.sub(r'<[^>]+>', '', b['html'])) for b in bl]
        cuts = [i for i, t in enumerate(plain) if re.match(r'^Каѳі́сма \S+\.?$', t)]
        tail = next(i for i, t in enumerate(plain) if t.startswith('Ѹ҆ста́въ ст҃ы́хъ ѻ҆тє́цъ'))
        rule = next(i for i, t in enumerate(plain) if t.startswith('Ѹ҆ста́въ ѡ҆ ѱалти́ри'))
        if len(cuts) != 20:
            sys.exit('⚠ Псалтирът: %d катизми вместо 20' % len(cuts))
        parts = [('Молитви преди четене на Псалтира', bl[:cuts[0]], None)]
        for n, (a, z) in enumerate(zip(cuts, cuts[1:] + [tail]), 1):
            parts.append(('Катизма %s' % NUM[n], bl[a + 1:z], 'Ѱало́мъ'))
        parts.append(('Тропари и молитви след катизмите', bl[tail:rule], None))
        parts.append(('Устав за пеенето на Псалтира през годината', bl[rule:], None))
        for t, b, head in parts:
            us = units_by(b, head) if head else units_of(b)
            out.append(section(sid, 'Псалтир с последования', None, t, us, SRC['sp']))
            sid += 1
    report.append('Псалтир с последования: пренесено %(ref)d, по правила %(rules)d' % stats)

    (W / 'hip_books.json').write_text(json.dumps(out, ensure_ascii=False, indent=1),
                                      encoding='utf-8')
    (W / 'hip_books_report.txt').write_text('\n'.join(report) + '\n', encoding='utf-8')
    n = sum(len(u['csl']) for s in out for u in s['units'])
    print('→ work/hip_books.json: %d раздела, %d молитви, %d блока' % (
        len(out), sum(len(s['units']) for s in out), n))
    print('\n'.join(report))


if __name__ == '__main__':
    main()
