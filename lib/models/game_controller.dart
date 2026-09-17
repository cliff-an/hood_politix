// lib/models/game_controller.dart
// Flutter 3.35.6 / Dart 3
// Projektangepasst: Reaktionen, Deal/Snitch, 5s-Timer, Snitch-Reveal,
// PlayerOrder/Deck-Listener, Multi-Instance (eine Instanz je gameId)

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import 'bot_game_driver.dart';
import 'firebase_service.dart';
import 'game_card.dart';
import 'player.dart';
import 'action_card.dart';
import 'card_action_type.dart';
import 'card_image_factory.dart';

import '../widgets/dialog_manager.dart';
import '../widgets/reaction_dialog_widget.dart';
import '../widgets/snitch_option_dialog.dart';
import '../widgets/dual_card_selection.dart';
import '../widgets/reveal_card_dialog.dart';

class GameController extends ChangeNotifier {
  // -------- Global Singleton (Kompatibilität zu bestehender UI) --------
  static GameController? _instance;
  static GameController get instance {
    if (_instance == null) {
      throw Exception("GameController wurde noch nicht initialisiert.");
    }
    return _instance!;
  }

  // -------- Eine Instanz je gameId (sicher bei mehreren Sessions) --------
  static final Map<String, GameController> _instances = {};
  static GameController getInstance(String gameId, FirebaseService firebaseService) {
    return _instances.putIfAbsent(gameId, () => GameController._internal(gameId, firebaseService));
  }

    /// Prüft, ob bereits eine globale Instanz aktiv ist.
  static bool get hasInstance => _instance != null;


  static void removeInstance(String gameId) {
    _instances.remove(gameId);
    if (_instance != null && _instance!.gameId == gameId) {
      _instance = null;
    }
  }

  /// Initialisierung + globale Kompatibilität (z. B. via Provider in Screens)
  static GameController initializeInstance(String gameId, FirebaseService firebaseService) {
    final ctrl = getInstance(gameId, firebaseService);
    _instance ??= ctrl; // hält bestehende Widgets kompatibel
    return ctrl;
  }

  // -------- Felder / State --------
  final String gameId;
  final DatabaseReference _gameRef;
  final FirebaseService firebaseService;

  bool _initialized = false;
  // Eigene Markierung statt sich auf ChangeNotifier-Internas zu verlassen:
  // mehrere Stellen hier planen Arbeit über einen await/Future.delayed
  // VORAUS (Zug-Timer-Start, s.u.) — wird dispose() währenddessen
  // aufgerufen, darf die verzögerte Fortsetzung notifyListeners() nicht
  // mehr aufrufen (ChangeNotifier wirft sonst "used after being disposed",
  // sichtbar als roter Fehler-Screen).
  bool _disposed = false;

  GameCard? _topCardOfDiscardPile;
  String? currentPlayerId;
  int turn = 0;

  bool isClockwise = true;
  List<String> playerOrder = [];
  List<Player> players = [];
  List<GameCard> discardPile = [];
  List<int> deck = [];

  String? lastReactionId;

  /// Für die öffentliche Kartenanzeige in der Tischmitte: die zuletzt
  /// aufgedeckte Aktionskarte + ein Zähler, der bei jeder neuen Karte
  /// hochzählt (für ALLE Spieler, nicht nur den, der reagieren muss).
  /// Wird direkt am Ablagestapel-Update erkannt (siehe
  /// _listenForGameUpdates) — deckt damit jede Aktionskarte ab, egal ob sie
  /// eine Reaktion auslöst oder nicht (z. B. weil niemand kontern kann).
  GameCard? lastReactionCard;
  int reactionFlashSeq = 0;
  int? _lastFlashedCardId;

  /// Emoji-Reaktion eines Spielers (nur feste Auswahl, kein Freitext) — für
  /// alle Spieler sichtbar, an der Position des Senders.
  String? lastEmoji;
  String? lastEmojiSenderId;
  int emojiSeq = 0;
  int? _lastEmojiTs;

