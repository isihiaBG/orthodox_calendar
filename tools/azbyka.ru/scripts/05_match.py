#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
05_match.py — Напасва извлечените от azbyka данни към СЪЩЕСТВУВАЩАТА
таблица saints (на български), за да се допълнят tropar/kondak/life.

Вход:
  --db saints.csv            изнесената таблица (id|date|name|rank|group_code|sign|tropar|kondak|life)
  output/index.csv           дата ↔ слъг ↔ показано име  (от 02_index.py)
  output/saints_raw_ru.csv   текстовете по слъг          (от 04_parse_saints.py)

Изход (в output/):
  match_auto.csv    сигурни съвпадения (score >= AUTO_THRESHOLD)
  match_review.csv  сива зона — за ръчен преглед, с топ-3 кандидата
  match_none.csv    твои редове без кандидат (най-често български светии,
                    които azbyka няма — това е нормално, не е грешка)

ВАЖНО: скриптът НЕ пипа базата. Само предлага. Прилагането е отделна стъпка,
след като прегледаш match_review.csv.

Метод:
  Датата стеснява до кандидатите за деня; името решава кой от тях е.
  Нормализация: маха ударения, години, скоби, уеднаквява титлите
  (сщмч./прмч./мчч. → мч.), груб стем на окончанията, пази малките числа
  (12, 70, 40 — те различават "Събор на 12-те" от "Събор на 70-те").
