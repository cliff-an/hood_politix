// lib/widgets/tutorial_coach_overlay.dart
// Nicht-modale Hinweise für den Tutorial-Modus. Liest ausschließlich schon
// vorhandene GameController-Zustände (reactionFlashSeq, players, ...) statt
// eigene Spiellogik zu duplizieren oder GameBoard zu verändern — rein
// additiv als Stack um GameBoard herum. Siehe Plan "Bot-Gegner" §6.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/action_card.dart';
import '../models/card_action_type.dart';
import '../models/firebase_service.dart';
import '../models/game_controller.dart';
import '../screens/lobby_screen.dart';

class TutorialCoachOverlay extends StatefulWidget {
  final String gameId;
  final Widget child;
  const TutorialCoachOverlay({
    super.key,
    required this.gameId,
    required this.child,
  });

  @override
  State<TutorialCoachOverlay> createState() => _TutorialCoachOverlayState();
}

class _TutorialCoachOverlayState extends State<TutorialCoachOverlay> {
  // Jeder Hinweis feuert höchstens einmal pro Session — reicht, der ganze
  // Ablauf läuft ohnehin nur einmal pro Account (siehe hasSeenTutorial).
  final Set<String> _shown = {};
  String? _hintText;
  Timer? _hideTimer;

  StreamSubscription<DatabaseEvent>? _reactionSubscription;
  int _lastHandLength = -1;
  int _lastFlashSeq = -1;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _listenForReactionWindow();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _reactionSubscription?.cancel();
    // Deckt sowohl "fertig gespielt" als auch "übersprungen" ab — ein
    // Abbruch/App-Kill mittendrin lässt das Flag bewusst false, das
    // Tutorial startet dann beim nächsten Login erneut.
    final uid = _myUid;
    if (uid != null) {
      FirebaseService.instance.markTutorialSeen(uid);
    }
    super.dispose();
  }

  /// GameScreen wird nur per pushReplacement erreicht (siehe
  /// LobbyScreen._maybeStartTutorial), der Verlaufsstapel hat also keinen
  /// vorherigen Eintrag — ein einfaches pop() (oder maybePop()) täte
  /// nichts. Gleiches Muster wie der "Spiel verlassen"-Button in
  /// gameboard_widget.dart und "Zur Lobby" in game_over_screen.dart.
  Future<void> _skipTutorial() async {
    final uid = _myUid;
    if (uid == null) return;
    final navigator = Navigator.of(context);
    // ERST den Controller abbauen, DANN leaveGame — sonst kann der noch
    // laufende BotGameDriver (als Anführer) auf genau die Änderung
    // reagieren, die leaveGame auslöst, und mit PERMISSION_DENIED
    // scheitern, weil wir dann schon aus players/ entfernt sind. Siehe
    // gameboard_widget.dart's "Spiel verlassen"-Button.
    if (GameController.hasInstance) {
      GameController.instance.dispose();
    }
    await FirebaseService.instance.leaveGame(widget.gameId, uid);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LobbyScreen(userId: uid)),
      (_) => false,
    );
  }

  void _showOnce(String key, String text) {
    if (_shown.contains(key) || !mounted) return;
    _shown.add(key);
    _hideTimer?.cancel();
    setState(() => _hintText = text);
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _hintText = null);
    });
  }

  /// Eigenes Reaktionsfenster: neuer reactions-Knoten mit handled==false,
  /// bei dem ich das Ziel bin.
  void _listenForReactionWindow() {
    _reactionSubscription = FirebaseDatabase.instance
        .ref('games/${widget.gameId}/reactions')
        .onValue
        .listen((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);
      if (data['handled'] == true) return;
      if (data['targetPlayerId'] != _myUid) return;
      _showOnce(
        'reaction',
        'Jemand hat eine Aktionskarte gespielt — du kannst reagieren oder die Strafe kassieren!',
      );
    });
  }

  void _checkController(GameController ctrl) {
    final me = _myUid;
    if (me == null) return;

    // Karte ziehen — eigene Handlänge gestiegen.
    final mine = ctrl.players.where((p) => p.id == me);
    if (mine.isNotEmpty) {
      final len = mine.first.handCardIds.length;
      if (_lastHandLength != -1 && len > _lastHandLength) {
        _showOnce(
          'draw',
          'Du hast eine Karte gezogen — sie liegt jetzt in deiner Hand.',
        );
      }
      _lastHandLength = len;
    }

    // Aktionskarte gespielt (von irgendwem) — reactionFlashSeq feuert für
    // JEDE Aktionskarte, nicht nur eigene Züge.
    if (ctrl.reactionFlashSeq != _lastFlashSeq) {
      _lastFlashSeq = ctrl.reactionFlashSeq;
      final card = ctrl.lastReactionCard;
      if (card is ActionCard) {
        switch (card.actionType) {
          case ActionType.deal:
            _showOnce(
              'deal',
              '"Deal" wurde gespielt — die Hände zweier Spieler werden komplett getauscht!',
            );
            break;
          case ActionType.snitch:
            _showOnce(
              'snitch',
              '"Snitch" wurde gespielt — eine einzelne Karte wird getauscht oder aufgedeckt.',
            );
            break;
          case ActionType.payback:
            _showOnce('payback', '"Payback" dreht die Spielrichtung um!');
            break;
          default:
            _showOnce(
              'action',
              'Eine Aktionskarte wurde gespielt — schau, was sie bewirkt!',
            );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<GameController>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkController(ctrl);
    });

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: ActionChip(
              backgroundColor: Colors.black54,
              label: const Text(
                'Tutorial überspringen ✕',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: _skipTutorial,
            ),
          ),
        ),
        if (_hintText != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: _HintBanner(
                text: _hintText!,
                onDismiss: () {
                  _hideTimer?.cancel();
                  setState(() => _hintText = null);
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _HintBanner extends StatelessWidget {
  final String text;
  final VoidCallback onDismiss;
  const _HintBanner({required this.text, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(12),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onDismiss,
              child: const Text('Verstanden'),
            ),
          ],
        ),
      ),
    );
  }
}
