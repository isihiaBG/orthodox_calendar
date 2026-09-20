#!/usr/bin/env python3
"""Нанася Пасха в assets/db/lives.db — песнопенията и сказанието.

    python3 06_apply.py --only hymns     # само песнопенията
    python3 06_apply.py --only text
    python3 06_apply.py                  # и двете
    python3 06_apply.py --dry-run

⚠⚠ ИДЕМПОТЕНТЕН ПО УСТРОЙСТВО. Нашите редове носят `note = OUR_NOTE` и се
трият В НАЧАЛОТО на всяко пускане — оттам повторно пускане дава същото, а не
удвоено. Капанът е платен три пъти в другите конвейери (виж CLAUDE.md,
„Идемпотентност на конвейерите").

⚠ Резервното копие ляга в `tools/paskha/backups/`, НЕ до базата:
`pubspec.yaml` включва цялата `assets/db/`, тъй че `lives.db.bak-…` там
пътува в APK-то.
"""
import argparse, html, json, os, re, shutil, sqlite3, sys, time
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
РАБОТА = КОРЕН / 'work'
ПРОЕКТ = КОРЕН.parents[1]
БАЗА = ПРОЕКТ / 'assets' / 'db' / 'lives.db'
КОПИЯ = КОРЕН / 'backups'

СЛЪГ = 'prazdnik-pasha-svetloe-hristovo-voskresenie'
OUR_NOTE = 'от azbyka.ru/paskha'
ИЗТОЧНИК = 'https://azbyka.ru/paskha'

# Видът се извежда от заглавието. ⚠ Редът има значение: „Стихиры" трябва да
# се провери ПРЕДИ „Стихира" би било все едно, но „Задостойник" съдържа
# „достойн" и не бива да пада при друг.
ВИДОВЕ = [
    (re.compile(r'канон', re.I), 'kanon'),
    (re.compile(r'задостойник', re.I), 'zadostoynik'),
    (re.compile(r'ипакои', re.I), 'ipakoi'),
    (re.compile(r'стихир', re.I), 'stihira'),
    (re.compile(r'тропар', re.I), 'tropar'),
    (re.compile(r'кондак', re.I), 'kondak'),
    (re.compile(r'величани', re.I), 'velichanie'),
    (re.compile(r'молитв', re.I), 'molitva'),
]


def вид(заглавие: str) -> str:
    for rx, k in ВИДОВЕ:
        if rx.search(заглавие):
            return k
    return 'other'


def глас(заглавие: str):
    m = re.search(r'глас\s*([\w\-]+)', заглавие, re.I)
    return f'глас {m.group(1)}' if m else None


def име_без_глас(заглавие: str) -> str:
    return re.sub(r',?\s*глас\s*[\w\-]+', '', заглавие, flags=re.I).strip()



# ---------------------------------------------------------------------------
# Оформяне на богослужебния текст
# ---------------------------------------------------------------------------
#
# ⚠⚠ ТЕКСТЪТ ВЛИЗА В ЕДИН АБЗАЦ и новите редове в него се губят. Затова
# канонът и стихирите се сливаха в стена от текст. Тук всеки ред става
# СВОЙ ред, а указанията получават червено.
#
# ⚠ Указанията се разпознават по ИЗРИЧЕН СПИСЪК, не по израз „дума до
# двоеточие": два реда от самия текст също завършват с двоеточие („Же́ны с
# ми́ры богому́дрыя в след Тебе́ теча́ху:"). Списъкът не може да ги сбърка.

УКАЗАНИЯ = [
    'На катавасии снова ирмос:', 'Слава, и ныне, глас 5:', 'Слава, и ныне:',
    'Богородичны:', 'Богородичен:', 'Катавасия:', 'Припев:', 'Ирмос:',
    'Слава:', 'И ныне:', 'Стих:',
]
# Ирмосът се изписва с КУРСИВ — той е образецът, по който се пеят останалите.
КУРСИВ_СЛЕД = ('Ирмос:', 'На катавасии снова ирмос:', 'Катавасия:')
RE_ПЕСЕН = re.compile(r'^Песнь\s+\d+')
RE_СКОБА = re.compile(r'\((?:Трижды|Дважды|Поемыя[^)]*)\)')
RE_ПСАЛОМ = re.compile(r'^\(Пс\.')
# ⚠ Препратката към псалом е ВРЪЗКА, не указание — сини, не червени, и се
# отварят ВЪТРЕ в приложението, успоредно на български и църковнославянски
# (`bg~utfcs` — утвърденото за целия проект).
RE_ПС_ВРЪЗКА = re.compile(r'\(Пс\.\s*([\d]+):([\d:,\-–]+)\)')


