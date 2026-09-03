import 'dart:async';
import 'package:flutter/material.dart';

/// Globaler Navigator-Key (in main.dart an MaterialApp übergeben)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Verwaltet modale Spiel-Dialoge (z. B. Reaktionen, Snitch, Reveal etc.)
/// und stellt sicher, dass niemals mehrere Dialoge gleichzeitig geöffnet sind.
class DialogManager {
  /// Warteschlange offener Dialoge (hilft beim Schließen).
  static final List<Completer<void>> _dialogQueue = [];

  /// Aktuelle Game-Session-ID (optional für Reaktionskontext)
  static String? currentGameId;

  /// Globaler RootContext, gesetzt über `DialogManager.setRootContext(context)`
  static BuildContext? _rootContext;

  /// RootContext initialisieren (z. B. in MaterialApp.builder)
  static void setRootContext(BuildContext context) {
    _rootContext = context;
    debugPrint("✅ DialogManager: RootContext gesetzt.");
  }

  /// Liefert den aktuell gültigen Kontext (root oder navigator)
  static BuildContext? get _effectiveContext {
    if (_rootContext != null) return _rootContext;
    if (navigatorKey.currentContext != null) return navigatorKey.currentContext;
    return null;
  }

  /// Öffnet einen App-weiten Dialog nur, wenn kein anderer aktiv ist.
  static Future<T?> showAppDialog<T>(
  Widget dialog, {
  required String gameId,
  bool barrierDismissible = false,
}) async {
  currentGameId = gameId;

  // Nimm **zuerst** den Kontext direkt vom globalen Navigator,
  // der garantiert in einem Navigator hängt:
  final navCtx = navigatorKey.currentState?.overlay?.context;
  final context = navCtx ?? _effectiveContext;

  if (context == null) {
    debugPrint("❌ DialogManager: Kein gültiger BuildContext gefunden!");
    return null;
  }

  if (_dialogQueue.isNotEmpty) {
    await _dialogQueue.last.future;
  }

  final completer = Completer<void>();
  _dialogQueue.add(completer);

  try {
    return await showDialog<T>(
      context: context, // ignore: use_build_context_synchronously
      barrierDismissible: barrierDismissible,
      useRootNavigator: true, // <- WICHTIG
      builder: (_) => dialog,
    );
  } finally {
    if (_dialogQueue.contains(completer)) _dialogQueue.remove(completer);
    completer.complete();
  }
}



  /// Schließt den aktuell sichtbaren Dialog, falls vorhanden.
  static void closeDialog() {
    final navigator = navigatorKey.currentState;
    if (navigator?.canPop() ?? false) {
      navigator!.pop();
      debugPrint("🧩 DialogManager: Aktiver Dialog geschlossen.");
    } else {
      debugPrint("⚠️ DialogManager: Kein Dialog zum Schließen gefunden.");
    }
  }

  /// Prüft, ob derzeit ein Dialog geöffnet ist.
  static bool isDialogOpen() => _dialogQueue.isNotEmpty;
}
