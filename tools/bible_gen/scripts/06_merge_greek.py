#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""06_merge_greek.py — слива двата гръцки превода в ЕДИН пакет. Без мрежа.

    python3 06_merge_greek.py            # → output/packs/bible-el.db
    python3 06_merge_greek.py --check    # само проверява сечението

⚠⚠ ЗАЩО. Досега гръцкият беше ДВА пакета: `g` (Нов завет) и `el-r`
(Септуагинта, Стар завет). Човек сваляше „Гръцки (НЗ)", отваряше Псалтира и
намираше празно; сваляше и „Гръцки (LXX)", отваряше Евангелието и пак
празно. Двата обаче НЕ СЕ ПРЕПОКРИВАТ никъде, тъй че са едно нещо, разделено
по недоразумение. (Наблюдение на потребителя, 11.09.2026.)

⚠⚠ СЕЧЕНИЕТО СЕ ПРОВЕРЯВА ПРИ ВСЯКО ПУСКАНЕ и скриптът СПИРА, ако намери
дори един общ стих. Сливане при застъпване значи мълчаливо изгубен текст —
единият превод би презаписал другия. Мерено към 11.09.2026: 7942 + 28057
стиха, 27 + 49 книги, сечение НУЛА.

⚠ ИМЕТО КАЗВА ОТКЪДЕ Е СТАРИЯТ ЗАВЕТ. Пълното име е „Гръцки (Старият завет
по Септуагинта)" — то се вижда при избора за сваляне; краткото, с което
човек си избира превод в лентата, остава само „Гръцки". Разликата не е
дребна: гръцкият Стар завет по Септуагинта се разминава с масоретския и по
номерация, и по състав. (Бележка на потребителя, 11.09.2026.)

⚠ Новият код е `el`. Старите `g` и `el-r` НЕ се трият от изданието в GitHub:
вече инсталирани копия ги ползват, а споделени линкове ги назовават.
Приложението ги приравнява към `el` (виж kGreekLegacy в bible_packs.dart).
"""

import argparse
import os
import sqlite3
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
FULL_DB = os.path.join(PROJECT_DIR, "output", "bible_full.db")
OUT_DIR = os.path.join(PROJECT_DIR, "output", "packs")

ИЗТОЧНИЦИ = ["el-r", "g"]          # ⚠ редът е канонически: СЗ, после НЗ
НОВ = "el"
ПЪЛНО = "Гръцки (Старият завет по Септуагинта)"
КРАТКО = "Гръцки"
СЪКР = "гр"
LANG_TABLES = ["verses", "titles", "notes", "annotations", "links"]


def table_sql(con, name):
    row = con.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name=?",
        (name,)).fetchone()
    return row[0] if row else None


def провери(src):
    """Спира, ако двата превода се препокриват някъде."""
    мн = {}
    for ез in ИЗТОЧНИЦИ:
        мн[ез] = {(b, c, v) for b, c, v in src.execute(
            "SELECT book, chapter, verse FROM verses WHERE lang=?", (ез,))}
        print("  %-6s %6d стиха" % (ез, len(мн[ез])))
    сеч = мн[ИЗТОЧНИЦИ[0]] & мн[ИЗТОЧНИЦИ[1]]
    книги = {b for b, _, _ in мн[ИЗТОЧНИЦИ[0]]} & \
            {b for b, _, _ in мн[ИЗТОЧНИЦИ[1]]}
    print("  сечение: %d стиха, %d книги" % (len(сеч), len(книги)))
    if сеч or книги:
        sys.exit(
            "⚠⚠ ПРЕПОКРИВАТ СЕ — сливането Е ЗАБРАНЕНО.\n"
            "При застъпване единият превод би презаписал другия МЪЛЧАЛИВО.\n"
            "Примери: %s" % sorted(сеч)[:5])
    return sum(len(v) for v in мн.values())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    арг = ap.parse_args()
    if not os.path.exists(FULL_DB):
        sys.exit("Няма %s — пусни първо 04_build_db.py БЕЗ --langs." % FULL_DB)
    src = sqlite3.connect(FULL_DB)
    общо = провери(src)
    if арг.check:
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "bible-%s.db" % НОВ)
    if os.path.exists(out):
        os.remove(out)
    dst = sqlite3.connect(out)

    # Схемата се преписва ОТ ИЗТОЧНИКА — както в 05_build_packs.py.
    dst.execute(table_sql(src, "languages"))
    for t in LANG_TABLES:
        sql = table_sql(src, t)
        if sql:
            dst.execute(sql)

    # ⚠ Редът за езика се взима от СЕПТУАГИНТАТА: тя носи шрифта и
    # междуредието, а те са едни и същи за двата (една писменост).
    кол = [r[1] for r in src.execute("PRAGMA table_info(languages)")]
    ред = dict(zip(кол, src.execute(
        "SELECT * FROM languages WHERE code=?", (ИЗТОЧНИЦИ[0],)).fetchone()))
    ред["code"] = НОВ
    ред["scope"] = "all"
    ред["bg_title"] = ПЪЛНО
    ред["bg_short"] = КРАТКО
    ред["bg_abbr"] = СЪКР
    if "title" in ред:
        ред["title"] = "Ελληνικά"
    dst.execute("INSERT INTO languages (%s) VALUES (%s)"
                % (",".join(кол), ",".join("?" * len(кол))),
                [ред[c] for c in кол])

    броеве = {}
    for t in LANG_TABLES:
        if not table_sql(src, t):
            continue
        поле = [r[1] for r in src.execute("PRAGMA table_info(%s)" % t)]
        if "lang" not in поле:
            continue
        i = поле.index("lang")
        n = 0
        for ез in ИЗТОЧНИЦИ:
            редове = src.execute(
                "SELECT * FROM %s WHERE lang=?" % t, (ез,)).fetchall()
            if not редове:
                continue
            # ⚠ Колоната `lang` се пренаписва на новия код — заявките в
            # приложението търсят по нея (виж BibleDb._dbFor).
            редове = [tuple(НОВ if k == i else x for k, x in enumerate(r))
                      for r in редове]
            dst.executemany(
                "INSERT INTO %s VALUES (%s)"
                % (t, ",".join("?" * len(редове[0]))), редове)
            n += len(редове)
        броеве[t] = n

    dst.execute("CREATE INDEX IF NOT EXISTS idx_verses_place"
                " ON verses (lang, book, chapter)")
    dst.commit()
    dst.execute("VACUUM")
    dst.commit()
    # ⚠ Проверка СЛЕД записа: сборът трябва да съвпада точно.
    има = dst.execute("SELECT COUNT(*) FROM verses").fetchone()[0]
    dst.close()
    if има != общо:
        sys.exit("⚠ Записани %d стиха вместо %d — НЕ качвай този файл."
                 % (има, общо))
    print("  →  %s   %.1f MB" % (out, os.path.getsize(out) / 1048576))
    print("  таблици:", ", ".join("%s=%d" % kv for kv in броеве.items()))
    print("  стихове: %d  ✓" % има)


if __name__ == "__main__":
    main()