def псаломски_връзки(s: str) -> str:
    def _връзка(m):
        глава, стихове = m.group(1), m.group(2).replace('–', '-')
        адрес = 'https://azbyka.ru/biblia/?Ps.%s:%s&amp;bg~utfcs' % (глава, стихове)
        return '(<a href="%s">Пс. %s:%s</a>)' % (адрес, глава, стихове)
    return RE_ПС_ВРЪЗКА.sub(_връзка, s)


# ⚠ Славословието накрая на стихирите. „Слава" и „и ныне" в него са
# УКАЗАНИЯ (кога се пее какво), а останалото е самият текст — затова само
# те са червени, не целият ред. Отделя се и с празен ред: то завършва
# дела, а слято с последната стихира не личи къде свършва тя.
RE_СЛАВОСЛОВИЕ = re.compile(
    r'^(Сла́ва|Слава)\s+(?:Отцу́|Отцу|на\s+Отца)\b')
# Двете указания, с ударения и без — текстът идва и на двата езика.
RE_УКАЗАНИЕ_В_СЛАВОСЛОВИЕ = re.compile(
    r'^(Сла́ва|Слава)\b|(?<=[,\s])(и\s+ны́не|и\s+ныне|и\s+сега)\b')


def славословие(ред: str) -> str:
    """Оцветява САМО указанията вътре в славословието."""
    return RE_УКАЗАНИЕ_В_СЛАВОСЛОВИЕ.sub(lambda m: червено(m.group(0)), ред)


def червено(s: str) -> str:
    return '<span class="rubric">%s</span>' % s


def оформи(текст: str) -> str:
    """Богослужебен текст → HTML с редове и червени указания."""
    редове = [r.strip() for r in текст.split('\n')]
    out = []
    for i, r in enumerate(редове):
        if not r:
            continue
        # ⚠ Празен ред ПРЕДИ нова песен и преди нова стихира — инак всичко
        # е плътна стена и краят на едното не личи от началото на другото.
        # ⚠ ДВА РАЗЛИЧНИ ВЪПРОСА, не един: „започва ли нов дял" (празен ред
        # пред него) и „указание ли е" (червено). Слети в един флаг,
        # „Воскресение Христово видевше" излизаше ЦЯЛ в червено — а той е
        # самият стих, не указание.
        нова_песен = bool(RE_ПЕСЕН.match(r))
        е_славословие = bool(RE_СЛАВОСЛОВИЕ.match(r))
        нов_дял = (нова_песен
                   or r.startswith('Воскресе́ние Христо́во ви́девше')
                   or е_славословие)
        нова_стихира = (i + 1 < len(редове) and RE_ПСАЛОМ.match(редове[i + 1] or ''))
        # ⚠ Псаломската препратка принадлежи на стиха НАД нея и се долепя за
        # него — сама на ред тя изглежда като изпаднал къс.
        if RE_ПСАЛОМ.match(r) and out and out[-1]:
            out[-1] += ' ' + псаломски_връзки(html.escape(r))
            continue
        # ⚠ Разделителят е ПРАЗЕН низ, не '<br>': съединяването после слага
        # своя разделител, тъй че изричен '<br>' тук дава ТРИ прекъсвания
        # вместо едно празно междуредие.
        if out and (нов_дял or нова_стихира):
            out.append('')
        if нова_песен:
            out.append(червено(html.escape(r)))
            continue
        for у in УКАЗАНИЯ:
            if r.startswith(у):
                остатък = r[len(у):].strip()
                ред = червено(html.escape(у))
                if остатък:
                    тяло = html.escape(остатък)
                    if у in КУРСИВ_СЛЕД:
                        тяло = '<em>%s</em>' % тяло
                    # Скоба-указание вътре в остатъка също е червена.
                    ред += ' ' + RE_СКОБА.sub(
                        lambda m: червено(m.group(0)), тяло)
                out.append(ред)
                break
        else:
            тяло = псаломски_връзки(
                RE_СКОБА.sub(lambda m: червено(m.group(0)), html.escape(r)))
            # ⚠ Псаломският стих пред всяка стихира е в КУРСИВ, както
            # ирмосите: и двете са образец, по който се пее следващото, а не
            # част от самото песнопение. Препратката остава извън курсива —
            # тя е връзка, не текст.
            if нова_стихира:
                тяло = '<em>%s</em>' % тяло
            elif е_славословие:
                тяло = славословие(тяло)
            out.append(тяло)
    return '<br>'.join(out)

