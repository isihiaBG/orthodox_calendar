#!/usr/bin/env python3
"""Таблиците на разгъването за гласа на телефона → lib/speech_tables.g.dart.

Изворът е същият като за ElevenLabs: съкращенията на библейските книги
(tools/bible_refs/linkify.py + bible.db) и пълните им имена за четене
(`books.bg_title`, с поправките от bible_speak.py). Dart файлът е изделие —
поправяй тук или в изворите и пускай наново:

    python3 tools/tts/gen_speech_dart.py
"""
import json
from pathlib import Path

import bible_speak
import pilot

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'lib' / 'speech_tables.g.dart'


def dart_map(name, d):
    rows = ''.join(f'  {json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)},\n'
                   for k, v in sorted(d.items()))
    return f'const Map<String, String> {name} = {{\n{rows}}};\n'


def dart_set(name, s):
    rows = ''.join(f'  {json.dumps(k, ensure_ascii=False)},\n' for k in sorted(s))
    return f'const Set<String> {name} = {{\n{rows}}};\n'


def main():
    src = ('// ⚠ ГЕНЕРИРАН ФАЙЛ — не го пипай на ръка.\n'
           '// Изворът: tools/tts/gen_speech_dart.py (таблиците на bible_speak.py и pilot.py).\n\n'
           '/// Съкращение на книга (ключ като `linkify._key`) → код.\n'
           + dart_map('kSpeechBookAbbr', bible_speak._TABLE)
           + '\n/// Код → името, както се чете на глас.\n'
           + dart_map('kSpeechBookTitle', bible_speak._TITLES)
           + '\n/// Мъжки имена на -а/-я след „св." (инак „света").\n'
           + dart_set('kSpeechSvMale', pilot.SV_MALE)
           + '\n/// Печатни грешки в изворите, поправени само за четенето.\n'
           + dart_map('kSpeechTextFixes', pilot.TEXT_FIXES))
    OUT.write_text(src)
    print(OUT, len(bible_speak._TABLE), 'съкращения,', len(bible_speak._TITLES), 'книги')


if __name__ == '__main__':
    main()
