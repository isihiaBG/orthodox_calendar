#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Единични четива от разни сайтове — текст И илюстрации.

Трети извор след `tools/lives_bg/` (pravoslavieto.com) и
`tools/lives_mitropolia/` (Софийска митрополия). Разликата: тук НЯМА
указател на сайт и няма засичане по име. Всеки ред в `input/sources.csv`
казва изрично „този светия от календара ← този адрес", защото находките
идват една по една, от различни сайтове.

    python3 apply.py --dry-run      какво би станало
    python3 apply.py                нанася
    python3 apply.py --only Евстат  само този

⚠ ИДЕМПОТЕНТЕН — какво е имало ПРЕДИ нас се пази в `work/originals.json`
и всяко следващо пускане строи от запомненото (същият механизъм като в
tools/lives_bg/06_apply.py; без него повторното пускане лепи четивото
втори път под първото).

⚠ Слъгът се вписва И В СЕМЕТО, не само в assets — инак се губи при
следващото `merge_years.py`.

⚠ ЕДИН СЛЪГ ЗА ВСИЧКИ ПАМЕТИ на един светия. Мнозина имат по две (една
неподвижна и една преходна); четивото е общо, тъй че редовете трябва да
делят слъга — установеният в проекта прецедент (Мария Египетска,
Евфросиния Суздалска). Затова `sources.csv` приема име с `%` за шаблон.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import shutil
import sqlite3
import time
import unicodedata
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parents[1]
CACHE = ROOT / 'cache'
WORK = ROOT / 'work'
INPUT = ROOT / 'input'
LIVES_DB = PROJECT / 'assets' / 'db' / 'lives.db'
CALENDAR_DB = PROJECT / 'assets' / 'db' / 'calendar_old.db'
SEED_DB = PROJECT / 'tools' / 'calendar_gen' / 'input' / 'db' / 'calendar_old.db'
IMAGES_DIR = PROJECT / 'assets' / 'lives_images'

UA = ('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36')
PAUSE = 1.0

RE_DROP = re.compile(r'<(script|style|noscript)\b.*?</\1>', re.S | re.I)
RE_TAG = re.compile(r'<[^>]+>')
# ⚠ Абзаците И картинките се вадят В ЕДИН ОБХОД, за да се запази РЕДЪТ им.
# Взети поотделно, изображенията губят мястото си в разказа и трябва да се
# налучкват после — грешка, платена веднъж в tools/lives_bg (виж README-то
# му: „НЕ се сдвояват с описанието по догадка").
RE_BLOCK = re.compile(r'<p\b[^>]*>(.*?)</p>|<img\b[^>]*>', re.S | re.I)
RE_SRC = re.compile(r'src="([^"]+)"', re.I)

# ⚠⚠ ПРАГЪТ ПО ДЪЛЖИНА Е МАХНАТ (05.09.2026).
#
# Дотук блок под 60 знака отпадаше. Прагът беше груб инструмент: той не
# различава ЧУЖДОТО от СВОЕТО, а просто реже всичко късо — и мълчаливо
# изхвърляше съдържание от източника. Три пъти го откри ПОТРЕБИТЕЛЯТ, а не
# проверка: заглавията „Тропар, гл. 4" и „Кондак, гл. 2", атрибуцията
# („Историческа справка: … Снимки: …") и заглавието на акатиста
# („АКАТИСТ / на / пресветата владичица наша Богородица").
#
# ⚠ Измерено преди махането — без прага влизат 27 допълнителни блока в
# осемте страници, от които ~19 са ИСТИНСКО съдържание. Сред тях две
# изречения от самия разказ („— Радвай се и ти, старче Божий!",
# „Старецът се разтреперил от уплаха."), пет атрибуции, „Празнува се на
# 11 ноември" и начало на молитва.
#
# ⚠ Логиката е ОБЪРНАТА: по подразбиране влиза всичко, а отпада само
# РАЗПОЗНАТО обзавеждане — виж [NOISE] и [NOISE_EXACT]. Същото правило
# вече важи за картинките (`IMG_SKIP` + `exclude_images.csv`).
MIN_PARA = 1

# Докъде блокът е достатъчно КЪС, за да е заглавие на песнопение или
# бележка за източник, а не абзац от разказа — виж [short_but_kept].
# ⚠ Отделно число от [MIN_PARA]: то решава дали блокът ВЛИЗА, а това —
# какъв Е.
SHORT_KIND_MAX = 60

