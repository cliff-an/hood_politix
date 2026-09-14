// lib/models/bot_game_driver.dart
// Treibt Bot-Spieler an: läuft auf JEDEM verbundenen menschlichen Client,
// aber nur der per Anführer-Wahl bestimmte Client handelt tatsächlich.
// Kein eigener Firebase-Auth für Bots nötig — jeder Bot-Zug ist ein
// Schreibzugriff des Anführers, ausgeführt über die bestehenden
// FirebaseService-Methoden (Wiederverwendung statt Duplizierung der
// Spiellogik). Siehe Plan "Bot-Gegner" §3.

import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../widgets/dialog_manager.dart';
import 'action_card.dart';
import 'bot_engine.dart';
import 'card_action_type.dart';
import 'firebase_service.dart';
import 'game_card.dart';
import 'game_controller.dart';

class BotGameDriver {
  BotGameDriver(this.gameId, this.controller, this.firebaseService);

  final String gameId;
  final GameController controller;
  final FirebaseService firebaseService;

  final Random _rng = Random();

  bool _disposed = false;
  bool _turnInFlight = false;
  bool _reactionInFlight = false;
  bool _snitchInFlight = false;

  StreamSubscription<DatabaseEvent>? _reactionSubscription;
  StreamSubscription<DatabaseEvent>? _snitchActionSubscription;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  // -------- Lifecycle --------
  void start() {
    controller.addListener(_onControllerChanged);
    _listenForBotReactions();
    _listenForBotSnitchAction();
    // Falls beim Einhängen bereits ein Bot dran ist (z. B. nach Anführer-
    // Wechsel durch Verbindungsabbruch des vorherigen Anführers).
    _onControllerChanged();
  }

  void dispose() {
    _disposed = true;
    controller.removeListener(_onControllerChanged);
    _reactionSubscription?.cancel();
    _snitchActionSubscription?.cancel();
  }

  // -------- Anführer-Wahl --------
  // Jeder Client berechnet unabhängig dasselbe Ergebnis aus den
  // vorhandenen Spielern — kein zusätzlicher Koordinations-State nötig.
  // Bekannte Grenze: ohne Presence/Heartbeat bleibt ein getrennter
  // Anführer rechnerisch Anführer, bis er wieder online ist — identisches
  // Risiko wie beim bestehenden 20s-Zugtimer (nur der aktive Spieler
  // selbst startet ihn).
  bool _isLeader() {
    final me = _myUid;
    if (me == null) return false;
    final humanIds = controller.players
        .where((p) => !p.isBot)
        .map((p) => p.id)
        .toList()
      ..sort();
    return humanIds.isNotEmpty && humanIds.first == me;
  }

  bool _isBotId(String? id) => id != null && id.startsWith('bot_');

  // -------- Zug-Ausführung --------
  void _onControllerChanged() {
    if (_disposed || _turnInFlight) return;
    final currentId = controller.currentPlayerId;
    if (!_isBotId(currentId) || !_isLeader()) return;

    _turnInFlight = true;
    _runBotTurn(currentId!, controller.turn).whenComplete(() {
      _turnInFlight = false;
      // Der Firebase-Listener für den NÄCHSTEN Zugwechsel kann feuern,
      // während dieser Zug hier gerade noch "in flight" war (derselbe
      // playCard-Aufruf, der den Zug beendet, löst über advanceToNextPlayer
      // exakt diese Benachrichtigung aus) — dann würde sie stillschweigend
      // verworfen und nichts würde je wieder nachschauen. Nach dem
      // Zurücksetzen hier deshalb immer einmal neu prüfen, statt auf ein
      // externes Ereignis zu warten, das nie mehr kommt.
      if (!_disposed) _onControllerChanged();
    });
  }

