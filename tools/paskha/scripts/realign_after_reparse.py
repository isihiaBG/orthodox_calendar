#!/usr/bin/env python3
"""Пренарежда преводите след ПРОМЯНА В РАЗЧИТАНЕТО.

    python3 realign_after_reparse.py --old <папка със старото work/pages> [--dry-run]

⚠⚠ ЗАЩО СЪЩЕСТВУВА. `14_apply_pages.py` изисква броят блокове в разчетеното
и в превода да СЪВПАДА — инак `zip` би слепил мълчаливо превода на един
абзац с връзките на друг. Затова всяка поправка в парсъра, която МАХА
блокове (напр. чуждия скрипт или блока с коментарите), обезсилва превода на
целия дял и статията изчезва от базата.

⚠ Тук съответствието се изчислява, вместо да се плаща превод наново:
старият и новият списък от блокове се подравняват по СЪДЪРЖАНИЕ
(`SequenceMatcher` върху руския текст) и от `blocks_bg` отпадат точно онези
позиции, чиито блокове са изчезнали.

⚠⚠ ПОЗВОЛЕНО Е САМО МАХАНЕ. Появи ли се НОВ блок, подравняването спира за
тази статия и я изписва — тогава преводът наистина липсва и дялът трябва да
мине през `12_translate_pages.py`.
"""
import argparse, json, sys
from difflib import SequenceMatcher
from pathlib import Path

КОРЕН = Path(__file__).resolve().parents[1]
НОВО = КОРЕН / 'work' / 'pages'
ПРЕВОД = КОРЕН / 'work' / 'pages_bg'


def отпечатък(дял):
    """Какво представя дяла при сравняване.

    ⚠⚠ ЗАГЛАВИЕТО, А НЕ ПЪРВИЯТ АБЗАЦ. Първият опит слагаше и абзаца — и
    се късаше точно когато той е изчезнал (при „Пасхални козунаци"
    единственият блок на последния дял беше скритата джаджа за бисквитки).
    Тогава дялът изглежда „нов", преводът му отпада цял и статията изчезва
    от базата, защото един дял остава непреведен.

    ⚠ Дял БЕЗ заглавие (нулевият) се разпознава по мястото си — редът на
    дяловете е неизменен, тъй че съпоставянето пак сработва.
    """
    return дял.get("title_ru") or ""


def дялове_карта(стари, нови):
    """стар индекс → нов индекс. None за изчезналите дялове.

    ⚠⚠ ЦЯЛ ДЯЛ МОЖЕ ДА ОТПАДНЕ. При „Огласително слово" единственият блок
    на нулевия дял беше чуждият скрипт; махне ли се, дялът остава празен,
    `разчети` го изхвърля и ВСИЧКИ следващи се изместват с едно. Преводът
    обаче е ключиран по НОМЕР на дял — без тази карта той се залепва за
    съседния дял и статията излиза с разбъркан текст, БЕЗ нищо да гръмне.
    """
    sm = SequenceMatcher(None, [отпечатък(d) for d in стари],
                         [отпечатък(d) for d in нови], autojunk=False)
    карта = {}
    for вид, i1, i2, j1, j2 in sm.get_opcodes():
        if вид == 'equal':
            for k in range(i2 - i1):
                карта[i1 + k] = j1 + k
    return карта


def подравни(стари, нови):
    """Кои СТАРИ позиции оцеляват. None, ако има новопоявил се блок."""
    sm = SequenceMatcher(None, [b['ru'] for b in стари],
                         [b['ru'] for b in нови], autojunk=False)
    оцелели = []
    for вид, i1, i2, j1, j2 in sm.get_opcodes():
        if вид == 'equal':
            оцелели += list(range(i1, i2))
        elif вид == 'delete':
            pass
        else:                      # insert / replace — нов текст
            return None
    return оцелели if len(оцелели) == len(нови) else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--old', required=True)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    СТАРО = Path(a.old)

    пипнати = махнати = 0
    проблемни = []
    for p in sorted(ПРЕВОД.glob('*.json')):  # noqa: C901
        стар_f, нов_f = СТАРО / p.name, НОВО / p.name
        if not (стар_f.exists() and нов_f.exists()):
            continue
        стар = json.loads(стар_f.read_text(encoding='utf-8'))
        нов = json.loads(нов_f.read_text(encoding='utf-8'))
        пр = json.loads(p.read_text(encoding='utf-8'))
        преди_махнати = махнати
        карта = дялове_карта(стар['sections'], нов['sections'])
        нови_дялове = {}
        промяна = len(стар['sections']) != len(нов['sections'])
        for i, sd in enumerate(стар['sections']):
            ключ = str(i)
            if ключ not in пр['sections']:
                continue
            j = карта.get(i)
            if j is None:
                промяна = True      # дялът е изчезнал — преводът му отпада
                continue
            nd = нов['sections'][j]
            bg = пр['sections'][ключ]['blocks_bg']
            запис = dict(пр['sections'][ключ])
            if len(sd['blocks']) != len(nd['blocks']):
                # ⚠ Преводът трябва да е бил в крак със СТАРОТО разчитане,
                # инак подравняването няма от какво да тръгне.
                if len(bg) != len(sd['blocks']):
                    проблемни.append('%s дял %d: превод %d ≠ старо %d'
                                     % (p.stem, i, len(bg), len(sd['blocks'])))
                    нови_дялове[str(j)] = запис
                    continue
                оцелели = подравни(sd['blocks'], nd['blocks'])
                if оцелели is None:
                    проблемни.append('%s дял %d: появил се нов блок'
                                     % (p.stem, i))
                    нови_дялове[str(j)] = запис
                    continue
                махнати += len(bg) - len(оцелели)
                запис['blocks_bg'] = [bg[k] for k in оцелели]
                промяна = True
            нови_дялове[str(j)] = запис
        пр['sections'] = нови_дялове
        if промяна:
            пипнати += 1
            if not a.dry_run:
                p.write_text(json.dumps(пр, ensure_ascii=False, indent=1),
                             encoding='utf-8')
            print('  %-46s −%d блока, дялове %d→%d'
                  % (p.stem, махнати - преди_махнати,
                     len(стар['sections']), len(нов['sections'])))
    print('-' * 60)
    print('пипнати статии: %d | махнати блока общо: %d' % (пипнати, махнати))
    for x in проблемни:
        print('  ⚠', x)
    if a.dry_run:
        print('(пробно — нищо не е записано)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