# ⚠ ТОЧНИ съвпадения, не части от текст. Късите низове са опасни като
# подниз: „Виж също" би хванало изречение, което го съдържа. Затова
# обзавеждането от една-две думи стои ТУК, а [NOISE] остава за дълги,
# характерни фрази.
NOISE_EXACT = (
    'Прочете още...', 'Прочете още', 'По-долу:', 'Виж също:', 'Виж също',
    'www.Pravoslavieto.com', 'Pravoslavieto.com', 'Русский | English',
    '+++', 'Благовестник', '• История', '• Молитва', '•История', '•Молитва',
)
MIN_TOTAL = 400
# Обзавеждането на сайтовете — менюта, футъри, бутони. Всеки нов извор
# добавя своите редове тук.
NOISE = (
    'Сподели', 'Прочети още', 'Абонирай', 'бисквитк', 'cookie',
    'Всички права', 'Виж още', 'Публикувано на', 'Категория', 'Тагове',
    'Хронология на богослуженията', 'Официалният сайт',
    'Свързани публикации', 'Вашият коментар', 'Оставете коментар',
    'Последвайте ни', 'Абонамент', 'Търсене',
    # ⚠ ШАБЛОН НА mitropolia-sofia.org, не част от житието: блокът за
    # „Именника на българските светии" и картата стои на ВСЯКА тяхна
    # страница — сверено, среща се и в житието на Симеон Самоковски, и в
    # това на Баташките новомъченици. По-лошо: там пише „Св. преп. Димитра
    # Доростолска", тоест чуждо име насред чуждо житие.
    # (Докладвано от потребителя, 05.09.2026.)
    'Именника на българските светии',
)
# ⚠ Картинки, които са ОБЗАВЕЖДАНЕ, а не илюстрация: лога, иконки, разделители.
# Разпознават се по пътя — същият похват като в tools/lives_bg (там всичко
# извън `icons/` беше стрелки и пликчета за е-поща).
IMG_SKIP = re.compile(
    # ⚠ „heder" (без „a") НЕ е печатна грешка тук: точно така е кръстен
    # файлът на антетката в mitropolia-sofia.org, и заради това тя влизаше
    # като първа „илюстрация" към житието на свщмч. Симеон Самоковски.
    # Сверено срещу базата: в цялото хранилище от 101 картинки само тази
    # една носи „header/heder" в името си.
    r'(logo|banner|header|heder|icon|button|spacer|pixel|avatar|emoji'
    r'|share|feed|rss'
    # ⚠ ОБЗАВЕЖДАНЕТО НА pravoslavieto.com ЖИВЕЕ В `/images/`, а истинските
    # илюстрации — в `/manastiri/`, `/hramove/`, `/poklonnichestvo/` и
    # подобни. Записано е и за tools/lives_bg (виж CLAUDE.md: „всичко в
    # ../images/ е обзавеждане — стрелки и пликчета за е-поща").
    # Тук изплува, когато картинките ВЪТРЕ в абзаци започнаха да се вадят:
    # в житието за връщането на мощите на прп. Йоан Рилски влизаха
    # `skiller.gif` (разделител), `book_open.gif` и `email.gif`.
    r'|pravoslavieto\.com/images/'
    # ⚠ „cropped-" е префиксът, с който WordPress записва ИЗРЯЗАНИЯ хедър на
    # сайта. Той тежи колкото истинска снимка и минава всяка проверка по
    # размер — но е обзавеждане. (Хванат на blagovestnik.bg, 01.09.2026:
    # панорама на Рилския манастир влезе като първа „илюстрация" към
    # житието на иконата.)
    r'|cropped-)',
    re.I)
IMG_MIN_BYTES = 6000        # под това е иконка, не илюстрация


def load_excluded() -> list[str]:
    """Редовете от `input/exclude_images.csv` — колона `url_contains`.

    ⚠ ИЗРИЧЕН СПИСЪК, не правило. Всеки ред е РЕДАКТОРСКО решение с
    обяснение защо, по образеца на `tools/lives_bg/input/exclude_images.csv`.

    ⚠ Съпоставя се по ЧАСТ ОТ АДРЕСА В ИЗВОРА, а не по името на файла в
    `assets/`: то се получава чак след тегленето и носи отпечатък на адреса,
    тъй че по него изключването не може да се напише предварително.

    ⚠ Липсващ файл НЕ е грешка — конвейерът работи и без него.
    """
    path = INPUT / 'exclude_images.csv'
    if not path.exists():
        return []
    out = []
    with path.open(encoding='utf-8') as fh:
        for r in csv.DictReader(fh):
            v = (r.get('url_contains') or '').strip()
            if v:
                out.append(v)
    return out


EXCLUDED_IMAGES = load_excluded()

# ⚠ Панорамните ивици са банери, не илюстрации. Хедърът на сайта е широк
# 4–6 пъти повече, отколкото висок; истинска икона или снимка не е.
IMG_MAX_ASPECT = 3.2


# ⚠ ИСТИНСКА ТРАНСЛИТЕРАЦИЯ, а не `unicodedata.normalize`. NFKD не пипа
# кирилицата — тя просто остава кирилица, а следващият филтър „само a-z0-9"
# я изхвърля цялата. Първият опит така роди слъгове `sv-20-iv-1956`, `sv-1995`
# и голото `sv-`: оцеляваха единствено ЦИФРИТЕ от годините (01.09.2026).
_TRANSLIT = str.maketrans({
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ж': 'zh',
    'з': 'z', 'и': 'i', 'й': 'j', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n',
    'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ф': 'f',
    'х': 'h', 'ц': 'c', 'ч': 'ch', 'ш': 'sh', 'щ': 'sht', 'ъ': 'a',
    'ь': '', 'ю': 'ju', 'я': 'ja', 'ѝ': 'i',
})
# Титли и служебни думи — не отличават светията, само удължават слъга.
_SLUG_DROP = {
    'sv', 'svv', 'svt', 'prp', 'mch', 'mchch', 'vmch', 'svshtmch', 'svshtizp',
    'prpmch', 'ikona', 'na', 'i', 'v', 's', 'pri', 'prez', 'car', 'knjaz',
    'prezviter', 'protoierej', 'ep', 'episkop', 'arhiep', 'mitr', 'patr',
    'presveta', 'bogorodica', 'bozhiej', 'materi',
}