def песнопения():
    """14-те песнопения → редове. ⚠ Канонът се СЛИВА в ЕДИН ред."""
    сурови = json.loads((РАБОТА / 'hymns.json').read_text(encoding='utf-8'))
    преводи = json.loads((РАБОТА / 'hymns_bg.json').read_text(encoding='utf-8'))
    редове, канон_csl, канон_bg = [], [], []
    for x in сурови:
        загл = x['kind_ru']
        k = вид(загл)
        bg = преводи.get(загл, '')
        if k == 'kanon':
            # ⚠ ЕДНО ПРОИЗВЕДЕНИЕ, НЕ ОСЕМ. Вкарани поотделно, осемте песни
            # биха дали етикет „8 канона" — същият довод като при акатиста.
            подзагл = re.sub(r'^Пасхален канон\s*—\s*', '', загл).strip()
            канон_csl.append(f'{подзагл}\n{x["csl"]}')
            канон_bg.append(f'{подзагл}\n{bg}')
            continue
        # ⚠ Стихирите и канонът носят структура в новите си редове; при
        # кратките (тропар, кондак) оформянето не мени нищо.
        редове.append({
            'kind': k, 'kind_ru': име_без_глас(загл), 'glas': глас(загл),
            'csl': оформи(x['csl']), 'bg': оформи(bg),
        })
    if канон_csl:
        редове.append({
            'kind': 'kanon', 'kind_ru': 'Пасхален канон',
            'glas': 'глас 1', 'csl': оформи('\n'.join(канон_csl)),
            'bg': оформи('\n'.join(канон_bg)),
        })
    return редове


def сказание():
    """18-те дяла → готово HTML за четеца."""
    ru = json.loads((РАБОТА / 'text.json').read_text(encoding='utf-8'))
    bg = json.loads((РАБОТА / 'text_bg.json').read_text(encoding='utf-8'))
    липсват = [i for i in range(len(ru['sections'])) if str(i) not in bg]
    if липсват:
        sys.exit(f'⚠ непреведени дялове: {липсват} — пусни 05_translate_text.py')
    части = []
    # ⚠ Картинката застава НАЙ-ОТГОРЕ — тя е образът на празника, не
    # илюстрация към определен дял. Размерите ВЛИЗАТ В ТАГА: без тях четецът
    # смята мястото по подразбиране и портретните излизат свити (виж
    # CLAUDE.md, „Илюстрациите — четири капана").
    карт = РАБОТА / 'image.json'
    if карт.exists():
        im = json.loads(карт.read_text(encoding='utf-8'))
        мерки = (' width="%d" height="%d"' % (im['width'], im['height'])
                 if im.get('width') else '')
        части.append('<img src="assets/lives_images/%s" alt="%s"%s>'
                     % (im['file'], html.escape(im.get('alt') or '', quote=True),
                        мерки))
    # ⚠⚠ СЪДЪРЖАНИЕ С КОТВИ. Изворът има такова (скрит блок с `ch_0_N`), а
    # сказанието е 19 дяла — без указател човек не вижда какво има вътре.
    # Котвата е „sec://N"; четецът намира блока с `id="sN"` и се ПЛЪЗГА до
    # него плавно (виж `_onLinkTap` в reader_screen.dart).
    съдържание = [(i, bg[str(i)]['title_bg'])
                  for i, _ in enumerate(ru['sections'])
                  if bg[str(i)]['title_bg']]
    if len(съдържание) > 3:
        части.append('<p class="grouphead">В тази статия</p>')
        for i, загл in съдържание:
            части.append('<p class="credit"><a href="sec://%d">%s</a></p>'
                         % (i, html.escape(загл)))

    for i, s in enumerate(ru['sections']):
        п = bg[str(i)]
        if п['title_bg']:
            части.append('<h3 id="s%d">%s</h3>' % (i, html.escape(п['title_bg'])))
        for k, (текст, блок) in enumerate(zip(п['blocks_bg'], s['blocks'])):
            тяло = връзки(текст, блок.get('links') or [])
            # ⚠ Уводното резюме (дял 0) в КУРСИВ — на azbyka.ru всяка
            # страница започва с такова и то не е част от изложението.
            # Курсивът го отличава, а буквицата сама го прескача, защото
            # абзацът не е гол `<p>`.
            if i == 0:
                части.append('<p class="epigraph">%s</p>' % тяло)
            else:
                части.append('<p>%s</p>' % тяло)
    части += допълнителни_раздели()
    return '\n'.join(части)