  Future<void> _runBotTurn(String botId, int turn) async {
    try {
      await Future.delayed(BotEngine.thinkDelay(_rng));
      if (_disposed) return;
      // Nach der Bedenkzeit erneut prüfen — Zustand kann sich geändert haben.
      if (controller.currentPlayerId != botId || !_isLeader()) return;
      if (!await _claimTurn(turn)) return; // ein anderer Client übernimmt

      if (!controller.hasFirstTurnStarted) {
        await FirebaseDatabase.instance
            .ref('games/$gameId/gameState/hasFirstTurnStarted')
            .set(true);
      }

      final hand = await firebaseService.getPlayerCards(gameId, botId);
      final chosen =
          BotEngine.chooseCardToPlay(hand, controller.topCardOfDiscardPile);

      if (chosen == null) {
        // Keine legale Karte -> ziehen. drawCardForCurrentPlayer beendet den
        // Zug NICHT selbst (siehe animated_deck.dart), also hier wie dort
        // unbedingt advanceToNextPlayer hinterher aufrufen.
        await controller.drawCard(botId);
        await firebaseService.advanceToNextPlayer(gameId);
        return;
      }

      // Mic-Check/Drop MUSS vor dem Ausspielen gesetzt sein — sonst bestraft
      // handleMicChecksAndDrop (innerhalb von playCard) den Bot fälschlich.
      final mic = BotEngine.decideMicAction(hand.length);
      if (mic == BotMicAction.check) {
        await firebaseService.markMicCheck(gameId, botId);
      } else if (mic == BotMicAction.drop) {
        await firebaseService.markMicDrop(gameId, botId);
      }

      final ctx = navigatorKey.currentState?.overlay?.context;
      if (ctx == null) return;

      if (chosen is ActionCard &&
          (chosen.actionType == ActionType.deal ||
              chosen.actionType == ActionType.snitch)) {
        await firebaseService.playCard(
          // ignore: use_build_context_synchronously
          ctx,
          gameId,
          botId,
          chosen,
          resolveTarget: () async => BotEngine.chooseTarget(
            botId,
            controller.players.map((p) => p.id).toList(),
            _rng,
          ),
          resolveSnitchChoice: _executeSnitchChoice,
        );
      } else {
        // Alle anderen Kartentypen öffnen in playCard nie einen Dialog auf
        // context — sichere Wiederverwendung ohne Duplizierung der Logik.
        // ignore: use_build_context_synchronously
        await firebaseService.playCard(ctx, gameId, botId, chosen);
      }
    } catch (e, st) {
      debugPrint('BotGameDriver: Fehler beim Bot-Zug ($botId): $e\n$st');
    }
  }

  /// Renn-Schutz für Zug-Ausführung: nur der Client, dessen Transaktion für
  /// diese Zug-Nummer zuerst committet, führt den Zug wirklich aus. Läuft
  /// NACH der Bedenkzeit (nicht davor) — stirbt der Anführer währenddessen,
  /// blockiert nichts, der nächste Client claimt beim nächsten Auslöser
  /// einfach selbst für dieselbe (noch offene) Zug-Nummer.
  Future<bool> _claimTurn(int turn) async {
    final me = _myUid;
    if (me == null) return false;
    final ref = FirebaseDatabase.instance.ref('games/$gameId/botTurnClaim');
    final result = await ref.runTransaction((current) {
      if (current is Map && current['turn'] == turn) {
        return Transaction.abort();
      }
      return Transaction.success({'turn': turn, 'claimedBy': me});
    });
    return result.committed;
  }

  // -------- Bot als Reaktions-Ziel --------
  // Spiegelt GameController._listenForReactions, aber gated auf Bot-Ziele
  // statt "targetPlayerId == ich" — dafür eine eigene, parallele
  // Subscription statt die menschliche wiederzuverwenden.
  void _listenForBotReactions() {
    _reactionSubscription?.cancel();
    _reactionSubscription = FirebaseDatabase.instance
        .ref('games/$gameId/reactions')
        .onValue
        .listen((_) => _maybeHandleBotReaction());
  }