def make_slug(name: str, taken: set[str]) -> str:
    s = name.lower()
    s = re.sub(r'\(.*?\)|†.*?(?=[,;]|$)', ' ', s)     # скоби и „† 1802"
    s = s.translate(_TRANSLIT)
    s = re.sub(r'[^a-z0-9]+', '-', s).strip('-')
    words = [w for w in s.split('-') if w and w not in _SLUG_DROP
             and not w.isdigit()]
    base = f'sv-{"-".join(words[:4])}'[:56].rstrip('-') if words else 'sv-zhitie'
    slug, n = base, 1
    while slug in taken:
        n += 1
        slug = f'{base}-{n}'
    return slug


def fetch(url: str, dest: Path, force: bool = False) -> bytes:
    if dest.exists() and not force and dest.stat().st_size > 500:
        return dest.read_bytes()
    req = urllib.request.Request(url, headers={'User-Agent': UA})
    with urllib.request.urlopen(req, timeout=45) as r:
        data = r.read()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    time.sleep(PAUSE)
    return data


def decode(raw: bytes) -> str:
    for enc in ('utf-8', 'cp1251', 'windows-1251', 'latin-1'):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode('utf-8', 'replace')


# ⚠ ЗАГЛАВИЯТА НА РАЗДЕЛИТЕ в обзорните страници. Част от изворите не дават
# по страница на светия, а една дълга страница с десетки жития, разделени със
# заглавия С ГЛАВНИ БУКВИ („СВ. ГРИГОРИЙ, ЕПИСКОП БЪЛГАРСКИ"). Оттам се взима
# САМО нужният раздел — инак в четивото на един светия влизат другите
# четиридесет. (Поводът: обзорът за светците от Македония, 105 236 знака,
# 01.09.2026.)
RE_SECTION = re.compile(
    r'<(h[1-6]|b|strong|font)\b[^>]*>\s*((?:[^<]|<(?!/?\1))*?)\s*</\1>',
    re.S | re.I)


def cut_section(raw_html: str, wanted: str) -> str:
    """Изрязва раздела, чието заглавие започва с [wanted].

    Спира на СЛЕДВАЩОТО заглавие от същия вид. Празен резултат значи, че
    заглавието не е намерено — тогава се връща цялата страница и това личи
    по дължината ѝ.
    """
    key = re.sub(r'\s+', ' ', wanted).strip().lower()
    if not key:
        return raw_html
    heads = []
    for m in RE_SECTION.finditer(raw_html):
        txt = re.sub(r'\s+', ' ', html.unescape(RE_TAG.sub('', m.group(2)))).strip()
        # ⚠ Само ГЛАВНИ букви и разумна дължина: инак всяко получерно
        # изречение насред текста минава за заглавие на раздел.
        if 8 < len(txt) < 100 and txt == txt.upper():
            heads.append((m.start(), m.end(), txt.lower()))
    start = end = None
    for i, (a, b, txt) in enumerate(heads):
        if start is None and txt.startswith(key):
            start = a
            # краят е следващото заглавие
            end = heads[i + 1][0] if i + 1 < len(heads) else len(raw_html)
            break
    if start is None:
        print(f'      ⚠ разделът „{wanted[:40]}" не е намерен — взима се цялата страница')
        return raw_html
    return raw_html[start:end]


# ⚠⚠ ВЪВЕЖДАЩИТЕ АБЗАЦИ ПРЕДИ САМИЯ РАЗКАЗ.
#
# Част от житията започват с ЦИТАТ (стар препис, свидетелство), последван от
# бележка откъде е той, и чак после тръгва разказът. И двата са изцяло в
# курсив в извора.
#
# ⚠ БЕЗ КЛАС ТЕ ПОЛУЧАВАТ БУКВИЦАТА: `splitDropCap` в четеца търси ГОЛ
# `<p>`, тъй че инициалът пада върху цитата или върху бележката под него,
# вместо върху първите думи на разказа. (Докладвано от потребителя за
# свщмч. Симеон Самоковски, 03.09.2026.)
#
# ⚠ Признакът е СТРУКТУРЕН, не по думи: целият абзац е в `<em>` (или
# `<strong><em>`), и стои ПРЕДИ първия гол абзац. Сверено срещу всичките
# осем страници в sources.csv — засяга ЕДИНСТВЕНО Симеон Самоковски;
# останалите седем имат гол първи абзац и не се променят.
RE_ALL_ITALIC = re.compile(
    r'^\s*(?:<(?:strong|b)>\s*)?<em>.*</em>\s*(?:</(?:strong|b)>\s*)?$', re.S)

# Цитат или бележка за източника му: дългият е цитатът, късият казва откъде
# е той. Границата е с голям запас — в Симеон те са 888 и 73 знака.
EPIGRAPH_MIN = 200

# ⚠⚠ КЪСИ БЛОКОВЕ, КОИТО ВСЕ ПАК ТРЯБВА ДА ВЛЯЗАТ.
#
# `MIN_PARA` (60 знака) отсява менюта и копчета — но с тях изхвърляше и три
# неща, които са част от четивото. Всичките бяха НЕВИДИМИ: текстът на
# тропара и кондака влизаше, а ЗАГЛАВИЯТА им не, тъй че песнопенията стояха
# като безименни абзаци. (Докладвано от потребителя, 05.09.2026.)
#
#   „Тропар, гл. 4"                          13 знака
#   „Кондак, гл. 2"                          13 знака
#   „Историческа справка: … Снимки: …"       54 знака