  // Turn-Timeout
  int remainingTime = 10;
  Timer? _turnTimer;
  bool hasFirstTurnStarted = false;

  // Subscriptions
  StreamSubscription<DatabaseEvent>? _currentPlayerSubscription;
  StreamSubscription<DatabaseEvent>? _gameUpdatesSubscription;
  StreamSubscription<DatabaseEvent>? _playersSubscription;
  StreamSubscription<DatabaseEvent>? _deckSubscription;
  StreamSubscription<DatabaseEvent>? _snitchRevealSubscription;
  StreamSubscription<DatabaseEvent>? _playerOrderSubscription;
  StreamSubscription<DatabaseEvent>? _reactionSubscription;

  BotGameDriver? _botDriver;

  // -------- Lifecycle --------
  GameController._internal(this.gameId, this.firebaseService)
      : _gameRef = FirebaseDatabase.instance.ref('games/$gameId');

  Future<void> initializeGameIfNeeded() async {
    if (_initialized) return;
    _initialized = true;

    final snap = await _gameRef.child("gameState").get();
    if (!snap.exists || snap.value == null) {
      await FirebaseService.instance.initializeGame(gameId);
    }

    _listenForGameUpdates();        // currentPlayerId + gameState/discardPile/order
    _listenForDeckUpdates();        // deck
    _listenForPlayersUpdates();     // players
    _listenForPlayerOrderUpdates(); // playerOrder (aktiv/finished filtern)
    _listenForSnitchReveal();       // snitchReveal Overlay
    _listenForSnitchAction();      // snitchAction (Swap/Reveal)
    _listenForFirstTurnFlag();      // hasFirstTurnStarted
    Future.microtask(_listenForReactions); // Reaktionsknoten

    // Immer aktiv, nicht nur wenn Bots im Spiel sind — dann braucht
    // fillWithBots() mitten im Spiel keine zusätzliche Verdrahtung.
    _botDriver = BotGameDriver(gameId, this, firebaseService)..start();
  }

  // -------- Public Getters --------
  GameCard? get topCardOfDiscardPile => _topCardOfDiscardPile;
  bool get isCurrentUserTurn =>
      currentPlayerId != null && currentPlayerId == FirebaseAuth.instance.currentUser?.uid;

