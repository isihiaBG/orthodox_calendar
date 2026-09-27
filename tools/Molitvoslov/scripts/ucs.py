"""Старото 8-битово кодиране на църковнославянските шрифтове (Ucs / Irmologion)
→ Unicode.

Текстът в такива книги ИЗГЛЕЖДА като смес от латиница, цифри и кирилица
(„Мlтвы ќтрєнніz", „с™0му д¦у"): шрифтът рисува на мястото на „l" л с титла, на
мястото на „0" — о с ударение, и т.н. Извън този шрифт текстът е безсмислен,
затова се превежда знак по знак в истинските Unicode знаци.

Таблицата е от frogstail/ucs-decoder (CC0-1.0, т.е. обществено достояние),
https://github.com/frogstail/ucs-decoder — дословно, само преписана на Python.
⚠ Знак, който НЕ е в таблицата, минава непроменен. Затова [unknown_chars] брои
всеки такъв, който не е обикновена кирилица, препинателен знак или интервал —
оттам се вижда пропуск в таблицата, вместо да остане тихо в текста.
"""

OXIA = '́'
VARIA = '̀'
KAMORA = '̑'
PSILI = '҆'
DASYA = '҅'
TITLO = '҃'
KAVYKA = '꙾'
POKRYTIE = '҇'
V_T = 'ⷡ'
G_T = 'ⷢ'
D_T = 'ⷣ'
ZH_T = 'ⷤ'
Z_T = 'ⷥ'
N_T = 'ⷩ'
O_T = 'ⷪ'
R_T = 'ⷬ'
S_T = 'ⷭ'
H_T = 'ⷯ'
CH_T = 'ⷱ'
YEROK = '̾'

TABLE = {
    '*': '꙳', '+': V_T + POKRYTIE, '0': 'о' + OXIA, '1': OXIA, '~': OXIA,
    '2': VARIA, '@': VARIA, '#': PSILI, '3': PSILI, '$': PSILI + OXIA,
    '4': PSILI + OXIA, '%': PSILI + VARIA, '5': PSILI + VARIA, '6': KAMORA,
    '^': KAMORA, '&': TITLO, '7': TITLO, '\\': TITLO, '8': YEROK, '_': YEROK,
    '9': 'ж' + TITLO, '<': H_T, '=': N_T + POKRYTIE, '>': R_T + POKRYTIE,
    '?': CH_T + POKRYTIE, 'A': 'а' + VARIA, 'a': 'а' + OXIA, 'B': 'ѣ' + KAMORA,
    'b': O_T + POKRYTIE, 'C': S_T + POKRYTIE, 'c': S_T + POKRYTIE,
    'D': 'д' + S_T + POKRYTIE, 'd': D_T, 'E': 'е' + VARIA, 'e': 'е' + OXIA,
    'F': 'Ѳ', 'f': 'ѳ', 'G': 'г' + TITLO, 'g': G_T + POKRYTIE, 'H': 'ѡ' + OXIA,
    'h': 'ы' + OXIA, 'I': 'І', 'i': 'і', 'J': 'і' + VARIA, 'j': 'і' + OXIA,
    'K': 'Ꙗ' + PSILI, 'k': 'ꙗ' + PSILI, 'L': 'л' + D_T, 'l': 'л' + TITLO,
    'M': 'Ѷ', 'm': 'ѷ', 'N': 'Ѻ' + PSILI, 'n': 'ѻ' + PSILI, 'O': 'Ѻ', 'o': 'ѻ',
    'P': 'Ѱ', 'p': 'ѱ', 'Q': 'Ѽ', 'q': 'ѽ', 'R': 'р' + TITLO,
    'r': 'р' + S_T + POKRYTIE, 'S': 'ѧ' + VARIA, 's': 'ѧ' + OXIA, 'T': 'Ѿ',
    't': 'ѿ', 'U': 'Ѹ', 'u': 'ѹ', 'V': 'Ѵ', 'v': 'ѵ', 'W': 'Ѡ', 'w': 'ѡ',
    'X': 'Ѯ', 'x': 'ѯ', 'Y': 'ꙋ' + VARIA, 'y': 'ꙋ' + OXIA, 'Z': 'Ѧ', 'z': 'ѧ',
    '{': 'ꙋ' + KAMORA, '|': 'ѧ' + PSILI + VARIA, '}': 'и' + TITLO,
    'Ђ': 'ѵ' + OXIA, 'ђ': 'ѵ' + G_T + POKRYTIE, 'Ѓ': 'А' + PSILI + OXIA,
    'ѓ': 'а' + PSILI + OXIA, '…': 'ѯ' + TITLO, '†': 'а' + KAMORA,
    '‡': 'і' + KAMORA, '€': Z_T, '‰': 'ѧ' + KAMORA, 'Љ': 'Ѧ' + PSILI,
    'љ': 'ѧ' + PSILI, '•': ZH_T, '™': 'т' + TITLO, '‹': 'і' + TITLO,
    '›': 'ѵ' + KAMORA, 'Њ': 'Ѡ' + PSILI, 'њ': 'ѡ' + PSILI,
    'Ќ': 'Ѹ' + PSILI + OXIA, 'ќ': 'ѹ' + PSILI + OXIA, 'Ћ': 'Ꙗ' + PSILI + OXIA,
    'ћ': 'ꙗ' + PSILI + OXIA, 'Џ': 'Ѻ' + PSILI + OXIA, 'џ': 'ѻ' + PSILI + OXIA,
    'Ў': 'Ѹ' + PSILI, 'ў': 'ѹ' + PSILI, 'Ј': 'І' + PSILI + OXIA,
    'ј': 'і' + PSILI + OXIA, '¤': '҂', 'Ґ': 'А' + PSILI, 'ґ': 'а' + PSILI,
    '¦': 'х' + TITLO, '§': 'ч' + TITLO, 'Ё': 'ѣ' + VARIA, 'ё': 'ѣ' + OXIA,
    '©': 'с' + TITLO, '®': 'Р' + D_T, 'Ї': 'І' + PSILI, 'ї': 'і' + PSILI,
    '°': KAVYKA, '±': 'ꙗ' + PSILI + VARIA, 'і': 'ї', 'µ': 'у', '№': 'а' + TITLO,
    'У': 'Ꙋ', 'у': 'ꙋ', 'Э': 'Ѣ', 'э': 'ѣ', 'Я': 'Ꙗ', 'я': 'ꙗ',
}

# Знаци, които минават непроменени и това е вярно: кирилицата извън таблицата
# и обичайната пунктуация.
_PLAIN = set('абвгдежзийклмнопрстфхцчшщъыьюєѕАБВГДЕЖЗИЙКЛМНОПРСТФХЦЧШЩЪЫЬЮЄЅ'
             ' \t\n.,:;!()[]-–—«»"\'/')


def decode(text: str) -> str:
    return ''.join(TABLE.get(ch, ch) for ch in text)


def unknown_chars(text: str) -> dict:
    """Знаците, които не са в таблицата и не са очевидно обикновени."""
    out = {}
    for ch in text:
        if ch not in TABLE and ch not in _PLAIN:
            out[ch] = out.get(ch, 0) + 1
    return out
