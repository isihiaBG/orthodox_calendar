#!/usr/bin/env python3
"""Сваля картинката на страницата → assets/lives_images/.

    python3 07_image.py

⚠ Размерите се четат ПРАВО ОТ БАЙТОВЕТЕ — конвейерът не иска Pillow, а без
`width`/`height` в тага четецът смята мястото по подразбиране (пейзажна
кутия) и портретната картинка излиза свита наполовина.

⚠ Името носи отпечатък на адреса, както в другите конвейери: в изворите един
и същ `pasha.jpg` може да стои на няколко места с различно съдържание.
"""
import hashlib, json, os, re, struct, sys
from pathlib import Path
import requests

КОРЕН = Path(__file__).resolve().parents[1]
РАБОТА = КОРЕН / 'work'
ПРОЕКТ = КОРЕН.parents[1]
ЦЕЛ = ПРОЕКТ / 'assets' / 'lives_images'


def размер(b: bytes):
    """(ширина, височина) от байтовете на JPEG/PNG."""
    if b[:8] == b'\x89PNG\r\n\x1a\n':
        w, h = struct.unpack('>II', b[16:24])
        return w, h
    if b[:2] == b'\xff\xd8':
        i = 2
        while i < len(b) - 9:
            if b[i] != 0xFF:
                i += 1; continue
            m = b[i + 1]
            if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                     0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack('>HH', b[i + 5:i + 9])
                return w, h
            if m in (0xD8, 0xD9) or 0xD0 <= m <= 0xD7:
                i += 2; continue
            i += 2 + struct.unpack('>H', b[i + 2:i + 4])[0]
    return None, None


def main() -> int:
    d = json.loads((РАБОТА / 'text.json').read_text(encoding='utf-8'))
    im = d.get('image') or {}
    url = im.get('url')
    if not url:
        sys.exit('няма картинка в text.json')
    r = requests.get(url, timeout=60,
                     headers={'User-Agent': 'Mozilla/5.0'})
    r.raise_for_status()
    b = r.content
    w, h = размер(b)
    ext = '.png' if b[:8] == b'\x89PNG\r\n\x1a\n' else '.jpg'
    основа = re.sub(r'[^a-z0-9]+', '_',
                    os.path.basename(url).rsplit('.', 1)[0].lower()).strip('_')
    име = f'pascha_{основа}_{hashlib.md5(url.encode()).hexdigest()[:8]}{ext}'
    ЦЕЛ.mkdir(parents=True, exist_ok=True)
    (ЦЕЛ / име).write_bytes(b)
    рец = {'file': име, 'width': w, 'height': h,
           'alt': im.get('alt') or '', 'url': url, 'bytes': len(b)}
    (РАБОТА / 'image.json').write_text(
        json.dumps(рец, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f'{име} — {w}×{h}, {len(b)} байта')
    print('записано в', os.path.relpath(ЦЕЛ / име, ПРОЕКТ))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
