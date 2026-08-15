#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
01_extract.py — Стъпка 1 (МЕХАНИЧНА, безплатна): разглобява двата тома на
„Симфония по творениям преподобных Оптинских старцев" до отделни откъси.

НИЩО не пише в бази — само в ../work/. Пуска се колкото пъти трябва.

Устройството на книгата
-----------------------
Симфонията е тематичен речник, не сборник по дни: всеки дял е тема
(АД, АЗБУКА, … Я), подредена по азбучен ред — том 1 носи А–О, том 2 П–Я.
Вътре в дяла откъсите са разделени с „* * *", а всеки завършва с атрибуция
от вида „(прп. Амвросий, 3, ч. 2)": старец + номер на източника от
библиографията + част.

⚠ Разделителят „* * *" САМ ПО СЕБЕ СИ не стига. Някои дялове започват с
епиграф в курсив, който не е отделен с нищо от първия откъс, и двата се
слепват в един. Затова откъсът се затваря по ДВА признака: „* * *" ИЛИ
абзац, който свършва с атрибуция. Атрибуцията е надеждният от двата —
всеки откъс си я носи.

Какво става с разметката
------------------------
  <em>…</em>            цитат от Писанието → обвива се в «…», точно както
                        при Теофан: моделът пази знаците, а 04_build_db.py
                        ги превръща в <span class="cite">.
  <a href="…?Mt.11:29"> препратка към Писанието → запушалка ⟦N⟧; надписът
                        се пресъздава машинно от кода (common.bulgarian_ref),
                        а НЕ се превежда.
  <a …#note170>170</a>  бележка под линия → МАХА СЕ. Тя пояснява остаряла
                        руска дума („заушение – удар с ръка по бузата"),
                        която в българския превод така или иначе изчезва;
                        а в кутийка от три реда в дневния изглед няма къде
                        да се отвори. Текстът ѝ (стои в title атрибута) се
                        пази в справочното поле `notes`, за да не се губи.

Вход:
  ../input/*.epub

Изход:
  ../work/quotes.json      всички откъси, с признаци за подбора
  ../work/sources.json     библиографията (номер → заглавие)
  ../work/extract.tsv      същото в плосък вид, за оглед в таблица

Употреба:
  python3 01_extract.py
  python3 01_extract.py --topic СМИРЕНИЕ    # оглед на един дял
"""

import argparse
import difflib
import glob
import html
import json
import os
import re
import sys
import zipfile
from collections import Counter, defaultdict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
INPUT_DIR = os.path.join(PROJECT_DIR, 'input')
WORK_DIR = os.path.join(PROJECT_DIR, 'work')

# Атрибуцията в края на откъса. Изданието не е последователно: среща се и
# слепено („прп.Макарий"), и с точка вместо запетая, и с част („ч. 2").
RE_ATTR = re.compile(
    r'\(\s*(?:прп|при|св|схиигум|игум)\.?\s*'
    r'([А-ЯЁ][а-яё]+)\s*[,.]?\s*(\d+)?\s*,?\s*(ч\.\s*\d+)?\s*\)\s*\.?\s*$')

RE_BLOCK = re.compile(r'<(p|div)[^>]*>(.*?)</\1>', re.S)
RE_H1 = re.compile(r'<h1[^>]*>(.*?)</h1>', re.S)
RE_SEP = re.compile(r'^[\*\s∗•]{3,}$')

# Препратка към Писанието: azbyka.ru/biblia/?Mt.11:29
RE_BIBLE = re.compile(
    r'<a\s[^>]*href="[^"]*azbyka\.ru/biblia/\?([^"&]+)[^"]*"[^>]*>(.*?)</a>',
    re.S)
# Бележка под линия: <a href="index_split_443.xhtml#note170" title="…"><sup>N</sup></a>
# Атрибутите се хващат вкупом и се разчитат отделно — редът им се мени от
# файл на файл, а с незадължителна група в самия израз title мълчаливо
# излиза празен (незадължителното съвпада с нищо още на първия знак).
RE_NOTE = re.compile(r'<a\s([^>]*)>\s*<sup[^>]*>\s*(\d+)\s*</sup>\s*</a>', re.S)
RE_TITLE = re.compile(r'title="([^"]*)"')
RE_EM = re.compile(r'<em[^>]*>(.*?)</em>', re.S)
# Целият абзац е един курсив — епиграф на дяла, а не цитат от Писанието.
RE_ALL_EM = re.compile(r'^\s*<em[^>]*>(.*)</em>\s*$', re.S)

# Имената на старците в утвърдения им български вид. Изданието бърка
# понякога („Варсонфоий", „Илларион", „Макария") — тук се изправя веднъж.
#
# ⚠ „Лев" НЕ става „Лъв". Собствените имена не се превеждат по смисъл —
# светията се казва прп. Лев Оптински. (Поправено 14.08.2026; дотогава
# картата го превеждаше и в базата бяха влезли 428 записа с „Лъв".)
ELDERS = {
    'Лев': 'Лев', 'Макарий': 'Макарий', 'Макария': 'Макарий',
    'Моисей': 'Моисей', 'Антоний': 'Антоний', 'Иларион': 'Иларион',
    'Илларион': 'Иларион', 'Амвросий': 'Амвросий', 'Анатолий': 'Анатолий',
    'Исаакий': 'Исаакий', 'Иосиф': 'Иосиф', 'Варсонофий': 'Варсонофий',
    'Варсонфоий': 'Варсонофий', 'Нектарий': 'Нектарий', 'Никон': 'Никон',
}

# Източници, които са СБОРНИЦИ С ПИСМА. Откъсите оттам по-често са отговор
# до конкретен човек („пишеш ми, че…") и по-рядко стоят сами. Не се
# изхвърлят — сред тях са и най-хубавите сентенции — но при подбора отстъпват
# на житията и беседите. Номерата са от библиографията в края на том 2.
LETTER_SOURCES = {'1', '3', '5', '17', '19', '30', '31'}

# Признаци, че откъсът е част от разговор, а не самостойна мисъл. Първата
# група преразказва какво е казал събеседникът, втората говори за нещо, което
# той вече е сторил („ти отиде", „вие наложихте") — и двете увисват без
# писмото, на което отговарят.
RE_PERSONAL = re.compile(
    r'(ты пишешь|вы пишете|пишешь|пишете|писала|писали|письм|спрашиваешь|'
    r'описала|жалуешься|скорбишь|благословение тебе|отвечаю|'
    r'говоришь|говорите|уведомл\w+|описываешь|описываете|сказываешь|'
    r'сетуешь|вопрошаешь|доносишь|изъясняешь|'
    r'Н\.\s?Н\.|м\.\s?[А-Я]\.)', re.I)
RE_PAST_YOU = re.compile(r'\b(ты|вы)\s+(не\s+)?\w+(ал|ала|ил|ила|ел|ела|'
                         r'али|или)\b', re.I)
# „Меня/мне" извън кавички е самият старец — значи разговор. Вътре в кавички
# е молещият се („Господи, даждь ми терпение") и не значи нищо такова.
RE_FIRST = re.compile(r'\b(меня|мне|мною)\b', re.I)
# Второ лице изобщо — по-мек признак от горния. „Ти" в поучение е съвсем на
# място (цялата книга на свт. Теофан е на „ти"), тъй че само се отбелязва.
RE_SECOND = re.compile(r'\b(теб[ея]|тво[йяею]|твои\w*|вам|ваш\w*|вас)\b', re.I)
# Първо лице на самия старец — „моето здраве", „съветите ми". Заедно с второ
# лице значи разговор, не поучение.
RE_MINE = re.compile(r'\b(мо[йяеё]\w*|мои\w*|меня|мне|мною)\b', re.I)
# Лицето, за което става дума, е назовано съкратено: „Т. У.", „Н-а", „N. N."
# и — най-често — с ЕДИН инициал: „Ссоры и споры с А.", „отцу И.". Изразът за
# единичния нарочно не хваща началото на изречение („А. Впрочем…") и
# съкращенията на библейските книги, които са с две и повече букви.
RE_NAMED = re.compile(r'(\b[А-Я]\.\s?[А-Я]\.|\b[А-Я][-–][а-я]{1,4}\b|'
                      r'\bN\.?\s?N\.?\b|\bNN\b|\b[А-Я]\.(?!\s?[А-Я]?[а-я]))')
# Роднина на събеседника — „брата твоего Господь да избави от виното".
# Двата словореда са отделни израза: руският слага притежателното и преди, и
# след съществителното, а един израз с алтернатива би хващал и „твоя воля е
# брат на страстта".
_KIN = r'(брат\w*|сестр\w*|муж\w*|жен\w*|сын\w*|доч\w*|мат\w*|отц\w*|дет\w*|племянни\w*)'
_YOUR = r'(тво(й|его|ему|ем|я|ей|ю|и|их|им)|ваш\w*)'
RE_KIN = re.compile(r'\b%s\s+%s|\b%s\s+%s' % (_YOUR, _KIN, _KIN, _YOUR), re.I)
# Кавичките се изваждат, преди да се търси първо лице: в „Господи, даждь ми
# терпение" то е на молещия се, не на стареца, и не прави откъса разговор.
RE_QUOTED = re.compile(r'«[^«»]*»')
# Речник, който предполага, че четящият ЖИВЕЕ в манастир: „скорбите от
# игуменката понасяй", „преди дълга към манастира". Такъв откъс увисва пред
# мирянина, отворил календара сутринта.
#
# ⚠ Нарочно е ИНСТИТУЦИОНАЛЕН, а не всяко срещане на „монах". „На въпроса на
# един инок как да победи гордостта старецът отговори…" е поучение за всекиго
# — монахът там е само рамката на разказа. Отсече ли се и то, губят се едни от
# най-хубавите, без нищо да се печели.
# ⚠ БРОЕНИЦАТА НЕ Е ТУК и не бива да се връща. Тя не е манастирско
# учреждение, а молитвено помагало, което мирянинът също държи в ръка —
# изрично решение на потребителя.
RE_MONASTIC = re.compile(
    r'\b(обител\w*|монастыр\w*|скит\w*|игумен\w*|настоятел\w*|послушник\w*|'
    r'постриг\w*|келл?и\w*|схимн\w*|мантия|новоначальн\w*)\b', re.I)

# Откъслечно начало: изречението продължава мисъл, която я няма.
#
# Второто правило лови сочещото навън начало „О тех…", „О том же…". То не се
# познава по темата, а по формата: „За онези пари: купи каквото ти трябва, а
# останалите върни" е съвършено смислено В ПИСМОТО и напълно безсмислено
# самò. Филтър по думата „пари" би сбъркал адреса — щеше да отсече и хубавите
# поучения за богатството, а тази щеше да мине, ако беше за друго.
RE_DANGLING = re.compile(r'^(Но |А |И |Что |Впрочем|Итак|Посему|Также|Еще |'
                         r'Затем|Далее|Оным|Сие |Тем |При том|Притом|'
                         r'Об? (тех|том|той|оном|сем|этом|этих)\b)')


# Латински двойници сред кирилицата — останали от разпознаването на текста.
# „K" в „Kрещение" е латинско в 193 случая; засегнати са 166 откъса. Дребно,
# но се лекува само тук: по-нататък думата не се търси по букви, а моделът
# я вижда като чужда буква насред руска дума.
RE_LATIN = re.compile(r'(?<![A-Za-z])([KCcOopPAaBEHMTXxyeu])(?=[а-яА-ЯёЁ])')
LATIN_TO_CYR = str.maketrans('KCcOopPAaBEHMTXxyeu', 'КСсОорРАаВЕНМТХхуеи')


def unescape(s):
    s = html.unescape(s).replace('\xa0', ' ').replace(' ', ' ')
    return RE_LATIN.sub(lambda m: m.group(1).translate(LATIN_TO_CYR), s)


def plain(s):
    """Маха всичко останало от разметката и нормализира интервалите."""
    s = re.sub(r'<br[^>]*/?>', '\n', s)
    s = re.sub(r'<[^>]+>', '', s)
    return re.sub(r'[ \t]+', ' ', unescape(s)).strip()


def sentences(text):
    return len(re.findall(r'[.!?…](?:\s|$)', text))


def markup(block, atoms, notes):
    """HTML на един абзац → текст със запушалки ⟦N⟧ и кавички «…».

    Връща текста; `atoms` и `notes` се допълват на място. Редът е важен:
    първо бележките (за да не влязат в цитата), после Писанието, накрая
    курсивът.
    """
    def take_note(m):
        attrs, num = m.group(1), m.group(2)
        if '#note' not in attrs:
            return m.group(0)
        title = RE_TITLE.search(attrs)
        notes.append({'n': int(num),
                      'body_ru': unescape(title.group(1)).strip()
                      if title else ''})
        return ''

    block = RE_NOTE.sub(take_note, block)
    # Останали голи <sup> без връзка — също са номера на бележки.
    block = re.sub(r'<sup[^>]*>\s*\d+\s*</sup>', '', block)

    def take_ref(m):
        code = unescape(m.group(1)).strip()
        atoms.append({'n': len(atoms) + 1, 'code': code,
                      'text_ru': plain(m.group(2))})
        return '⟦%d⟧' % len(atoms)

    block = RE_BIBLE.sub(take_ref, block)

    # Курсивът в тази книга е цитат — от Писанието или богослужебен. Обвива
    # се в «…», ако вече не е в кавички.
    #
    # ⚠ Освен когато е ЦЕЛИЯТ абзац: тогава е епиграф на дяла — думи на самия
    # старец, отделени с курсив по оформителски съображения. Обвиеше ли се,
    # атрибуцията му остава вътре в кавичките и не се разпознава.
    if RE_ALL_EM.match(block):
        block = RE_ALL_EM.match(block).group(1)

    def quote(m):
        inner = plain(m.group(1))
        if not inner:
            return ''
        if inner.startswith('«') and inner.endswith('»'):
            return inner
        # Крайната пунктуация остава ИЗВЪН кавичките, за да не се получи «…,»
        tail = ''
        while inner and inner[-1] in ' ,.;:':
            tail = inner[-1] + tail
            inner = inner[:-1]
        return '«%s»%s' % (inner, tail) if inner else tail

    block = RE_EM.sub(quote, block)
    text = plain(block)
    # Пренасянията вътре в абзаца са оформителски (<br> около цитатите) —
    # в едно изречение от три реда те само чупят изгледа.
    text = re.sub(r'\s*\n\s*', ' ', text)
    # Изданието понякога изяжда интервала след затварящ курсив: „…»к“, „…»(“.
    text = re.sub(r'»(?=[^\s.,;:!?…»)])', '» ', text)
    return re.sub(r'[ \t]+', ' ', text).strip()


def read_epub(path):
    """Връща {име: съдържание} за xhtml файловете в архива."""
    with zipfile.ZipFile(path) as z:
        return {os.path.basename(n): z.read(n).decode('utf-8')
                for n in z.namelist() if n.endswith(('.xhtml', '.html'))}


def parse_sources(files):
    """Библиографията в края на том 2 → {номер: заглавие}."""
    for name, s in files.items():
        if 'ИСПОЛЬЗОВАННАЯ ЛИТЕРАТУРА' not in s:
            continue
        out = {}
        for b in RE_BLOCK.findall(s):
            t = plain(b[1])
            m = re.match(r'(\d+)\.\s+(.+)', t)
            if m:
                out[m.group(1)] = m.group(2).strip()
        return out
    return {}


def chapters(files):
    """Само тематичните дялове: без заглавната страница и без бележките."""
    for name in sorted(files):
        if not name.startswith('index_split_'):
            continue
        s = files[name]
        m = RE_H1.search(s)
        if not m:
            continue
        title = plain(m.group(1))
        if not title or re.fullmatch(r'\d+', title):
            continue                       # дял с бележка под линия
        if 'Симфония по творениям' in title or 'ЛИТЕРАТУРА' in title:
            continue
        yield name, title, s[m.end():]


def split_quotes(body):
    """Абзаците на един дял → списък от откъси (всеки: списък от абзаци).

    Затваря откъса по „* * *" ИЛИ по абзац, завършващ с атрибуция. Виж
    предупреждението в началото на файла защо и двете са нужни.
    """
    out, cur = [], []
    for raw in RE_BLOCK.findall(body):
        block = raw[1]
        if not plain(block):
            continue
        if RE_SEP.match(plain(block)):
            if cur:
                out.append(cur)
                cur = []
            continue
        cur.append(block)
        if RE_ATTR.search(plain(block)):
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return out


def extract_vol(path, vol, sources):
    files = read_epub(path)
    quotes = []
    topics = 0
    for name, topic, body in chapters(files):
        topics += 1
        for i, blocks in enumerate(split_quotes(body), 1):
            atoms, notes = [], []
            parts = [markup(b, atoms, notes) for b in blocks]
            text = ' '.join(p for p in parts if p)
            m = RE_ATTR.search(text)
            elder = src = part = None
            if m:
                elder = ELDERS.get(m.group(1), m.group(1))
                src, part = m.group(2), (m.group(3) or '').replace(' ', '')
                text = text[:m.start()].strip()
            # Останала атрибуция в средата значи, че разделянето е сгрешило.
            text = re.sub(r'\s+([,.;:])', r'\1', text).strip()
            if len(text) < 20:
                continue
            quotes.append({
                'id': 'v%d-%s-%02d' % (vol, name[12:15], i),
                'vol': vol, 'topic_ru': topic,
                'elder': elder, 'src': src, 'src_part': part,
                'src_title': sources.get(src or '', ''),
                'body_ru': text,
                'atoms': atoms, 'notes': notes,
                # Признаци за 02_select.py — смятат се тук, защото зависят от
                # руския текст, и се записват, за да са видими при преглед.
                'flags': {
                    'len': len(text),
                    'sentences': sentences(text),
                    'letters': (src or '') in LETTER_SOURCES,
                    'personal': bool(RE_PERSONAL.search(text)
                                     or RE_PAST_YOU.search(text)),
                    'firstperson': bool(RE_FIRST.search(RE_QUOTED.sub('',
                                                                     text))),
                    'second': bool(RE_SECOND.search(text)),
                    'dialogue': bool(RE_SECOND.search(text)
                                     and RE_MINE.search(RE_QUOTED.sub('',
                                                                      text))),
                    'named': bool(RE_NAMED.search(text)),
                    'kin': bool(RE_KIN.search(text)),
                    'bracket': text.startswith('['),
                    'monastic': bool(RE_MONASTIC.search(text)),
                    'dangling': bool(RE_DANGLING.match(text)),
                    'ellipsis': text.endswith(('…', '..')) or '…' in text,
                    'refs': len(atoms),
                    'notes': len(notes),
                },
            })
    return topics, quotes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--topic', help='отпечатва един дял и спира')
    args = ap.parse_args()

    epubs = sorted(glob.glob(os.path.join(INPUT_DIR, '*.epub')))
    if len(epubs) != 2:
        print('Очаквах два .epub файла в %s, намерих %d.' % (INPUT_DIR,
                                                             len(epubs)))
        sys.exit(1)

    sources = parse_sources(read_epub(epubs[1]))
    print('библиография: %d източника' % len(sources))

    all_quotes, ntopics = [], 0
    for vol, path in enumerate(epubs, 1):
        n, qs = extract_vol(path, vol, sources)
        ntopics += n
        all_quotes.extend(qs)
        print('том %d: %3d дяла, %4d откъса — %s'
              % (vol, n, len(qs), os.path.basename(path)[:52]))

    # Дублетите в книгата са малко (една и съща мисъл под две теми), но има.
    #
    # ⚠ Част от тях НЕ са буквални. „Но не поропщи, ибо всякий идущий этим
    # путем" и „Но не ропщи, ибо всякий, идущий этим путем" са едно и също
    # място, набрано два пъти — сравнението на целия текст ги пропуска, а и
    # на началото също, защото разликата пада на 52-рия знак.
    #
    # Затова: откъсите се групират по първите 40 знака (за да не се сравнява
    # всеки с всеки — 4500² е много), а вътре в групата се мерят с
    # SequenceMatcher. Над 0,85 прилика е една и съща мисъл. По-дългият
    # печели, защото по-късият обикновено е отрязан.
    seen, buckets, uniq = {}, defaultdict(list), []
    for q in sorted(all_quotes, key=lambda q: -len(q['body_ru'])):
        k = re.sub(r'[^\w]+', '', q['body_ru'].lower())
        twin = seen.get(k)
        if twin is None:
            for other, ok in buckets[k[:40]]:
                if difflib.SequenceMatcher(None, ok, k).ratio() > 0.85:
                    twin = other
                    break
        if twin is not None:
            twin['also_in'].append(q['topic_ru'])
            continue
        q['also_in'] = []
        seen[k] = q
        buckets[k[:40]].append((q, k))
        uniq.append(q)
    uniq.sort(key=lambda q: q['id'])

    os.makedirs(WORK_DIR, exist_ok=True)
    with open(os.path.join(WORK_DIR, 'quotes.json'), 'w',
              encoding='utf-8') as fh:
        json.dump(uniq, fh, ensure_ascii=False, indent=1)
    with open(os.path.join(WORK_DIR, 'sources.json'), 'w',
              encoding='utf-8') as fh:
        json.dump(sources, fh, ensure_ascii=False, indent=1)
    with open(os.path.join(WORK_DIR, 'extract.tsv'), 'w',
              encoding='utf-8') as fh:
        fh.write('id\tтом\tтема\tстарец\tизточник\tзнаци\tизр.\tтекст\n')
        for q in uniq:
            fh.write('%s\t%d\t%s\t%s\t%s\t%d\t%d\t%s\n'
                     % (q['id'], q['vol'], q['topic_ru'], q['elder'] or '',
                        q['src'] or '', q['flags']['len'],
                        q['flags']['sentences'], q['body_ru']))

    print('-' * 64)
    print('дялове: %d | откъси: %d | уникални: %d'
          % (ntopics, len(all_quotes), len(uniq)))
    noattr = sum(1 for q in uniq if not q['elder'])
    print('без атрибуция: %d' % noattr)
    print('с препратки към Писанието: %d | с бележки: %d'
          % (sum(1 for q in uniq if q['atoms']),
             sum(1 for q in uniq if q['notes'])))
    by = Counter(q['elder'] for q in uniq if q['elder'])
    print('по старци: ' + ', '.join('%s %d' % kv for kv in by.most_common()))
    lens = sorted(q['flags']['len'] for q in uniq)
    print('дължини: медиана %d, ≤150 знака %d, ≤220 знака %d'
          % (lens[len(lens) // 2],
             sum(1 for l in lens if l <= 150),
             sum(1 for l in lens if l <= 220)))

    if args.topic:
        print('=' * 64)
        for q in uniq:
            if q['topic_ru'] == args.topic:
                print('· [%s] %s  (прп. %s, %s)'
                      % (q['id'], q['body_ru'], q['elder'], q['src']))
    print('→ %s' % WORK_DIR)


if __name__ == '__main__':
    main()