def допълнителни_раздели():
    """„Литература по темата" и „Близки понятия" — накрая на четивото.

    ⚠ Връзките са ВЪНШНИ на този етап (отварят се през `external_link.dart`,
    тоест с питане). Част от тях ще станат вътрешни по-нататък.

    ⚠ Всеки ред е ОТДЕЛЕН абзац, не списък: `<ul>/<li>` нямат стил в
    `reader_styles.dart` и биха излезли като гол текст без отстъп.
    """
    файл = РАБОТА / 'links.json'
    ако = РАБОТА / 'links_bg.json'
    if not (файл.exists() and ако.exists()):
        return []
    d = json.loads(файл.read_text(encoding='utf-8'))
    bg = json.loads(ако.read_text(encoding='utf-8'))

    def пр(s):
        return bg.get(s, s)

    out = []
    # ⚠ Пази СЛИВАНЕТО: двата реда към песнопенията стават един, на мястото
    # на първия от тях.
    сложено_песнопение = [False]

    def ред_за(x):
        """Готовият ред за една връзка, или None ако трябва да отпадне."""
        if песнопение_ли(x['url']):
            if сложено_песнопение[0]:
                return None
            сложено_песнопение[0] = True
            # ⚠ БЕЗ „<span class=translabel>" за автор — това е НАШАТА
            # секция, не чуждо съчинение.
            return '<a href="hymns://%s">%s</a>' % (
                html.escape(ПЕСНОПЕНИЯ_СЛЪГ, quote=True),
                html.escape(ПЕСНОПЕНИЯ_НАСЛОВ))
        ред = '<a href="%s">%s</a>' % (
            html.escape(вътрешен(x['url']), quote=True),
            html.escape(пр(x['title_ru'])))
        if x.get('by_ru'):
            ред += ' <span class="translabel">%s</span>' % html.escape(пр(x['by_ru']))
        return ред

    if d.get('literature'):
        out.append('<h3>Литература по темата</h3>')
        for г in d['literature']:
            if г['title_ru']:
                # ⚠ Групата е ПОДЗАГЛАВИЕ, но не <h3> — инак се смесва с
                # подзаглавията на самото сказание. И НЕ Е `prayerhead`:
                # той е винен, а червеното е за богослужебни указания —
                # тук би направило списъка на цветни ивици.
                out.append('<p class="grouphead">%s</p>' % html.escape(пр(г['title_ru'])))
            for x in г['items']:
                ред = ред_за(x)
                if ред:
                    out.append('<p class="credit">%s</p>' % ред)
    if d.get('related'):
        out.append('<h3>Близки понятия</h3>')
        редове = [r for r in (ред_за(x) for x in d['related']) if r]
        out.append('<p class="credit">%s</p>' % ' · '.join(редове))
    return out


# ⚠⚠ ЧАСТ ОТ ВРЪЗКИТЕ НЕ СА ЗА ПРЕВОД — те сочат КАЛЕНДАРА на azbyka.
# Пасхалната таблица препраща към конкретни дни („9 май", „11 май") и към
# два празника по слъг. Те трябва да водят към НАШИЯ календар, не навън:
# датите го имаме, а двата слъга съвпадат с нашите дословно.
RE_ДЕН = re.compile(r'azbyka\.ru/days/(\d{4}-\d{2}-\d{2})')
RE_ПРАЗНИК = re.compile(r'azbyka\.ru/days/([a-z0-9\-]+)')
_НАШИ_СЛЪГОВЕ = None


