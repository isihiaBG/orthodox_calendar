#!/usr/bin/env python3
"""work/parimii_days.json → lib/parimii_days.dart (ГЕНЕРИРАН, не се пипа на ръка).

    python3 12_gen_parimii_dart.py      # след 11_parimii.py

Картата е `const` — секцията „Евангелие и Апостол" се смята синхронно (виж
защо в CLAUDE.md: асинхронно четене вътре в нея връща мигновеното разгъване).

⚠ `keys` — корените на имената в паметта („йоаса", „белго"). Неподвижна
паримия излиза в деня САМО ако някой от тях го има в имената на светиите за
деня — така руска местна памет, каквато в нашия календар няма, остава само в
книгата. Празник без собствено име (Рождество, Въздвижение) носи корена на
празника, а той е в името на деня.
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJ = ROOT.parents[1]
IN = ROOT / 'work' / 'parimii_days.json'
OUT = PROJ / 'lib' / 'parimii_days.dart'

STOP = {
    'свети', 'света', 'светия', 'светите', 'светия', 'светител', 'светителя', 'светители',
    'преподобни', 'преподобна', 'преподобните', 'мъченик', 'мъченица', 'мъченици',
    'свещеномъченик', 'свещеномъченици', 'великомъченик', 'великомъченица', 'праведни',
    'праведна', 'праведните', 'благоверни', 'благоверния', 'благоверната', 'пресвета',
    'пресветата', 'пророк', 'пророка', 'апостол', 'апостола', 'апостоли', 'апостолите',
    'архиепископ', 'епископ', 'митрополит', 'патриарх', 'игумен', 'чудотворец',
    'чудотворци', 'изповедник', 'икона', 'иконата', 'мощи', 'мощите', 'пренасяне',
    'пренасянето', 'откриване', 'откриването', 'обретение', 'успение', 'успението',
    'преставяне', 'преставянето', 'памет', 'паметта', 'събор', 'събора', 'новия', 'нови',
    'велики', 'велика', 'първи', 'първия', 'всички', 'всичка', 'наречена', 'именувана',
    'евангелист', 'евангелиста', 'богослов', 'христа', 'ради', 'юродив', 'княз', 'княгиня',
    'цар', 'царица', 'година', 'църковната', 'църковна', 'богородица', 'богородици',
    'господне', 'господен', 'господ', 'христос', 'христово', 'христова', 'негова', 'неговите',
}


def stems(title):
    words = re.findall(r'[А-ЯЁа-яёѝЍ]+', title)
    out = []
    for w in words:
        lw = w.lower()
        if len(lw) < 4 or lw in STOP:
            continue
        if not w[0].isupper() and lw not in ('рождество', 'въздвижение', 'богоявление',
                                             'сретение', 'благовещение', 'преображение',
                                             'въведение', 'покров', 'обрезание'):
            continue
        s = lw[:5]
        if s not in out:
            out.append(s)
    return out


def q(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'") + "'"


def main():
    days = json.loads(IN.read_text(encoding='utf-8'))
    lines = [
        '// ГЕНЕРИРАН от tools/Molitvoslov/scripts/12_gen_parimii_dart.py — не се пипа на ръка.',
        '//',
        '// Паримиите за деня: ключ „ММ-ДД" (църковна дата) или „P±N" (дни от Пасха).',
        '// Виж parimii_lookup в края на файла.',
        '',
        '/// Едно четиво: службата, надписът и препратката(ите) за библейския четец.',
        'class ParimiaReading {',
        '  final String service;',
        '  final String label;',
        '  final String book;',
        '  final List<String> refs;',
        '',
        '  /// Свободна компилация — отваря се в книгата „Паримии", не в Библията.',
        '  final bool compiled;',
        '  const ParimiaReading(this.service, this.label, this.book, this.refs,',
        '      {this.compiled = false});',
        '}',
        '',
        'class ParimiaDay {',
        '  final String title;',
        '  final List<String> keys;',
        '  final bool movable;',
        '  final bool russian;',
        '',
        '  /// Разделът в книгата „Паримии" (molitvoslov.db).',
        '  final int section;',
        '  final List<ParimiaReading> readings;',
        '  const ParimiaDay(this.title, this.keys, this.movable, this.russian, this.section,',
        '      this.readings);',
        '}',
        '',
        'const Map<String, List<ParimiaDay>> kParimii = {',
    ]
    n = 0
    for key in sorted(days):
        lines.append('  %s: [' % q(key))
        for e in days[key]:
            ks = [] if e['movable'] else stems(e['title'])
            lines.append('    ParimiaDay(%s, [%s], %s, %s, %d, [' % (
                q(e['title']), ', '.join(q(k) for k in ks),
                'true' if e['movable'] else 'false', 'true' if e['russian'] else 'false',
                e['sec']))
            for r in e['readings']:
                compiled = 'сборно' in r['label']
                lines.append('      ParimiaReading(%s, %s, %s, [%s]%s),' % (
                    q(r['service']), q(r['label']), q(r['book']),
                    ', '.join(q(x) for x in r['refs']),
                    ', compiled: true' if compiled else ''))
                n += 1
            lines.append('    ]),')
        lines.append('  ],')
    lines += [
        '};',
        '',
        '/// Паримиите за деня.',
        '///',
        '/// ⚠ Неподвижна паримия излиза САМО ако коренът на паметта (`keys`) е в',
        '/// имената на светиите за деня — руските местни памети остават в книгата.',
        '/// Подвижните (Великият пост, Страстната седмица, Пентикостарът) излизат',
        '/// винаги, освен изрично руските (`russian`).',
        'List<ParimiaDay> parimiiFor({',
        '  required String churchMonthDay,',
        '  required int daysFromPascha,',
        '  required List<String> saintNames,',
        '}) {',
        "  final names = saintNames.map((s) => s.toLowerCase()).join(' | ');",
        '  final out = <ParimiaDay>[];',
        "  final mv = 'P${daysFromPascha >= 0 ? '+' : ''}$daysFromPascha';",
        '  for (final d in kParimii[mv] ?? const <ParimiaDay>[]) {',
        '    if (!d.russian) out.add(d);',
        '  }',
        '  for (final d in kParimii[churchMonthDay] ?? const <ParimiaDay>[]) {',
        '    if (d.keys.isEmpty || d.keys.any(names.contains)) out.add(d);',
        '  }',
        '  return out;',
        '}',
        '',
    ]
    OUT.write_text('\n'.join(lines), encoding='utf-8')
    print('→ %s: %d дни, %d четива' % (OUT.relative_to(PROJ), len(days), n))


if __name__ == '__main__':
    main()
