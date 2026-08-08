# CLAUDE.md

Guidance for AI assistants working in this repository.

## 1. What this is

**Православен календар** — a Flutter (Dart) app showing the Bulgarian Orthodox
Church calendar, with the ability to switch between **Old Style (Julian)** and
**New Style (Gregorian)** reckoning. For every day it shows the commemorated
saints, their lives (жития), troparia/kontakia, the fast period and fast type,
the tone (глас), and the week/Sunday of the liturgical cycle. Everything works
offline out of bundled SQLite databases.

Alongside the app there is `tools/calendar_gen/` — a **Python pipeline that
generates the calendar databases** for an arbitrary (year, style) from rules
extracted out of the seed database.

Author: Hieromonk Kalinik (Vasilev). Code is GPL-3.0; the calendar *content*
(lives, translations, icons) is not — it belongs to its original sources.

**Target platform is Android.** iOS/Linux/Windows/Web/macOS runner directories
exist (stock Flutter scaffolding) but are untested. `.claude/launch.json`
defines a `flutter-web` server config for quick previewing only.

## 2. Read this before you touch dates

This is the single largest source of bugs in the project. Almost every
non-obvious piece of code exists because of it.

* **Every date stored in the databases is a CIVIL (Gregorian) date.**
  `calendar_days.date` and `saints.date` are civil dates in `YYYY-MM-DD`.
  Nothing in the DB is stored as a "Julian date".
* **The Old/New Style switch is a switch between two whole databases**, not a
  display transformation. `calendar_old.db` places the fixed feasts 13 days
  later in civil time; `calendar_new.db` places them on the civil date itself.
* **The −13/+13 day offset is only valid for 1900–2099.** Anywhere general
  arithmetic is needed, use `julianGregorianOffset(year)` from
  `lib/paschalion.dart` / `tools/calendar_gen/paschalion.py`, not a literal 13.
  Literal 13 appears in UI navigation code (`main.dart`, `month_screen.dart`,
  `search_screen.dart`) — this is intentional and scoped to display, but do not
  spread it into new data logic.
