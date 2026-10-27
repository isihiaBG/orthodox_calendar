# Православен календар — CLAUDE.md

Flutter приложение (Android, плюс уеб билд) за православен църковен календар
на български: жития, служби, пости, празници, четива, Библия, Молитвослов,
книги и четене на глас. Хранилището е публично: `isihiaBG/orthodox_calendar`.

**Комуникацията, вкл. коментарите в кода, е на български.**
⚠ Потребителят е и авторът на „Разговори…" (йером. Калиник Пецев) — решенията
за текста, ударенията и звука на книгата са негови.

Подробностите са в `docs/notes/` (по-долу има указател). Чети ги, когато
работиш по съответната част. Не ги зареждай всичките наведнъж.

## Започни оттук

Текущото състояние, последният билд и какво чака автора:
[docs/notes/status.md](docs/notes/status.md). Отворените задачи са в
[docs/notes/backlog.md](docs/notes/backlog.md).

⚠ При нов запис за състоянието пиши в `status.md` (най-новото отгоре), не тук.
Нова находка по подсистема пиши в нейния файл в `docs/notes/`. Тук влиза само
правило, което важи за целия проект.

## Устройство накратко

- Данните са SQLite бази в `assets/db/`:
  - `calendar_old.db` / `calendar_new.db` — по стил, по няколко години;
  - `lives.db` — жития и песнопения;
  - `reference.db`, `teofan.db`, `optina.db`, `lives_plus.db`, `bible.db`,
    `molitvoslov.db`.
  Само `lives` се ATTACH-ва към календарната. Виж `lib/database_helper.dart`.
- Томовете („Месецослов", „Читалня") се четат живо от `.epub` в `assets/`.
- Генераторите и конвейерите са в `tools/` (част от папките са в `.gitignore`,
  тогава техните README са единственото описание).
- Календарът се прави от **семето** `tools/calendar_gen/input/db/calendar_old.db`.
  Поправките са там, не в `assets/db/` — виж [calendar.md](docs/notes/calendar.md).

## Общи правила (платени скъпо)

- **Изворите се поправят, не изделията.** Поправка направо в база или `.epub`
  в `assets/` се губи при следващото сглобяване. Пипай извора на конвейера и
  пускай веригата **докрай, по реда ѝ** (пропусната стъпка = тиха загуба).
  Повечето конвейери не са идемпотентни: ръчен бекъп преди пускане.
- **Тихият отказ е най-скъпият бъг.** Голо `return` при непостроен регион, при
  `context.mounted` след `await`, при неразчетен линк — всяко струва часове.
  Повтаряй опита, съобщавай или пиши в лог; не излизай мълчаливо.
- **`BuildContext` през `await`:** взимай `NavigatorState` /
  `ScaffoldMessenger` ПРЕДИ първото `await`. `Navigator.of(navigatorKey.currentContext)`
  не намира този навигатор — ползвай `currentState`.
- **„Кое се показва" и „кое е заредено" не бива да са две състояния.** Изведи
  едното от другото.
- **Улавяй и връщай позиция през една и съща примитива.** Мерещият е огледален
  на рисуващия (същият шрифт, същите парчета).
- **Меродавно е устройството, не десктопът.** SQLite и `LIKE` се държат различно.
  Сверявай инсталирания билд по md5, не по изхода на `adb install`. Часовникът
  на телефона изостава.
- **Мери, не извеждай** (вертикално подравняване в pdf пакета, литургични
  адреси, височини). Малък `dart run` / `flutter test` тест е по-бърз от билд.
- **Разделител, който може да се срещне в данните, не е разделител** (екранирай).
- **Не пиши ударения, имена и факти по памет** — решава авторът / изворът.
- **Нищо от `.bak` не бива да влиза в `assets/`** (`pubspec.yaml` включва целите
  папки): `ls assets/db/*.bak-*` трябва да е празно преди билд.
- Ключове и пароли (ElevenLabs, DeepSeek, keystore, `lib/audio_secret.dart`)
  **никога не се показват** и не влизат в git.

## Билд и релийз

