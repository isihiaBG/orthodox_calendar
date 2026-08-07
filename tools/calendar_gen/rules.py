"""Малък език за правила на подвижни празници.

Синтаксис:
  анкер     ::= "Пасха" | "Петдесетница" | "ВсичкиСветии"
              | именуван неподвижен празник (църковен, от anchor_feasts речника)
              | гола църковна дата "ММ-ДД"
  член      ::= анкер
              | член "+" N | член "-" N              (денонощия)
              | член ">=" W | член "<=" W              (на-или-след / на-или-преди)
              | член ">"  W | член "<"  W              (строго след / строго преди)
              | член "~"  W                            (най-близкия W)
  правило   ::= член
              | "?[" X "==" W "];[" правило_да "];[" правило_не "]"

  W (ден от седмицата): пон,вт,ср,чет,пет,съб,нед

Пример: "(ВсичкиСветии+1)>=пет" — от неделята на Всички светии, ден напред
(понеделник, начало на Петровия пост), после първия петък на-или-след него.

Гола дата "ММ-ДД" е ВИНАГИ църковна (Юлианска), затова резултатът е един и
същ спрямо календарния цикъл и при двата стила — само гражданското число,
в което пада, се мести (виж civil_from_church).
"""
import datetime
import re

from paschalion import civil_from_church, pascha_civil

WEEKDAY = {'пон': 0, 'вт': 1, 'ср': 2, 'чет': 3, 'пет': 4, 'съб': 5, 'нед': 6}

_TOKEN = re.compile(
    r'\s*(Пасха|Петдесетница|ВсичкиСветии|\d{2}-\d{2}|[А-Яа-я]+'
    r'|>=|<=|~|>|<|\+|-|\d+|\(|\)|\?\[|\]\[|\];\[|\])\s*')


def _resolve_anchor(name: str, year: int, style: bool,
                     anchor_feasts: dict[str, tuple[int, int]]) -> datetime.date:
    if name == 'Пасха':
        return pascha_civil(year)
    if name == 'Петдесетница':
        return pascha_civil(year) + datetime.timedelta(days=49)
    if name == 'ВсичкиСветии':
        return pascha_civil(year) + datetime.timedelta(days=56)
    m = re.fullmatch(r'(\d{2})-(\d{2})', name)
    if m:
        return civil_from_church(year, int(m.group(1)), int(m.group(2)), style)
    if name in anchor_feasts:
        mm, dd = anchor_feasts[name]
        return civil_from_church(year, mm, dd, style)
    raise ValueError(f'непознат анкер: {name!r}')


def _apply_weekday(d: datetime.date, op: str, w: int) -> datetime.date:
    delta = (w - d.weekday()) % 7
    if op == '>=':
        return d + datetime.timedelta(days=delta)
    if op == '<=':
        return d - datetime.timedelta(days=(7 - delta) % 7)
    if op == '>':
        return d + datetime.timedelta(days=delta or 7)
    if op == '<':
        return d - datetime.timedelta(days=((7 - delta) % 7) or 7)
    if op == '~':
        fwd = delta            # дни напред до W
        back = (d.weekday() - w) % 7  # дни назад до W
        return d + datetime.timedelta(days=fwd) if fwd <= back \
            else d - datetime.timedelta(days=back)
    raise ValueError(f'непозната операция: {op!r}')


class _Parser:
    def __init__(self, text, year, style, anchor_feasts):
        self.toks = [t for t in _TOKEN.findall(text) if t.strip() != '' or t == '']
        self.toks = _TOKEN.findall(text)
        self.i = 0
        self.year, self.style, self.anchor_feasts = year, style, anchor_feasts

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else None

    def take(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def parse_rule(self) -> datetime.date:
        if self.peek() == '?[':
            self.take()
            x = self.parse_term()
            assert self.take() == '=='
            w = WEEKDAY[self.take()]
            assert self.take() == '][' or True  # токенизаторът дава "];["
            true_branch = self._collect_until(']')
            self.take()  # "];["
            false_branch = self._collect_until(']')
            self.take()  # "]"
            cond = x.weekday() == w
            branch = true_branch if cond else false_branch
            return _Parser(branch, self.year, self.style, self.anchor_feasts).parse_rule()
        return self.parse_term()

    def _collect_until(self, closing):
        # Помощно за условния клон: прибира суровия текст между скобите.
        depth = 0
        out = []
        while True:
            t = self.peek()
            if t in ('(',):
                depth += 1
            if t == ')':
                depth -= 1
            if t in (closing, '];[') and depth == 0:
                break
            out.append(self.take())
        return ' '.join(out)

    def parse_term(self) -> datetime.date:
        d = self.parse_atom()
        while self.peek() in ('+', '-', '>=', '<=', '>', '<', '~'):
            op = self.take()
            if op in ('+', '-'):
                n = int(self.take())
                d = d + datetime.timedelta(days=n if op == '+' else -n)
            else:
                w = WEEKDAY[self.take()]
                d = _apply_weekday(d, op, w)
        return d

    def parse_atom(self) -> datetime.date:
        if self.peek() == '(':
            self.take()
            d = self.parse_term()
            assert self.take() == ')'
            return d
        name = self.take()
        return _resolve_anchor(name, self.year, self.style, self.anchor_feasts)


def resolve(rule_text: str, year: int, style: bool,
            anchor_feasts: dict[str, tuple[int, int]]) -> datetime.date:
    """style=True -> стар стил, False -> нов стил."""
    return _Parser(rule_text, year, style, anchor_feasts).parse_rule()