  // -------- Listener --------
  void _listenForGameUpdates() {
    _currentPlayerSubscription?.cancel();
    _gameUpdatesSubscription?.cancel();

    // A) currentPlayerId -> Timer-Handling
    _currentPlayerSubscription =
        _gameRef.child("gameState/currentPlayerId").onValue.listen((event) {
      final newId = event.snapshot.value?.toString();
      if (newId == null) return;

      if (currentPlayerId != newId) {
        currentPlayerId = newId;
        notifyListeners();

        // Timer resetten
        _cancelTurnTimerInternal();

        // Starte Timeout nur für den lokalen Spieler — und nur, wenn das
        // Spiel wirklich läuft. currentPlayerId wird schon beim Erstellen
        // des Spiels gesetzt (Ersteller ist "dran"), lange bevor gestartet
        // wurde; ohne diese Prüfung läuft der Timer schon im Warteraum ab
        // und beendet das Spiel für einen einzelnen wartenden Spieler
        // (order.length < 2 in advanceToNextPlayer), bevor überhaupt ein
        // zweiter Spieler/Freund beitreten konnte.
        final myId = FirebaseAuth.instance.currentUser?.uid;
        if (newId == myId) {
          _gameRef.child('gameState/state').get().then((stateSnap) {
            if (_disposed) return;
            if (stateSnap.value?.toString() != 'in progress') return;
            if (!hasFirstTurnStarted) {
              // dispose() kann während dieser Sekunde Wartezeit aufgerufen
              // werden (z. B. Spiel verlassen kurz nach Zugwechsel) — ohne
              // den Check würde _startTurnTimerInternal() hier auf einem
              // bereits entsorgten ChangeNotifier notifyListeners()
              // aufrufen und mit "used after being disposed" abstürzen.
              Future.delayed(const Duration(seconds: 1), () {
                if (!_disposed) _startTurnTimerInternal();
              });
            } else {
              _startTurnTimerInternal();
            }
          });
        }
      }
    });

    // B) gameState-Objekt -> Richtung, Reihenfolge, Ablagestapel
    _gameUpdatesSubscription =
        _gameRef.child("gameState").onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return;

      final data = Map<String, dynamic>.from(raw);
      isClockwise = (data["isClockwise"] ?? true) == true;
      turn = (data["turn"] as num?)?.toInt() ?? turn;
      playerOrder = List<String>.from(
        (data["playerOrder"] as List?)?.map((e) => e.toString()) ?? const [],
      );
      discardPile = (data["discardPile"] as List<dynamic>?)
              ?.map((m) => GameCard.fromMap(Map<String, dynamic>.from(m as Map)))
              .toList() ??
          <GameCard>[];

      _topCardOfDiscardPile = discardPile.isNotEmpty ? discardPile.last : null;

      // Neue Aktionskarte oben auf dem Stapel -> öffentlicher Flash in der
      // Tischmitte, für alle Spieler. Läuft an JEDER Aktionskarte, nicht
      // nur an echten Reaktionen — playCard/continueReactionChain schreiben
      // beide immer zuerst in discardPile, bevor irgendwelche
      // Reaktions-/Effektlogik greift, das deckt also auch unkonterte
      // Aktionskarten mit ab.
      final top = _topCardOfDiscardPile;
      if (top is ActionCard && top.id != _lastFlashedCardId) {
        _lastFlashedCardId = top.id;
        lastReactionCard = top;
        reactionFlashSeq++;
      }

      // Emoji-Reaktion eines Spielers -> für alle sichtbar, an dessen Position.
      final emojiPing = data['emojiPing'];
      if (emojiPing is Map) {
        final ts = (emojiPing['ts'] as num?)?.toInt();
        final emoji = emojiPing['emoji']?.toString();
        final sender = emojiPing['senderId']?.toString();
        if (ts != null && emoji != null && sender != null && ts != _lastEmojiTs) {
          _lastEmojiTs = ts;
          lastEmoji = emoji;
          lastEmojiSenderId = sender;
          emojiSeq++;
        }
      }

      // Sync remainingTime from Firebase so non-active players see the countdown
      final myId = FirebaseAuth.instance.currentUser?.uid;
      if (currentPlayerId != myId) {
        final rt = (data["remainingTime"] as num?)?.toInt();
        if (rt != null) remainingTime = rt;
      }

      notifyListeners();
    });
  }

  void _listenForSnitchAction() {
  FirebaseDatabase.instance
    .ref('games/$gameId/snitchAction')
    .onValue
    .listen((event) async {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return;

      final data = Map<String,dynamic>.from(raw);
      final sourceId = data['currentPlayerId'] as String?;
      final targetId = data['targetPlayerId'] as String?;
      final snitchMap = data['snitchCard'] as Map<dynamic,dynamic>?;

      // Nur Source-Client reagiert
      if (sourceId != FirebaseAuth.instance.currentUser?.uid
          || snitchMap == null
          || targetId == null) {
        return;
      }

      final snitchCard = GameCard.fromMap(
        Map<String,dynamic>.from(snitchMap),
      ) as ActionCard;

      // Kartetausch-Dialog **beim Source** öffnen
      await performSnitchAction(
        gameId,
        sourceId!,
        targetId,
        snitchCard,
      );

      // Aufräumen
      await FirebaseDatabase.instance
        .ref('games/$gameId/snitchAction')
        .remove();
    });
}


  void _listenForPlayerOrderUpdates() {
    _playerOrderSubscription?.cancel();
    _playerOrderSubscription = _gameRef
        .child('gameState/playerOrder')
        .onValue
        .listen((event) {
      final raw = event.snapshot.value;
      final order = raw is List ? List<String>.from(raw) : <String>[];
      playerOrder = order;
      // Nur aktive Spieler im Kreis behalten (fertige rausfiltern)
      players = players.where((p) => playerOrder.contains(p.id)).toList();
      notifyListeners();
    });
  }

  void _listenForDeckUpdates() {
    _deckSubscription?.cancel();
    _deckSubscription =
        _gameRef.child("gameState/deck").onValue.listen((event) {
      final raw = event.snapshot.value as List<dynamic>? ?? [];
      deck = raw.map((e) => int.parse(e.toString())).toList();
      notifyListeners();
    });
  }

  void _listenForPlayersUpdates() {
    _playersSubscription?.cancel();
    _playersSubscription = _gameRef.child("players").onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) {
        players = [];
        notifyListeners();
        return;
      }

      final map = Map<String, dynamic>.from(raw);
      players = map.entries
          .where((e) => e.value is Map)
          .map((e) => Player.fromMap(Map<String, dynamic>.from(e.value), e.key))
          .toList();

      notifyListeners();
    });
  }

  void _listenForSnitchReveal() {
    _snitchRevealSubscription?.cancel();
    _snitchRevealSubscription =
        _gameRef.child('snitchReveal').onChildAdded.listen((event) async {
      final raw = event.snapshot.value;
      if (raw == null || raw is! Map) return;

      final myId = FirebaseAuth.instance.currentUser?.uid;
      final data = Map<String, dynamic>.from(raw);
      final sourceId = data['sourceId'] as String?;

      final cardId = (data['cardId'] as num?)?.toInt();
      if (cardId == null) return;

      final card = await firebaseService.getCardById(gameId, cardId);

      // Auto-close after 3 s so all players see the revealed card briefly
      Timer(const Duration(seconds: 3), () {
        DialogManager.closeDialog();
        // Only source player cleans up the Firebase node
        if (sourceId == myId) {
          _gameRef.child('snitchReveal/${event.snapshot.key}').remove();
        }
      });

      await DialogManager.showAppDialog<void>(
        AlertDialog(
          title: const Text('Snitch zeigt Karte'),
          content: Image.asset(CardImageFactory.getCardImagePath(card)),
        ),
        gameId: gameId,
      );
    });
  }

  void _listenForFirstTurnFlag() {
    _gameRef.child("gameState/hasFirstTurnStarted").onValue.listen((event) {
      hasFirstTurnStarted = event.snapshot.value == true;
      notifyListeners();
    });
  }

  /// Reaktionslogik (Deal/Snitch/Five-O/…)
  void _listenForReactions() {
    _reactionSubscription?.cancel();
    _reactionSubscription =
        _gameRef.child('reactions').onValue.listen((event) async {
      final data = event.snapshot.value;

      // Hinweis: die öffentliche Kartenanzeige in der Tischmitte (siehe
      // lastReactionCard/reactionFlashSeq) hängt inzwischen direkt am
      // discardPile-Update in _listenForGameUpdates, nicht mehr hier —
      // das deckt auch Aktionskarten ab, auf die niemand reagieren kann
      // (dann entsteht gar kein reactions-Knoten).

      if (data == null || data is! Map) return;

      final handled = data['handled'] == true;
      final dynamic ridRaw = data['reactionId'];
      final String? target = data['targetPlayerId'] as String?;
      final String me = FirebaseAuth.instance.currentUser!.uid;

      if (handled) return;
      if (ridRaw == null) return;
      final String rid = ridRaw.toString();
      if (rid == lastReactionId) return;
      if (target != me) return;

      lastReactionId = rid;

      final rawCards = data['reactableCards'] as List? ?? [];
      final reactable = rawCards
          .map((c) => GameCard.fromMap(Map<String, dynamic>.from(c as Map)))
          .whereType<ActionCard>()
          .toList();

      if (reactable.isEmpty) {
        await firebaseService.handleUnansweredReaction(gameId);
        await _gameRef.child('reactions/handled').set(true);
        return;
      }

      final rawChain = data['reactionChain'] as List? ?? [];
      final previousCard = rawChain.isNotEmpty
          ? GameCard.fromMap(Map<String, dynamic>.from(rawChain.last as Map))
          : null;

      await DialogManager.showAppDialog<void>(
        ReactionDialog(
          reactableCards: reactable,
          previousCard: previousCard,
          onCardSelected: (selected) async {
            await firebaseService.continueReactionChain(
              gameId, me, selected as ActionCard,
            );
          },
          onNoReaction: () async {
            // Sonderpfade: Deal/Snitch ohne Reaktion → sofort ausführen
            final List chainData = (data['reactionChain'] as List?) ?? [];
            if (chainData.isNotEmpty) {
              final firstMap =
                  Map<String, dynamic>.from(chainData.first as Map);
              final initial = GameCard.fromMap(firstMap);
              final source = data['sourcePlayerId'].toString();
              final target = data['targetPlayerId'].toString();

              if (initial is ActionCard && initial.actionType == ActionType.deal) {
                await firebaseService.performDealActionNoReaction(
                    gameId, source, target);
                await firebaseService.nextTurn(gameId);
                await _gameRef.child('reactions/handled').set(true);
                return;
              }
              if (initial is ActionCard && initial.actionType == ActionType.snitch) {
                await firebaseService.notifyCurrentPlayerToExecuteSnitchAction(
                    gameId, source, target, initial);
                // Do NOT call nextTurn here — source device handles turn advancement in performSnitchAction
                await _gameRef.child('reactions/handled').set(true);
                return;
              }
            }
            await firebaseService.handleUnansweredReaction(gameId);
            await _gameRef.child('reactions/handled').set(true);
          },
        ),
        gameId: gameId,
      );
    });
  }

  // -------- Turn-Timer (20 Sekunden) --------
  // Die remainingTime-Schreibzugriffe hier sind bewusst "fire and forget"
  // (nicht awaited) — reiner Best-Effort-Sync des sichtbaren Countdowns für
  // andere Spieler, kein kritischer Spielzustand. Genau deshalb aber auch
  // .catchError() nötig: cancel() stoppt nur KÜNFTIGE Ticks, ein bereits
  // losgeschickter (unawaited!) Schreibzugriff des letzten Ticks — oder
  // sogar der disposal-eigene Schreibzugriff unten — kann noch unterwegs
  // sein, wenn kurz danach leaveGame() den Spieler aus players/ entfernt.
  // Ohne catchError wird das dann als nicht abgefangener PERMISSION_DENIED-
  // Fehler sichtbar, obwohl der Countdown für ein verlassenes Spiel
  // niemanden mehr interessiert.
  void _startTurnTimerInternal() {
    _cancelTurnTimerInternal();
    remainingTime = 20;
    _gameRef.child('gameState/remainingTime').set(remainingTime).catchError((_) {});
    notifyListeners();

    _turnTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      remainingTime--;
      _gameRef.child('gameState/remainingTime').set(remainingTime).catchError((_) {});
      notifyListeners();

      if (remainingTime <= 0) {
        t.cancel();
        final myId = FirebaseAuth.instance.currentUser?.uid;
        if (currentPlayerId == myId && myId != null) {
          await FirebaseService.instance.penalty(gameId, myId);
        }
      }
    });
  }

  void cancelTurnTimer() => _cancelTurnTimerInternal();

  void _cancelTurnTimerInternal() {
    _turnTimer?.cancel();
    _turnTimer = null;
    remainingTime = 0;
    _gameRef.child('gameState/remainingTime').set(remainingTime).catchError((_) {});
  }

  // -------- UI-Helper --------
  String playerName(String id) {
    try {
      return players.firstWhere((p) => p.id == id).name;
    } catch (_) {
      return '';
    }
  }

  String playerAvatar(String id) {
    const fallback = 'lib/images/man.png';
    try {
      final p = players.firstWhere((p) => p.id == id);
      return (p.avatarUrl.isNotEmpty == true) ? p.avatarUrl : fallback;
    } catch (_) {
      return fallback;
    }
  }

  // -------- Zielwahl (Deal/Snitch) --------
  Future<String?> selectTargetPlayer(
      BuildContext context, String gameId, String currentPlayerId) async {
    List<Player> list = await FirebaseService.instance.fetchPlayers(gameId);
    list.removeWhere((player) => player.id == currentPlayerId);

    if (list.isEmpty) {
      debugPrint("❌ Keine anderen Spieler verfügbar!");
      return null;
    }

    // Use the global navigator key to avoid stale-context issues after async gaps
    final navCtx = navigatorKey.currentState?.overlay?.context;
    if (navCtx == null) return null;

    final Player? selectedPlayer = await showDialog<Player>(
      context: navCtx, // ignore: use_build_context_synchronously
      builder: (ctx) {
        return SimpleDialog(
          title: const Text('Wähle einen Spieler'),
          children: list
              .map((player) => SimpleDialogOption(
                    onPressed: () => Navigator.of(ctx).pop(player),
                    child: Text(player.name),
                  ))
              .toList(),
        );
      },
    );
    return selectedPlayer?.id;
  }

  // -------- Spielaktionen --------
  Future<void> drawCard(String playerId) async {
    // Beim ersten Zug Flag setzen, damit Timer korrekt funktioniert
    if (!hasFirstTurnStarted) {
      hasFirstTurnStarted = true;
      await _gameRef.child("gameState/hasFirstTurnStarted").set(true);
    }
    cancelTurnTimer();
    await FirebaseService.instance.drawCardForCurrentPlayer(gameId, playerId);
  }

  Future<void> playCard(
      BuildContext context, String playerId, GameCard card) async {
    if (!hasFirstTurnStarted) {
      hasFirstTurnStarted = true;
      await _gameRef.child("gameState/hasFirstTurnStarted").set(true);
    }
    cancelTurnTimer();
    // ignore: use_build_context_synchronously
    await FirebaseService.instance.playCard(context, gameId, playerId, card);
  }

  /// Öffnet optional den Reaktions-Dialog aus Widgets heraus
  Future<void> openReactionDialog(
    BuildContext context, {
    required List<ActionCard> reactables,
    required ActionCard playedCard,
    required String targetPlayerId,
  }) async {
    await DialogManager.showAppDialog<void>(
      ReactionDialog(
        reactableCards: reactables,
        previousCard: playedCard,
        onCardSelected: (GameCard card) async {
          await FirebaseService.instance.continueReactionChain(
            gameId, targetPlayerId, card as ActionCard,
          );
        },
        onNoReaction: () async {
          await FirebaseService.instance.handleUnansweredReaction(gameId);
        },
      ),
      gameId: gameId,
    );
  }

  /// Spieler A spielt "Deal": Ziel wählen → ggf. sofort ausführen oder Reaktionsknoten anlegen
  Future<void> triggerDealAction(
    BuildContext context,
    String gameId,
    String currentPlayerId,
    ActionCard dealCard,
  ) async {
    final target = await selectTargetPlayer(context, gameId, currentPlayerId);
    if (target == null || target == currentPlayerId) return;

    final reactables =
        await firebaseService.getReactableCards(gameId, target, dealCard);
    if (reactables.isEmpty) {
      await firebaseService.performDealActionNoReaction(
          gameId, currentPlayerId, target);
    } else {
      await firebaseService.setReactions(
        gameId, target, reactables, dealCard, currentPlayerId,
      );
    }
  }

  /// Spieler A spielt "Snitch": Ziel wählen, Reaktionsknoten setzen (Five-O kann reagieren)
  Future<void> triggerSnitchAction(
    BuildContext context,
    String gameId,
    String currentPlayerId,
    ActionCard snitchCard,
  ) async {
    final target = await selectTargetPlayer(context, gameId, currentPlayerId);
    if (target == null || target == currentPlayerId) return;

    await firebaseService.setReactions(
      gameId,
      target,
      await firebaseService.getReactableCards(gameId, target, snitchCard),
      snitchCard,
      currentPlayerId,
    );
  }

  /// Führt die Snitch-Aktion beim Source-Spieler aus (Swap/Reveal), wenn Firebase es triggert
  Future<void> performSnitchAction(
    String gameId,
    String currentPlayerId,
    String targetPlayerId,
    GameCard snitchCard,
  ) async {
      // 15-Sekunden-Zeitlimit für die GESAMTE Snitch-Aktion (Auswahl
      // Tauschen/Zeigen UND anschließende Kartenwahl zusammen, nicht pro
      // Dialog-Schritt einzeln) — reagiert der Spieler nicht rechtzeitig,
      // wird der offene Dialog geschlossen und ohne Aktion zum nächsten
      // Spieler weitergeschaltet. `resolved` sorgt dafür, dass eine
      // verspätete Nutzerentscheidung (Dialog war gerade noch offen, als
      // der Timer feuerte) hinterher nicht zusätzlich schreibt/weiterschaltet.
      var resolved = false;
      final timeoutTimer = Timer(const Duration(seconds: 15), () async {
        if (resolved) return;
        resolved = true;
        DialogManager.closeDialog();
        await FirebaseService.instance.advanceToNextPlayer(gameId);
      });

      await DialogManager.showAppDialog<void>(
        SnitchOptionDialog(
          onChosen: (choice) async {
          if (resolved) return;
          DialogManager.closeDialog();

          if (choice == SnitchChoice.swap) {
            final mine =
                await firebaseService.getPlayerCards(gameId, currentPlayerId);
                if (mine.isEmpty || resolved) return;
            final theirs =
                await firebaseService.getPlayerCards(gameId, targetPlayerId);
                if (theirs.isEmpty || resolved) return;

            await DialogManager.showAppDialog<void>(
              DualCardSelectDialog(
                currentPlayerCards: mine,
                targetPlayerCards: theirs,
                onCardsSelected: (mineCard, theirCard) async {
                  if (resolved) return;
                  if (mineCard != null && theirCard != null) {
                    resolved = true;
                    timeoutTimer.cancel();
                    await firebaseService.swapHandCard(
                      gameId, currentPlayerId, targetPlayerId, mineCard, theirCard,
                    );
                    await firebaseService.updateGameStatus(gameId);
                    await Future.delayed(const Duration(milliseconds: 300));
                    await firebaseService.advanceToNextPlayer(gameId);
                  }
                }, currentPlayerName: '', targetPlayerName: '',
              ),
              gameId: gameId,
            );
          } else {
            final theirs =
                await firebaseService.getPlayerCards(gameId, targetPlayerId);
                if (theirs.isEmpty || resolved) return;
            await DialogManager.showAppDialog<void>(
              RevealCardDialog(
                targetCards: theirs,
                onCardRevealed: (card) async {
                  if (resolved) return;
                  resolved = true;
                  timeoutTimer.cancel();
                  await firebaseService.revealSnitchCard(
                      gameId, targetPlayerId, card.id, currentPlayerId);
                  DialogManager.closeDialog();
                  await firebaseService.updateGameStatus(gameId);
                  await Future.delayed(const Duration(milliseconds: 300));
                  await firebaseService.advanceToNextPlayer(gameId);
                },
              ),
              gameId: gameId,
            );
          }
        }, onReveal: (int cardId) async {  }, onSwap: (GameCard myCard, GameCard targetCard) async {  },
      ),
      gameId: gameId,
    );
    timeoutTimer.cancel();
  }

  // -------- Dispose --------
  @override
  void dispose() {
    _disposed = true;
    _currentPlayerSubscription?.cancel();
    _gameUpdatesSubscription?.cancel();
    _playersSubscription?.cancel();
    _deckSubscription?.cancel();
    _snitchRevealSubscription?.cancel();
    _playerOrderSubscription?.cancel();
    _reactionSubscription?.cancel();
    _botDriver?.dispose();

    _cancelTurnTimerInternal();

    removeInstance(gameId);
    super.dispose();
  }
}