# Заглавие на песнопение. ⚠ Изисква се ГЛАС или двоеточие, за да не мине
# случайно изречение, започващо с „Молитва".
RE_HYMN_HEAD = re.compile(
    r'^\s*(тропар|кондак|величание|молитва|стихира|икос|канон|светилен)'
    r'\b.{0,30}$', re.I)

# Бележка за източника накрая. ⚠ По ДВОЕТОЧИЕ след познат етикет, а не по
# гола дума: „снимки" се среща и в разказа.
RE_CREDIT = re.compile(
    r'^\s*(историческа справка|снимки|снимка|фото|източник|източници'
    r'|превод|текст|материал)\s*:', re.I)


# ⚠ АТРИБУЦИЯ КЪМ КНИГА — проверява се БЕЗ ОГЛЕД НА ДЪЛЖИНАТА.
#
# „Из книгата „100 Чудотворни икони…", Православно издателство „Витезда"."
# е 108 знака, тоест далеч над [SHORT_KIND_MAX], а е точно толкова бележка
# за източника, колкото и късото „Снимки: …". Стоеше като гол `<p>` с
# `<strong>` вътре и се четеше като ПОДЗАГЛАВИЕ на молитвата над него.
# (Докладвано от потребителя, 11.09.2026.)
RE_BOOK_CREDIT = re.compile(
    r'^\s*(из|по)\s+(книгата|книга|сборника|изданието)\b', re.I)

# ⚠ РЕДЪТ С АВТОРА И ДАТАТА в началото на статията („от · Православие Бг ·
# 29/09/2021"). Той НЕ е разказ, а служебен ред на сайта — а понеже стоеше
# като гол `<p>`, `splitDropCap` му слагаше БУКВИЦА и житието започваше с
# инициал върху думата „от". Класът `centernote` го решава наведнъж:
# четецът го рисува като приглушен центриран курсив, а буквицата сама
# прескача всичко, което не е гол `<p>`.
#
# ⚠ Признакът е СТРУКТУРЕН: „от", разделители „·" и дата — не по име на
# сайт, което утре може да е друго.
RE_BYLINE = re.compile(
    r'^\s*от\s*[·|]\s*.{1,80}[·|]\s*\d{1,2}/\d{1,2}/\d{4}\s*$', re.I)

# ⚠⚠ ОПАШКАТА НА САЙТА — оттук нататък НИЩО не е четиво.
#
# Подир самата статия pravoslavie.bg слага подкана за дарения, Patreon,
# банкова сметка, етикети, дати на други публикации и съобщение за
# авторските права. Всичко това влизаше в житието.
#
# ⚠ Отсича се на ПЪРВОТО от тези изречения и се СПИРА (`break`), вместо
# всяко да се изброява като шум: опашката е шаблон и утре ще носи още един
# ред, който няма да е в никой списък. Спирането покрива и онова, което
# още не сме видели.
#
# ⚠ И трябва да е ПОДНИЗ, не точно съвпадение — редовете носят вътре
# връзки и удебелявания, тъй че текстът им се мени.
STOP_AT = (
    'Разчитаме на вашите дарения',
    'Ако желаете да бъдете част от усилията на екипа',
    'За дарения по банков път',
    'Станете редовен дарител',
    'Следвайте ни в',
    'Copyright ©',
    'Етикети:',
)


def short_but_kept(plain: str) -> str:
    """Вид на късия блок, който все пак влиза: '' = не влиза.

    Връща `prayerhead` за заглавие на песнопение и `source` за бележка за
    източника — оттам build_html им слага класа.
    """
    if RE_HYMN_HEAD.match(plain):
        return 'prayerhead'
    if RE_BYLINE.match(plain):
        return 'centernote'
    if RE_CREDIT.match(plain):
        # ⚠ НЕ `source` — този клас е ЗАПАЗЕН за нашата атрибуция („Източник:
        # <адрес>"), която приложението слага НАКРАЯ. PDF-ът СПИРА на първия
        # блок с клас `source` (нарочно: след него не бива да идва нищо), тъй
        # че бележка от извора със същия клас изяждаше нашия ред след себе
        # си. Хванато веднага от потребителя (05.09.2026).
        return 'credit'
    return ''


def is_excluded(url: str) -> bool:
    """Изрично отхвърлена ли е тази картинка — виж [load_excluded]."""
    return any(frag in url for frag in EXCLUDED_IMAGES)


