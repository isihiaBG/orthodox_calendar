#!/usr/bin/env python3
"""Нанася преведените статии в assets/db/lives.db, таблица `articles`.

    python3 14_apply_pages.py --stage 1 --dry-run
    python3 14_apply_pages.py --stage 1

⚠⚠ СЛЪГЪТ В ПРИЛОЖЕНИЕТО Е „azb-<слъг>". Разпознава се на ДВЕ места в кода
(`lookupBySlug` и `_slugForFingerprint`) — без второто цитат от статия се
запазва, но споделеният линк не се отваря. Капанът е платен вече два пъти.

⚠ Идемпотентен: таблицата се пресъздава при всяко пускане от work/pages_bg/.

⚠ Картинките идват от work/pages_img.json и ВЛИЗАТ С РАЗМЕРИ в тага — без
тях четецът смята мястото по подразбиране и портретните излизат свити.
"""
import argparse, csv, html, json, os, re, shutil, sqlite3, sys, time
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
РАЗЧЕТЕНО = КОРЕН / 'work' / 'pages'
ПРЕВОД = КОРЕН / 'work' / 'pages_bg'
СПИСЪК = КОРЕН / 'input' / 'pages.csv'
ПРОЕКТ = КОРЕН.parents[1]
БАЗА = ПРОЕКТ / 'assets' / 'db' / 'lives.db'
КОПИЯ = КОРЕН / 'backups'
ПРЕДСТАВКА = 'azb-'

СХЕМА = """
DROP TABLE IF EXISTS articles;
CREATE TABLE articles (
    slug     TEXT PRIMARY KEY,   -- БЕЗ представката: „grex"
    title_bg TEXT NOT NULL,
    title_ru TEXT,
    body     TEXT NOT NULL,
    source   TEXT NOT NULL,
    chars    INTEGER NOT NULL
);
"""

RE_МАРКЕР = re.compile(r'⟦(\d+)⟧(.*?)⟦/\1⟧', re.S)


# ⚠⚠ ПОД ТОЛКОВА ЗНАКА СТАТИЯТА НЕ Е СТАТИЯ.
#
# Трите кръстословици са интерактивни (JavaScript) и от страницата им не
# остава нищо освен заглавието — 22 до 29 знака. Пуснати в базата, те са
# празни четива, а връзките към тях изглеждат работещи. Най-късата
# същинска статия е 423 знака, тъй че прагът е далеч от нея.
#
# ⚠ Проверката е ТУК, а не списък с изключени слъгове: утрешна страница от
# същия вид ще отпадне сама, вместо да се появи като празно четиво.
МИН_ЗНАЦИ = 200


def тяло_знаци(слъг: str) -> int:
    """Колко знака дава РАЗЧЕТЕНОТО — без да се сглобява цялата статия."""
    f = РАЗЧЕТЕНО / (слъг + '.json')
    if not f.exists():
        return 0
    d = json.loads(f.read_text(encoding='utf-8'))
    # ⚠ И ЗАГЛАВИЯТА НА ДЯЛОВЕТЕ. „Пасхални козунаци" е указател: един
    # абзац и двайсет и едно заглавия. Броени само абзаците, такава
    # страница пада под прага и изчезва, макар да е напълно четима.
    return (sum(len(b['ru']) for s in d['sections'] for b in s['blocks'])
            + sum(len(s.get('title_ru') or '') for s in d['sections']))


def преведени_слъгове():
    """Кои статии вече ги има — за да станат връзките към тях ВЪТРЕШНИ.

    ⚠⚠ И ДВЕТЕ УСЛОВИЯ: има превод И има какво да се чете. Инак връзка към
    отпаднала статия сочи навътре и не отваря нищо — тих отказ.
    """
    return {p.stem for p in ПРЕВОД.glob('*.json')
            if тяло_знаци(p.stem) >= МИН_ЗНАЦИ}


def вътрешен(url: str, налични: set) -> str:
    m = re.search(r'azbyka\.ru/([^?#/]+)/?$', url)
    if m and m.group(1) in налични:
        return 'saint://' + ПРЕДСТАВКА + m.group(1)
    return url


