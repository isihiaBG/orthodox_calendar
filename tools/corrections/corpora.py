#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Достъп до ВСИЧКИ преведени на български текстове в проекта.

Тук е единственото място, което знае къде живее преводът. Другите скриптове
в папката (apply.py) само получават текст и връщат текст.

⚠ Пипат се ИЗВОРИТЕ на конвейерите, а не готовите изделия. Поправка направо
в базата или в .epub-а се губи при следващото сглобяване — правилото важи
за целия проект (виж CLAUDE.md, „Поправки по превода"). Изключение прави
само `lives.db`: тя се строи от `texts.csv`, но пътят дотам минава през
скриптове, които теглят наново от azbyka.ru, тъй че по установената в
13_bible_links_bg.py практика се кърпи И самата база — иначе поправката не
се вижда, докато не се прегенерира целият конвейер.

Съответствието извор → изделие:

    texts.csv                       → assets/db/lives.db          (и двете)
    Translate_lives/work/…/translated → assets/books/*.epub       (иска 04_build_epub.py)
    reference_gen/…/work/translated → assets/db/reference.db      (иска 03_build_db.py)
    translate_Teofan/work/translated → assets/db/teofan.db        (иска 03_build_db.py)
    translate_Optina/work/translated → assets/db/optina.db        (иска 04_build_db.py)
"""

import csv
import glob
import io
import json
import os
import sqlite3
import sys
import tarfile
import time

csv.field_size_limit(sys.maxsize)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _път(*части):
    return os.path.join(ROOT, *части)


class Корпус(object):
    """Общото поведение: обхожда своите текстове и по желание записва."""

    име = ''

    def обходи(self, преобрази, пиши=False):
        """`преобрази(текст) -> нов текст`.

        Връща списък от (адрес, стар, нов) за променените места.
        """
        raise NotImplementedError


# --------------------------------------------------------------------------
# CSV с разделител „|" (texts.csv на житията от базата)
# --------------------------------------------------------------------------

class КорпусCSV(Корпус):
    def __init__(self, име, път, колони, ключ, разделител='|'):
        self.име = име
        self.път = път
        self.колони = колони
        self.ключ = ключ
        self.разделител = разделител

    def обходи(self, преобрази, пиши=False):
        if not os.path.exists(self.път):
            return []
        with io.open(self.път, encoding='utf-8', newline='') as f:
            r = csv.DictReader(f, delimiter=self.разделител)
            полета = r.fieldnames
            редове = list(r)
        промени = []
        for ред in редове:
            for кол in self.колони:
                стар = ред.get(кол) or ''
                нов = преобрази(стар)
                if нов != стар:
                    ред[кол] = нов
                    промени.append(('%s/%s' % (ред.get(self.ключ, '?'), кол),
                                    стар, нов))
        if пиши and промени:
            _резервно(self.път)
            with io.open(self.път, 'w', encoding='utf-8', newline='') as f:
                w = csv.DictWriter(f, fieldnames=полета,
                                   delimiter=self.разделител)
                w.writeheader()
                w.writerows(редове)
        return промени


# --------------------------------------------------------------------------
# SQLite
# --------------------------------------------------------------------------

class КорпусSQLite(Корпус):
    def __init__(self, име, път, таблица, колони, ключ):
        self.име = име
        self.път = път
        self.таблица = таблица
        self.колони = колони
        self.ключ = ключ

    def обходи(self, преобрази, пиши=False):
        if not os.path.exists(self.път):
            return []
        con = sqlite3.connect(self.път)
        con.text_factory = str
        cur = con.cursor()
        cur.execute('SELECT %s, %s FROM %s'
                    % (self.ключ, ', '.join(self.колони), self.таблица))
        редове = cur.fetchall()
        промени, за_запис = [], []
        for ред in редове:
            ид, стойности = ред[0], list(ред[1:])
            нови = []
            смени = False
            for кол, стар in zip(self.колони, стойности):
                стар = стар or ''
                нов = преобрази(стар)
                нови.append(нов)
                if нов != стар:
                    смени = True
                    промени.append(('%s/%s' % (ид, кол), стар, нов))
            if смени:
                за_запис.append((нови, ид))
        if пиши and за_запис:
            con.close()
            _резервно(self.път)
            con = sqlite3.connect(self.път)
            cur = con.cursor()
            сет = ', '.join('%s=?' % к for к in self.колони)
            cur.executemany('UPDATE %s SET %s WHERE %s=?'
                            % (self.таблица, сет, self.ключ),
                            [(tuple(н) + (и,)) for н, и in за_запис])
            con.commit()
        con.close()
        return промени


# --------------------------------------------------------------------------
# JSON — преводните файлове на четирите конвейера
# --------------------------------------------------------------------------

class КорпусJSON(Корпус):
    """`пътища` е списък от кортежи-пътеки в дървото, където '*' значи
    „всички елементи на списъка"."""

    def __init__(self, име, шаблон, пътища):
        self.име = име
        self.шаблон = шаблон
        self.пътища = пътища

    def обходи(self, преобрази, пиши=False):
        промени = []
        for път in sorted(glob.glob(_път(*self.шаблон))):
            with io.open(път, encoding='utf-8') as f:
                данни = json.load(f)
            местни = []
            for пътека in self.пътища:
                _обходи_пътека(данни, пътека, преобрази, местни)
            if местни:
                кратък = os.path.relpath(път, ROOT)
                промени += [('%s%s' % (кратък, а), с, н) for а, с, н in местни]
                if пиши:
                    _резервно(път)
                    # indent=1 и ensure_ascii=False — точно както пишат
                    # четирите конвейера. Друго форматиране би „променило"
                    # всеки файл, без да е сменена нито дума.
                    with io.open(път, 'w', encoding='utf-8') as f:
                        json.dump(данни, f, ensure_ascii=False, indent=1)
        return промени


def _обходи_пътека(възел, пътека, преобрази, промени, адрес=''):
    if not пътека:
        return
    ключ, остатък = пътека[0], пътека[1:]
    if ключ == '*':
        if not isinstance(възел, list):
            return
        for i, дете in enumerate(възел):
            if остатък:
                _обходи_пътека(дете, остатък, преобрази, промени,
                               '%s[%d]' % (адрес, i))
            elif isinstance(дете, str):
                нов = преобрази(дете)
                if нов != дете:
                    възел[i] = нов
                    промени.append(('%s[%d]' % (адрес, i), дете, нов))
        return
    if not isinstance(възел, dict) or ключ not in възел:
        return
    ново_адрес = '%s.%s' % (адрес, ключ)
    if остатък:
        _обходи_пътека(възел[ключ], остатък, преобрази, промени, ново_адрес)
    elif isinstance(възел[ключ], str):
        нов = преобрази(възел[ключ])
        if нов != възел[ключ]:
            промени.append((ново_адрес, възел[ключ], нов))
            възел[ключ] = нов


class Резерв(object):
    """Едно архивче на пускане, с копие на всеки файл ПРЕДИ да се пипне.

    ⚠ Нито един от преводните извори не е в git (`texts.csv` и четирите
    папки `work/translated/` са изключени заради тежест и чужди права), тъй
    че това е ЕДИНСТВЕНОТО връщане назад. Проверено на 17.08.2026 —
    `git ls-files` върна нула за всичките пет.

    Архивът стои в tools/corrections/backups/, а НЕ до самия файл. Практиката
    „копие до файла" остави седем `lives.db.bak-…` вътре в assets/db/ и те
    заминаха в релийзния APK — 15,8 MB от 74-те (виж CLAUDE.md, „Практически
    бележки"). Тук папката е една, вижда се и се чисти наведнъж.

    Връщане назад:  tar xzf tools/corrections/backups/<име>.tar.gz -C .
    """

    def __init__(self):
        self.път = None
        self._архив = None
        self._вече = set()

    def прибери(self, файл):
        # ⚠ ЕДИН ФАЙЛ — ЕДИН ЧЛЕН. `lives.db` се пипа от два корпуса
        # (таблиците `texts` и `hymns`), тъй че без тази проверка влизаше
        # двойно: първият член пристинен, вторият — вече след записа в
        # `texts`. При разархивиране вторият презаписваше първия и връщането
        # назад тихо не се получаваше. Загубени ~40 минути на 17.08.2026:
        # изглеждаше, че базата е върната, а тя носеше половината промени.
        if файл in self._вече:
            return
        self._вече.add(файл)
        if self._архив is None:
            папка = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                 'backups')
            if not os.path.isdir(папка):
                os.makedirs(папка)
            self.път = os.path.join(
                папка, '%s.tar.gz' % time.strftime('%Y%m%d_%H%M%S'))
            self._архив = tarfile.open(self.път, 'w:gz')
        self._архив.add(файл, arcname=os.path.relpath(файл, ROOT))

    def затвори(self):
        if self._архив is not None:
            self._архив.close()
            self._архив = None


# Общият резерв за текущото пускане. apply.py го затваря накрая.
РЕЗЕРВ = Резерв()


def _резервно(път):
    РЕЗЕРВ.прибери(път)


# --------------------------------------------------------------------------
# Списъкът
# --------------------------------------------------------------------------

_BG_КОЛОНИ = ['life', 'tropar_trans', 'tropar2_trans',
              'kondak_trans', 'kondak2_trans']

КОРПУСИ = [
    КорпусCSV('lives-csv', _път('tools', 'azbyka.ru', 'db', 'texts.csv'),
              _BG_КОЛОНИ, 'slug'),
    КорпусSQLite('lives-db', _път('assets', 'db', 'lives.db'),
                 'texts', _BG_КОЛОНИ, 'slug'),
    КорпусSQLite('hymns-db', _път('assets', 'db', 'lives.db'),
                 'hymns', ['bg', 'note'], 'rowid'),
    КорпусJSON('lives-epub',
               ('tools', 'Translate_lives', 'work', '*', 'translated', '*.json'),
               [('units', '*', 'translated')]),
    КорпусJSON('reference',
               ('tools', 'reference_gen', 'Translate', 'work', 'translated',
                '*.json'),
               [('title_bg',), ('units_bg', '*')]),
    КорпусJSON('teofan',
               ('tools', 'translate_Teofan', 'work', 'translated', '*.json'),
               [('units_bg', '*')]),
    КорпусJSON('optina',
               ('tools', 'translate_Optina', 'work', 'translated', '*.json'),
               [('body_bg',)]),
]


def по_име(имена):
    if not имена:
        return КОРПУСИ
    return [к for к in КОРПУСИ if к.име in имена]
