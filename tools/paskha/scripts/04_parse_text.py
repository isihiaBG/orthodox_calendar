#!/usr/bin/env python3
"""Основният текст за Пасха → `work/text.json`. Без мрежа.

    cache/page1.html → увод + 17 дяла със заглавия, връзките и картинката

⚠⚠ ОСНОВНАТА СТРАНИЦА Е `/paskha/1`. Адресите в съдържанието сочат
„1/#ch_0_N"; `/paskha` връща същия HTML, но е по-лесно да се сбърка, че
текстът е другаде.

⚠⚠ „ЛИТЕРАТУРА ПО ТЕМЕ" СЕ СРЕЩА И ГОРЕ В НАВИГАЦИЯТА. Отрязан по ПЪРВОТО
срещане, целият текст изчезва и статията излиза с нула абзаца — точно това
ме подведе първия път. Краят се търси с `rfind`.

⚠⚠ ЕДИН АБЗАЦ Е БЕЗ ЗАТВАРЯЩ ТАГ. В дяла „Когато у храмов… престольный
праздник?" стои `<p>…текст…</div>` — без `</p>`. Изразът `<p>(.*?)</p>` не го
хваща и дялът излиза ПРАЗЕН, мълчаливо. Затова абзацът се затваря и по
следващия `<p`/`</div`.

    python3 04_parse_text.py
"""
import html as _html
import json
import re
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
КЕШ = КОРЕН / 'cache'
РАБОТА = КОРЕН / 'work'

RE_TAG = re.compile(r'<[^>]+>')
RE_ABZAC = re.compile(r'<p[^>]*>(.*?)(?:</p>|(?=<p[\s>])|(?=</div))', re.S)
# ⚠⚠ И ЕДИНИЧНИ КАВИЧКИ. Страницата пише енциклопедичните връзки с
# `href='…'` (клас `bg_hlnames`) — 39 от 94-те. Израз само за двойни ги
# подминаваше МЪЛЧАЛИВО: 14 намерени вместо 53.
RE_LINK = re.compile(r'''<a\s[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>''', re.S)

# ⚠ Навигацията на сайта, която не е част от статията — по ТОЧЕН адрес.
#
# ⚠⚠ НЕ по подниз. Първата версия пазеше „azbyka.ru/$" с намерението да
# изключи само началната страница, а `strip('$')` го превръщаше в
# „azbyka.ru/" — то се съдържа във ВСЯКА връзка и филтърът изяде 79 от 95,
# мълчаливо. Затова тук стоят цели адреси и сравнението е за равенство.
НЕ_СА_ЧЕТИВО = {
    'https://azbyka.ru/', 'https://azbyka.ru',
    'https://azbyka.ru/pravkurs', 'https://azbyka.ru/dictionary',
    'https://azbyka.ru/auth', 'https://azbyka.ru/1/s-chego-nachat',
}


def гол(html: str) -> str:
    """HTML → гол текст.

    ⚠⚠ РАЗЕКРАНИРА И ЧИСЛОВИТЕ СЪЩНОСТИ (`&#1044;` → „Д"). Част от
    страниците в azbyka.ru дават ЦЕЛИЯ кирилски текст така — една буква
    става осем знака. Дотук се заменяха само именуваните, тъй че текстът
    минаваше нататък екраниран: преводът излизаше верен (моделът се справя),
    но обемът изглеждаше ПЕТ ПЪТИ по-голям и порциите се режеха на къса
    ръка. „Вера" излизаше 200 152 знака вместо истинските 34 330.
    """
    s = re.sub(r'<br\s*/?>', ' ', html, flags=re.I)
    s = RE_TAG.sub('', s)
    # ⚠ `html.unescape` поема И именуваните, И числовите — заменките по-долу
    # вече са излишни, но остават безвредни за низ, минал само през тях.
    s = _html.unescape(s)
    s = s.replace('\xa0', ' ')
    return re.sub(r'\s+', ' ', s).strip()


def абзаци(html: str) -> list[dict]:
    out = []
    for сурово in RE_ABZAC.findall(html):
        txt = гол(сурово)
        if len(txt) < 25:
            continue
        връзки = []
        for href, име in RE_LINK.findall(сурово):
            nm = гол(име)
            if not nm or href.startswith('#'):
                continue
            if href.startswith('//'):
                href = 'https:' + href
            elif href.startswith('/'):
                href = 'https://azbyka.ru' + href
            # ⚠ Сравнението е СЛЕД нормализирането на адреса — инак
            # относителният „/auth" никога не съвпада с пълния.
            if href.rstrip('/') in {x.rstrip('/') for x in НЕ_СА_ЧЕТИВО}:
                continue
            връзки.append({'text': nm, 'url': href})
        out.append({'ru': txt, 'links': връзки})
    return out


def main() -> int:
    РАБОТА.mkdir(parents=True, exist_ok=True)
    t = (КЕШ / 'page1.html').read_text(encoding='utf-8')
    i = t.find('main-page-content')
    j = t.rfind('Литература по теме')
    body = t[i:j]

    # ⚠ Съдържанието на страницата (списъкът с котви) стои ВЪТРЕ в тялото и
    # трябва да отпадне — инак 18 заглавия влизат като текст.
    k = body.find('</ul>', body.find('id=toc'))
    if k > 0:
        body = body[k:]

    части = re.split(r'<h2[^>]*>(.*?)</h2>', body, flags=re.S)
    дялове = [{'title_ru': '', 'blocks': абзаци(части[0])}]
    for n in range(1, len(части) - 1, 2):
        дялове.append({'title_ru': гол(части[n]),
                       'blocks': абзаци(части[n + 1])})

    # ⚠ Картинката — единствената същинска на страницата.
    картинка = None
    for m in re.finditer(r'<img[^>]+>', body):
        src = re.search(r'src="([^"]+)"', m.group(0))
        if src and 'wp-content/uploads' in src.group(1):
            alt = re.search(r'alt="([^"]*)"', m.group(0))
            картинка = {'url': src.group(1),
                        'alt': гол(alt.group(1)) if alt else ''}
            break

    данни = {'source': 'https://azbyka.ru/paskha/1',
             'image': картинка, 'sections': дялове}
    (РАБОТА / 'text.json').write_text(
        json.dumps(данни, ensure_ascii=False, indent=1), encoding='utf-8')

    зн = sum(len(b['ru']) for d in дялове for b in d['blocks'])
    вр = sum(len(b['links']) for d in дялове for b in d['blocks'])
    празни = [d['title_ru'] for d in дялове if not d['blocks']]
    print(f'дялове {len(дялове)} | абзаци '
          f'{sum(len(d["blocks"]) for d in дялове)} | знаци {зн:,}')
    print(f'връзки в текста: {вр}')
    print(f'картинка: {картинка["url"] if картинка else "НЯМА"}')
    if празни:
        print(f'⚠ ПРАЗНИ ДЯЛОВЕ ({len(празни)}):')
        for p in празни:
            print(f'   {p[:70]}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
