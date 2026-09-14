#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Прокимените → `lib/prokimen.dart`. Без мрежа.

    python3 11_gen_prokimen_dart.py

⚠⚠ ПРОКИМЕНЪТ Е ПРЕПРАТКА КЪМ ПИСАНИЕТО, не свой текст — вписан като текст,
той би бил единайсети препис на едно и също нещо и би излизал само на
славянски. Като препратка се получава наготово на всеки превод, който
човекът е свалил. (Идея на потребителя, 11.09.2026.)

⚠ БЕЗ SQLite, като при обръщенията („Братя,"): няколкостотин къси реда не
заслужават база — вграждат се като `const` и се четат без достъп до диска.

⚠ Ръчните поправки по българското отрязване идват от
`input/prokimen_trim_bg_manual.csv` и имат ПРЕВЕС над автоматичното.
Колоната там е самият ТЕКСТ, не отместване — виж 09_trim_review.py.
"""
import csv
import json
import pathlib
import sqlite3

ГНЕЗДО = pathlib.Path(__file__).resolve().parents[1]
КОРЕН = pathlib.Path(__file__).resolve().parents[3]
ИЗХОД = КОРЕН / 'lib' / 'prokimen.dart'


def ръчни() -> dict[str, dict]:
    п = ГНЕЗДО / 'input' / 'prokimen_trim_bg_manual.csv'
    if not п.exists():
        return {}
    вън = {}
    with п.open(encoding='utf-8') as f:
        for r in csv.DictReader(f):
            вън[r['ref']] = {'bg_ref': (r.get('bg_ref') or '').strip(),
                             'bg_text': (r.get('bg_text') or '').strip()}
    return вън


def d(s: str) -> str:
    return "'" + s.replace('\\', r'\\').replace("'", r"\'") + "'"


def main() -> None:
    данни = json.loads(
        (ГНЕЗДО / 'work/prokimen_addressed.json').read_text(encoding='utf-8'))
    поправки = ръчни()
    db = sqlite3.connect(КОРЕН / 'assets/db/bible.db')
    бг = {f'{b}.{c}:{v}': t for b, c, v, t in db.execute(
        "SELECT book, chapter, verse, text FROM verses WHERE lang='bg'")}

    def част(ref, trim):
        """Един текст: препратка + отрязване по език."""
        ако = поправки.get(ref)
        tr = dict(trim or {})
        цел = ref
        if ако:
            # ⚠ Ръчната поправка е ТЕКСТ — отместването се смята от него,
            # за да не се съхраняват числа, каквито никой не може да свери.
            if ако['bg_ref']:
                цел_бг = ако['bg_ref']
            else:
                цел_бг = ref
            пълен = бг.get(цел_бг, '')
            откъс = ако['bg_text']
            i = пълен.find(откъс) if откъс else -1
            if i >= 0:
                tr['bg'] = [i, len(пълен) - i - len(откъс)]
                if ако['bg_ref']:
                    tr['bg_ref'] = ако['bg_ref']
            else:
                tr.pop('bg', None)
        полета = [f'ref: {d(цел)}']
        езици = {k: v for k, v in tr.items() if k in ('utfcs', 'bg')}
        if езици:
            вътре = ', '.join(f"{d(k)}: [{v[0]}, {v[1]}]"
                              for k, v in sorted(езици.items()))
            полета.append('trim: {%s}' % вътре)
        if tr.get('bg_ref'):
            полета.append(f"bgRef: {d(tr['bg_ref'])}")
        return 'P(%s)' % ', '.join(полета)

    def запис(r):
        k = r['prokimena'][0]
        # ⚠ ПРИ ВЪЗКРЕСНИТЕ ГЛАСЪТ Е САМИЯТ АДРЕС. Дялът се казва „Глас 1",
        # а редът вътре е просто „Прокимен: …" — книгата не го повтаря.
        # Без това етикетът излизаше „Прокимен" вместо „Прокимен, глас 1".
        if r.get('addr_kind') == 'tone' and not k.get('glas'):
            k = dict(k, glas=int(r['addr']))
        части = [част(k.get('ref'), (k.get('trim') or {}).get('ref'))] \
            if k.get('ref') else []
        стихове = []
        for i, v in enumerate(k.get('verse_refs') or []):
            if v:
                стихове.append(част(v['ref'],
                                    (k.get('trim') or {}).get(f'verse{i}')))
        if not части:
            return None
        глас = k.get('glas')
        # ⚠ Втори прокимен („Другий прокимен" / „И святаго, глас N") се
        # ПРОПУСКА засега: той иска да се знае ЧИЯ е втората памет, а това
        # е същият открит въпрос като адресирането на редовите четива.
        зач = ', '.join(str(x) for x in sorted(set(r['zachala'])))
        return 'K(%s, %s, [%s], [%s])' % (
            глас if глас else 'null', части[0], ', '.join(стихове), зач)

    групи = {'fixed': {}, 'tone': {}, 'weekday': {}, 'pascha': {}}
    for r in данни:
        вид = r.get('addr_kind')
        z = запис(r)
        if not z or вид not in групи:
            continue
        if вид == 'pascha':
            # ⚠ Подвижните се ключират по ЗАЧАЛО: точен адрес спрямо Пасха
            # още няма (виж отвореното за отстъпката). Зачалото е достатъчно
            # САМО вътре в прозореца около Пасха и САМО когато сочи един
            # дял — иначе се пада към гласа/делника. Мерено: извън прозореца
            # 123 от 231 съвпадения са ЛЪЖЛИВИ.
            for зач in r['zachala']:
                групи['pascha'].setdefault(str(зач), []).append(z)
        else:
            групи[вид].setdefault(r['addr'], []).append(z)

    l = []
    l.append('// ГЕНЕРИРАН ФАЙЛ — не се редактира на ръка.')
    l.append('// Прави го tools/evangelie_slujebno/scripts/'
             '11_gen_prokimen_dart.py')
    l.append('//')
    l.append('// ⚠⚠ ПРОКИМЕНЪТ Е ПРЕПРАТКА КЪМ ПИСАНИЕТО, не свой текст.')
    l.append('// Мерено: 891 от 1020 текста в книгата се намират дословно в')
    l.append('// `bible.db`, 816 от тях в Псалтира. Вписан като текст, той би')
    l.append('// бил единайсети препис на едно и също нещо и би излизал само')
    l.append('// на славянски; като препратка идва наготово на всеки превод,')
    l.append('// който човекът е свалил. (Идея на потребителя, 11.09.2026.)')
    l.append('//')
    l.append('// ⚠ `trim` е (отрязано отпред, отрязано отзад) В ЗНАЦИ и е')
    l.append('// РАЗЛИЧНО за всеки превод. За църковнославянския се МЕРИ')
    l.append('// (текстът на прокимена е същият, само в друга графика); за')
    l.append('// българския се пренася по дял от стиха и препинателна')
    l.append('// граница, а 13 случая са нанесени на ръка. За останалите')
    l.append('// преводи отрязване НЯМА и се показва целият стих — по')
    l.append('// правилото при цитатите: по-добре малко повече, отколкото')
    l.append('// откъс, срязан насред дума.')
    l.append('')
    l.append('/// Едно място от Писанието с отрязване по език.')
    l.append('class P {')
    l.append('  final String ref;')
    l.append('  /// ⚠ Само за българския и само където номерацията се')
    l.append('  /// разминава — виж „Номерацията на псалмите" в README-то.')
    l.append('  final String? bgRef;')
    l.append('  final Map<String, List<int>> trim;')
    l.append('  const P({required this.ref, this.bgRef,')
    l.append('      this.trim = const {}});')
    l.append('}')
    l.append('')
    l.append('/// Прокимен: глас, самият той и стиховете му.')
    l.append('class K {')
    l.append('  final int? glas;')
    l.append('  final P text;')
    l.append('  final List<P> verses;')
    l.append('  /// Зачалата, които книгата дава за ТАЗИ памет.')
    l.append('  ///')
    l.append('  /// ⚠⚠ ТЕ СА ПОТВЪРЖДЕНИЕТО, че четивото е на тази памет, а')
    l.append('  /// не редовото за деня: мерено, при 204 от 323 дни с памет')
    l.append('  /// в месецослова четивото все пак е редовото.')
    l.append('  final List<int> zachala;')
    l.append('  const K(this.glas, this.text, this.verses, this.zachala);')
    l.append('}')
    l.append('')
    имена = {'fixed': 'kProkimenFixed', 'tone': 'kProkimenTone',
             'weekday': 'kProkimenWeekday', 'pascha': 'kProkimenPascha'}
    докс = {
        'fixed': 'Неподвижна църковна дата „ММ-ДД".',
        'tone': 'Възкресен прокимен по глас (1..8).',
        'weekday': 'Делничен прокимен, понеделник = 1.',
        'pascha': 'Подвижните, ключирани по ЗАЧАЛО.\n'
                  '///\n'
                  '/// ⚠⚠ ПОЛЗВА СЕ САМО В ПРОЗОРЕЦА ОКОЛО ПАСХА и само\n'
                  '/// когато зачалото сочи ЕДИН дял. Извън прозореца 123 от\n'
                  '/// 231 съвпадения са лъжливи — мерено.',
    }
    for вид, име in имена.items():
        l.append('/// %s' % докс[вид])
        l.append('const Map<String, List<K>> %s = {' % име)
        for ключ in sorted(групи[вид]):
            l.append("  %s: [%s]," % (d(ключ), ', '.join(групи[вид][ключ])))
        l.append('};')
        l.append('')
    ИЗХОД.write_text('\n'.join(l), encoding='utf-8')
    print('→ %s' % ИЗХОД)
    for вид, име in имена.items():
        print('   %-18s %d ключа' % (име, len(групи[вид])))


if __name__ == '__main__':
    main()
