#!/usr/bin/env python3
"""HIP (orthlib.ru) → Unicode църковнославянски.

HIP е „инвариантният" запис на църковнославянски с ASCII/кирилски знаци
(стандарт HIP-9, http://www.orthlib.ru/hip/hip-9.html и hip9slav.html).
Тук е покрит съвременният набор (уровень 0) плюс шепата знаци, които
реално се срещат в Ирмология; непознатото се ИЗПИСВА в `unknown`, не се
подминава мълчаливо.

⚠ Изходът е в СЪЩИТЕ начертания, в които `ucs.py` дава останалите
богослужебни книги — иначе в един и същи раздел буквите биха се разминали:

    о_у → ѹ  (диграфът в началото)     у  → ꙋ  (гамаобразното ук)
    w   → ѡ      w\\т → ѿ               jа → ꙗ     я → ѧ   jь → ѣ
    _е  → є      _о  → ѻ      s → ѕ     f  → ѳ     v → ѵ
    i   → ї  (с две точки по подразбиране), а с ударение → і + ударение
    \\д  → ⷣ҇  (буквено титло + покритие, като „Гдⷭ҇и")

Разметката:
    %< … %>   киновар  → <span class="rubric">…</span>
    %{…}      коментар (номера на листове, бележки на набора) — маха се
    %[ %] %( %)  разрядка, дребен шрифт — махат се (без смисъл за нас)
    {…}       бележка под линия — маха се
    празен ред = нов абзац
"""
import html
import re

ACC = {
    "'": '́', '`': '̀', '^': '̑', '=': '҆', '$': '҅',
    '~': '҃', '"': '̏',
}
# буква над буквата (\+буква) → комбиниращата кирилска + покритие
SUPER = {
    'б': 'ⷠ', 'в': 'ⷡ', 'г': 'ⷢ', 'д': 'ⷣ', 'ж': 'ⷤ',
    'з': 'ⷥ', 'к': 'ⷦ', 'л': 'ⷧ', 'м': 'ⷨ', 'н': 'ⷩ',
    'о': 'ⷪ', 'п': 'ⷫ', 'р': 'ⷬ', 'с': 'ⷭ', 'т': 'ⷮ',
    'х': 'ⷯ', 'ц': 'ⷰ', 'ч': 'ⷱ', 'ш': 'ⷲ', 'щ': 'ⷳ',
    'f': 'ⷴ', 'а': 'ⷶ', 'е': 'ⷷ', 'у': 'ꙴ', 'ю': 'ⷻ',
    'я': 'ⷽ', 'и': 'ꙵ',
}
POKRYTIE = '҇'
PAYEROK = '꙽'

# Многознакови означения → (малка, главна)
MULTI = {
    'о_у': ('ѹ', 'Ѹ'), 'о<у>': ('ѹ', 'Ѹ'), 'w\\т': ('ѿ', 'Ѿ'),
    '_кс': ('ѯ', 'Ѯ'), '<кс>': ('ѯ', 'Ѯ'), '_пс': ('ѱ', 'Ѱ'), '<пс>': ('ѱ', 'Ѱ'),
    '_i': ('і', 'І'), '<i>': ('і', 'І'), '_w': ('ѽ', 'Ѽ'), '<w>': ('ѽ', 'Ѽ'),
    '<_w>': ('ꙍ', 'Ꙍ'), '_е': ('є', 'Є'), '<е>': ('є', 'Є'), '_о': ('ѻ', 'Ѻ'),
    '<о>': ('ѻ', 'Ѻ'), '_у': ('у', 'У'), '<у>': ('у', 'У'),
    'jjь': ('ꙓ', 'Ꙓ'), 'jь': ('ѣ', 'Ѣ'), 'jа': ('ꙗ', 'Ꙗ'), 'jе': ('ѥ', 'Ѥ'),
    'jя': ('ѩ', 'Ѩ'), 'ju': ('ѭ', 'Ѭ'),
}
SINGLE = {
    'у': ('ꙋ', 'Ꙋ'), 'w': ('ѡ', 'Ѡ'), 'я': ('ѧ', 'Ѧ'), 's': ('ѕ', 'Ѕ'),
    'f': ('ѳ', 'Ѳ'), 'v': ('ѵ', 'Ѵ'), 'i': ('ї', 'Ї'), 'u': ('ѫ', 'Ѫ'),
    'g': ('ꙁ', 'Ꙁ'), 'q': ('ҁ', 'Ҁ'),
}
# визуално еднакви латински → кирилски (HIP ги смята за един и същ знак)
LOOKALIKE = str.maketrans('AaBEeKkMHOoPpCcTXxYy', 'АаВЕеКкМНОоРрСсТХхУу')
PUNCT = {'<->': '–', '<?>': '?', '<.>': '·', '<_>': '', '<>': '\n\n', '__': '', '_/': '\n\n',
         '<|>': '', '#': '҂', '@': '', '<*>': '*', '<,>': ',',
         # Знаците на празниците (hip9slav.html); цветът идва от киновара
         # около тях — червените три точки са славословие, черните шестерична.
         # Шрифтът Triodion ги има (U+1F540…1F544).
         '<(+)>': '\U0001F540', '<\\+/>': '\U0001F541', '<+>': '\U0001F542',
         '<(:.>': '\U0001F543', '<.:)>': '\U0001F544'}
