# Православен календар (orthodox_calendar)

*[Български](#български) · [English](#english)*

---

<a name="български"></a>

## Български

Мултиплатформено мобилно приложение за православен църковен календар на **български език**,
с възможност за показване както по **стар (юлиански)**, така и по **нов (григориански)**
стил. За всеки ден показва паметта на светиите, жития, тропари и кондаци, вида на
постния период, гласа и празниците.

Приложението е с **отворен код** и се разработва с некомерсиална, просветителска цел.

### Какво отличава приложението

За разлика от повечето подобни календари, които следват само един стил, тук
потребителят може да **превключва между стар и нов стил** и да вижда съответствията
между двата. Това прави приложението еднакво полезно както за следващите юлианския
календар, така и за онези, свикнали с гражданския.

### Възможности

- Показване по стар (юлиански) **и** нов (григориански) стил с възможност за превключване
- Навигация по дати
- Търсене по ключови думи вкл. и с възможност за филтриране чрез #, напр. #бг #ру #гр #атон #житие #тропар #кондак ...
- Жития на светиите за всеки ден
- Тропари и кондаци на църковно-славянски (транскрипция с новобългарски букви) и техните преводи.
- Постни периоди и вид на поста с препратки към типикона
- Икони на светиите и празниците
- Работа офлайн (данните се съхраняват локално)

### Технологии

Към настоящия момент приложението е компилирано и тествано единствено за Android. 
Тестовете на други платформи като iOS , Linux, Windows , TV са планирани за по-късен етап.

За изходния код се ползват:
- **Flutter** (Dart) — потребителски интерфейс
- **SQLite** — локална база данни
- **Python** — помощни скриптове за подготовка на данните

### Източници и атрибуция

Календарните данни (дата, глас, пост, седмица/неделя) са обективни църковни
сведения. Текстовете на житията, преводите и иконите принадлежат на съответните
първоизточници и се използват с уважение към авторството.

Под всяко житие в приложението се изписва източникът, от който е взето, за да се
даде възможност на потребителя да провери информацията в оригинал.

> Ако сте носител на права върху съдържание, използвано тук, и имате забележка,
> моля свържете се с мен — ще реагирам своевременно.

### Лиценз ##################################################################

Кодът в това хранилище е под лиценз **[GPL-3.0]**.

С прости думи казано: всеки може да копира и преизползва програмния код вкл. за комерсиални цели, но при разпространяване на производния код, съдържащ каквато и да е част от този код, се задължава да държи целия производен код отворен (под същия лиценз) :)

Този лиценз покрива **само програмния код**. Съдържанието на календара
(жития, преводи, икони) **не** попада под него и остава собственост на
съответните първоизточници, използвано съгласно техните условия.

### Състояние на проекта

Проектът е в активна разработка. Функционалности, структура на базата и
интерфейсът подлежат на промяна.

### Автор

Разработва се като личен проект с отворен код.
Предложения и забележки са добре дошли през Issues.

---

<a name="english"></a>

## English

A multiplatform mobile application featuring an Orthodox Church calendar in **Bulgarian**,
with the ability to display dates in both the **Old (Julian)** and
**New (Gregorian)** style. For each day it shows the commemorated saints, their
lives, troparia and kontakia, the type of fasting period, the tone, and the feasts.

The application is **open source** and developed with a non-commercial,
educational purpose.

### What makes it different

Unlike most similar calendars, which follow only one style, this application lets
the user **switch between the Old and New style** and see the correspondence
between the two. This makes it equally useful both for those who follow the Julian
calendar and for those accustomed to the civil one.

### Features

- Display in Old (Julian) **and** New (Gregorian) style with switching
- Navigation by date
- Search by keyword, including filtering via #, e.g. #bg #ru #gr #athos #life #tropar #kondak ...
- Lives of the saints for each day
- Troparia and kontakia in Church Slavonic (transcribed using contemporary Bulgarian letters) as well as their Bulgarian translation.
- Fasting periods and type of fast
- Icons of the saints and feasts
- Offline support (data is stored locally)

### Technologies

For now, the application is only compiled and tested on Android.
Testing on other platforms — like iOS, Linux, Windows, and TV — is scheduled for a later stage.

Under the hood, the code relies on:
- **Flutter** (Dart) — user interface
- **SQLite** — local database
- **Python** — helper scripts for data preparation

### Sources and attribution

The calendar data (date, tone, fast, week/Sunday) are objective ecclesiastical
facts. The texts of the saints' lives, the translations, and the icons belong to
their respective original sources and are used with respect for authorship.

Beneath each life the application displays the source it was taken from, so that
the user can verify the information against the original.

> If you hold rights to content used here and have any concern, please contact
> me — I will respond promptly.


### License ##################################################################

The code in this repository is licensed under **[GPL-3.0]**.

In simple terms: anyone may copy and reuse this code, including for 
commercial purposes, but when distributing derivative code containing 
any part of this code, they are obliged to keep the entire derivative 
code open (under the same license) :)

This license covers **only the program code**. The calendar content (lives,
translations, icons) is **not** covered by it and remains the property of the
respective original sources, used in accordance with their terms.

### Project status

The project is under active development. Features, database structure, and the
interface are subject to change.

### Author

Developed as a personal open-source project.
Suggestions and feedback are welcome via Issues.