* **Three kinds of commemoration exist**, and they move differently when the
  style changes:
  1. **fixed** — tied to the church date (Nativity is always 25 December) →
     shifts by the Julian/Gregorian offset in civil time.
  2. **pascha** — tied to Pascha (Great Lent, Pentecost, the tones, the
     weeks/Sundays). The paschalion is shared by both styles, so these fall on
     the **same civil day in both** → no shift.
  3. **anchor** — movable relative to a *fixed* feast ("Saturday before
     Theophany", "Sunday after Nativity"). Recomputed against the already
     shifted feast — neither a flat shift nor Pascha-relative.
  A single `calendar_days` row mixes layers, so a row can never be moved as a
  unit. This is exactly why the Python generator disassembles and rebuilds.
* **A bare church date `"MM-DD"` in `rules.py` is always the church (Julian)
  number, not an old-style civil date.** Same convention as the dual notation
  "16/29 юли": the number without a slash is the church one. The README warns
  that this direction has been confused before.
* Pascha is **computed, never read from the DB** (`paschalion.dart` /
  `paschalion.py`, Meeus' Julian variant), so screens that depend on it work
  for years outside the range of the bundled database.

## 3. The database assets are NOT in this repository

`.gitignore` excludes `assets/db/*.db` and `tools/calendar_gen/input/db/*.db`.
A fresh clone therefore has **no `assets/db/` directory at all**, and:

* `flutter run` will start but every screen will fail to load data
  (`rootBundle.load('assets/db/calendar_old.db')` throws).
* The Python generator cannot run — it reads
  `tools/calendar_gen/input/db/calendar_old.db` (a copy of the seed
  `assets/db/calendar_old.db`), which is also ignored.

Required files, obtained from the maintainer:

```
assets/db/calendar_old.db          # Old Style calendar
assets/db/calendar_new.db          # New Style calendar
assets/db/lives.db                 # texts, shared by both styles
assets/db/<name>.db.version        # optional plain-text version number
tools/calendar_gen/input/db/calendar_old.db   # seed for the generator
```

**Do not commit `.db` files.** If a task requires the data and it is absent,
say so plainly rather than fabricating a database or altering `.gitignore`.

Two untracked leftovers live in the working tree — `lives.db` (0 bytes, at the
repo root) and `lib/month_screen.dart.back`. Ignore both; do not commit them.

## 4. Commands

Flutter is **not installed in the Claude Code remote environment**, so
`flutter analyze` / `flutter test` cannot be run here. Reason carefully about
Dart changes instead of relying on the analyzer, and say so when you could not
verify a change by running it.

```bash
# App
flutter pub get
flutter run                      # Android device/emulator
flutter run -d web-server --web-port 8765   # matches .claude/launch.json
flutter analyze
flutter test
flutter build apk --release
dart run flutter_launcher_icons  # regenerate Android launcher icons

# Localization (ARB → lib/l10n/app_localizations*.dart)
flutter gen-l10n                 # config in l10n.yaml; `generate: true` in pubspec

# Calendar generator (from tools/calendar_gen/)
python3 classify.py              # report only, changes nothing — read this first
python3 extract_rules.py         # extract + round-trip verify the rules
python3 build.py --year 2026 --style old   # must ~reproduce calendar_old.db
python3 build.py --year 2026 --style new
# output lands in tools/calendar_gen/out/ (gitignored)
```

The generator has no third-party dependencies (stdlib `sqlite3`, `csv`, `re`).
`check.py` is described in the tools README but **does not exist yet**.

## 5. Architecture

### Data layer

`lib/database_helper.dart` is a static singleton around **two** SQLite
databases:

* `calendar_old.db` **or** `calendar_new.db` — chosen by
  `AppSettings.isOldStyle`; the calendar proper (dates, tones, fasts, saints).
* `lives.db` — the texts (lives, troparia, kontakia, services), **shared by
  both styles**, `ATTACH`ed to the same connection as `lives`. Queries join
  across them: `LEFT JOIN lives.texts l ON l.slug = s.slug`. The join key is
  `slug`; a calendar row with no slug simply gets NULLs. This exists so a
  130 KB life is not duplicated into every style and every year's database.

Switching the style **closes and reopens** the connection (`_initDatabase`),
reloads the lookup caches (`fastPeriods`, `fastTypes`) and recomputes
`dataMinDate` / `dataMaxDate` from `MIN/MAX(calendar_days.date)`.

**Gotcha:** `needsCopy` is currently hard-coded to `true` in both
`_initDatabase()` and `_ensureLivesDb()`, so the asset databases are copied
over the on-device copies **on every launch**. The version-file mechanism
(`assets/db/<name>.db.version` + a `db_version_<name>` SharedPreferences key)
is written but bypassed — the real condition is commented out one line above
each. Preserve this unless explicitly asked to re-enable versioning.

### Schema (as produced by `build.py`)

| table | columns of note |
|---|---|
| `calendar_days` | `date` (PK, civil), `tone`, `fast_period`, `fast_type`, `fast_explanation_key`, `week_id`, `sunday_id`, `note` |
| `saints` | `id`, `date` (civil), `name`, `rank`, `group_code`, `sign`, `slug` |
| `weeks`, `sundays` | `id`, `name`, `note`, `tone` — no dates, referenced by id |
| `fast_periods`, `fast_types`, `saint_ranks`, `saint_groups`, `fast_explanations` | static lookup tables, copied verbatim |
| `readings` | copied verbatim — **known limitation**, its dates are only correct for 2026 Old Style |
| `lives.texts` (separate DB) | `slug`, `name`, `tropar`, `tropar_trans`, `tropar2`, `kondak`, `kondak_trans`, `kondak2`, `life`, `sluzhba`, `source` |

`saint_group_mapping` and `prayers` are deliberately **not** carried over — the
app never reads them.

Enumerations (mirrored in `lib/l10n/app_bg.arb` and `tools/calendar_gen/fasts.py`):

* `fast_period`: 0 Блажи се, 1 Постен ден, 2 Велик пост, 3 Петров пост,
  4 Богородичен пост, 5 Рождественски пост
* `fast_type`: 0 без указания, 1 без месо, 2 риба, 3 хайвер, 4 олио,
  5 олио след вечерня, 6 без олио, 7 сухоядение (unused — folded into 6),
  8 хляб/смокини/вино, 9 пълно въздържание

### App structure — `lib/`

Entry and shell:

* `main.dart` — `runApp`, theme wiring, and `CalendarPageView`: the day/month
  toggle, the `PageView` over days, the AppBar (menu, search, today, date
  picker, settings). `AppSettings.load()` **must** finish before `runApp` —
  `DatabaseHelper` picks the database from `isOldStyle`.
  Page bounds start from a synchronous estimate (1 Jan − 14 days … 31 Dec + 14
  days of the current year) and are silently refined from the DB by
  `_refineDateBoundsFromDatabase()`.
* `app_settings.dart` — global mutable state. Only `isOldStyle` and
  `oldStyleFirst` are persisted (SharedPreferences); `currentPage`, `today`,
  `flashDate` are session state.
* `app_theme.dart` — **all** colours, font sizes, dimensions and icon paths
  (`AppColors`, `AppFonts`, `AppSizes`, `AppIcons`). New colours go here, never
  inline in a widget. `AppIcons.forRank(rank)` maps a saint's rank 1–5 to the
  typikon sign SVG and its colour (1 Велик господски, 2 Бдение, 3 Полиелей,
  4 Славословна, 5 Шестерична, anything else → no sign).
* `app_drawer.dart` — the shared navigation drawer, plus the global
  `appSettingsChangedHook`. `main.dart` registers `_onSettingsChanged` into it
  in `initState`; secondary screens (`holidays_screen`, `fasts_screen`) fire it
  so the calendar rebuilds and re-navigates after a style change.
* `settings_screen.dart` — settings body, used both as `SettingsDrawer` and as
  a full screen.

Screens:

* `day_screen.dart` — one day: dual date header, week/Sunday, tone, fast,
  saints list, expandable readings sections.
* `month_screen.dart` — scrolling month grid; public `MonthScreenState` API
  used from `main.dart`: `navigateToDate`, `getMiddleDate`,
  `refreshAfterSettingsChange`, `currentDate`.
* `search_screen.dart` — bottom-sheet search with `#` filters.
* `reader_screen.dart` (3.5k lines, the largest file) — the unified reader for
  lives / troparia / kontakia / services: font sizing, drop cap, `saint://`
  internal links that push another `ReaderScreen`, source attribution, PDF
  share.
* `holidays_screen.dart`, `fasts_screen.dart` — reference screens for feasts
  and fasts. `holidays_screen` reads dates from the current calendar DB;
  `fasts_screen` reads **nothing** — everything is computed from the paschalion.
* `about_screen.dart`.

Widgets and helpers:

* `saint_expandable_tile.dart` — lazy expandable saint row. The day query
  fetches only cheap boolean flags (`has_life`, `has_tropar`…); full texts load
  on tap via the injected `loadTexts()`. **Never pull text columns into a
  per-day query** — a single life can be 130 KB.
* `models/day_model.dart` — `CalendarDay`, `Saint`, `fromMap` factories.
* `paschalion.dart` — Pascha, `julianGregorianOffset`, `civilFromChurch`.
* `moon_calculator.dart` — Meeus lunar phases (used by `month_screen`), pure
  math, no data source.
* `dual_date_text.dart`, `year_selector.dart`, `round_icon_button.dart`,
  `info_sheet.dart`, `typikon_legend_sheet.dart`, `fast_explanation_sheet.dart`
  — shared UI pieces, extracted specifically so copies do not drift apart.
* `pdf_export.dart` — A4 PDF built manually with the `pdf` package.
  `Printing.convertHtml` was tried and abandoned (deprecated and hangs); do not
  reintroduce it.
* `hyphenate.dart` — soft-hyphen insertion for justified Cyrillic text.
  **Currently not imported anywhere.** If you wire it in, cache the result —
  hyphenating a 130 KB life on every build is expensive.
* `app_strings.dart` — a nearly-empty placeholder for future localization.

### Search filters

The search field accepts `#` tokens, combined with logical AND:

* group filters → `saints.group_code`: `#bg #ru #gr #athos #rs #ge #ro #jer
  #us #vs` plus Cyrillic aliases (`#бг`, `#ру`, `#атон`…).
* content filters → presence of a text in `lives.texts`: `#троп`, `#конд`,
  `#жит`, `#служ` and Latin equivalents.
* negation with `#!`: `#троп #!кон` = has a troparion and has no kontakion.
* `*` is translated to SQL `%`. An unrecognised `#token` is searched as plain
  text. When any filter is active, weeks and Sundays are excluded from results.

## 6. The calendar generator — `tools/calendar_gen/`

Read `tools/calendar_gen/README.md` (Bulgarian) before changing anything here;
it is the authoritative description and explains the reasoning.

Pipeline, in order:

1. `classify.py` — sorts `saints` rows into fixed / pascha / anchor by regex
   over the name, prints a report. **Changes nothing.** Most mistakes surface
   here, so run it first.
2. `overrides.csv` — manual decisions for disputed rows, keyed by
   **date + name** (not `id` — ids shift on every edit of `saints`). Also
   accepts `skip` to drop a row from the output entirely.
3. `extract_rules.py` — derives the "eternal" rules (church month/day for
   fixed, offset from Pascha for pascha, anchor + direction + weekday for
   anchor) and **round-trip verifies** them: applied to 2026 Old Style they
   must reproduce the original civil dates. Writes nothing.
4. `rules.py` — a small DSL for movable feasts. Anchors: `Пасха`,
   `Петдесетница`, `ВсичкиСветии`, a named fixed feast, or a bare church date
   `"MM-DD"`. Operators: `+N`/`-N` days, `>=W`/`<=W`/`>W`/`<W`/`~W` (weekday
   jumps), and the conditional `?[X==W];[then];[else]`. Full grammar is in the
   module docstring.
5. `known_movable.csv` — rules for entries whose movability is not written in
   their text at all, or is phrased outside `classify.py`'s regex. Columns:
   `date,name,rule,note`. **`date` and `name` must be copied literally out of
   the DB via SQL** — the data contains non-breaking spaces (`\xa0`) and
   retyping them silently breaks the match.
6. `build.py --year Y --style old|new` — writes
   `out/calendar_<style>_<year>.db`. Aborts if `extract_rules` reports
   round-trip mismatches.
7. `check.py` — described in the README, **not yet written**.

Supporting modules: `paschalion.py` (mirror of the Dart one), `fasts.py`
(`fast_period`, `fast_type`, `fast_explanation_key`), `weeks_sundays.py` (tone
and week/Sunday numbering, computed from scratch per year rather than copied).

The seed `calendar_old.db` is opened **read-only** (`file:...?mode=ro`) and is
never edited by these scripts. Edits to the seed's `saints` table propagate to
all years and styles by re-running the generator.

## 7. Conventions

* **Language.** All code comments, UI strings, and the tools README are in
  **Bulgarian**. Keep writing them in Bulgarian — do not translate existing
  comments to English, and do not add English comments to Dart/Python files
  here. Commit messages have historically been Bulgarian or the single word
  `backup`; write short descriptive messages (Bulgarian or English is fine).
* **Comment style.** Files open with a header block explaining what the file is
  *and why it exists* — including approaches that were tried and abandoned.
  This is a deliberate, valuable habit; when you extract or rewrite a file,
  carry the reasoning across rather than dropping it.
* **No localization yet.** `flutter_localizations`, `l10n.yaml`, `app_bg.arb`
  and the generated `lib/l10n/app_localizations*.dart` are all in place, but
  **nothing in the app imports `AppLocalizations`** — every user-facing string
  is hard-coded Bulgarian, and `MaterialApp` is pinned to `Locale('bg','BG')`.
  Do not start a piecemeal migration to ARB unless asked; if you do add strings
  to the ARB, keep them in sync with `app_strings.dart` intentions.
* **Colours** live in `AppColors`; the app is dark-mode only
  (`ColorScheme.dark`). Semantic markers from the DB (e.g. `sign_color`
  = `'red'`) are mapped to theme colours in `app_theme.dart`, never rendered
  from a DB hex value directly.
* **Formatting** is inconsistent (mixed tabs and spaces, some hand-aligned
  blocks). Match the surrounding file; do not reformat unrelated code.
* **Lints:** `package:flutter_lints/flutter.yaml`, no custom rules
  (`analysis_options.yaml`).
* **Fonts** are declared in `pubspec.yaml`: `Bukvica` (drop caps),
  `TamburinModern` (titles), `Cambria` (body, with italic and bold). The
  reader's `DropCapFont` mention in a comment refers to `Bukvica`.
* **Typikon sign SVGs** live in `assets/icons/tipikon_0*.svg`.

## 8. Testing

`test/widget_test.dart` contains an empty `main()` — there are effectively **no
tests**. The strongest correctness check in the project is the generator's
round-trip: `build.py --year 2026 --style old` should almost exactly reproduce
`calendar_old.db`. If you add tests, pure-logic units (`paschalion.dart`,
`moon_calculator.dart`, `rules.py`, `fasts.py`) are the ones that can be tested
without the missing databases.

## 9. Git workflow

Work on the branch you were assigned; push with `git push -u origin <branch>`.
Do not open a pull request unless explicitly asked. `main` is the default
branch.

## 10. Things not to do

* Do not commit `.db` files, or loosen the `.gitignore` rules that exclude them.
* Do not add text columns (`life`, `sluzhba`, `tropar`…) to per-day or
  per-month queries — flags only, texts on demand.
* Do not hard-code a 13-day offset in new data/calendar logic; use
  `julianGregorianOffset` / `civil_from_church`.
* Do not edit `tools/calendar_gen/input/db/calendar_old.db` from a script; it
  is the read-only seed.
* Do not treat a bare `"MM-DD"` in `rules.py` as a civil date.
* Do not reintroduce `Printing.convertHtml` in `pdf_export.dart`.
* Do not translate the Bulgarian comments or UI strings.
