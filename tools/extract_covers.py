#!/usr/bin/env python3
"""Извлича кориците на томовете от .epub-ите в assets/covers/.

Кориците се пакетират като отделни файлове, а не се четат живо от
архивите: библиотеката ги показва всичките наведнъж (виж
lib/cover_flow.dart) и разархивирането на дванайсет тома при всяко влизане
се вижда като забавяне точно на екрана, който трябва да е най-хубавият.

Пуска се наново, когато се сменят кориците в самите томове:

    python3 tools/extract_covers.py

Изписва и по колко дни и жития носи всеки том — числата стоят преписани в
`_volumes` в lib/library_screen.dart (там са const, за да не се отваря нито
един архив за долния панел).
"""

import glob
import os
import xml.etree.ElementTree as ET
import zipfile

NS = {'n': 'http://www.daisy.org/z3986/2005/ncx/'}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'covers')


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(ROOT, 'assets', 'books', '*.epub'))):
        z = zipfile.ZipFile(path)
        # „Жития на светиите - 09(сеп) - Димитрий Ростовски.epub" → „09"
        num = os.path.basename(path).split(' - ')[1][:2]
        with open(os.path.join(OUT, f'{num}.jpg'), 'wb') as f:
            f.write(z.read('OEBPS/Images/cover.jpg'))

        # Дните са върховите записи с деца; житията — децата им.
        root = ET.fromstring(z.read('OEBPS/toc.ncx'))
        tops = root.find('n:navMap', NS).findall('n:navPoint', NS)
        days = [t for t in tops if t.findall('n:navPoint', NS)]
        lives = sum(len(d.findall('n:navPoint', NS)) for d in days)
        print(f'{num}  дни={len(days):3d}  жития={lives:4d}')


if __name__ == '__main__':
    main()
