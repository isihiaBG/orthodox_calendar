#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
02_select.py — Стъпка 2 (МЕХАНИЧНА, безплатна): избира 400 сентенции измежду
4550-те откъса — 366 за дните на годината и 34 в запас за подмяна.

НИЩО НЕ СЕ РЕЖЕ. Сентенцията влиза в базата цяла или изобщо не влиза.
Дължината участва само като ПРЕДПОЧИТАНИЕ в оценката: къс афоризъм печели
пред дълъг, но дълъг с добра мисъл спокойно бие къс без такава — и остава
единствен избор за тема, в която няма нищо по-стегнато. Твърдият таван
(--max-len, по подразбиране 600 знака) отрязва само цели писма, които не
биха се побрали в кутийката на дневния изглед при никакъв шрифт.

Трите изисквания и как се удовлетворяват
----------------------------------------
1. ВСИЧКИ СТАРЦИ ПОЧТИ ПО РАВНО. Равно поравно е невъзможно: прп. Исаакий
   има 7 откъса в цялата симфония, прп. Нектарий — 27, докато прп. Амвросий
   има 1224. Затова квотата се смята с „водно запълване": оскъдните старци
   влизат с всичко, което имат, а излишъкът се дели поравно между едрите.
   При 400 излиза по 37 за деветимата едри, 24 за прп. Нектарий и 7 за
   прп. Исаакий.