def връзки(текст: str, links: list, налични: set) -> str:
    out, poz = [], 0
    for m in RE_МАРКЕР.finditer(текст):
        out.append(html.escape(текст[poz:m.start()]))
        n = int(m.group(1))
        url = вътрешен(links[n - 1]['url'], налични) if 0 < n <= len(links) else ''
        вътре = html.escape(m.group(2))
        out.append('<a href="%s">%s</a>' % (html.escape(url, quote=True), вътре)
                   if url else вътре)
        poz = m.end()
    out.append(html.escape(текст[poz:]))
    return знаци(re.sub(r'⟦/?\d+⟧', '', ''.join(out)))


RE_ZNAK = re.compile(r'⟦znak([1-5])⟧')


def знаци(текст: str) -> str:
    """Запушалките за знаците на Типикона → тагове, СЛЕД екранирането.

    ⚠⚠ РЕДЪТ Е ПРИЧИНАТА ДА СА ЗАПУШАЛКИ. Написан направо в превода,
    тагът минава през `html.escape` и излиза на екрана като текст
    „&lt;znak n=1&gt;". Същият похват вече се ползва в справочника
    (`03_build_db.py` в tools/reference_gen).

    ⚠ Тагът се ЗАТВАРЯ изрично — самозатварящият се `<znak/>` поглъща
    остатъка от абзаца (платено веднъж в справочника).

    ⚠ Изворът ги дава като знаци от Unicode (🕀, 🕱, 🕂, 🕃), каквито
    почти никой шрифт няма: на екрана излизаха празни квадратчета точно
    там, където текстът обяснява как изглежда знакът. Тук вместо тях
    застават SVG-тата, с които календарът бележи ранга на светията.
    """
    return RE_ZNAK.sub(lambda m: '<znak n="%s"></znak>' % m.group(1), текст)