def наши_слъгове():
    global _НАШИ_СЛЪГОВЕ
    if _НАШИ_СЛЪГОВЕ is None:
        c = sqlite3.connect(ПРОЕКТ / 'assets' / 'db' / 'calendar_new.db')
        _НАШИ_СЛЪГОВЕ = {r[0] for r in c.execute(
            'SELECT DISTINCT slug FROM saints WHERE slug IS NOT NULL')}
        c.close()
    return _НАШИ_СЛЪГОВЕ


def отместване(дата: str):
    """Дата „ГГГГ-ММ-ДД" → колко дни е от Пасха на СВОЯТА година."""
    import datetime
    sys.path.insert(0, str(ПРОЕКТ / 'tools' / 'calendar_gen'))
    import paschalion
    d = datetime.date.fromisoformat(дата)
    return (d - paschalion.pascha_civil(d.year)).days


_СТАТИИ = None


def статии():
    """Кои статии вече са в базата — връзките към тях стават вътрешни."""
    global _СТАТИИ
    if _СТАТИИ is None:
        c = sqlite3.connect(БАЗА)
        try:
            _СТАТИИ = {r[0] for r in c.execute('SELECT slug FROM articles')}
        except sqlite3.Error:
            _СТАТИИ = set()
        c.close()
    return _СТАТИИ


# ⚠⚠ ДВАТА ЛИНКА КЪМ ПЕСНОПЕНИЯТА СОЧАТ НАШАТА СЕКЦИЯ И СЕ СЛИВАТ В ЕДИН.
#
# „Тропар, кондак, стихири на Пасха" и „Пасхален канон с тълкувание" водеха
# към статии от azbyka.ru, минали през машинен превод. Приложението обаче
# носи същото наготово и по-добре: секцията „Тропар и кондак" за Пасха има
# СЕДЕМ песнопения с истински църковнославянски текст и превод, между тях и
# целия пасхален канон (19 749 знака цсл.). Затова двата реда стават ЕДИН,
# сочещ „hymns://<слъг>". (Решение на потребителя, 20.09.2026.)
ПЕСНОПЕНИЯ_СЛЪГ = 'prazdnik-pasha-svetloe-hristovo-voskresenie'
ПЕСНОПЕНИЯ_НАСЛОВ = 'Тропар, кондак, стихири и пасхален канон'
КЪМ_ПЕСНОПЕНИЯТА = (
    'pashalnye-pesnopeniya',
    'pasxalnyj-kanon-tvorenie-ioanna-damaskina',
)


def песнопение_ли(url: str) -> bool:
    return any(к in url for к in КЪМ_ПЕСНОПЕНИЯТА)


def вътрешен(url: str) -> str:
    """Адрес към чужд календар → наш вътрешен, ако можем.

    ⚠⚠ ДАТАТА СТАВА ОТМЕСТВАНЕ СПРЯМО ПАСХА, не се заковава. Страницата е
    писана за една година (2027) и таблицата с неделите след Пасха носи
    нейните числа; закована, тя щеше да лъже всяка следваща година.
    Приложението смята Пасха само и разгъва „day://+7" в истинската дата.
    """
    # ⚠ ПРЕДИ всичко останало: инак `статии()` би го хванала като
    # преведена статия и линкът пак щеше да води към машинния превод.
    if песнопение_ли(url):
        return 'hymns://' + ПЕСНОПЕНИЯ_СЛЪГ
    m = RE_ДЕН.search(url)
    if m:
        try:
            return 'day://%+d' % отместване(m.group(1))
        except Exception:                      # noqa: BLE001
            return 'day://' + m.group(1)       # по-добре закована, отколкото нищо
    m = RE_ПРАЗНИК.search(url)
    if m and m.group(1) in наши_слъгове():
        return 'saint://' + m.group(1)
    # ⚠ Преведена статия → вътрешна връзка. Непреведена остава външна;
    # при следващ етап същият ред я прибира, без нищо да се пипа.
    m = re.search(r'azbyka\.ru/([^?#/]+)/?$', url)
    if m and m.group(1) in статии():
        return 'saint://azb-' + m.group(1)
    return url