MULTI_KEYS = sorted(list(MULTI) + list(PUNCT), key=len, reverse=True)


_MODE = re.compile(r'<::(\w+)>')


def _case(key, s):
    """Главна, ако първата „компютърна" буква в означението е главна."""
    for ch in s:
        if ch.isalpha():
            return ch.isupper()
    return False


def _norm_i(out):
    """ї + ударение → і + ударение (HIP-9, п. I.13: акцентът маха
    надстрочника по подразбиране). Също и за ѽ → ꙍ."""
    out = re.sub('ї(?=[̀́̑҆҅])', 'і', out)
    out = re.sub('Ї(?=[̀́̑҆҅])', 'І', out)
    out = re.sub('ѽ(?=[̀́̑҆҅])', 'ꙍ', out)
    return out


def convert(src, unknown=None):
    """HIP текст (вече декодиран от cp1251) → [абзац], всеки абзац е html с
    червени <span class="rubric">. Само частите в режим <::слав>/<::рус>."""
    s = src.replace('\r', '')
    # Коментари %{…} (с вложени скоби) — първо, защото носят „<" и „>".
    out, i, depth = [], 0, 0
    while i < len(s):
        if s.startswith('%{', i):
            d, j = 1, i + 2
            while j < len(s) and d:
                d += {'{': 1, '}': -1}.get(s[j], 0)
                j += 1
            i = j
            continue
        out.append(s[i])
        i += 1
    s = ''.join(out)

    res, mode, red = [], 'слав', False
    i = 0
    buf = []

    def emit(t):
        buf.append(t)

    while i < len(s):
        c = s[i]
        m = _MODE.match(s, i)
        if m:
            mode = m.group(1)
            i = m.end()
            continue
        if c == '%' and i + 1 < len(s):
            k = s[i + 1]
            if k == '<':
                emit('\x01'); red = True
            elif k == '>':
                emit('\x02'); red = False
            i += 2
            continue
        if c == '{':                      # бележка под линия — маха се цяла
            d, j = 1, i + 1
            while j < len(s) and d:
                d += {'{': 1, '}': -1}.get(s[j], 0)
                j += 1
            i = j
            continue
        if c == '&':                      # склейка на лигатура
            i += 1
            continue
        if mode in ('лат', 'греч', 'глаг'):
            i += 1                        # чужди вмъкнати бележки — не ни трябват
            continue
        if mode == 'рус':
            emit(c)
            i += 1
            continue
        low = s[i:i + 4].translate(LOOKALIKE)
        hit = next((k for k in MULTI_KEYS if low.lower().startswith(k.lower())), None)
        if hit:
            raw = s[i:i + len(hit)]
            if hit in PUNCT:
                emit(PUNCT[hit])
            else:
                lo, up = MULTI[hit]
                emit(up if _case(hit, raw) else lo)
            i += len(hit)
            continue
        if c == '\\' and i + 1 < len(s):
            k = s[i + 1].translate(LOOKALIKE)
            kl = k.lower()
            if kl == 'ъ':
                emit(PAYEROK)
            elif kl == '-':
                emit(POKRYTIE)
            elif kl in SUPER:
                emit(SUPER[kl] + POKRYTIE)
            elif kl in (':', '.', '@', '^'):
                emit({':': '̈', '.': '̇', '@': '̆', '^': ''}[kl])
            elif unknown is not None:
                unknown.add('\\' + k)
            i += 2
            continue
        if c in ACC:
            emit(ACC[c])
            i += 1
            continue
        if c == '<':
            j = s.find('>', i)
            tok = s[i:j + 1] if j > 0 else c
            if unknown is not None:
                unknown.add(tok)
            i += len(tok)
            continue
        cc = c.translate(LOOKALIKE)
        if cc.lower() in SINGLE:
            lo, up = SINGLE[cc.lower()]
            emit(up if cc.isupper() else lo)
        elif cc == '|':
            if unknown is not None:
                unknown.add('|' + s[i + 1:i + 2])
            i += 2
            continue
        else:
            emit(cc)
        i += 1

    text = _norm_i(''.join(buf))
    paras = []
    for p in re.split(r'\n\s*\n', text):
        p = re.sub(r'\s+', ' ', p).strip()
        if not p.replace('\x01', '').replace('\x02', '').strip():
            continue
        paras.append(p)
    # Червеното може да тече през абзаци — затваря се и отваря наново.
    outp, open_ = [], False
    for p in paras:
        h, st = [], open_
        if st:
            h.append('<span class="rubric">')
        for ch in p:
            if ch == '\x01':
                if not st:
                    h.append('<span class="rubric">'); st = True
            elif ch == '\x02':
                if st:
                    h.append('</span>'); st = False
            else:
                h.append(html.escape(ch, quote=False))
        open_ = st
        if st:
            h.append('</span>')
        x = re.sub(r'<span class="rubric">\s*</span>', '', ''.join(h)).strip()
        if x:
            outp.append(x)
    return outp
