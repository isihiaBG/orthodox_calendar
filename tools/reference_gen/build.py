#!/usr/bin/env python3
"""Създава assets/db/reference.db с ПРИМЕРНО съдържание.

⚠ НАДЖИВЯН. Истинската база вече се прави от
`Translate/scripts/03_build_db.py` — от преведените текстове. Този скрипт
стои само като напомняне за първоначалната структура; ако го пуснеш, ще
ЗАТРИЕ истинското съдържание с примерното.

Съдържанието тук е примерно (виж _SAMPLE по-долу): целта беше структурата
да е готова, за да се направи екранът, преди текстовете да съществуват.

    python3 tools/reference_gen/build.py

Презаписва базата на място. Тя не се пази в git (assets/db/ е игнорирана),
затова този скрипт е единственият ѝ източник.
"""

import os
import sqlite3

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'assets', 'db', 'reference.db')

SCHEMA = """
DROP TABLE IF EXISTS ref_articles;
DROP TABLE IF EXISTS ref_groups;

-- Разгъващите се полета в списъка.
CREATE TABLE ref_groups (
    id       INTEGER PRIMARY KEY,
    title    TEXT    NOT NULL,
    position INTEGER NOT NULL
);

-- Редовете вътре в тях; всеки води към едно четиво.
-- `body` е HTML — четецът (reader_screen.dart) го рендира както житията,
-- но БЕЗ орнаментираната буквица: това са указания, не жития.
CREATE TABLE ref_articles (
    id       INTEGER PRIMARY KEY,
    group_id INTEGER NOT NULL REFERENCES ref_groups(id),
    title    TEXT    NOT NULL,
    body     TEXT    NOT NULL,
    position INTEGER NOT NULL
);

CREATE INDEX idx_articles_group ON ref_articles(group_id, position);
"""

def _body(title):
    """Примерен текст — достатъчно дълъг, за да се види как се държи
    четецът при превъртане."""
    return (
        f"<h3>{title}</h3>"
        "<p>Това е <b>примерен текст</b>, сложен само за да има какво да се "
        "отвори, докато структурата на екрана се изгражда. Истинското "
        "съдържание ще замени този абзац.</p>"
        "<p>Вторият абзац съществува, за да се провери преноса на редове, "
        "разстоянието между абзаците и поведението при увеличаване и "
        "намаляване на шрифта от бутоните в лентата.</p>"
        "<p>Трети абзац — за да има какво да се превърти надолу.</p>"
    )

# (заглавие на полето, [заглавия на редовете вътре])
_SAMPLE = [
    ('Канонически правила', [
        'Канонически правила на Православната Църква за миряните в богослужението',
        'Канонически правила относно участието на жените в богослужението',
        'Богослужебен устав за миряни',
    ]),
    ('Устав за поста по Типика', [
        'Въведение',
        'Общи положения на православния устав за трапезата',
        'Редът на трапезата извън дълготрайните пости',
        'Трапезата по време на пост',
        'Велик пост',
        'Пост на светите апостоли',
        'Успенски пост',
        'Рождественски пост',
        'Трапезата през Петдесетницата',
        'Заключение',
    ]),
    ('За помена на починалите', [
        'За помена на починалите',
    ]),
    ('Ред за четене на Евангелието през Великия пост', [
        'Ред за четене на Евангелието през Великия пост',
    ]),
    ('Съкращения в календара', [
        'Съкращения в календара',
    ]),
    ('Знаци на Типикона', [
        'Знаци на Типикона',
    ]),
]


def main():
    out = os.path.normpath(OUT)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)

    db = sqlite3.connect(out)
    db.executescript(SCHEMA)

    article_id = 0
    for gi, (group_title, articles) in enumerate(_SAMPLE, start=1):
        db.execute('INSERT INTO ref_groups (id, title, position) VALUES (?,?,?)',
                   (gi, group_title, gi))
        for ai, title in enumerate(articles, start=1):
            article_id += 1
            db.execute(
                'INSERT INTO ref_articles (id, group_id, title, body, position)'
                ' VALUES (?,?,?,?,?)',
                (article_id, gi, title, _body(title), ai))

    db.commit()
    groups = db.execute('SELECT COUNT(*) FROM ref_groups').fetchone()[0]
    arts = db.execute('SELECT COUNT(*) FROM ref_articles').fetchone()[0]
    db.close()
    print(out)
    print(f'ref_groups={groups} ref_articles={arts}')


if __name__ == '__main__':
    main()