2. ВСИЧКИ ТЕМИ. Симфонията има 509 дяла, а местата са 400 — покриването на
   всичките е аритметически невъзможно. Затова: НАЙ-МНОГО ПО ЕДНА сентенция
   от тема (така покриваме 400 различни, вместо да трупаме по три от
   „Молитва"), а изпадат най-малките и най-страничните дялове. Кои точно —
   изписва се в selection.md, за да може да се преглежда и да се възразява.
   67 дяла отпадат сами: там всеки откъс е цяло писмо от порядъка на
   хиляда знака.

3. ЗАПАС ЗА ПОДМЯНА. Избраните са 400, но дни получават 366. Останалите 34
   стоят в базата с day = NULL и чакат: види ли се, че някоя не пасва,
   заменя се с връстница от същия старец, без нов превод и без нов разход.

Ръчна намеса: ../work/manual_select.json (ако го има)
    {"drop": ["v1-198-03"], "keep": ["v2-014-02"], "day": {"v1-020-01": "03-25"}}
  `drop` изхвърля, `keep` налага независимо от оценката, `day` заковава дата.
  Файлът има превес над всичко тук и оцелява при повторно пускане.

Вход:   ../work/quotes.json          (от 01_extract.py)
Изход:  ../work/selected.json        400-те, с дата и оценка
        ../work/selection.md         за преглед с очи, преди да се плаща
        ../work/dropped_topics.txt   темите, останали извън избора

Употреба:
  python3 02_select.py
  python3 02_select.py --total 400 --max-len 600
  python3 02_select.py --show ЛЮБОВЬ      # всички кандидати по тема
"""

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
WORK_DIR = os.path.join(PROJECT_DIR, 'work')

# Дължината, при която сентенцията се чете на един дъх в кутийка от три-четири
# реда. Извън този прозорец оценката пада плавно — не рязко.
SWEET_LOW, SWEET_HIGH = 80, 260

DAYS_IN_MONTH = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


# Дялове, които изобщо не влизат в жребия. Тук стоят теми, чийто СПОР е
# отминал — не защото поучението е слабо, а защото въпросът не се задава
# вече. „За старообрядците може да се молим само с домашна молитва" е точен
# отговор на въпрос, който никой от четящите днешния календар не си задава.
#
# Изключването е на ниво ДЯЛ, а не по дума в текста: решението е „тази тема
# не ни трябва", а филтър по дума би отсякъл и всяко случайно споменаване в
# чужд дял, без да улови мълчаливите.
SKIP_TOPICS = {
    'СТАРООБРЯДЦЫ',
    # Краят на света, изведен от откриването на хипнозата.
    'ГИПНОЗ',
    # „Шахматната игра служи за губене на време." Безобидно на пръв поглед,
    # но за деня на човек, който играе шах, е упрек без повод.
    'ШАХМАТЫ',
    # И четирите годни тук обясняват КОЙ Е ВИНОВЕН за самоубийството или
    # какво чака самоубиеца отвъд („идат на самото дъно адово, и мъките им са
    # ужасни и безкрайни"). Няма как да се избере безопасна: човек, изгубил
    # свой близък така, ще прочете присъда над него, отворил календара за
    # деня. Дялът отпада цял.
    'САМОУБИЙСТВО',
    # Единствената годна тук е за „немощния съсъд женски" и за спасението
    # „чрез чадородие" — Писание, и краят ѝ е защита на жената („грешно е да
    # си презрителен към тях"). Но за жена без деца изречението е присъда, а
    # заместник в дяла няма.
    'ЖЕНА',
    # Единствената годна тук обявява поименно реален човек за погинал (гр.
    # Толстой). Присъда над определено лице не е работа на календара.
    'ГИБЕЛЬ',
}


def score(q):
    """Колко подхожда откъсът за сентенция на деня. По-високо е по-добре."""
    f = q['flags']
    s = 100.0

    # Дължина — плавно, в двете посоки.
    if f['len'] < SWEET_LOW:
        s -= (SWEET_LOW - f['len']) / 2.0
    elif f['len'] > SWEET_HIGH:
        s -= (f['len'] - SWEET_HIGH) / 12.0

    if f['sentences'] <= 1:
        s += 6                      # завършен афоризъм
    elif f['sentences'] >= 4:
        s -= 4 * (f['sentences'] - 3)

    if f['second']:
        s -= 10                     # „на теб" — все още върши работа
    if f['letters']:
        s -= 6                      # от сборник с писма
    if f['ellipsis']:
        s -= 14                     # многоточието е изпуснат текст
    if f['refs'] > 1:
        s -= 6 * (f['refs'] - 1)    # една препратка е добре, три са много
    if f['notes']:
        s -= 5                      # обяснявана остаряла дума
    if q['also_in']:
        s += 3                      # книгата я е сложила под две теми
    return round(s, 1)


def acceptable(q, max_len):
    """Твърдите правила. Отхвърля само това, което не може да стои само."""
    f = q['flags']
    if q['topic_ru'] in SKIP_TOPICS:
        return 'дял с отминал спор'
    if not q['elder']:
        return 'без атрибуция'
    if f['len'] < 40:
        return 'отломък'
    if f['len'] > max_len:
        return 'цяло писмо'
    if f['personal']:
        return 'отговор до определен човек'
    if f.get('named'):
        return 'назовава събеседника („Т. У.", „Н-а")'
    if f.get('dialogue') or f.get('firstperson'):
        return 'разговор (старецът говори за себе си)'
    if f.get('kin'):
        return 'за роднина на събеседника'
    if f.get('bracket'):
        return 'започва с редакторска вметка'
    if f.get('monastic'):
        return 'за живеещи в манастир'
    if f['dangling']:
        return 'започва насред мисъл'
    return None


def waterfill(available, total):
    """Квота по старци: оскъдните влизат целите, едрите делят остатъка.

    Наивното „total/брой старци" би поискало 33 от прп. Исаакий, който има
    7 — и трите му липсващи места просто щяха да се загубят.
    """
    quota, left, rest = {}, dict(available), total
    while left:
        share = rest / len(left)
        small = [e for e, n in left.items() if n <= share]
        if not small:
            for e in left:
                quota[e] = int(share)
            # Целочисленото деление остави трохи — на най-заможните.
            for e in sorted(left, key=lambda e: -available[e]):
                if sum(quota.values()) >= total:
                    break
                quota[e] += 1
            return quota
        for e in small:
            quota[e] = left.pop(e)
            rest -= quota[e]
    return quota


def pick(cands, total, manual):
    """Избира `total` откъса: най-много един на тема, с квота по старци.

    Два прохода. Първо оскъдните старци — иначе, докато стигнем до тях,
    хубавите им теми вече ще са заети от прп. Амвросий. После останалите,
    по важност на темата (за важност се брои колко е писано по нея).
    """
    by_topic = defaultdict(list)
    for q in cands:
        by_topic[q['topic_ru']].append(q)
    for lst in by_topic.values():
        lst.sort(key=lambda q: -q['score'])

    avail = Counter(q['elder'] for q in cands)
    quota = waterfill(avail, total)

    chosen, used_topics, used_elders = [], set(), Counter()

    def take(q):
        chosen.append(q)
        used_topics.add(q['topic_ru'])
        used_elders[q['elder']] += 1

    # Нулев проход: наложените на ръка.
    forced = {q['id']: q for q in cands if q['id'] in manual.get('keep', [])}
    for q in forced.values():
        take(q)

    # Проход 1 — по старци, от най-оскъдния към най-заможния.
    for elder in sorted(quota, key=lambda e: avail[e]):
        mine = sorted((q for q in cands if q['elder'] == elder),
                      key=lambda q: -q['score'])
        for q in mine:
            if used_elders[elder] >= quota[elder]:
                break
            if q['topic_ru'] in used_topics:
                continue
            take(q)

    # Проход 2 — останалите места, по важност на темата (за важност се брои
    # колко е писано по нея). Първо СТРОГО: гледат се само старци под квотата,
    # а тема, в която няма такъв, се подминава. Чак ако след това е останало
    # празно, се минава наново без ограничение — иначе местата, които прп.
    # Иларион не може да запълни (има само 49 откъса), просто щяха да се
    # загубят, вместо да отидат при някой друг.
    order = sorted(by_topic, key=lambda t: (-len(by_topic[t]), t))
    for strict in (True, False):
        for topic in order:
            if len(chosen) >= total:
                break
            if topic in used_topics:
                continue
            pool = by_topic[topic]
            if strict:
                pool = [q for q in pool
                        if used_elders[q['elder']] < quota.get(q['elder'], 0)]
                if pool:
                    take(max(pool, key=lambda q: q['score']))
            elif pool:
                # Преливането отива при най-малко натоварения спрямо квотата
                # си, не при най-високата оценка — иначе всичкото се струпва
                # при прп. Амвросий, който има най-много откъси.
                take(min(pool, key=lambda q: (
                    used_elders[q['elder']] / max(1, quota.get(q['elder'], 1)),
                    -q['score'])))

    # Проход 3 — РАЗМЯНА, без да се пипа списъкът с теми.
    #
    # Двата прохода отгоре са лакоми и подреждат старците по оскъдност, тъй
    # че най-заможните стигат последни и заварват хубавите си теми заети.
    # Така прп. Макарий, който има 571 годни откъса, излизаше с колкото прп.
    # Моисей с неговите 61. Тук всяка тема, заета от старец НАД дела си, се
    # предлага на старец ПОД неговия, стига и той да е писал по нея. Броят на
    # темите не се мени — мени се само чий глас се чува по всяка от тях.
    # ⚠ Указателят е по `id`, не по тема. Обикновено темата е единствена и
    # двете са едно и също, но наложените през `keep` нарочно делят тема
    # (осем сентенции за Иисусовата молитва) — указател по тема ги слепва в
    # една и мълчаливо изяжда седем от избора.
    holder = {q['id']: q for q in chosen}
    per_topic = Counter(q['topic_ru'] for q in chosen)
    for _ in range(50):
        moved = 0
        for qid, cur in list(holder.items()):
            if qid in forced or per_topic[cur['topic_ru']] > 1:
                continue
            if used_elders[cur['elder']] <= quota.get(cur['elder'], 0):
                continue
            alts = [q for q in by_topic[cur['topic_ru']]
                    if q['elder'] != cur['elder'] and q['id'] not in holder
                    and used_elders[q['elder']] < quota.get(q['elder'], 0)]
            if not alts:
                continue
            best = max(alts, key=lambda q: q['score'])
            used_elders[cur['elder']] -= 1
            used_elders[best['elder']] += 1
            del holder[qid]
            holder[best['id']] = best
            moved += 1
        if not moved:
            break

    return list(holder.values()), quota


def kindred(a, b):
    """Две теми от едно гнездо ли са? „БЛАГОДАРЕНИЕ" и „БЛАГОДАТЬ" са."""
    if a == b:
        return True
    if a.split()[0] == b.split()[0]:
        return True                     # „МОЛИТВА" и „МОЛИТВА ИИСУСОВА"
    return a[:6] == b[:6]               # общ корен


def assign_days(chosen, reserve_count, manual):
    """Раздава 366 дати; най-слабите остават в запас с day = None.

    ⚠ Датите се раздават ТУК, а не в превода — 04_build_db.py ги чете от
    selected.json. Така разбъркването им наново е безплатно: вече преведеното
    си стои, мени се само на кой ден се пада.

    Съседните дни трябва да се различават И по старец, И по тема. Простото
    кръгово редуване по старци върши първото, но не и второто: вътре в
    списъка на всеки старец темите стоят по азбучен ред и седмицата излиза
    БДЕНИЕ – БЕСПЕЧНОСТЬ – БЛАГА – БЛАГОДАРЕНИЕ. Затова всеки ден се избира
    с поглед назад към последните седем: наказва се повторение на стареца, на
    темата от същото гнездо и на началната буква, при това толкова по-силно,
    колкото по-скорошно е.

    Второто наказание е за струпване в единия край на годината. Старците са
    от 7 до 45 сентенции; при равни други условия се тегли от онзи, който
    най-много ИЗОСТАВА спрямо равномерния си дял до тази дата. Така прп.
    Исаакий със своите седем се пада веднъж на около два месеца, вместо и
    седемте да излязат наведнъж през декември.
    """
    # Наложените на ръка се нареждат най-отпред и така НИКОГА не попадат в
    # запаса — той се къса от опашката. Инак наложиш нещо, а то се озовава
    # без дата, защото оценката му е ниска: точно от което си го спасявал.
    keep = set(manual.get('keep', []))
    by_elder = defaultdict(list)
    for q in chosen:
        by_elder[q['elder']].append(q)
    for lst in by_elder.values():
        lst.sort(key=lambda q: (q['id'] not in keep, -q['score']))

    # Запасът се дели пропорционално между ЗАМОЖНИТЕ старци: всеки дава от
    # най-слабите си. Оскъдните не дават нищо — прп. Исаакий има седем
    # сентенции в цялата симфония и подмяна с негова връстница е невъзможна
    # при всяко положение. Влезе ли и той в жребия, губим един от седемте
    # дни в годината, в които изобщо може да се чуе.
    RICH = 24
    rich = [e for e in by_elder if len(by_elder[e]) >= RICH]
    pot = sum(len(by_elder[e]) for e in rich)
    per = {}
    left = reserve_count
    order = sorted(rich, key=lambda e: -len(by_elder[e]))
    for e in order:
        share = min(round(reserve_count * len(by_elder[e]) / pot), left,
                    max(0, len(by_elder[e]) - 1))
        per[e] = share
        left -= share
    for e in order:                      # закръгленията оставиха остатък
        while left > 0 and per[e] < len(by_elder[e]) - 1:
            per[e] += 1
            left -= 1
        if left <= 0:
            break

    reserve = []
    for e, lst in by_elder.items():
        if per.get(e):
            reserve.extend(lst[-per[e]:])
            del lst[-per[e]:]
    reserve_ids = {q['id'] for q in reserve}

    dates = ['%02d-%02d' % (m, d)
             for m in range(1, 13) for d in range(1, DAYS_IN_MONTH[m - 1] + 1)]
    fixed = manual.get('day', {})
    free = [d for d in dates if d not in set(fixed.values())]

    pool = [q for lst in by_elder.values() for q in lst]
    for q in pool:
        q['day'] = fixed.get(q['id'])
    waiting = [q for q in pool if not q['day']]
    total = Counter(q['elder'] for q in waiting)
    total_t = Counter(q['topic_ru'] for q in waiting)
    used, used_t = Counter(), Counter()
    slots = len(free)

    window = 7                  # колко назад се гледа
    recent = []
    sequence = []
    for n, date in enumerate(free):
        if not waiting:
            break

        def clash(q):
            pen = 0
            for i, r in enumerate(recent):
                weight = len(recent) - i        # по-скорошното тежи повече
                if r['elder'] == q['elder']:
                    pen += 3 * weight
                if kindred(r['topic_ru'], q['topic_ru']):
                    pen += 3 * weight
                elif r['topic_ru'][0] == q['topic_ru'][0]:
                    pen += weight
            return pen

        def debt(q):
            """Колко изостават старецът и темата спрямо дела си дотук.

            Темата участва наравно със стареца заради дяловете, наложени
            вкупом през manual_select.json: 45-те сентенции за Иисусовата
            молитва. Без нея избягването ги ОТЛАГА, докато не остане нищо
            друго — и всичките се струпват в последните седем седмици, по
            една на ден. Гладът е обичайната беда на лакомите избори.
            """
            return (total[q['elder']] * (n + 1) / slots - used[q['elder']]
                    + total_t[q['topic_ru']] * (n + 1) / slots
                    - used_t[q['topic_ru']])

        # Едно събрано число, а не подредба на две мерки: изчакването и
        # разнообразието трябва да се претеглят, не да си отстъпват изцяло.
        best = min(waiting, key=lambda q: clash(q) - 12 * debt(q)
                   - q['score'] / 1000)
        best['day'] = date
        waiting.remove(best)
        used[best['elder']] += 1
        used_t[best['topic_ru']] += 1
        sequence.append(best)
        recent.append(best)
        del recent[:-window]

    for q in waiting:                    # не са останали дати
        q['day'] = None
        reserve_ids.add(q['id'])
    for q in reserve:
        q['day'] = None
    fixed_ones = [q for q in pool if q['id'] in fixed]
    return sequence + fixed_ones + waiting + reserve, reserve_ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--total', type=int, default=400)
    ap.add_argument('--max-len', type=int, default=600,
                    help='твърд таван в знаци; над него е цяло писмо')
    ap.add_argument('--show', help='отпечатва кандидатите по една тема')
    args = ap.parse_args()

    path = os.path.join(WORK_DIR, 'quotes.json')
    if not os.path.exists(path):
        print('Няма %s — пусни първо 01_extract.py.' % path)
        sys.exit(1)
    quotes = json.load(open(path, encoding='utf-8'))

    manual_path = os.path.join(WORK_DIR, 'manual_select.json')
    manual = (json.load(open(manual_path, encoding='utf-8'))
              if os.path.exists(manual_path) else {})
    if manual:
        print('ръчни поправки от manual_select.json: %s'
              % ', '.join('%s %d' % (k, len(v)) for k, v in manual.items()))

    dropped = Counter()
    cands = []
    for q in quotes:
        if q['id'] in manual.get('drop', []):
            dropped['изхвърлен на ръка'] += 1
            continue
        # Наложеното на ръка минава ПРЕЗ всички правила. Иначе 44-те за
        # Иисусовата молитва щяха да се сблъскат с правилото „за живеещи в
        # манастир": учението за нея е предадено на монаси и половината от
        # тях говорят за килия и петстотница. Изричното решение на човека
        # тежи повече от правилото, изведено от статистика.
        why = None if q['id'] in manual.get('keep', []) \
            else acceptable(q, args.max_len)
        if why:
            dropped[why] += 1
            continue
        q['score'] = score(q)
        cands.append(q)

    print('=' * 64)
    print('откъси: %d | приемливи: %d' % (len(quotes), len(cands)))
    for why, n in dropped.most_common():
        print('   отпаднали, %-28s %4d' % (why + ':', n))
    print('теми с поне един приемлив: %d от %d'
          % (len(set(q['topic_ru'] for q in cands)),
             len(set(q['topic_ru'] for q in quotes))))

    if args.show:
        for q in sorted((q for q in cands if q['topic_ru'] == args.show),
                        key=lambda q: -q['score']):
            print('%5.1f [%s, %d зн.] %s  (прп. %s)'
                  % (q['score'], q['id'], q['flags']['len'], q['body_ru'],
                     q['elder']))
        return

    chosen, quota = pick(cands, args.total, manual)
    ordered, reserve_ids = assign_days(chosen, args.total - 366, manual)

    print('-' * 64)
    print('избрани: %d (с дата %d, в запас %d)'
          % (len(ordered), sum(1 for q in ordered if q['day']),
             sum(1 for q in ordered if not q['day'])))
    print('%-14s %6s %8s %7s' % ('старец', 'квота', 'избрани', 'налични'))
    got = Counter(q['elder'] for q in ordered)
    avail = Counter(q['elder'] for q in cands)
    for e in sorted(got, key=lambda e: -got[e]):
        print('%-14s %6d %8d %7d' % (e, quota.get(e, 0), got[e], avail[e]))
    lens = sorted(q['flags']['len'] for q in ordered)
    print('дължини на избраните: медиана %d, най-къса %d, най-дълга %d'
          % (lens[len(lens) // 2], lens[0], lens[-1]))
    print('различни теми: %d' % len(set(q['topic_ru'] for q in ordered)))

    out = []
    for q in sorted(ordered, key=lambda q: (q['day'] is None, q['day'] or '',
                                            q['id'])):
        out.append({
            'id': q['id'], 'day': q['day'], 'score': q['score'],
            'elder': q['elder'], 'topic_ru': q['topic_ru'],
            'vol': q['vol'], 'src': q['src'], 'src_part': q['src_part'],
            'src_title': q['src_title'],
            'body_ru': q['body_ru'], 'atoms': q['atoms'],
            'notes': q['notes'], 'also_in': q['also_in'],
            'flags': q['flags'],
        })
    with open(os.path.join(WORK_DIR, 'selected.json'), 'w',
              encoding='utf-8') as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)

    # Списък за преглед с очи. Руският текст е нарочно цял — това е
    # последната спирка, преди да се плати за превод.
    with open(os.path.join(WORK_DIR, 'selection.md'), 'w',
              encoding='utf-8') as fh:
        fh.write('# Избрани сентенции от Оптинските старци\n\n')
        fh.write('%d за дните на годината, %d в запас. Подредени по дата.\n\n'
                 % (sum(1 for q in out if q['day']),
                    sum(1 for q in out if not q['day'])))
        fh.write('За да се изхвърли някоя, впиши `id`-то ѝ в `drop` на '
                 '`work/manual_select.json` и пусни наново.\n\n')
        for q in out:
            fh.write('**%s** · %s · *%s* · `%s` · %d зн. · %.1f т.\n\n%s\n\n'
                     % (q['day'] or 'ЗАПАС', 'прп. ' + q['elder'],
                        q['topic_ru'], q['id'], q['flags']['len'],
                        q['score'], q['body_ru']))

    used = set(q['topic_ru'] for q in out)
    with open(os.path.join(WORK_DIR, 'dropped_topics.txt'), 'w',
              encoding='utf-8') as fh:
        nocand = set(q['topic_ru'] for q in quotes) - set(
            q['topic_ru'] for q in cands)
        fh.write('# Теми на симфонията, останали извън избора\n')
        fh.write('# (509 дяла, 400 места — покриването на всички е '
                 'невъзможно)\n\n')
        fh.write('## Без нито един приемлив откъс (%d)\n' % len(nocand))
        fh.write('# Там всеки откъс е цяло писмо или отговор до определен '
                 'човек.\n')
        for t in sorted(nocand):
            fh.write('%s\n' % t)
        rest = sorted(set(q['topic_ru'] for q in cands) - used)
        fh.write('\n## Имаше кандидати, но не стигнаха местата (%d)\n'
                 % len(rest))
        for t in rest:
            fh.write('%s\n' % t)

    print('→ work/selected.json, work/selection.md, work/dropped_topics.txt')


if __name__ == '__main__':
    main()
