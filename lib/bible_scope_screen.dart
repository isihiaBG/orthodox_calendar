// bible_scope_screen.dart
//
// Изборът „в кои книги да се търси" — отделен екран с отметки.
//
// ⚠ ОТДЕЛЕН ЕКРАН, а не още една секция в панела с настройките. Панелът е
// тесен (Drawer заема част от ширината), а тук нивата са ТРИ — завет, дял,
// книга — и всяко иска отстъп навътре. Сместени в панела, книгите остават с
// шейсет точки за име и се пренасят на два реда; а най-важното е, че този
// избор не е „настройка", която се щраква мимоходом, а работа: човек сяда и
// отмята десетина места. За такова нещо е нужен цял екран.
//
// ⚠ УСТРОЕН Е КАТО СЪДЪРЖАНИЕТО, нарочно. Същите дялове, същият ред, същите
// имена — човек вече знае къде да търси „Съборни послания". Единствената
// добавка са отметките отляво и разгъването.

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'bible_book_groups.dart';
import 'bible_db.dart';
import 'bible_scope_preset_dialogs.dart';
import 'bible_scope_presets.dart';
import 'bible_search_settings.dart';
import 'kathisma.dart';
import 'reader_font_size.dart';

/// Отваря екрана и връща новия избор, или `null` при отказ.
Future<BibleScopePick?> pickBibleScope(
    BuildContext context, BibleScopePick current) {
  return Navigator.of(context).push<BibleScopePick>(
    MaterialPageRoute(builder: (_) => _BibleScopeScreen(initial: current)),
  );
}

class _BibleScopeScreen extends StatefulWidget {
  final BibleScopePick initial;
  const _BibleScopeScreen({required this.initial});

  @override
  State<_BibleScopeScreen> createState() => _BibleScopeScreenState();
}

/// Кой от двата завета — Псалтирът си има собствен ред и не минава оттук
/// (той се дели на катизми, не на дялове с книги).
enum _Part { nt, ot }

class _BibleScopeScreenState extends State<_BibleScopeScreen> {
  List<BibleBook> _books = const [];
  bool _loading = true;

  late final Set<String> _picked = {...widget.initial.books};
  late final Set<int> _kathismata = {...widget.initial.kathismata};

  /// Кое е разгънато — по ключ („nt", „nt/Евангелия", „psalter").
  final Set<String> _open = {};