"""

import argparse
import csv
import difflib
import os
import re
import sys
import unicodedata

csv.field_size_limit(sys.maxsize)   # житията са дълги полета

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "output")

# Прагове — настрой ги след първия пробег по реалните данни.
AUTO_THRESHOLD = 0.75    # >= това → приема се автоматично
MIN_THRESHOLD = 0.45     # < това → няма кандидат
TOP_N = 3                # колко кандидата да покаже в review

# ---------------------------------------------------------------------------
# Нормализация на имената (BG ↔ RU)
# ---------------------------------------------------------------------------

TITLES = {
    # руски
    "сщмч": "мч", "сщмчч": "мч", "прмч": "мч", "прмчч": "мч", "мчч": "мч",
    "мц": "мч", "мцц": "мч", "мч": "мч", "вмч": "мч", "вмц": "мч",
    "свт": "свт", "свтт": "свт", "прп": "прп", "прпп": "прп",
    "ап": "ап", "апп": "ап", "блгв": "блгв", "блж": "блж",
    "прав": "прав", "прор": "прор", "равноап": "равноап",
    # български
    "прпмч": "мч", "мчца": "мч", "св": "", "свв": "",
}

STOP = {"на", "и", "му", "брат", "още", "наричан", "също", "който", "е",
        "вместо", "накрая", "или", "от", "по", "за", "със", "с",
        # иконни обръщения — различават се по език, а същинското име на
        # иконата е един токен; махаме ги, за да остане само то:
        "икона", "икони", "иконы", "пресвета", "пресвятой", "пресвятыя",
        "богородица", "богородицы", "божией", "матери", "чудотворна",
        "чудотворной", "чудотворната"}

SUFFIXES = ("ского", "ская", "ские", "кого", "ому", "ого", "ый", "ий",
            "ья", "ия", "ей", "ов", "ев",
            "а", "я", "ы", "и", "у", "ю", "е", "о")


def strip_accents(s: str) -> str:
    """Маха комбиниращите ударения (Васи́лия → Василия), пази буквите."""
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")


def normalize(name: str) -> list[str]:
    s = strip_accents(name.lower())
    s = re.sub(r"\(.*?\)", " ", s)          # (1833), (Серб.), (Василовден)
    s = re.sub(r"†|\+", " ", s)
    s = re.sub(r"\b\d{3,4}\b", " ", s)      # години — но пази 12, 70, 40
    s = re.sub(r"\b(ок|г|гг|пр|хр|до|р|х|в|вв)\b", " ", s)
    s = s.replace("ё", "е").replace("ъ", "")   # ru ё ; bg Петър → Петр
    # Гръцката θ: българската традиция дава Т (Теодосий, Евтимий, Тома),
    # руската — Ф (Феодосий, Евфимий, Фома). Уеднаквяваме симетрично:
    s = s.replace("ф", "т")
    s = re.sub(r"[^\w\s]", " ", s)
    out = []
    for t in s.split():
        t = TITLES.get(t, t)
        if t and t not in STOP:
            out.append(t)
    return out


def stem(t: str) -> str:
    if t.isdigit():
        return t
    for suf in SUFFIXES:
        if len(t) > 4 and t.endswith(suf):
            return t[:-len(suf)]
    return t


def toks(name: str) -> list[str]:
    return [stem(t) for t in normalize(name)]


# Токеновото покритие е ненадеждно за много кратки имена: кандидат от един
# токен ("Петра") тривиално получава 100% покритие, ако този токен се среща
# някъде в дълго име ("Събор … Петър, брат му Андрей, …"). Затова се доверяваме
# на покритието само когато по-краткото име има поне толкова токена:
MIN_TOKENS_FOR_COVER = 3


def tok_cover(a_toks: list[str], b_toks: list[str]) -> float:
    """Каква част от токените на по-краткото име се покрива от другото."""
    if not a_toks or not b_toks:
        return 0.0
    short, long_ = (a_toks, b_toks) if len(a_toks) <= len(b_toks) else (b_toks, a_toks)
    if len(short) < MIN_TOKENS_FOR_COVER:
        return 0.0          # твърде кратко → разчитаме само на seq_score
    used = list(long_)
    hit = 0
    for t in short:
        best, bi = 0.0, -1
        for i, u in enumerate(used):
            r = difflib.SequenceMatcher(None, t, u).ratio()
            if r > best:
                best, bi = r, i
        if best >= 0.75:
            hit += 1
            if bi >= 0:
                used.pop(bi)
    return hit / len(short)


def seq_score(a_toks: list[str], b_toks: list[str]) -> float:
    return difflib.SequenceMatcher(
        None, " ".join(sorted(a_toks)), " ".join(sorted(b_toks))).ratio()


def score(a_toks: list[str], b_toks: list[str]) -> float:
    """Комбинирана оценка: издържа и на разлика в дължината на имената."""
    return max(tok_cover(a_toks, b_toks), seq_score(a_toks, b_toks))


# ---------------------------------------------------------------------------
# Четене / писане
# ---------------------------------------------------------------------------

YEAR_RE = re.compile(r"\b(\d{3,4})\b")


def year_warn(bg_name: str, az_name: str) -> str:
    """
    Сравнява годините в двете имена. НЕ наказва резултата — годините в двата
    източника често значат различни неща (година на смъртта срещу година на
    прославянето, различни датировъчни традиции), тъй че наказание би сваляло
    верни съвпадения. Само вдига флаг за ръчна проверка.
    """
    ya = [int(y) for y in YEAR_RE.findall(bg_name)]
    yb = [int(y) for y in YEAR_RE.findall(az_name)]
    if not ya or not yb:
        return ""
    d = min(abs(x - y) for x in ya for y in yb)
    if d <= 5:
        return ""
    if d <= 20:
        return f"YEAR_DIFF_{d}"
    return f"YEAR_MISMATCH_{d}"


def read_csv(path: str) -> list[dict]:
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="|", quotechar="'"))


def clean_field(v) -> str:
    if v is None:
        return ""
    v = str(v).replace("'", '"').replace("|", "/")
    v = v.replace("\r", " ").replace("\n", " ")
    return re.sub(r"[ \t]+", " ", v).strip()


def write_csv(path: str, fields: list[str], rows: list[dict]):
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter="|", quotechar="'",
                           quoting=csv.QUOTE_MINIMAL, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: clean_field(r.get(k, "")) for k in fields})


# ---------------------------------------------------------------------------
# Основна логика
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Fuzzy match azbyka → съществуваща база")
    ap.add_argument("--db", required=True, help="път до изнесената saints.csv")
    ap.add_argument("--auto", type=float, default=AUTO_THRESHOLD)
    ap.add_argument("--min", type=float, default=MIN_THRESHOLD)
    ap.add_argument("--skip-rank0", action="store_true",
                    help="прескочи редовете с rank=0 (коментари), вместо да ги матчва")
    args = ap.parse_args()

    db_rows = read_csv(args.db)
    index_rows = read_csv(os.path.join(OUT_DIR, "index.csv"))
    raw_rows = read_csv(os.path.join(OUT_DIR, "saints_raw_ru.csv"))

    texts = {r["slug"]: r for r in raw_rows}

    # Кандидати по дата. Иконите и съборите остават — те също се матчват.
    by_date: dict[str, list[dict]] = {}
    for r in index_rows:
        by_date.setdefault(r["date"], []).append(r)

    # Предварително токенизираме кандидатите (иначе е бавно)
    cand_toks = {}
    for r in index_rows:
        cand_toks[id(r)] = toks(r["name_as_shown"])

    # --- Проверка на диапазоните (честа причина за "нищо не матчва") ---
    db_dates = {r["date"] for r in db_rows}
    idx_dates = set(by_date)
    missing = sorted(db_dates - idx_dates)
    if missing:
        print("!" * 68)
        print(f"ВНИМАНИЕ: {len(missing)} дати от базата нямат кеширани страници:")
        print(f"  {missing[0]} … {missing[-1]}")
        print("  Тези редове ще излязат в match_none.csv само защото липсват")
        print("  данни. Свали ги с:")
        print(f"    python3 01_fetch_days.py --start {missing[0]} --end {missing[-1]}")
        print("  после пусни пак 02 → 03 → 04 → 05.")
        print("!" * 68)
        print()

    auto, review, none, skipped = [], [], [], []

    for i, db in enumerate(db_rows, 1):
        if i % 200 == 0:
            print(f"  … {i}/{len(db_rows)}")

        base = {
            "db_id": db["id"], "db_date": db["date"], "db_name": db["name"],
            "db_rank": db.get("rank", ""), "db_group": db.get("group_code", ""),
        }

        # rank=0 при Стоил е смесена категория ("коментар"): част от нея
        # СЪЩЕСТВУВА на azbyka (предпразненство, попразненство, отдание,
        # възпоменаване на вселенски събори — някои дори със свои тропари),
        # друга част я няма (Велики понеделник, задушници, начало на пост).
        # Затова по подразбиране ги матчваме нормално — тези без съответствие
        # ще паднат в match_none.csv сами. Прескачането е само по желание.
        if args.skip_rank0 and db.get("rank", "") == "0":
            skipped.append(base)
            continue

        a = toks(db["name"])
        cands = by_date.get(db["date"], [])
        scored = sorted(
            ((score(a, cand_toks[id(c)]), c) for c in cands),
            key=lambda x: -x[0])[:TOP_N]

        if not scored or scored[0][0] < args.min:
            none.append({**base,
                         "best_score": f"{scored[0][0]:.2f}" if scored else "",
                         "best_name": scored[0][1]["name_as_shown"] if scored else "",
                         "candidates_for_date": len(cands)})
            continue

        best_score, best = scored[0]
        t = texts.get(best["slug"], {})
        row = {
            **base,
            "score": f"{best_score:.2f}",
            "slug": best["slug"],
            "az_name": best["name_as_shown"],
            "az_sign": best.get("sign", ""),
            "url": best.get("url", ""),
            "tropar": t.get("tropar", ""),
            "tropar_trans": t.get("tropar_trans", ""),
            "tropar2": t.get("tropar2", ""),
            "tropar2_trans": t.get("tropar2_trans", ""),
            "kondak": t.get("kondak", ""),
            "kondak_trans": t.get("kondak_trans", ""),
            "kondak2": t.get("kondak2", ""),
            "kondak2_trans": t.get("kondak2_trans", ""),
            "life_html": t.get("life_html", ""),
            "sluzhba": t.get("sluzhba", ""),
            "icons": t.get("icons", ""),
            "az_review": t.get("review", ""),
            "year_warn": year_warn(db["name"], best["name_as_shown"]),
        }

        if best_score >= args.auto:
            auto.append(row)
        else:
            # В сивата зона показваме и алтернативите
            alts = " ;; ".join(f"{s:.2f} {c['name_as_shown'][:45]} [{c['slug']}]"
                               for s, c in scored[1:])
            review.append({**row, "alternatives": alts})

    write_csv(os.path.join(OUT_DIR, "match_auto.csv"),
              ["db_id", "db_date", "db_name", "db_rank", "db_group", "score",
               "slug", "az_name", "az_sign", "url",
               "tropar", "tropar_trans", "tropar2", "tropar2_trans",
               "kondak", "kondak_trans", "kondak2", "kondak2_trans",
               "life_html", "sluzhba", "icons", "az_review", "year_warn"], auto)

    write_csv(os.path.join(OUT_DIR, "match_review.csv"),
              ["db_id", "db_date", "db_name", "db_rank", "db_group", "score",
               "slug", "az_name", "alternatives", "url",
               "tropar", "tropar_trans", "kondak", "kondak_trans",
               "life_html", "sluzhba", "az_review", "year_warn"], review)

    write_csv(os.path.join(OUT_DIR, "match_none.csv"),
              ["db_id", "db_date", "db_name", "db_rank", "db_group",
               "best_score", "best_name", "candidates_for_date"], none)

    write_csv(os.path.join(OUT_DIR, "match_skipped.csv"),
              ["db_id", "db_date", "db_name", "db_rank", "db_group"], skipped)

    n = len(db_rows)
    print("\n" + "=" * 58)
    print(f"Редове в базата      : {n}")
    print(f"Авто (>= {args.auto:.2f})       : {len(auto):>5}  ({100*len(auto)/n:.1f}%)")
    print(f"За преглед           : {len(review):>5}  ({100*len(review)/n:.1f}%)")
    print(f"Без съвпадение       : {len(none):>5}  ({100*len(none)/n:.1f}%)")
    if skipped:
        print(f"Прескочени (rank=0)  : {len(skipped):>5}  ({100*len(skipped)/n:.1f}%)")
    print("=" * 58)
    warns = sum(1 for r in auto if r.get("year_warn"))
    if warns:
        print(f"\nВ авто с несъвпадащи години: {warns} — виж колона year_warn.")
        print("Годините в двата източника може да значат различно (смърт /")
        print("прославяне / друга традиция), но проверете ги за всеки случай.")

    if none:
        bg = sum(1 for r in none if r["db_group"] == "BG")
        print(f"\nОт без-съвпадение: {bg} са с group_code=BG — очаквано,")
        print("azbyka няма българските светии.")
    print(f"\nПрегледай: {os.path.join(OUT_DIR, 'match_review.csv')}")


if __name__ == "__main__":
    main()
