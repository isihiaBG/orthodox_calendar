// cover_picker.dart
//
// Скелетът на екран с тесте корици: фонът, разположението изправено и
// легнало, плаващата стрелка „назад".
//
// Изнесен от library_screen.dart, когато се появи ВТОРИ такъв екран —
// въвеждащият избор на стил (welcome_screen.dart). Дотогава всичко живееше
// вътре в библиотеката и вторият екран щеше да го препише: две копия на
// един и същ градиент, едно и също легнало разположение и една и съща
// стрелка, които при първата поправка се разминават.
//
// ⚠ Тук НЯМА нищо за книги, нито за стилове на календара. Скелетът получава
// готови корици и два строителя — за панела отдолу (изправено) и за
// краткия надпис (легнало). Кой какво значи решава повикващият.
//
// Самата въртележка (cover_flow.dart) си беше независима отначало и не е
// пипана.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';
import 'cover_flow.dart';

class CoverPickerScaffold extends StatefulWidget {
  /// Заглавието на лентата. Легнало лента няма — виж [_floatingExit].
  final String title;

  final List<ImageProvider> covers;
  final int index;
  final ValueChanged<int> onIndexChanged;

  /// Тап върху централната корица (или върху копчето в панела).
  final ValueChanged<int> onOpen;

  /// Панелът под тестето, ИЗПРАВЕНО. Тук е мястото за име, сведения и
  /// копче — каквото значи изборът на този екран.
  final Widget Function(BuildContext, int index) infoBuilder;

  /// Кратък надпис долу, ЛЕГНАЛО — колкото да се провери избраното, не да
  /// се чете. null маха надписа.
  final String Function(int index)? landscapeLabel;

  /// Ключ към въртележката — нужен на повикващия, за да вземе мястото на
  /// централната корица при отваряне (виж CoverFlowState.centerCoverRect).
  final GlobalKey<CoverFlowState>? flowKey;

  /// Главното меню, ако този екран трябва да го има.
  ///
  /// ⚠ Подава се ОТВЪН, вместо тук да се внася `AppDrawer`. Причината не е
  /// само чистота: `app_drawer.dart` сам внася въвеждащия екран на „Библия",
  /// тъй че обратният внос затваря кръг. По-важното обаче е, че екранът за
  /// избор на КАЛЕНДАР (welcome_screen.dart) стъпва на същия скелет, а той е
  /// стартов и меню там няма къде да води.
  ///
  /// Има ли меню, `AppBar` сам слага хамбургера вместо стрелката „назад" —
  /// затова второ поле за това не е нужно.
  final Widget? drawer;

  /// Ширина към височина на кориците — подава се нататък на [CoverFlow].
  ///
  /// ⚠ Различните комплекти имат различни пропорции: томовете са 479×741, а
  /// трите книги на „Библия" — 523×741. Наложи ли се чуждо съотношение,
  /// рисунката се разтяга и това се вижда веднага.
  final double aspect;

  /// Допълнително съдържание НАД панела — например чекбоксът „не показвай
  /// повече". Изправено стои между тестето и панела; легнало не се показва
  /// (там няма място, а и екранът се отваря наново при следващо пускане).
  final Widget? extra;

  /// Да НЕ пали системната лента при излизане. Ползва се, когато следващият
  /// екран сам стои без нея — виж BookReader.keepImmersiveOnExit.
  final bool keepImmersiveOnExit;

  const CoverPickerScaffold({
    super.key,
    required this.title,
    required this.covers,
    required this.index,
    required this.onIndexChanged,
    required this.onOpen,
    required this.infoBuilder,
    this.landscapeLabel,
    this.flowKey,
    this.drawer,
    this.aspect = kCoverAspect,
    this.extra,
    this.keepImmersiveOnExit = false,
  });

  @override
  State<CoverPickerScaffold> createState() => _CoverPickerScaffoldState();
}

class _CoverPickerScaffoldState extends State<CoverPickerScaffold> {
  bool _immersive = false;

