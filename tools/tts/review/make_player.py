#!/usr/bin/env python3
"""Страница за слушане на пробна беседа — звукът е вграден (11.10.2026).

    python3 make_player.py c13        → review/slushai.html

Прототип на плейъра в приложението: маркира изречението, което се чете,
пуска от докоснато изречение, ±5 секунди, бележките след изречението си.
"""
import base64
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / 'out' / 'razgovori'

name = sys.argv[1] if len(sys.argv) > 1 else 'c13'
d = json.loads((OUT / f'{name}.json').read_text())
notes = {}
for p in sorted(OUT.glob('note*.json')):
    n = int(p.stem[4:])
    notes[n] = {'s': json.loads(p.read_text())['sents'][0]['s'],
                'a': 'data:audio/mpeg;base64,' + base64.b64encode((OUT / f'note{n}.mp3').read_bytes()).decode()}
data = {'chapter': d, 'audio': 'data:audio/mpeg;base64,' + base64.b64encode(
    (OUT / f'{name}.mp3').read_bytes()).decode(), 'notes': notes}
head = (HERE / 'player_head.html').read_text()
tail = (HERE / 'player_tail.html').read_text()
(HERE / 'slushai.html').write_text(head + json.dumps(data, ensure_ascii=False) + tail)
print('slushai.html', (HERE / 'slushai.html').stat().st_size // 1024, 'KB')
