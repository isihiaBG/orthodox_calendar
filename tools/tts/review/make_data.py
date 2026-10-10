"""Данните за страницата „Преглед на ударенията" — от решенията на модела.

Всяка дума: id, честота, двузначна ли е, вариантите (с бройки и по един
пример) и мястото на ударението във всеки. Нерешените носят вариант „?"."""
import json, sys
from collections import Counter
sys.path.insert(0, '.')
import accent

book = sys.argv[1] if len(sys.argv) > 1 else 'razgovori'
acc, dic = accent.load_accents(), accent.load_dict()
chapters = accent.book_blocks(accent.BOOKS[book])
cache = json.loads((accent.WORK / f'{book}_llm.json').read_text())
llm = {b: {int(s): i for s, i in v.items()} for b, v in cache.items()}
accent.consensus(chapters, dic, llm)
seen = {}
for _, blocks in chapters:
    for b in blocks:
        text, bid = b['text'], accent.bid_of(b['text'])
        def add(low, form, s, wlen, amb):
            e = seen.setdefault(low, {'n': 0, 'amb': amb, 'forms': Counter(), 'ex': {}})
            e['n'] += 1; e['forms'][form] += 1
            if form not in e['ex']:
                a, z = max(0, s - 60), min(len(text), s + wlen + 60)
                e['ex'][form] = [text[a:s], text[s:s + wlen], text[s + wlen:z]]
        for s, i in (llm.get(bid) or {}).items():
            w = accent.WORD.match(text, s)
            if w:
                low = w.group(0).lower()
                add(low, i, s, len(low), len(dic.get(low, ())) > 1)
        for s, w, amb in accent.mark(text, acc, dic, llm.get(bid))[1]:
            add(w.lower(), -1, s, len(w), amb)
rows = []
for k, (low, e) in enumerate(sorted(seen.items(), key=lambda kv: (-kv[1]['n'], kv[0]))):
    rows.append({'id': f'w{k:04d}', 'w': low, 'n': e['n'], 'amb': e['amb'],
                 'f': [[i, c, e['ex'][i]] for i, c in e['forms'].most_common()]})
json.dump(rows, open(f'review/{book}_words.json', 'w'), ensure_ascii=False, separators=(',', ':'))
print(len(rows), 'думи;', sum(r['amb'] for r in rows), 'двузначни;',
      sum(any(f[0] == -1 for f in r['f']) for r in rows), 'с нерешени')
