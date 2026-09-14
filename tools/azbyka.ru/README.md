# azbyka.ru — житията, службите и песнопенията от azbyka.ru

## Какво е това

Първият и най-голям конвейер на проекта. Сваля от **azbyka.ru** дневните
страници на църковния календар, оттам вади страниците на всеки светия, и от
тях — житието, службата и песнопенията (тропари, кондаци, молитви,
величания). После ги превежда от руски на български с DeepSeek и ги сглобява
в `assets/db/lives.db` — базата, от която приложението чете житията.

⚠ **Папката е в `.gitignore`** (тежък кеш от хиляди HTML страници и чужди
текстове). Този файл е част от малкото, което е в git — пази го.

## Какво произвежда

| изход | какво е |
|---|---|
| `days/` | кеш на свалените HTML страници — не се трие напразно, всяко сваляне е учтиво към сайта |
| `output/index.csv` | мостът дата ↔ слъг ↔ адрес |
| `db/texts.csv` | **курираната, вечна таблица** с текстовете; тук има и ръчни редакции |
| `assets/db/lives.db` | готовата база за приложението (таблици `texts` и `hymns`) |

## Пълният ред

⚠ Номерата **са** редът на изпълнение. Стъпки 01 и 03 пипат мрежата, всички
останали работят офлайн по кеша.

```bash
cd tools/azbyka.ru/scripts

python3 01_fetch_days.py --start 2026-01-01 --end 2026-12-31   # ⚠ мрежа
python3 02_index.py
python3 03_fetch_saints.py                                     # ⚠ мрежа
python3 04_parse_saints.py
python3 05_match.py --db ../db/saints.csv
python3 06_merge_into_texts.py --in ../output/saints_raw_ru.csv
python3 08_split.py
python3 09_export_for_translation.py
python3 10_translate_deepseek.py        # ⚠ ПЛАТЕНА стъпка
python3 11_edit_deepseek.py             # ⚠ ПЛАТЕНА, по избор
python3 12_merge_translations_into_texts.py
python3 13_bible_links_bg.py
```

Песнопенията са отделна, по-късна верига върху същия кеш:

```bash
python3 14_extract_hymns.py        # кешираните страници → output/hymns.csv
python3 15_translate_hymns.py      # ⚠ ПЛАТЕНА; превежда само НЕпреведеното
python3 16_build_hymns_table.py    # → assets/db/lives.db, таблица hymns
```

## Стъпките една по една

**01_fetch_days.py** — сваля дневните страници. Тегли всяка дата само веднъж;
прекъснато пускане се продължава просто с повторно пускане.
```bash
python3 01_fetch_days.py --start 2026-01-01 --end 2026-12-31
python3 01_fetch_days.py --retry      # само онова, което е гръмнало
```

**02_index.py** — разчита свалените дни офлайн и прави `output/index.csv`.
Без аргументи.

**03_fetch_saints.py** — сваля страницата на всеки светия от списъка.
```bash
python3 03_fetch_saints.py
python3 03_fetch_saints.py --slugs ../output/athos_slugs.txt
```

**04_parse_saints.py** — от кешираните страници вади текстовете.
```bash
python3 04_parse_saints.py --out ../output/saints_raw_ru.csv
```
⚠ В папката стои и `04_parse_saints_old (removes outer links).py` — **стара
версия, не се пуска**. Държи се само за справка.

**05_match.py** — напасва свалените светии към съществуващата таблица.
```bash
python3 05_match.py --db ../db/saints.csv --auto --min 0.8
```
`--auto` приема сигурните съвпадения без питане; `--min` е прагът на
приликата; `--skip-rank0` пропуска коментарите (дни без светия).

**06_merge_into_texts.py** — долива нови слъгове в `db/texts.csv`,
**без** да презаписва съществуващи редове.
```bash
python3 06_merge_into_texts.py --in ../output/saints_raw_ru.csv
python3 06_merge_into_texts.py --in … --overwrite   # ⚠ ПРЕЗАПИСВА ръчни редакции
```

**07_athos.py** — еднократна добавка на светогорските светии. Не е част от
редовния ред.

**08_split.py** — от `db/texts.csv` строи SQLite базата.
```bash
python3 08_split.py --db ../db/texts.csv
```

**09_export_for_translation.py** — изважда само преводимите полета.

**10_translate_deepseek.py** — ⚠ **платената стъпка.** Едно повикване на
светия, с всичките му полета накуп.
```bash
python3 10_translate_deepseek.py --limit 5        # пилот, за да се измери
python3 10_translate_deepseek.py --slug sv-ioan-rilski
python3 10_translate_deepseek.py --show-prompt    # само показва промпта
```

**11_edit_deepseek.py** — ⚠ платена, по избор. Второ минаване: моделът вижда
готовия български и само го поправя.

**12_merge_translations_into_texts.py** — влива преводите обратно в
`db/texts.csv`. С `--edited` взима редактираните вместо суровите.

**13_bible_links_bg.py** — пренасочва библейските препратки към българския
текст (опашката `&bg~utfcs`).
```bash
python3 13_bible_links_bg.py --dry-run    # само показва какво би сменил
python3 13_bible_links_bg.py
```

**14/15/16** — песнопенията. `15` превежда само онова, което още няма
български; `16` прави `DROP TABLE` и сглобява таблицата наново.
```bash
python3 15_translate_hymns.py --limit 3 --dry-run
python3 16_build_hymns_table.py --dry-run
```

## ⚠ Предупреждения

- **`db/texts.csv` е курираната таблица и в нея има РЪЧНИ редакции.** Всяко
  пускане с `--overwrite` ги трие. Направи копие, преди да рискуваш.
- **Платените стъпки са 10, 11 и 15.** Винаги първо с `--limit 3`, за да
  видиш качеството и цената, и чак после наедро.
- **Редът 16 → после 06_hymns.py от `match_dmitry_lives/`** има значение:
  `16` прави `DROP TABLE hymns`, тъй че пуснат след другия, ще изтрие
  неговите редове. Виж CLAUDE.md, раздела за песнопенията.
- **Кешът в `days/` не се трие.** Повторното сваляне на хиляди страници е
  часове и е нелюбезно към сайта.
- **Ключът за DeepSeek** се чете от `.env` в тази папка (ред
  `DEEPSEEK_API_KEY=…`). Не влиза в git.

## Ако нещо се обърка

- „Няма DEEPSEEK_API_KEY" → липсва или е празен `.env`.
- Прекъснато сваляне → просто пусни скрипта наново, той прескача готовото.
- Празен резултат след `05_match.py` → почти винаги прагът `--min` е твърде
  висок, или имената в `saints.csv` са с други форми.