def parse(raw_html: str, page_url: str,
          section: str = '') -> tuple[str, list[tuple[str, str]]]:
    """Заглавието и блоковете: [('p', текст) | ('img', абсолютен адрес)]."""
    if section:
        raw_html = cut_section(raw_html, section)
    t = RE_DROP.sub(' ', raw_html)
    m = re.search(r'<title>(.*?)</title>', t, re.S | re.I)
    title = html.unescape(re.sub(r'\s+', ' ', m.group(1))).strip() if m else ''
    if section:
        # ⚠ Изрязаният раздел няма `<title>` — той е на цялата страница и
        # остава извън изрязаното. Заглавието е ПЪЛНОТО име на раздела, а не
        # ключът, по който сме го търсили (той е нарочно къс).
        head = RE_SECTION.search(t)
        full = (re.sub(r'\s+', ' ',
                       html.unescape(RE_TAG.sub('', head.group(2)))).strip()
                if head else '')
        title = full or section
    # опашките, които сайтовете лепят към заглавието
    title = re.sub(r'\s*[|–-]\s*[^|–-]{0,40}(митрополия|Църква|bg|com|org)\s*$',
                   '', title, flags=re.I).strip()

    out: list[tuple[str, str]] = []
    seen_text: set[str] = set()
    for m in RE_BLOCK.finditer(t):
        chunk = m.group(0)
        if chunk.lower().startswith('<img'):
            src = RE_SRC.search(chunk)
            if not src:
                continue
            url = urllib.parse.urljoin(page_url, html.unescape(src.group(1)))
            if IMG_SKIP.search(url) or is_excluded(url):
                continue
            out.append(('img', url))
            continue

        inner = m.group(1) or ''

        # ⚠⚠ КАРТИНКА ВЪТРЕ В АБЗАЦ СЕ ГУБЕШЕ МЪЛЧАЛИВО.
        #
        # RE_BLOCK е „<p>…</p> ИЛИ <img>", тъй че при
        # `<p class="wp-block-paragraph"><a href="…"><img …></a></p>`
        # печели ПЪРВАТА алтернатива — абзацът, — а `<img>`-ът вътре се
        # сваля по-долу от RE_TAG заедно с останалите тагове. Излизаше
        # празен `<a> </a>` и нито един ред в отчета.
        #
        # Точно така изчезнаха ДВЕТЕ истински илюстрации в житието на
        # свщмч. Симеон Самоковски (пейзажът с паметната плоча и иконата в
        # храма), докато хедърът и подвалът — самостоятелни `<img>` извън
        # абзац — минаваха безпрепятствено.
        # (Докладвано от потребителя, 03.09.2026; поправено 04.09.2026.)
        #
        # ⚠ Вадят се ПРЕДИ текста на абзаца, защото в извора стоят в
        # началото му и обтичат разказа отдясно (`float: right`).
        for im in re.finditer(r'<img\b[^>]*>', inner, re.I):
            isrc = RE_SRC.search(im.group(0))
            if not isrc:
                continue
            iurl = urllib.parse.urljoin(page_url, html.unescape(isrc.group(1)))
            if IMG_SKIP.search(iurl) or is_excluded(iurl):
                continue
            out.append(('img', iurl))

        frag = keep_inline(inner, page_url)
        plain = html.unescape(RE_TAG.sub('', frag)).strip()
        # ⚠ Шумът се маха ПРЪВ: късото изключение по-долу не бива да върне
        # блок, който иначе би отпаднал като меню или шаблон.
        # ⚠⚠ ОПАШКАТА НА САЙТА СПИРА ЦИКЪЛА — виж [STOP_AT]. Проверява се
        # ПРЕДИ шума, защото щом веднъж сме стигнали дотам, нататък няма
        # какво да се преценява ред по ред.
        if any(stop in plain for stop in STOP_AT):
            break
        if not plain or any(n.lower() in plain.lower() for n in NOISE):
            continue
        # ⚠ Точните съвпадения — виж [NOISE_EXACT].
        if plain.strip() in NOISE_EXACT:
            continue
        # ⚠ Късите блокове, които все пак са част от четивото — виж
        # [short_but_kept]. Проверява се ПРЕДИ прага, но СЛЕД шума.
        # ⚠ ВИДЪТ на късия блок се разпознава НЕЗАВИСИМО от прага.
        #
        # Дотук двете бяха вързани за едно число (`len < MIN_PARA`) и
        # махането на прага изключи разпознаването: „Кондак 1" тръгна като
        # обикновен абзац и загуби класа си `prayerhead` — тоест винения
        # цвят и получера. Прагът решава дали блокът ВЛИЗА; това тук решава
        # КАКЪВ Е. Двете нямат обща причина.
        # ⚠ Атрибуцията към книга се разпознава БЕЗ ОГЛЕД НА ДЪЛЖИНАТА —
        # виж [RE_BOOK_CREDIT]; тя е дълга, а е бележка за източника.
        kept = short_but_kept(plain) if len(plain) < SHORT_KIND_MAX else ''
        if not kept and RE_BOOK_CREDIT.match(plain):
            kept = 'bookcredit'
        if len(plain) < MIN_PARA and not kept:
            continue
        if plain in seen_text:
            continue
        seen_text.add(plain)
        out.append((kept or 'p', frag))
    return title, out


def _dimensions(data: bytes) -> tuple[int, int] | None:
    """Размерите на JPEG/PNG в пиксели — без външна библиотека.

    ⚠ Четат се от САМИТЕ БАЙТОВЕ: конвейерът не бива да иска Pillow само
    заради това.

    ⚠ НУЖНИ СА В САМИЯ ТАГ. `LivesImageExtension` смята мястото ПРЕДИ
    изображението да се е заредило и без `width`/`height` пада на кутия
    „цяла ширина × 0.66" — пейзажна. Портретна икона, вписана с
    `BoxFit.contain` в такава кутия, се свива по ширина и излиза наполовина.
    Точно това се случи с първите четива от този конвейер (01.09.2026):
    в легнало изглеждаха добре, в изправено — тесни.
    """
    try:
        if data[:2] == b'\xff\xd8':                     # JPEG
            i = 2
            while i < len(data) - 9:
                if data[i] != 0xFF:
                    i += 1
                    continue
                marker = data[i + 1]
                if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                    h = int.from_bytes(data[i + 5:i + 7], 'big')
                    w = int.from_bytes(data[i + 7:i + 9], 'big')
                    return (w, h) if w and h else None
                i += 2 + int.from_bytes(data[i + 2:i + 4], 'big')
        elif data[:8] == b'\x89PNG\r\n\x1a\n':          # PNG
            w = int.from_bytes(data[16:20], 'big')
            h = int.from_bytes(data[20:24], 'big')
            return (w, h) if w and h else None
    except Exception:                                  # noqa: BLE001
        pass
    return None