  /// ⚠ Нужен, за да се отвори менюто от ЛЕГНАЛИЯ изглед.
  ///
  /// Там няма лента, тъй че копчето е плаващо и се строи в `body`. Първата
  /// версия ползваше `Scaffold.of(context)` — и не работеше: подаденият
  /// контекст е този на `build`, тоест НАД скелета, който същият `build`
  /// създава. `Scaffold.of` търси НАГОРЕ по дървото и не го намира.
  /// Ключът сочи право към него и не зависи от това откъде се вика.
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setImmersive(true);
  }

  /// Системната лента се скрива за ЦЕЛИЯ екран, не само легнало.
  ///
  /// Легнало причината е хармонията: лентата реже горния ръб на тестето.
  /// Изправено причината е друга и по-важна — онова, което се отваря
  /// оттук, също е без лента (четецът на книги). Различават ли се двата
  /// екрана, смяната на режима пада точно по средата на прехода между
  /// тях: полето отгоре изчезва, целият изглед се пренарежда и страницата
  /// подскача нагоре, докато се проявява.
  void _setImmersive(bool on) {
    if (_immersive == on) return;
    _immersive = on;
    SystemChrome.setEnabledSystemUIMode(
      on ? SystemUiMode.immersiveSticky : SystemUiMode.manual,
      overlays: on ? const [] : SystemUiOverlay.values,
    );
  }

  @override
  void dispose() {
    // ЗАДЪЛЖИТЕЛНО: режимът важи за ЦЯЛОТО приложение, не за екрана. Без
    // това календарът остава без системна лента, ако човек излезе оттук.
    //
    // ⚠ Изключение: [CoverPickerScaffold.keepImmersiveOnExit] — когато
    // това, към което се отива, само стои без лента. Тогава паленето тук
    // би било само едно премигване, защото следващият екран я гаси
    // веднага.
    if (!widget.keepImmersiveOnExit) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: SystemUiOverlay.values);
    }
    super.dispose();
  }

  /// Подът под тестето: отражението трябва да ляга върху нещо, инак виси в
  /// празното. Тъмно горе, малко по-светло долу — както при оригинала.
  Widget _backdrop({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0A0C), Color(0xFF17171B), Color(0xFF0E0E11)],
          stops: [0.0, 0.62, 1.0],
        ),
      ),
      child: child,
    );
  }

  Widget _deck() => CoverFlow(
        key: widget.flowKey,
        covers: widget.covers,
        aspect: widget.aspect,
        initialIndex: widget.index,
        onSelected: widget.onIndexChanged,
        onOpen: widget.onOpen,
      );

  /// Изходът за легналия изглед — плаващо копче горе вляво.
  ///
  /// Легнало лента няма — тя би отнела височина тъкмо там, където всяка е
  /// нужна на кориците, и би разбила тъмнината. Но с нея си отива и
  /// единственият изход от екрана, тъй че копчето остава само.
  ///
  /// ⚠ ЕДНАКВО с изправено: има ли меню, тук стои ХАМБУРГЕР, не стрелка.
  /// Дотук легнало винаги излизаше „назад", а изправено — в менюто; тоест
  /// едно и също копче на едно и също място вършеше две различни неща според
  /// това как човек държи телефона.
  ///
  /// Мястото и размерът са ТОЧНО тези на лентовото копче: гнездо 56×44,
  /// иконка в средата. Така при завъртане то не подскача.
  Widget _floatingExit(BuildContext context) {
    final hasMenu = widget.drawer != null;
    return Positioned(
      left: 0,
      top: 0,
      child: SizedBox(
        width: 56,
        height: 44,
        child: Center(
          child: Material(
            color: Colors.black.withValues(alpha: 0.38),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              // ⚠ През КЛЮЧА, не през `Scaffold.of` — виж [_scaffold].
              onTap: () => hasMenu
                  ? _scaffold.currentState?.openDrawer()
                  : Navigator.of(context).maybePop(),
              child: SizedBox(
                width: 40,
                height: 40,
                child: Icon(hasMenu ? Icons.menu : Icons.arrow_back,
                    size: 22, color: AppColors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _landscape(BuildContext context) {
    final label = widget.landscapeLabel?.call(widget.index);
    return Stack(
      children: [
        Positioned.fill(child: _deck()),
        _floatingExit(context),
        if (label != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: IgnorePointer(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.85),
                  fontSize: 13,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Scaffold(
      key: _scaffold,
      backgroundColor: const Color(0xFF0A0A0C),
      drawer: widget.drawer,
      extendBodyBehindAppBar: landscape,
      appBar: landscape
          ? null
          : AppBar(
              backgroundColor: AppColors.toolbar,
              // Същата височина като в справочните секции и в четеца —
              // лентите на приложението не бива да си играят на различни.
              toolbarHeight: 44,
              title: Text(widget.title),
            ),
      body: _backdrop(
        child: SafeArea(
          child: landscape
              ? _landscape(context)
              : Column(
                  children: [
                    Expanded(child: _deck()),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(child: widget.infoBuilder(context, widget.index)),
                          if (widget.extra != null) widget.extra!,
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
