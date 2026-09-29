"""Песните на канона в трите основни акатиста — с цс шрифт от PDF-а.

    python3 06_akatisti.py && python3 06c_akatisti_pdf.py && python3 05_build_db.py

Досега в таба „Акатисти" кондаците и икосите бяха с цс шрифт (06b, azbyka.ru),
а песните на канона около тях — само с граждански. PDF-ът на Канонника
(„Вертоград") носи трите последования ЦЕЛИ, с цс шрифт:

    стр.  19  канон умилителен със акатист към Иисус Христос   → 101
    стр. 334  канон благодарен със акатист към Богородица        → 102
    стр. 535  канон със акатист към св. Николай                  → 103

⚠ Взимат се САМО ПЕСНИТЕ (по номер) — и само където цс още няма. Кондаците,
икосите и молитвите вече имат цс от azbyka.ru и не се пипат: двойно подаден,
един и същ текст би стоял два пъти вдясно.
⚠ Пуска се СЛЕД 06_akatisti.py — той пресъздава akatisti.json отначало.
"""
import importlib.util
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = os.path.join(ROOT, 'work')

_spec = importlib.util.spec_from_file_location(
    'kan', os.path.join(os.path.dirname(__file__), '07_kanonnik.py'))
kan = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(kan)

# раздел → (първа, последна отпечатана страница в PDF-а)
RANGES = {101: (19, 52), 102: (334, 365), 103: (535, 579)}


def song_key(title):
    t = (title or '').replace(kan.ak.ACUTE, '')
    m = re.match(r'(?:Пе?снь|Песен)\s+(\d+)', t)
    return int(m.group(1)) if m else None


def cut_akathist(blocks):
    """⚠ При Богородица акатистът е вмъкнат НАПРАВО в 6-та песен, без своя
    заглавие („Посе́мъ кондакѝ и҆ і҆́косы…"). Той вече е в своите единици —
    песента се реже преди него."""
    for i, b in enumerate(blocks):
        t = kan.pdf_ucs.bare(re.sub(r'<[^>]+>', '', b['html'])).replace('҆', '')
        if t.startswith('Посемъ кондак') or re.match(r'(Кондакъ|Ікосъ)\s+\S+:', t):
            return blocks[:i]
    return blocks


def main():
    path = os.path.join(W, 'akatisti.json')
    secs = json.load(open(path, encoding='utf-8'))
    doc = kan.pdf_ucs.open_doc(kan.PDF)
    for sec in secs:
        rng = RANGES.get(sec['sec'])
        if not rng:
            continue
        pdf = kan.pdf_ucs.units(kan.pdf_ucs.lines(doc, rng[0] - 1, rng[1] - 1))
        songs = {u['key'][1]: u for u in pdf if u['key'][0] == 'song'}
        hit = 0
        for u in sec['units']:
            n = song_key(u.get('title_csl'))
            if n and n in songs and not u.get('csl'):
                u['csl'] = cut_akathist(songs[n]['blocks'])
                u['title_cs'] = songs[n]['title']
                hit += 1
        print('  %d  песни с цс шрифт: %d от %d' % (sec['sec'], hit, len(songs)))
    json.dump(secs, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('→ work/akatisti.json')


if __name__ == '__main__':
    main()