def _aspect(data: bytes) -> float | None:
    d = _dimensions(data)
    return d[0] / d[1] if d and d[1] else None


# Тагове, които четецът разбира и които носят смисъл в четивото.
_KEEP = {'strong', 'b', 'em', 'i', 'br'}
_AS = {'b': 'strong', 'i': 'em'}


def keep_inline(fragment: str, page_url: str) -> str:
    """Сваля таговете до онова, което четецът рисува — И ПАЗИ ВРЪЗКИТЕ.

    ⚠ Връзките остават ДЕЙСТВАЩИ (искане на потребителя, 01.09.2026). В
    статиите те сочат към други четива и към книги — „брат Йосиф Муньос",
    „игумения Серафима (Ливен)" — и без тях текстът губи препратките си.
    Четецът ги отваря през `external_link.dart`, тоест пита, преди да излезе
    навън.

    ⚠ КОТВИТЕ (`#_ftn2`) се махат, но ТЕКСТЪТ им остава. Те сочат бележка
    под линия в самата страница; при нас такава котва води наникъде, а
    номерът „[2]" пред нея е смислен — самите бележки влизат в четивото
    като последни абзаци.

    ⚠ Относителните адреси се разрешават спрямо страницата: „../../ps/index.htm"
    извън своя сайт не значи нищо.
    """
    def swap(m: re.Match) -> str:
        raw = m.group(0)
        name = re.match(r'</?([\w:]+)', raw)
        if not name:
            return ' '
        tag = name.group(1).lower()
        if tag in _KEEP:
            t = _AS.get(tag, tag)
            if t == 'br':
                return '<br>'
            return f'</{t}>' if raw.startswith('</') else f'<{t}>'
        if tag == 'a':
            if raw.startswith('</'):
                return '</a>'
            href = re.search(r'href="([^"]*)"', raw, re.I)
            if not href:
                return ''
            url = html.unescape(href.group(1)).strip()
            if url.startswith('#') or url.lower().startswith(
                    ('javascript:', 'mailto:')):
                return ''                       # котва/скрипт — само текстът
            url = urllib.parse.urljoin(page_url, url)
            return f'<a href="{html.escape(url, quote=True)}">'
        # ⚠ Инлайн тагът се маха БЕЗ интервал — инак дума, разкъсана на два
        # `<span>`-а, се изписва разделена („вт o ри", капанът от lives_bg).
        if tag in {'span', 'font', 'u', 'small', 'sup', 'sub', 'big', 'o:p'}:
            return ''
        return ' '

    # ⚠ ENTITY-ТАТА В ТЕКСТА СЕ РАЗКОДИРАТ, но таговете остават.
    #
    # Част от изворите са в cp1251 и пишат кирилицата като числови entity-та
    # (`&#1047;&#1072;…`). Дотук текстът минаваше непокътнат и в четивото
    # влизаха голи кодове вместо букви (сказанието за „Акатистна", 01.09.2026).
    # Разкодира се САМО между таговете, а `<`, `>` и `&` се връщат обратно,
    # за да остане HTML-ът валиден.
    def unescape_text(m: re.Match) -> str:
        txt = html.unescape(m.group(0))
        return (txt.replace('&', '&amp;').replace('<', '&lt;')
                   .replace('>', '&gt;'))

    fragment = re.sub(r'[^<>]+', unescape_text, fragment)
    out = RE_TAG.sub(swap, fragment)
    # ⚠ Затварящо `</a>` без отварящо остава, ако линкът е бил котва —
    # четецът го подминава, но по-чисто е да не се среща изобщо.
    out = re.sub(r'(?<!>)</a>', '', out) if '<a href' not in out else out
    out = unicodedata.normalize('NFC', re.sub(r'\s+', ' ', out)).strip()
    return out


def save_images(blocks: list[tuple[str, str]],
                slug: str) -> dict[str, tuple[str, int, int]]:
    """Тегли илюстрациите; връща {адрес: (име на файла, ширина, височина)}."""
    IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    got: dict[str, tuple[str, int, int]] = {}
    for kind, val in blocks:
        if kind != 'img' or val in got:
            continue
        # ⚠ Името носи отпечатък на АДРЕСА, не само последната част от пътя:
        # в различните сайтове „1.jpg" е различна картинка (капанът от
        # tools/lives_bg).
        # ⚠ Локален файл (ръчно подаден) се КОПИРА, не се тегли.
        # ⚠ Спрямо КОРЕНА на проекта, не спрямо папката на скрипта: пътят в
        # `sources.csv` се пише както се вижда от хранилището
        # („tools/lives_extra/cache/img/…"), а скриптът се пуска от `scripts/`.
        local = Path(val)
        if not local.is_absolute():
            local = PROJECT / val
        if not val.lower().startswith(('http://', 'https://')) and local.exists():
            data = local.read_bytes()
            name = re.sub(r'[^0-9A-Za-z._-]+', '_', local.name)[:48]
            IMAGES_DIR.mkdir(parents=True, exist_ok=True)
            (IMAGES_DIR / name).write_bytes(data)
            dim = _dimensions(data) or (0, 0)
            got[val] = (name, dim[0], dim[1])
            continue
        stem = re.sub(r'[^0-9A-Za-z._-]+', '_',
                      urllib.parse.unquote(val.rsplit('/', 1)[-1]))[:40]
        if '.' not in stem:
            stem += '.jpg'
        base, ext = stem.rsplit('.', 1)
        name = f'{base}_{hashlib.md5(val.encode()).hexdigest()[:8]}.{ext}'
        dest = IMAGES_DIR / name
        try:
            data = fetch(val, CACHE / 'img' / name)
        except Exception as e:                        # noqa: BLE001
            print(f'      ⚠ картинка: {e}')
            continue
        if len(data) < IMG_MIN_BYTES:
            continue                                   # иконка, не илюстрация
        ratio = _aspect(data)
        if ratio and (ratio > IMG_MAX_ASPECT or ratio < 1 / IMG_MAX_ASPECT):
            print(f'      ⏭ банер ({ratio:.1f}:1): {name}')
            continue
        dest.write_bytes(data)
        dim = _dimensions(data) or (0, 0)
        got[val] = (name, dim[0], dim[1])
    return got