Никога release билд без изрична молба. Когато е поискан — само arm64:

```bash
flutter build apk --release --target-platform android-arm64 \
  --build-name=0.9.<N> --build-number=<N> --dart-define=BUILD_DATE=<ГГГГ-ММ-ДД>
```

- `<N>` е винаги по-голямо от последния билд (виж `status.md`), иначе
  `INSTALL_FAILED_VERSION_DOWNGRADE`.
- Изходът е `Правосл._календар.apk` + `.zip` в `build/app/outputs/flutter-apk/`.
- При всеки релийз:
  - 1–3 реда за човека в `assets/release_notes.json`;
  - заглавие в ChangeLog `## <дата> — версия 0.9.<N>`;
  - `tools/release/publish_app.py <N>`, после commit + push.
- Нов звук: обнови `assets/audio_index.json` ПРЕДИ билд (с `?x=$(date +%s)`).
- ⚠ Преди Google Play: `kAppSelfUpdate = false`, махни `REQUEST_INSTALL_PACKAGES`
  и `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`.

Подробно: [dev-practice.md](docs/notes/dev-practice.md).

Разработка: `flutter run -d <id>` с fifo за `r` (горещото презареждане НЕ пренася
`assets/`). Устройство: TFY LX1, adb `ALDE6R2401002080`. Капани с `pgrep -f` /
`pkill -f` (хващат собствената обвивка) — виж dev-practice.md.

## Указател към бележките

| файл | за какво |
|---|---|
| [status.md](docs/notes/status.md) | текущо състояние, последните сесии |
| [backlog.md](docs/notes/backlog.md) | отворени задачи; история на затворените |
| [overview.md](docs/notes/overview.md) | общото описание на приложението |
| [calendar.md](docs/notes/calendar.md) | генераторът, пости, подвижни/граждански дати, слъгове, сверки |
| [readings.md](docs/notes/readings.md) | Евангелие и Апостол, прокимени, литургичният адрес |
| [day-sections.md](docs/notes/day-sections.md) | слова, Дебольски, Типикон, „Особености на деня" |
| [hymns.md](docs/notes/hymns.md) | песнопенията, тропари и кондаци |
| [lives-pipelines.md](docs/notes/lives-pipelines.md) | lives_bg / lives_extra / mitropolia, илюстрации, надписи |
| [azbyka-articles.md](docs/notes/azbyka-articles.md) | статиите от azbyka.ru |
| [reference-teofan-optina.md](docs/notes/reference-teofan-optina.md) | „Справочник", Теофан, Оптинските |
| [corrections.md](docs/notes/corrections.md) | масови поправки, библейските връзки (linkify) |
| [reader-common.md](docs/notes/reader-common.md) | общото на четците: позиция, буквица, обтичане, живи дати |
| [book-reader.md](docs/notes/book-reader.md) | „Месецослов", томовете, бележките под линия |
| [chitalnya.md](docs/notes/chitalnya.md) | „Читалня", „Разговори…" |
| [bible.md](docs/notes/bible.md) | „Библия": пакети, препратки, търсене, режими |
| [molitvoslov.md](docs/notes/molitvoslov.md) | „Молитвослов" и богослужебните книги |
| [quotes-links.md](docs/notes/quotes-links.md) | цитати, споделяне, адреси, App Links |
| [search.md](docs/notes/search.md) | търсене и хаштагове |
| [pdf.md](docs/notes/pdf.md) | PDF и мениджърът на страниците |
| [tts-audio.md](docs/notes/tts-audio.md) | четене на глас, звукът, плейърът |
| [fonts.md](docs/notes/fonts.md) | шрифтовете и лицензите им |
| [ui-general.md](docs/notes/ui-general.md) | настройки, меню, общ интерфейс |
| [dev-practice.md](docs/notes/dev-practice.md) | билд, релийз, adb, уеб, капани на средата |

Пълното старо съдържание е разпределено дословно в тези файлове — нищо не е
изтрито. Неразделеният оригинал е в git историята (`git show HEAD~1:CLAUDE.md`
след комита на разделянето).