def връзки(текст: str, links: list) -> str:
    """⟦n⟧…⟦/n⟧ → `<a href>`; останалото се екранира.

    ⚠ Екранира се ПО ПАРЧЕТА, извън котвите — инак самите тагове излизат
    като видим текст. Същият капан е платен в `03_build_db.py` на словата.
    """
    out, poz = [], 0
    for m in re.finditer(r'⟦(\d+)⟧(.*?)⟦/\1⟧', текст, re.S):
        out.append(html.escape(текст[poz:m.start()]))
        n = int(m.group(1))
        url = вътрешен(links[n - 1]['url']) if 0 < n <= len(links) else ''
        вътре = html.escape(m.group(2))
        # ⚠ И ВИДИМИЯТ ТЕКСТ е дата („9 май") — заменя се със запушалка,
        # която четецът разгъва при отваряне. Инак линкът води на вярната
        # дата, а надписът до него казва друга.
        if url.startswith('day://+') or url.startswith('day://-'):
            вътре = '⟦пасха%s⟧' % url[len('day://'):]
        out.append(f'<a href="{html.escape(url, quote=True)}">{вътре}</a>'
                   if url else вътре)
        poz = m.end()
    out.append(html.escape(текст[poz:]))
    # Остатъчни маркери (блок, минал по резервния път) се махат мълчаливо —
    # по-добре текст без връзка, отколкото видими ⟦3⟧.
    return re.sub(r'⟦/?\d+⟧', '', ''.join(out))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', choices=['hymns', 'text'])
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    прави_песн = a.only in (None, 'hymns')
    прави_текст = a.only in (None, 'text')

    песн = песнопения() if прави_песн else []
    текст = сказание() if прави_текст else None

    if песн:
        print('ПЕСНОПЕНИЯ:')
        for i, р in enumerate(песн):
            print(f"  [{i}] {р['kind']:12} {р['kind_ru'][:28]:30} "
                  f"{р['glas'] or '':8} цсл={len(р['csl']):6} бг={len(р['bg']):6}")
    if текст is not None:
        гол = re.sub(r'<[^>]+>', '', текст)
        print(f'СКАЗАНИЕ: {len(текст)} знака HTML, {len(гол)} гол текст, '
              f"{текст.count('<h3>')} подзаглавия, {текст.count('<a href')} връзки")
    if a.dry_run:
        print('\n--dry-run: нищо не е записано'); return 0

    КОПИЯ.mkdir(exist_ok=True)
    коп = КОПИЯ / ('lives.db.bak-%s' % time.strftime('%Y%m%d_%H%M%S'))
    shutil.copy2(БАЗА, коп)
    print('\nкопие:', os.path.relpath(коп, ПРОЕКТ))

    db = sqlite3.connect(БАЗА)
    if прави_песн:
        db.execute('DELETE FROM hymns WHERE slug = ? AND note = ?',
                   (СЛЪГ, OUR_NOTE))
        for i, р in enumerate(песн):
            db.execute(
                'INSERT INTO hymns (slug, ord, kind, kind_ru, seq, glas, csl,'
                ' bg, note) VALUES (?,?,?,?,?,?,?,?,?)',
                (СЛЪГ, i, р['kind'], р['kind_ru'], 1, р['glas'],
                 р['csl'], р['bg'], OUR_NOTE))
    if прави_текст:
        има = db.execute('SELECT count(*) FROM texts WHERE slug = ?',
                         (СЛЪГ,)).fetchone()[0]
        if има:
            db.execute('UPDATE texts SET life = ?, source = ? WHERE slug = ?',
                       (текст, ИЗТОЧНИК, СЛЪГ))
        else:
            кол = [r[1] for r in db.execute('PRAGMA table_info(texts)')]
            поле = {'slug': СЛЪГ, 'life': текст, 'source': ИЗТОЧНИК,
                    'name': 'Светло Христово Възкресение (Великден)'}
            поле = {k: v for k, v in поле.items() if k in кол}
            db.execute('INSERT INTO texts (%s) VALUES (%s)'
                       % (','.join(поле), ','.join('?' * len(поле))),
                       list(поле.values()))
    db.commit()
    print('песнопения:', db.execute(
        'SELECT count(*) FROM hymns WHERE slug = ?', (СЛЪГ,)).fetchone()[0])
    print('житие:', db.execute(
        'SELECT length(COALESCE(life,"")) FROM texts WHERE slug = ?',
        (СЛЪГ,)).fetchone() or 0)
    db.close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
