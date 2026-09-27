"""Молитвословът с църковнославянски шрифт (.epub от azbyka.ru) → Unicode.

    input/molitvoslov-cerkovnoslavjanskim-shriftom_23374.epub
      → work/csl_book.html     целият текст в Unicode, за оглед
      → отчет: непознати знаци (пропуск в таблицата на ucs.py)

Книгата е ЕДИН файл (OEBPS/Book.html). Всичко в нея е в кодирането Ucs, освен
заглавието <h1> (то е обикновен руски текст и НЕ бива да минава през
таблицата — „Молитвослов" би станало безсмислица).

⚠ Червените указания („Посемъ постой мало молча…") са <strong>. Тук се
превръщат в <span class="rubric"> — класа, с който приложението вече рисува
червените указания на Типикона (`palette.wine`). (Указание на потребителя:
всички пояснителни текстове — в стандартното винено.)
"""
import html
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(__file__))
import ucs  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'input', 'molitvoslov-cerkovnoslavjanskim-shriftom_23374.epub')
OUT = os.path.join(ROOT, 'work', 'csl_book.html')

RE_TAG = re.compile(r'(<[^>]+>)')


def convert(body: str) -> tuple[str, dict]:
    """Превежда само ТЕКСТА между таговете; таговете остават както са."""
    out, unknown = [], {}
    in_h1 = False
    for part in RE_TAG.split(body):
        if part.startswith('<'):
            low = part.lower()
            if low.startswith('<h1'):
                in_h1 = True
            elif low.startswith('</h1'):
                in_h1 = False
            out.append(part)
            continue
        text = html.unescape(part)
        if in_h1:
            out.append(html.escape(text, quote=False))
            continue
        for ch, n in ucs.unknown_chars(text).items():
            unknown[ch] = unknown.get(ch, 0) + n
        out.append(html.escape(ucs.decode(text), quote=False))
    res = ''.join(out)
    res = res.replace('<strong>', '<span class="rubric">').replace('</strong>', '</span>')
    return res, unknown


def main():
    z = zipfile.ZipFile(SRC)
    src = z.read('OEBPS/Book.html').decode('utf-8')
    m = re.search(r'<body>(.*)</body>', src, re.S)
    body, unknown = convert(m.group(1))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as f:
        f.write('<html><head><meta charset="utf-8"/></head><body>')
        f.write(body)
        f.write('</body></html>')
    print('→', OUT, '(%d знака)' % len(body))
    print('непознати знаци:', len(unknown))
    for ch, n in sorted(unknown.items(), key=lambda x: -x[1]):
        print('   %r U+%04X  ×%d' % (ch, ord(ch), n))


if __name__ == '__main__':
    main()