def build_html(title: str, blocks: list[tuple[str, str]],
               images: dict[str, tuple[str, int, int]]) -> str:
    out = [f'<h3>{html.escape(title)}</h3>'] if title else []

    # ⚠ Докъде стигат ВЪВЕЖДАЩИТЕ абзаци — виж [RE_ALL_ITALIC]. Всичко до
    # първия ГОЛ абзац е цитат и бележка за него, не разказ; те получават
    # клас, за да ги прескочи буквицата.
    intro_end = 0
    for kind, val in blocks:
        if kind != 'p':
            # ⚠ Заглавие на песнопение или бележка ПРЕКЪСВА въвеждащата
            # зона — тя е само в началото, преди разказа.
            if kind in ('prayerhead', 'source', 'credit', 'centernote', 'bookcredit'):
                break
            continue
        if RE_ALL_ITALIC.match(val):
            intro_end += 1
        else:
            break

    p_seen = 0
    for kind, val in blocks:
        # ⚠ Късите блокове със свой вид — заглавие на песнопение и бележка
        # за източника. Класовете са същите, които ползват и останалите
        # четива, тъй че се оформят еднакво (виж reader_styles.dart).
        if kind in ('prayerhead', 'source', 'credit', 'centernote', 'bookcredit'):
            body = val
            if kind in ('prayerhead', 'credit', 'centernote', 'bookcredit'):
                # ⚠⚠ ВЪНШНИТЕ `<strong>`/`<em>` СЕ МАХАТ.
                #
                # В четеца `'strong'` е ТАГ-стил (`color: ink`), а той има
                # ПРЕВЕС над клас-стила на родителя — тъй че заглавието
                # излизаше мастилено вместо ВИНЕНО, каквото е при всички
                # останали тропари и кондаци. Курсивът от `<em>` също не му
                # е мястото: `.prayerhead` е получер прав.
                # (Докладвано от потребителя, 05.09.2026, за акатиста на
                # Иверската Монреалска икона.)
                #
                # ⚠ Получерът НЕ се губи — идва от самия клас
                # (`fontWeight: w600` в reader_styles.dart).
                body = re.sub(r'^\s*(?:<(?:strong|b|em|i)>\s*)+', '', body)
                body = re.sub(r'(?:\s*</(?:strong|b|em|i)>)+\s*$', '', body)
            out.append(f'<p class="{kind}">{body}</p>')
            continue
        if kind == 'img':
            rec = images.get(val)
            if rec:
                name, w, h = rec
                # ⚠ Размерите ВИНАГИ се изписват — виж [_dimensions] защо.
                wh = f' width="{w}" height="{h}"' if w and h else ''
                out.append(f'<img src="assets/lives_images/{name}"{wh}>')
        else:
            # ⚠ БЕЗ escape: `val` вече е HTML фрагмент с разрешените тагове
            # (виж keep_inline) — ескейпнат, връзките биха се изписали като
            # текст.
            cls = ''
            if p_seen < intro_end:
                plain = RE_TAG.sub('', val).strip()
                # Дългият е самият цитат, късият казва откъде е той.
                # ⚠ БЕЛЕЖКАТА КЪМ ЦИТАТА има СВОЙ клас, а не `centernote`.
                # Той се ползва и от `tools/lives_bg` за бележки за
                # източник (центрирани), а тук потребителят поиска друго:
                # ДЯСНО подравнена и с размера на самия цитат, защото
                # центрирана и по-едра се чете като ПОДЗАГЛАВИЕ.
                # (05.09.2026.)
                cls = (' class="epigraph"' if len(plain) >= EPIGRAPH_MIN
                       else ' class="epigraphnote"')
            p_seen += 1
            out.append(f'<p{cls}>{val}</p>')
    return '\n'.join(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--only', help='част от името')
    ap.add_argument('--force', action='store_true', help='тегли наново')
    args = ap.parse_args()

    with (INPUT / 'sources.csv').open(encoding='utf-8') as fh:
        rows = [r for r in csv.DictReader(fh) if r.get('url')]
    if args.only:
        rows = [r for r in rows if args.only.lower() in r['name'].lower()]
    if not rows:
        raise SystemExit('няма редове в input/sources.csv')

    cal = sqlite3.connect(CALENDAR_DB)
    con = sqlite3.connect(LIVES_DB)
    seed = sqlite3.connect(SEED_DB)
    taken = {r[0] for r in con.execute('SELECT slug FROM texts')}
    taken |= {r[0] for r in con.execute('SELECT DISTINCT slug FROM hymns')}

    orig_path = WORK / 'originals.json'
    originals = (json.loads(orig_path.read_text(encoding='utf-8'))
                 if orig_path.exists() else {})

    plan = []
    for r in rows:
        pattern = r['name'].strip()
        hits = cal.execute(
            'SELECT DISTINCT name, COALESCE(slug, "") FROM saints WHERE name LIKE ?',
            (pattern,)).fetchall()
        if not hits:
            print(f'  ⚠ няма такъв светия в календара: {pattern[:56]}')
            continue
        slug = next((s for _, s in hits if s), '')
        if not slug:
            slug = r.get('slug', '').strip()
        print(f'  {hits[0][0][:52]}  ({len(hits)} памет'
              f'{"и" if len(hits) > 1 else ""})')

        page = CACHE / (re.sub(r'[^0-9A-Za-z]+', '_', r['url'])[-60:] + '.html')
        try:
            raw = decode(fetch(r['url'], page, force=args.force))
        except Exception as e:                        # noqa: BLE001
            print(f'      ⚠ {e}')
            continue
        title, blocks = parse(raw, r['url'], (r.get('section') or '').strip())
        # ⚠ РЪЧНО ПОДАДЕНА ИЛЮСТРАЦИЯ — колоната `image` в sources.csv.
        # Приема локален файл ИЛИ адрес. Слага се веднага след заглавието.
        # Нужна е, когато публикацията разказва за икона, но самата икона я
        # няма в нея (Зографската „Чуваща молитвите"), или когато
        # изображението там е негодно и се взима от друго място
        # („Акатистна-Предвъзвестителка"). Ако е зададена, картинките от
        # самата страница се ПРОПУСКАТ — инак до избраната застава онази,
        # заради която сме я търсили.
        manual_img = (r.get('image') or '').strip()
        if manual_img:
            blocks = [b for b in blocks if b[0] != 'img']
            blocks.insert(0, ('img', manual_img))
        total = sum(len(v) for k, v in blocks if k == 'p')
        nimg = sum(1 for k, _ in blocks if k == 'img')
        if total < MIN_TOTAL:
            print(f'      ⚠ само {total} знака — пропуснат')
            continue
        print(f'      «{title[:56]}»')
        print(f'      {total} знака, {nimg} картинки на страницата')
        plan.append((r, [h[0] for h in hits], slug, title, blocks))

    if args.dry_run:
        print('\n--dry-run: НИЩО не е записано')
        return
    if not plan:
        raise SystemExit('нищо за внасяне')

    backups = ROOT / 'backups'
    backups.mkdir(exist_ok=True)
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    shutil.copy2(LIVES_DB, backups / f'lives.db.{stamp}')
    print(f'\nрезервно копие: backups/lives.db.{stamp}')

    for r, names, slug, title, blocks in plan:
        images = save_images(blocks, slug)
        life_new = build_html(title, blocks, images)
        if not slug:
            slug = r.get('slug', '').strip() or make_slug(names[0], taken)
            taken.add(slug)
        key = r['url']
        if key in originals:
            old_life = originals[key]['life']
            old_src = originals[key]['source']
        else:
            row = con.execute('SELECT life, source FROM texts WHERE slug=?',
                              (slug,)).fetchone()
            old_life = row[0] if row else None
            old_src = row[1] if row else None
            originals[key] = {'slug': slug, 'life': old_life, 'source': old_src}

        if old_life and RE_TAG.sub('', old_life).strip():
            life = (f'{old_life.rstrip()}\n<h3>Допълнение</h3>\n'
                    + re.sub(r'^\s*<h3>.*?</h3>\s*', '', life_new,
                             count=1, flags=re.S))
        else:
            life = life_new
        srcs = [u.strip() for u in (old_src or '').split('\n') if u.strip()]
        if r['url'] not in srcs:
            srcs.append(r['url'])

        if con.execute('SELECT 1 FROM texts WHERE slug=?', (slug,)).fetchone():
            con.execute('UPDATE texts SET life=?, source=? WHERE slug=?',
                        (life, '\n'.join(srcs), slug))
        else:
            con.execute('INSERT INTO texts (slug, name, life, source)'
                        ' VALUES (?,?,?,?)', (slug, names[0], life,
                                              '\n'.join(srcs)))
        # ⚠ Слъгът — на ВСИЧКИ памети на този светия и В СЕМЕТО.
        for n in names:
            seed.execute('UPDATE saints SET slug=? WHERE name=?', (slug, n))
        print(f'  ✓ {names[0][:46]}  slug={slug}, '
              f'{len(images)} илюстрации, {len(life)} знака')
    con.commit()
    seed.commit()
    orig_path.parent.mkdir(exist_ok=True)
    orig_path.write_text(json.dumps(originals, ensure_ascii=False, indent=1),
                         encoding='utf-8')
    print('\n⚠ СЛЕДВА прегенериране (слъгове са вписани в семето):')
    print('    cd tools/calendar_gen && rm -f out/*.db')
    print('    python3 merge_years.py --years 2025 2026 2027 --style old')
    print('    python3 merge_years.py --years 2025 2026 2027 --style new')


if __name__ == '__main__':
    main()