  /// Има ли изобщо записани набори — от това зависи живо ли е „зареди".
  ///
  /// ⚠ Пази се в състоянието, а не се пита при всяко рисуване: проверката
  /// чете от диска, а лентата се преизгражда при всяка отметка.
  bool _hasPresets = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshPresets();
  }

  Future<void> _refreshPresets() async {
    final list = await BibleScopePresets.all();
    if (!mounted) return;
    setState(() => _hasPresets = list.isNotEmpty);
  }

  Future<void> _load() async {
    final books = await BibleDb.books();
    if (!mounted) return;
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  // ── Кои книги влизат в кой дял ─────────────────────────────────────────

  List<BibleBookGroup> _groupsOf(_Part part) =>
      part == _Part.nt ? kNtGroups : kOtGroups;

  /// Кодовете на книгите в дял — само наличните в базата, по реда на дяла.
  List<String> _codesOf(_Part part) {
    final have = {for (final b in _books) b.code};
    return [
      for (final g in _groupsOf(part))
        for (final c in g.codes)
          if (have.contains(c)) c
    ];
  }

  BibleBook? _book(String code) {
    for (final b in _books) {
      if (b.code == code) return b;
    }
    return null;
  }

  // ── Състояние на отметките ─────────────────────────────────────────────

  /// Тристепенно: всички / нито едно / част.
  ///
  /// ⚠ `null` значи „част" — така го разбира и `Checkbox(tristate: true)`.
  /// Без междинното състояние група с две отметнати от седем книги изглежда
  /// точно като празна и човек я отмята пак, с което трие своя избор.
  bool? _stateOf(Iterable<String> codes) {
    var on = 0, total = 0;
    for (final c in codes) {
      total++;
      if (_picked.contains(c)) on++;
    }
    if (total == 0 || on == 0) return false;
    return on == total ? true : null;
  }

  void _setAll(Iterable<String> codes, bool on) {
    setState(() {
      for (final c in codes) {
        if (on) {
          _picked.add(c);
        } else {
          _picked.remove(c);
        }
      }
    });
  }

  /// Псалтирът се брои отделно: той е една книга, но се отмята по катизми.
  bool? get _psalterState {
    if (_picked.contains('Ps')) return true;
    if (_kathismata.isEmpty) return false;
    return _kathismata.length == kKathismata.length ? true : null;
  }

  void _setPsalter(bool on) {
    setState(() {
      if (on) {
        // ⚠ Отметнат ЦЯЛ, Псалтирът влиза като книга, а катизмите се чистят.
        // Инак двата вида избор започват да описват едно и също място и
        // първата им разлика става тиха грешка (виж [BibleScopePick]).
        _picked.add('Ps');
        _kathismata.clear();
      } else {
        _picked.remove('Ps');
        _kathismata.clear();
      }
    });
  }

  void _toggleKathisma(int n, bool on) {
    setState(() {
      // Тръгне ли човек по катизми, целият Псалтир отстъпва на тях.
      _picked.remove('Ps');
      if (on) {
        _kathismata.add(n);
      } else {
        _kathismata.remove(n);
      }
      // Отметнати всички до една — това е „целият Псалтир", и се записва
      // така: по-късо е и оцелява, ако утре катизмите се преброят другояче.
      if (_kathismata.length == kKathismata.length) {
        _kathismata.clear();
        _picked.add('Ps');
      }
    });
  }

  int get _totalPicked {
    var n = _picked.length;
    if (_kathismata.isNotEmpty) n += 1; // Псалтирът, макар и на части
    return n;
  }

  // ── Рисуване ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.toolbar,
        foregroundColor: Colors.white,
        // ⚠ Късо, защото вдясно стои „Изчисти": „Къде да се търси" се режеше
        // до „Къде да се тър…". Екранът и без това се отваря от ред, който
        // вече е казал за какво става дума.
        // ⚠ Разстоянията са СТЕГНАТИ, защото вдясно стоят три копчета:
        // по подразбиране `AppBar` дава 16 отстъп след стрелката и по 48 на
        // всяко копче, с което „Избери книги" оставаше без място и се режеше
        // до „Избери кн…". Заглавието НЕ се смалява — то трябва да изглежда
        // като заглавията на другите екрани; свива се обзавеждането около него.
        titleSpacing: 0,
        // ⚠ 20, а не подразбиращите се 22 — същият размер като заглавието на
        // панела „Разширено търсене", откъдето се влиза тук. Двете стоят едно
        // след друго и различните им ръстове личаха повече от печалбата.
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500),
        title: const Text('Избери книги'),
        // ⚠ ТРИ ИКОНКИ, а не надписи. „Изчисти" беше дума, защото беше сам; с
        // три действия думите не се събират, а и трите са от познатия набор
        // (кошче, дискета, папка) — там, където иконата е недвусмислена, тя
        // печели място, без да губи смисъл.
        //
        // ⚠ РЕДЪТ ИМ СЛЕДВА РАБОТАТА, не риска: зареждаш готово (вляво),
        // записваш направеното (в средата), изчистваш, за да почнеш наново
        // (вдясно) — отляво надясно, както се чете. Първият опит ги нареди
        // обратно, за да е „разрушителното" далеч от палеца, но кошчето тук
        // не руши нищо: то маха ОТМЕТКИ, не записани селекции, и връщането е
        // едно отмятане разстояние.
        actions: [
          _barAction(
            icon: Icons.folder_open_outlined,
            tooltip: 'Зареди записана селекция',
            // ⚠ Мъртво, докато няма НИТО ЕДНА записана — тогава диалогът би
            // се отворил само за да каже, че е празен.
            enabled: _hasPresets,
            onTap: _loadPreset,
          ),
          _barAction(
            icon: Icons.save_outlined,
            tooltip: 'Запиши селекцията',
            // ⚠ Празна селекция НЕ се записва: „нула избрани книги" под име е
            // ред, който после ще обърка човека, а не ще му помогне.
            enabled: !_isEmptyPick,
            onTap: _savePreset,
          ),
          _barAction(
            icon: Icons.delete_outline,
            tooltip: 'Изчисти избраното',
            // ⚠ Мъртво, когато няма какво да се чисти. Инак копчето кани към
            // действие, което няма да се случи, а разрушителна иконка, която
            // мълчи при натиск, изглежда като счупена.
            enabled: !_isEmptyPick,
            onTap: () => setState(() {
              _picked.clear();
              _kathismata.clear();
            }),
          ),
          const SizedBox(width: 4),
        ],
      ),
      // ⚠ ПОТВЪРЖДЕНИЕТО Е ДОЛУ И ПОСТОЯННО, не в лентата. Отмятането е дълга
      // работа със скролване; копче горе би излязло от полезрението точно
      // когато човек свърши. Освен това броят до него казва какво ще излезе —
      // единственият начин да се види сборът, без да се брои на ръка.
      bottomNavigationBar: _bottomBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 16, bottom: 12),
              children: [
                _partTile(_Part.nt, 'Нов завет'),
                _partTile(_Part.ot, 'Стар завет'),
                _psalterTile(),
              ],
            ),
    );
  }

  bool get _isEmptyPick => _picked.isEmpty && _kathismata.isEmpty;

  BibleScopePick get _current =>
      BibleScopePick(books: {..._picked}, kathismata: {..._kathismata});

  /// Едно копче в лентата.
  ///
  /// ⚠ Посивяването е с прозрачност, а не с друг цвят: така мъртвото копче се
  /// чете като „същото, но не сега", а не като второ, различно нещо.
  Widget _barAction({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 22),
        color: Colors.white,
        disabledColor: Colors.white.withValues(alpha: 0.28),
        // ⚠ Разстоянието между копчетата се дава от PADDING-а, не от `minWidth`.
        // `constraints` стига до `ButtonStyle` като minimumSize, тоест като ПОД —
        // а той не застъпва, докато е под тапващия минимум от 46. Padding-ът пък се
        // добавя направо към иконката и се вижда веднага.
        constraints: const BoxConstraints(minWidth: 46, minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        onPressed: enabled ? onTap : null,
      ),
    );
  }

  Future<void> _savePreset() async {
    final list = await BibleScopePresets.all();
    if (!mounted) return;
    final name = await askPresetName(
      context,
      existing: list,
      initial: BibleScopePresets.suggestName(list),
      count: _totalPicked,
    );
    if (name == null || !mounted) return;

    await BibleScopePresets.save(BibleScopePreset(
      name: name,
      saved: DateTime.now(),
      pick: _current,
    ));
    await _refreshPresets();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Селекцията „$name" е записана.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadPreset() async {
    final chosen = await pickPreset(context);
    // ⚠ Списъкът се проверява НАНОВО и след отказ: в диалога може да е трита
    // селекция, тъй че „зареди" трябва да посивее, ако е останал празен.
    await _refreshPresets();
    if (chosen == null || !mounted) return;
    setState(() {
      _picked
        ..clear()
        ..addAll(chosen.pick.books);
      _kathismata
        ..clear()
        ..addAll(chosen.pick.kathismata);
      // ⚠ Разгънатото се СВИВА при зареждане. Иначе отворените отпреди дялове
      // показват отметки, които вече не са техните, и екранът изглежда, че се
      // е разбъркал сам.
      _open.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Заредена е „${chosen.name}".'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _bottomBar() {
    final n = _totalPicked;
    final empty = n == 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                empty
                    ? 'Нищо не е избрано'
                    : 'Избрани: $n ${n == 1 ? "книга" : "книги"}',
                style: TextStyle(
                    color: empty ? AppColors.textMuted : AppColors.textPrimary,
                    fontSize: 14),
              ),
            ),
            FilledButton(
              // ⚠ Празен избор НЕ се приема: „търси в нищо" няма как да
              // върне резултат, а човек би останал с чувството, че търсенето
              // е счупено. По-добре копчето да мълчи, докато няма какво.
              onPressed: empty
                  ? null
                  : () => Navigator.of(context).pop(BibleScopePick(
                      books: {..._picked}, kathismata: {..._kathismata})),
              child: const Text('Готово'),
            ),
          ],
        ),
      ),
    );
  }

  /// „Нов завет" / „Стар завет" — отметка, име и стрелка за разгъване.
  Widget _partTile(_Part part, String title) {
    final codes = _codesOf(part);
    final key = part.name;
    final open = _open.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          level: 0,
          state: _stateOf(codes),
          title: title,
          trailing: '${codes.length}',
          open: open,
          onToggle: (v) => _setAll(codes, v),
          onExpand: () => setState(
              () => open ? _open.remove(key) : _open.add(key)),
        ),
        if (open)
          for (final g in _groupsOf(part))
            _groupTile(part, g),
        const Divider(height: 1, color: AppColors.sectionDivider),
      ],
    );
  }

  Widget _groupTile(_Part part, BibleBookGroup g) {
    final have = {for (final b in _books) b.code};
    final codes = [for (final c in g.codes) if (have.contains(c)) c];
    if (codes.isEmpty) return const SizedBox.shrink();

    // ⚠ Дял без име („Деяния") НЕ получава свой ред с отметка — той е една
    // книга и втора отметка над нея не значи нищо ново. Книгата обаче застава
    // на нивото на ДЯЛОВЕТЕ, не на книгите.
    //
    // ⚠ Първият опит я слагаше с отстъпа на книгите и това лъжеше: тя стои
    // веднага под свитата група „Евангелия", тъй че по-големият отстъп я
    // прави да изглежда като нейно съдържание — единствената книга, която уж
    // сме разгънали. На нивото на дяловете тя е това, което е: самостоятелен
    // дял, който случайно има една книга.
    if (g.title.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final c in codes) _bookTile(c, level: 1)],
      );
    }

    final key = '${part.name}/${g.title}';
    final open = _open.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          level: 1,
          state: _stateOf(codes),
          title: g.title,
          trailing: '${codes.length}',
          open: open,
          onToggle: (v) => _setAll(codes, v),
          onExpand: () => setState(
              () => open ? _open.remove(key) : _open.add(key)),
        ),
        if (open)
          for (final c in codes) _bookTile(c),
      ],
    );
  }

  Widget _bookTile(String code, {int level = 2}) {
    final b = _book(code);
    return _row(
      level: level,
      state: _picked.contains(code),
      title: b?.short ?? code,
      trailing: b == null ? '' : '${b.chapters}',
      onToggle: (v) => _setAll([code], v),
    );
  }

  Widget _psalterTile() {
    final open = _open.contains('psalter');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row(
          level: 0,
          state: _psalterState,
          title: 'Псалтир',
          trailing: '${kKathismata.length} катизми',
          open: open,
          onToggle: _setPsalter,
          onExpand: () => setState(
              () => open ? _open.remove('psalter') : _open.add('psalter')),
        ),
        if (open)
          for (final k in kKathismata)
            _row(
              level: 1,
              state: _picked.contains('Ps') || _kathismata.contains(k.number),
              title: 'Катизма ${k.number}',
              trailing: k.range,
              onToggle: (v) => _toggleKathisma(k.number, v),
            ),
      ],
    );
  }

  /// Един ред: отметка, име, брой и (ако има какво) стрелка за разгъване.
  ///
  /// ⚠ ОТМЕТКАТА И РАЗГЪВАНЕТО СА ДВЕ РАЗЛИЧНИ ЦЕЛИ. Тапът върху името
  /// разгъва, а не отмята — иначе човек, който иска да види какво има вътре,
  /// избира цялата група по погрешка и го разбира чак долу, по броя.
  /// Отмята се само върху самата кутийка (и малко около нея).
  Widget _row({
    required int level,
    required bool? state,
    required String title,
    required String trailing,
    required void Function(bool) onToggle,
    bool open = false,
    VoidCallback? onExpand,
  }) {
    final size = BibleTocFontSize.value;
    // Стъпката навътре е една и съща на всяко ниво — тя единствена показва
    // йерархията, защото линии между редовете няма.
    final indent = 4.0 + level * 22.0;
    return InkWell(
      onTap: onExpand ?? () => onToggle(!(state ?? false)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(indent, 2, 12, 2),
        child: Row(
          children: [
            Checkbox(
              value: state,
              tristate: true,
              onChanged: (_) => onToggle(!(state ?? false)),
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: AppColors.textMuted, width: 1.5),
            ),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: level == 0 ? size + 1 : size,
                  height: 1.15,
                  color: AppColors.textPrimary,
                  fontWeight:
                      level == 0 ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (trailing.isNotEmpty)
              Text(trailing,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 13)),
            if (onExpand != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 22,
                  color: AppColors.textMuted,
                ),
              )
            else
              const SizedBox(width: 28),
          ],
        ),
      ),
    );
  }
}
