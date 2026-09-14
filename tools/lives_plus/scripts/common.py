"""Общото за конвейера `lives_plus` — разчитане на .epub и адресиране.

⚠ Папката е в `.gitignore`, тъй че README-то до нея е ЕДИНСТВЕНИЯТ запис на
находките. Ако се изтрие, знанието си отива с нея.
"""
import os
import re
import zipfile

RE_TAG = re.compile(r'<[^>]+>')
RE_NOTE_LINK = re.compile(r'<a[^>]*href="[^"]*note[^"]*"[^>]*>.*?</a>', re.S | re.I)
RE_PARA = re.compile(r'<p[^>]*class="[^"]*paragraph[^"]*"[^>]*>(.*?)</p>', re.S | re.I)
RE_H = re.compile(r'<h[1-6][^>]*>(.*?)</h[1-6]>', re.S | re.I)


def plain(html: str) -> str:
    """Гол текст: маха ЕЛЕМЕНТА на бележката, не цифрите.

    ⚠ Същото правило като в `build_lives_index.py`: заглавията носят и
    ИСТИНСКИ числа („светите 42 мъченици"), а те не се различават по вид от
    номер на бележка — различават се по МЯСТО.
    """
    s = RE_NOTE_LINK.sub('', html)
    s = RE_TAG.sub(' ', s)
    s = (s.replace('&#160;', ' ').replace('&nbsp;', ' ')
          .replace('&amp;', '&').replace('&laquo;', '«').replace('&raquo;', '»')
          .replace('&mdash;', '—').replace('&ndash;', '–')
          .replace('&quot;', '"').replace('&lt;', '<').replace('&gt;', '>'))
    return re.sub(r'\s+', ' ', s).strip()


def toc_items(path: str):
    """(заглавие, път, html) за всеки дял от съдържанието, ПО РЕДА В КНИГАТА.

    ⚠ Дяловете с ЧИСТО ЧИСЛОВО заглавие се пропускат — това са бележките под
    линия. В „Приложения. Жития святых" истинските дялове са 17, а в
    съдържанието стоят 276: останалите 257 са бележки.

    ⚠⚠ НЕ СВИВА ПО ПЪТ. Разделът („Часть 2") и първото му слово сочат ЕДИН И
    СЪЩ файл — разделът към началото му, словото към котва вътре
    (`index_split_019.xhtml#calibre_toc_22`). Свиване ТУК пази първото
    срещнато, тоест РАЗДЕЛА, а самото слово изчезва без никакъв признак. Така
    се губеха три: „о расслабленном", „в неделю девятую" и първото поклонение.
    Свиването става в 01_extract.py, СЛЕД като разделите отпаднат.

    ⚠ Етикетът се сдвоява с НЕПОСРЕДСТВЕНО СЛЕДВАЩИЯ `content`, а не с
    „първия src подир `<navPoint`": navPoint-ите са ВЛОЖЕНИ и лаком израз
    прескача от бащата в детето.
    """
    z = zipfile.ZipFile(path)
    ncx = [n for n in z.namelist() if n.endswith('.ncx')][0]
    base = os.path.dirname(ncx)
    x = z.read(ncx).decode('utf-8', 'replace')
    out = []
    for t, src in re.findall(
            r'<navLabel>\s*<text>(.*?)</text>\s*</navLabel>\s*'
            r'<content[^>]*src="([^"]+)"', x, re.S):
        title = re.sub(r'\s+', ' ', plain(t)).strip()
        if re.fullmatch(r'\d+', title):
            continue
        full = os.path.join(base, src.split('#')[0]) if base else src.split('#')[0]
        try:
            html = z.read(full).decode('utf-8', 'replace')
        except KeyError:
            continue
        out.append((title, full, html))
    return out


def blocks_of(html: str) -> list[str]:
    """Абзаците на дяла, БЕЗ заглавието."""
    return [plain(b) for b in RE_PARA.findall(html) if plain(b)]