  /// Liest den reactions-Knoten frisch und behandelt ihn, falls ein Bot das
  /// Ziel ist. Re-entrant statt reinem Listener-Callback: derselbe Knoten
  /// kann sich WÄHREND der Bearbeitung erneut ändern (z. B. eine neue Kette
  /// per continueReactionChain) — ruft ein Firebase-Update genau dann, wenn
  /// _reactionInFlight noch true ist, würde die Benachrichtigung sonst
  /// stillschweigend verworfen und nie wiederholt. Deshalb am Ende immer
  /// einmal neu prüfen statt auf ein weiteres externes Ereignis zu warten.
  Future<void> _maybeHandleBotReaction() async {
    if (_disposed || _reactionInFlight) return;

    final snap =
        await FirebaseDatabase.instance.ref('games/$gameId/reactions').get();
    final raw = snap.value;
    if (raw == null || raw is! Map) return;

    final map = Map<String, dynamic>.from(raw);
    final handled = map['handled'] == true;
    final ridRaw = map['reactionId'];
    final target = map['targetPlayerId'] as String?;

    if (handled || ridRaw == null || !_isBotId(target)) return;
    if (!_isLeader()) return;

    final rid = ridRaw.toString();

    _reactionInFlight = true;
    try {
      await Future.delayed(BotEngine.thinkDelay(_rng));
      if (_disposed) return;
      // Nach der Bedenkzeit erneut lesen — inzwischen evtl. schon erledigt.
      final freshSnap =
          await FirebaseDatabase.instance.ref('games/$gameId/reactions').get();
      final freshRaw = freshSnap.value;
      if (freshRaw == null || freshRaw is! Map) return;
      final fresh = Map<String, dynamic>.from(freshRaw);
      if (fresh['handled'] == true) return;
      if ((fresh['reactionId']?.toString()) != rid) return;
      if (!_isLeader()) return;
      if (!await _claimReaction(rid)) return;

      await _handleBotReaction(fresh, target!);
    } finally {
      _reactionInFlight = false;
    }
    if (!_disposed) await _maybeHandleBotReaction();
  }

  Future<bool> _claimReaction(String reactionId) async {
    final ref = FirebaseDatabase.instance.ref('games/$gameId/reactions/botClaim');
    final result = await ref.runTransaction((current) {
      if (current is String && current == reactionId) {
        return Transaction.abort();
      }
      return Transaction.success(reactionId);
    });
    return result.committed;
  }

  Future<void> _handleBotReaction(
    Map<String, dynamic> data,
    String botId,
  ) async {
    final gameRef = FirebaseDatabase.instance.ref('games/$gameId');
    final rawCards = data['reactableCards'] as List? ?? [];
    final reactable = rawCards
        .map((c) => GameCard.fromMap(Map<String, dynamic>.from(c as Map)))
        .whereType<ActionCard>()
        .toList();

    if (reactable.isEmpty) {
      await firebaseService.handleUnansweredReaction(gameId);
      await gameRef.child('reactions/handled').set(true);
      return;
    }

    final chosen = BotEngine.chooseReaction(reactable);

    if (chosen != null) {
      await firebaseService.continueReactionChain(gameId, botId, chosen);
      return;
    }

    // Keine Reaktion -> Sonderpfade Deal/Snitch ohne Reaktion, sonst normale
    // Strafabwicklung. Spiegelt GameController._listenForReactions' onNoReaction.
    final rawChain = data['reactionChain'] as List? ?? [];
    if (rawChain.isNotEmpty) {
      final initial = GameCard.fromMap(
        Map<String, dynamic>.from(rawChain.first as Map),
      );
      final source = data['sourcePlayerId'].toString();
      final target = data['targetPlayerId'].toString();

      if (initial is ActionCard && initial.actionType == ActionType.deal) {
        await firebaseService.performDealActionNoReaction(gameId, source, target);
        await firebaseService.nextTurn(gameId);
        await gameRef.child('reactions/handled').set(true);
        return;
      }
      if (initial is ActionCard && initial.actionType == ActionType.snitch) {
        await firebaseService.notifyCurrentPlayerToExecuteSnitchAction(
          gameId,
          source,
          target,
          initial,
        );
        // Turn-Advance übernimmt der Source-Client (Mensch oder Bot) in
        // _executeSnitchChoice/performSnitchAction — hier NICHT aufrufen.
        await gameRef.child('reactions/handled').set(true);
        return;
      }
    }

    await firebaseService.handleUnansweredReaction(gameId);
    await gameRef.child('reactions/handled').set(true);
  }