def сглоби(слъг: str, налични: set, картинки: dict) -> dict | None:
    изв = РАЗЧЕТЕНО / (слъг + '.json')
    пр = ПРЕВОД / (слъг + '.json')
    if not (изв.exists() and пр.exists()):
        return None
    d = json.loads(изв.read_text(encoding='utf-8'))
    b = json.loads(пр.read_text(encoding='utf-8'))
    знаци = тяло_знаци(слъг)
    if знаци < МИН_ЗНАЦИ:
        print('  ⚠ %s: само %d знака — не е четиво, прескачам'
              % (слъг, знаци))
        return None
    липсват = [i for i in range(len(d['sections'])) if str(i) not in b['sections']]
    if липсват:
        return None                      # още не е преведена докрай

    # ⚠⚠ БРОЯТ БЛОКОВЕ ТРЯБВА ДА СЪВПАДА. `zip` по-долу би слепил мълчаливо
    # превода на един абзац с връзките на друг и би отрязал остатъка — точно
    # класът тиха грешка, който този проект плаща най-скъпо. Разминат ли се
    # (напр. след промяна в разчитането), дялът се връща за нов превод.
    разминати = [i for i, sec in enumerate(d['sections'])
                 if len(b['sections'][str(i)]['blocks_bg']) != len(sec['blocks'])]
    if разминати:
        print('  ⚠ %s: дялове с разминат брой блокове %s — прескачам'
              % (слъг, разминати))
        return None

    имг = картинки.get(слъг, [])
    части = []

    def картинка(k):
        if k >= len(имг):
            return
        im = имг[k]
        мерки = (' width="%d" height="%d"' % (im['width'], im['height'])
                 if im.get('width') else '')
        части.append('<img src="assets/lives_images/%s" alt="%s"%s>'
                     % (im['file'], html.escape(im.get('alt') or '', quote=True), мерки))

    # ⚠⚠ ЗАГЛАВИЕТО НА СТАТИЯТА ВЛИЗА В САМОТО ЧЕТИВО.
    #
    # Четецът слага свое заглавие САМО ако четивото няма собствено
    # `<h1>`–`<h6>`. Статиите имат `<h3>` на всеки дял, тъй че той решаваше
    # „има си заглавие" и не слагаше нищо — а първото `<h3>` е на ВТОРИЯ
    # дял. Отвън: статията започва без заглавие. (Докладвано от потребителя,
    # 20.09.2026.) Същата подредба като в житията: заглавие, после уводът.
    заглавие = b.get('title_bg') or d.get('title_ru') or ''
    if заглавие:
        части.append('<h3>%s</h3>' % html.escape(заглавие))
    картинка(0)
    for i, s in enumerate(d['sections']):
        п = b['sections'][str(i)]
        if п['title_bg']:
            части.append('<h3 id="s%d">%s</h3>' % (i, html.escape(п['title_bg'])))
        if i > 0:
            картинка(i)                  # останалите — пред следващите дялове
        for j, (текст, блок) in enumerate(zip(п['blocks_bg'], s['blocks'])):
            тяло = връзки(текст, блок.get('links') or [], налични)
            # ⚠⚠ КУРСИВЕН Е САМО ПЪРВИЯТ БЛОК, НЕ ЦЕЛИЯТ НУЛЕВ ДЯЛ.
            #
            # Нулевият дял е „всичко преди първото <h2>" — при повечето
            # статии това е целият увод, а при някои и цялото четиво:
            # пасхалният канон излизаше 214 абзаца приглушен курсив, а
            # „Благодатният огън" — десет. Освен това `splitDropCap` търси
            # ГОЛ `<p>`, тъй че буквицата прескачаше всичко това и падаше
            # чак след първото подзаглавие, насред статията.
            #
            # ⚠ Изворът НЕ бележи определението с нищо — проверено: то е
            # обикновен `<p>`. Затова признакът е МЯСТОТО: първият абзац
            # под заглавието е определението („Грях (гръц. …) – …"),
            # останалото е разказ.
            уводен = (i == 0 and j == 0)
            части.append('<p class="epigraph">%s</p>' % тяло if уводен
                         else '<p>%s</p>' % тяло)
    тяло = '\n'.join(части)
    return {'slug': слъг, 'title_bg': b.get('title_bg') or d.get('title_ru') or слъг,
            'title_ru': d.get('title_ru') or '', 'body': тяло,
            'source': d['url'], 'chars': len(re.sub(r'<[^>]+>', '', тяло))}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--stage', type=int)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    картинки = {}
    p = КОРЕН / 'work' / 'pages_img.json'
    if p.exists():
        картинки = json.loads(p.read_text(encoding='utf-8'))

    редове = list(csv.DictReader(open(СПИСЪК, encoding='utf-8')))
    if a.stage:
        редове = [r for r in редове if int(r['stage']) == a.stage]
    налични = преведени_слъгове()

    # ⚠⚠ ЕДИН СЛЪГ СЕ СРЕЩА ПО НЯКОЛКО ПЪТИ В СПИСЪКА. Няколко различни
    # адреса на сайта водят до една и съща страница („pasha" и „pasxa" са
    # по четири реда). Докато преводите им ги нямаше, `сглоби` връщаше
    # None и повторението не личеше; щом излязоха готови, записът гръмна с
    # „UNIQUE constraint failed: articles.slug" — и то СЛЕД `DROP TABLE`,
    # тъй че таблицата остана ПРАЗНА. Затова се дедуплицира тук.
    статии, чакат, видени = [], [], set()
    for r in редове:
        if r['slug'] in видени:
            continue
        видени.add(r['slug'])
        рец = сглоби(r['slug'], налични, картинки)
        (статии if рец else чакат).append(рец or r['slug'])

    for с in статии:
        print('  %-26s %6d знака  %2d връзки  %s'
              % (с['slug'], с['chars'], с['body'].count('<a href'),
                 'картинка' if '<img' in с['body'] else ''))
    print('готови: %d | непреведени докрай: %d' % (len(статии), len(чакат)))
    if чакат:
        print('   чакат:', ', '.join(чакат[:8]))
    if a.dry_run or not статии:
        return 0

    КОПИЯ.mkdir(exist_ok=True)
    коп = КОПИЯ / ('lives.db.bak-%s' % time.strftime('%Y%m%d_%H%M%S'))
    shutil.copy2(БАЗА, коп)
    print('копие:', os.path.relpath(коп, ПРОЕКТ))

    db = sqlite3.connect(БАЗА)
    db.executescript(СХЕМА)
    db.executemany(
        'INSERT INTO articles (slug,title_bg,title_ru,body,source,chars)'
        ' VALUES (?,?,?,?,?,?)',
        [(с['slug'], с['title_bg'], с['title_ru'], с['body'], с['source'],
          с['chars']) for с in статии])
    db.commit()
    print('в базата:', db.execute('SELECT count(*) FROM articles').fetchone()[0])
    db.close()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
