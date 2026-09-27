// db_platform.dart
//
// Коя SQLite да ползва приложението — избира се веднъж, при пускане.
//
// ⚠ УСЛОВЕН ИМПОРТ, а не `if (kIsWeb)` в main.dart: уеб фабриката
// (`sqflite_common_ffi_web`) носи WASM SQLite и shared worker и няма работа
// в Android билда. Така тя изобщо не влиза в него, а на телефона остава
// досегашният `sqflite` с SQLite-а на системата.
export 'db_platform_native.dart'
    if (dart.library.js_interop) 'db_platform_web.dart';