  // -------- Bot als Snitch-Quelle --------
  // GameController._listenForSnitchAction reagiert nur, wenn sourceId dem
  // eigenen Firebase-Auth-uid entspricht — das passiert bei einem Bot als
  // Quelle nie (bot_N ist keine echte uid). Eigene, parallele Subscription
  // auf denselben Knoten, gated auf Bot-Quellen statt auf die eigene uid.
  void _listenForBotSnitchAction() {
    _snitchActionSubscription?.cancel();
    _snitchActionSubscription = FirebaseDatabase.instance
        .ref('games/$gameId/snitchAction')
        .onValue
        .listen((_) => _maybeHandleBotSnitchAction());
  }

  /// Re-entrant wie _maybeHandleBotReaction — derselbe Race würde sonst
  /// auftreten, falls ein Bot direkt hintereinander mehrfach Snitch-Quelle
  /// ist.
  Future<void> _maybeHandleBotSnitchAction() async {
    if (_disposed || _snitchInFlight) return;

    final snap = await FirebaseDatabase.instance
        .ref('games/$gameId/snitchAction')
        .get();
    final raw = snap.value;
    if (raw == null || raw is! Map) return;

    final data = Map<String, dynamic>.from(raw);
    final sourceId = data['currentPlayerId'] as String?;
    final targetId = data['targetPlayerId'] as String?;
    final snitchMap = data['snitchCard'] as Map?;

    if (!_isBotId(sourceId) || targetId == null || snitchMap == null) return;
    if (!_isLeader()) return;

    _snitchInFlight = true;
    try {
      await Future.delayed(BotEngine.thinkDelay(_rng));
      if (_disposed) return;
      if (!_isLeader()) return;
      // Atomarer Konsum: wer zuerst erfolgreich auf null setzt, führt aus.
      // Ersetzt eine separate Claim + anschließendes .remove().
      final consumed = await _claimSnitchAction(sourceId!, targetId);
      if (!consumed) return;

      final snitchCard = GameCard.fromMap(
        Map<String, dynamic>.from(snitchMap),
      ) as ActionCard;
      await _executeSnitchChoice(sourceId, targetId, snitchCard);
    } finally {
      _snitchInFlight = false;
    }
    if (!_disposed) await _maybeHandleBotSnitchAction();
  }

  Future<bool> _claimSnitchAction(String sourceId, String targetId) async {
    final ref = FirebaseDatabase.instance.ref('games/$gameId/snitchAction');
    final result = await ref.runTransaction((current) {
      if (current == null || current is! Map) return Transaction.abort();
      if (current['currentPlayerId'] != sourceId ||
          current['targetPlayerId'] != targetId) {
        return Transaction.abort();
      }
      return Transaction.success(null); // konsumiert = entfernt den Knoten
    });
    return result.committed;
  }

  /// Dialogfreies Äquivalent zu GameController.performSnitchAction — wird
  /// sowohl als resolveSnitchChoice (Bot spielt Snitch, kein Reaktionsziel)
  /// als auch von der Bot-Snitch-Quellen-Subscription oben aufgerufen
  /// (Bot ist Ziel eines Deal/Snitch, das unbeantwortet blieb).
  Future<void> _executeSnitchChoice(
    String source,
    String target,
    ActionCard snitchCard,
  ) async {
    if (BotEngine.chooseSnitchSwap(_rng)) {
      final mine = await firebaseService.getPlayerCards(gameId, source);
      if (mine.isEmpty) return;
      final theirs = await firebaseService.getPlayerCards(gameId, target);
      if (theirs.isEmpty) return;
      final myCard = mine[_rng.nextInt(mine.length)];
      final theirCard = theirs[_rng.nextInt(theirs.length)];
      await firebaseService.swapHandCard(gameId, source, target, myCard, theirCard);
      await firebaseService.updateGameStatus(gameId);
      await Future.delayed(const Duration(milliseconds: 300));
      await firebaseService.advanceToNextPlayer(gameId);
    } else {
      final theirs = await firebaseService.getPlayerCards(gameId, target);
      if (theirs.isEmpty) return;
      final card = theirs[_rng.nextInt(theirs.length)];
      await firebaseService.revealSnitchCard(gameId, target, card.id, source);
      await firebaseService.updateGameStatus(gameId);
      await Future.delayed(const Duration(milliseconds: 300));
      await firebaseService.advanceToNextPlayer(gameId);
    }
  }
}
