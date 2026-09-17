// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_meta.dart';
import 'package:collection/collection.dart';

import '/models/avatar_catalog.dart';
import '/models/bot_engine.dart';
import '/models/game_controller.dart';
import '/models/number_card.dart';
import '/models/player.dart';

import 'action_card.dart';
import 'card_action_type.dart';
import 'deck.dart';
import 'gameData.dart';
import 'game_card.dart';

class FirebaseService {
  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  GameCard? lastPlayedCard;
  String? get currentPlayerId => _auth.currentUser?.uid;
  late bool isClockwise = true;
  bool isTurnChanged = false;
    // --- Hilfs-Const für Turntimer (falls du remainingTime nutzt)
  int kTurnSeconds = 20;


  // Stream für Auth-Änderungen
  Stream<String?> get onCurrentUserChanged =>
      _auth.authStateChanges().map((User? user) => user?.uid);

  // Singleton
  static final FirebaseService _instance = FirebaseService._privateConstructor();
  static FirebaseService get instance => _instance;

  FirebaseService._privateConstructor()
      : _auth = FirebaseAuth.instance,
        _database = FirebaseDatabase.instance {
    _auth.authStateChanges().listen((User? user) {
      // optional: login/logout handling
    });
  }

  // Für Tests mit Mocks
  FirebaseService.testWithMocks({
    required FirebaseAuth mockAuth,
    required FirebaseDatabase mockDatabase,
  })  : _auth = mockAuth,
        _database = mockDatabase;

  /// Einmaliger erneuter Versuch für einen reinen Lesezugriff, der mit
  /// PERMISSION_DENIED scheitert — siehe Kommentar bei der Nutzung in
  /// startGame(). Nur für .get()-Aufrufe gedacht (nebenwirkungsfrei,
  /// daher gefahrlos wiederholbar), nicht für Schreibzugriffe.
  Future<DataSnapshot> _getWithRetry(
    DatabaseReference ref, {
    Duration delay = const Duration(milliseconds: 400),
  }) async {
    try {
      return await ref.get();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      await Future.delayed(delay);
      return await ref.get();
    }
  }

  // ---------- Realtime Listener ----------

  Stream<DatabaseEvent> listenForGameUpdates(String gameId) {
    final gameRef = _database.ref('games/$gameId');
    return gameRef.onValue;
  }

  Stream<DatabaseEvent> listenForPlayerHandUpdates(String gameId, String playerId) {
    final path = 'games/$gameId/players/$playerId/handCardIds';
    return FirebaseDatabase.instance.ref(path).onValue;
  }

  // ---------- Auth ----------

  Future<User?> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      return userCredential.user;
    } catch (e) {
      print(e);
      return null;
    }
  }

  // ---------- Game Bootstrapping ----------

  Future<void> initializeGame(String gameId) async {
    final gameRef = _database.ref('games/$gameId');

    // Eine Startkarte von aktuellem Deck ziehen
    final initialCard = await drawRandomCard(gameId);

    await gameRef.child("gameState").set({
      "discardPile": [initialCard.toMap()],
      "isClockwise": true,
      "playerOrder": [],
    });

    // An alle existierenden Spieler 5 Handkarten verteilen
    final players = await fetchPlayers(gameId);
    for (final player in players) {
      await giveInitialHandCards(gameId, player.id);
    }
  }

  Future<String> getGameState(String gameId) async {
    final snap = await _database.ref('games/$gameId/gameState/state').get();
    if (!snap.exists || snap.value == null) return 'waiting';
    return snap.value.toString();
  }

  Future<GameCard> drawRandomCard(String gameId) async {
    final deckRef = _database.ref('games/$gameId/gameState/deck');
    final cardRef = _database.ref('games/$gameId/cards');

    final deckSnapshot = await deckRef.get();
    if (!deckSnapshot.exists || deckSnapshot.value == null) {
      throw Exception("Das Deck ist leer.");
    }

    final deckCardIds = List<int>.from((deckSnapshot.value as List).map((e) => int.parse(e.toString())));
    if (deckCardIds.isEmpty) throw Exception("Das Deck ist leer.");

    final drawnId = deckCardIds.removeLast();
    await deckRef.set(deckCardIds);

    final cardSnapshot = await cardRef.child(drawnId.toString()).get();
    if (!cardSnapshot.exists || cardSnapshot.value == null) {
      throw Exception("Karte nicht gefunden.");
    }

    return GameCard.fromMap(Map<String, dynamic>.from(cardSnapshot.value as Map));
  }

  Future<void> giveInitialHandCards(String gameId, String playerId) async {
    final deckRef = _database.ref('games/$gameId/gameState/deck');
    final handRef = _database.ref('games/$gameId/players/$playerId/handCardIds');

    final deckSnapshot = await deckRef.get();
    if (!deckSnapshot.exists || deckSnapshot.value == null) {
      throw Exception("Das Deck ist leer.");
    }

    final deckCardIds = List<int>.from((deckSnapshot.value as List).map((e) => int.parse(e.toString())));
    if (deckCardIds.length < 5) throw Exception("Nicht genügend Karten im Deck.");

    final initial = <int>[];
    for (int i = 0; i < 5; i++) {
      initial.add(deckCardIds.removeLast());
    }

    await deckRef.set(deckCardIds);
    await handRef.set(initial);
  }

  /// Entfernt Nulls und leere Keys aus einem Update-Map, damit `updateChildren` nie crasht.
Map<String, Object?> _sanitizeUpdateMap(Map<String, Object?> raw) {
  final cleaned = <String, Object?>{};
  raw.forEach((k, v) {
    if (k.trim().isEmpty) return; // <- WICHTIG: niemals "" als Key
    // Firebase akzeptiert null in update() zum Löschen; falls du das nicht möchtest, hier filtern.
    cleaned[k] = v;
  });
  return cleaned;
}

/// Liest eine Liste von Spieler-IDs aus /players und optional aus gameState/playerOrder.
/// Ergebnis ist: nur existierende Player-IDs, ohne Duplikate.
Future<List<String>> _loadValidPlayerOrder(String gameId) async {
  final gameRef = _database.ref('games/$gameId');

  final results = await Future.wait([
    gameRef.child('players').get(),
    gameRef.child('gameState/playerOrder').get(),
  ]);
  final playersSnap = results[0];
  final orderSnap   = results[1];

  final presentIds = <String>{};
  if (playersSnap.exists && playersSnap.value is Map) {
    for (var k in (playersSnap.value as Map).keys) {
      final id = k?.toString().trim() ?? '';
      if (id.isNotEmpty) presentIds.add(id);
    }
  }

  // Reihenfolge aus playerOrder nehmen, wenn vorhanden, sonst die Keys aus players.
  final List<String> order = [];
  if (orderSnap.exists) {
    final raw = orderSnap.value;
    if (raw is List) {
      for (final e in raw) {
        final id = (e ?? '').toString().trim();
        if (id.isNotEmpty && presentIds.contains(id)) order.add(id);
      }
    } else if (raw is Map) {
      // Falls jemand es mal als Map geschrieben hat: nach Key sortiert iterieren
      final asMap = Map<String, dynamic>.from(raw);
      // sortiere nach Key, füge Werte (IDs) hinzu
      for (final e in asMap.entries.sorted((a, b) => a.key.compareTo(b.key))) {
        final id = (e.value ?? '').toString().trim();
        if (id.isNotEmpty && presentIds.contains(id)) order.add(id);
      }
    }
  }

  // Fallback: falls kein gültiger order-Eintrag, nimm die vorhandenen Spieler
  if (order.isEmpty) {
    order.addAll(presentIds);
  }

  // Duplikate entfernen, Reihenfolge beibehalten
  final seen = <String>{};
  final unique = <String>[];
  for (final id in order) {
    if (!seen.contains(id)) {
      seen.add(id);
      unique.add(id);
    }
  }
  return unique;
}


  Future<String> createNewGame(
    String gameName,
    String userId, {
    String? password,
    // 'normal' | 'training' | 'tutorial' — training/tutorial-Spiele werden
    // aus der öffentlichen Lobby-Liste rausgefiltert und starten direkt
    // ohne Warteraum (siehe createTrainingGame/createTutorialGame).
    String mode = 'normal',
    // Nur bei normalen Spielen gesetzt: Ziel-Spieleranzahl, die der
    // Warteraum für die optionale "Mit N Bots starten"-Anzeige braucht.
    int? targetPlayerCount,
  }) async {
  try {
    final userName = await _fetchUserName(userId);
    final avatarUrl = resolveAvatarPath(await _fetchAvatarId(userId));
    final gameRef = _database.ref('games').push();
    final gameId = gameRef.key!;
    final isPrivate = password != null && password.isNotEmpty;

    // Deck + Kartenobjekte erstellen
    final deck = Deck();
    final deckIds = deck.cards.map((c) => c.id).toList();
    final cardsData = <String, dynamic>{};
    for (final c in deck.cards) {
      cardsData['${c.id}'] = c.toMap();
    }

    await gameRef.set({
      'meta': {
        'name': gameName, // 🔹 Spielname speichern
        'isPrivate': isPrivate,
        'mode': mode,
        if (targetPlayerCount != null) 'targetPlayerCount': targetPlayerCount,
      },
      'players': {
        userId: {'name': userName, 'handCardIds': [], 'avatarUrl': avatarUrl},
      },
      'gameState': {
        'currentPlayerId': userId,
        'deck': deckIds,
        'discardPile': [],
        'state': 'waiting for players',
        'turn': 0,
        'isClockwise': true,
        'playerOrder': [userId],
      },
      'gameInfo': {'createdAt': ServerValue.timestamp},
      'cards': cardsData,
    });

    // Passwort separat außerhalb von meta/ ablegen — meta/ wird von jedem
    // Lobby-Client laufend live mitgelesen (getGamesMetaStream), das
    // Passwort soll dort nicht automatisch mitgeschickt werden.
    if (isPrivate) {
      await gameRef.child('access/password').set(password);
    }

    await assignJoinCode(gameId);
    await _setCurrentGameWithPresence(userId, gameId);

    return gameId;
  } catch (e) {
    print('Fehler beim Erstellen eines neuen Spiels: $e');
    rethrow;
  }
}


  // starterUserId wird aktuell nicht gelesen — wer beginnt, wird immer
  // zufällig aus den vorhandenen Spielern gewählt (siehe playerIds.shuffle
  // unten). Parameter bleibt aus Kompatibilitätsgründen erhalten.
  Future<void> startGame(
    String gameId,
    String starterUserId, {
    // Für das Tutorial: liefert ein leicht vorbereitetes statt komplett
    // zufälliges Deck (siehe Deck.shuffledWithActionBias). Normale Spiele
    // und der Trainingsmodus nutzen den Default unverändert.
    Deck Function()? deckFactory,
  }) async {
    final gameRef = _database.ref('games/$gameId');
    final playersRef = gameRef.child("players");

    // Direkt nach schnellem Spiel-Wechsel (verlassen -> sofort neues Spiel
    // erstellen) kam es beobachtbar vor, dass genau dieser erste Lesezugriff
    // auf ein Spiel, das der Client gerade selbst angelegt hat, einmalig mit
    // PERMISSION_DENIED scheiterte — obwohl die Regeln (state ==
    // "waiting for players") das eigentlich erlauben. Die Websocket-
    // Verbindung des RTDB-SDKs braucht nach vielen Verbindungswechseln in
    // kurzer Zeit offenbar einen Moment, um Auth-Kontext neu zu
    // synchronisieren; ein einzelner erneuter Versuch nach kurzer Pause
    // behebt das zuverlässig, da es ein rein lesender, nebenwirkungsfreier
    // Aufruf ist.
    final playersSnapshot = await _getWithRetry(playersRef);
    if (!playersSnapshot.exists || playersSnapshot.value == null) {
      throw Exception("Keine Spieler zum Starten des Spiels gefunden.");
    }
    final playerMap = Map<String, dynamic>.from(playersSnapshot.value as Map);
    if (playerMap.length < 2) {
      throw Exception("Mindestens 2 Spieler sind erforderlich.");
    }

    final playerIds = playerMap.keys.map((e) => e.toString()).toList()..shuffle();
    final currentPlayerId = playerIds.first;

    // Deck aufbauen & mischen
    final deck = deckFactory != null ? deckFactory() : (Deck()..shuffle());

    // Single batch update — replaces 20+ sequential writes
    final batch = <String, dynamic>{};

    for (final pid in playerIds) {
      final hand = deck.drawMultiple(5);
      batch['players/$pid/handCardIds'] = hand.map((c) => c.id).toList();
      for (final c in hand) {
        batch['cards/${c.id}'] = c.toMap();
      }
    }

    final initial = deck.draw();
    batch['gameState/discardPile'] = [initial.toMap()];
    batch['cards/${initial.id}'] = initial.toMap();

    for (final c in deck.cards) {
      batch['cards/${c.id}'] = c.toMap();
    }
    batch['gameState/deck'] = deck.cards.map((c) => c.id).toList();
    batch['gameState/state'] = 'in progress';
    batch['gameState/currentPlayerId'] = currentPlayerId;
    batch['gameState/isClockwise'] = true;
    batch['gameState/playerOrder'] = playerIds;

    await gameRef.update(batch);
  }

  // --- Bots -------------------------------------------------------------

  /// Fügt [count] Bot-Spieler hinzu (gleiche Knotenform wie ein Mensch,
  /// zusätzlich isBot:true). IDs sind bot_$startIndex .. bot_$(startIndex+count-1)
  /// und nur innerhalb dieses Spiels eindeutig.
  Future<void> addBotPlayers(String gameId, int count, {int startIndex = 0}) async {
    if (count <= 0) return;
    final batch = <String, dynamic>{};
    for (var i = 0; i < count; i++) {
      final idx = startIndex + i;
      batch['players/bot_$idx'] = {
        'name': BotCatalog.nameFor(idx),
        'handCardIds': [],
        'avatarUrl': BotCatalog.avatarPathFor(idx),
        'isBot': true,
      };
    }
    await _database.ref('games/$gameId').update(batch);
  }

  /// Trainingsmodus: 1 Mensch + [botCount] Bots, startet sofort (kein
  /// Warteraum) mit normalem Zufallsdeck.
  Future<String> createTrainingGame(String userId, int botCount) async {
    final gameId = await createNewGame('Training', userId, mode: 'training');
    await addBotPlayers(gameId, botCount);
    await startGame(gameId, userId);
    return gameId;
  }

  /// Tutorial: 1 Mensch + 3 Bots, startet sofort mit leicht vorbereitetem
  /// Deck (mehr Aktionskarten früh im Stapel, siehe Deck.shuffledWithActionBias).
  Future<String> createTutorialGame(String userId) async {
    final gameId = await createNewGame('Tutorial', userId, mode: 'tutorial');
    await addBotPlayers(gameId, 3);
    await startGame(gameId, userId, deckFactory: Deck.shuffledWithActionBias);
    return gameId;
  }

  /// Füllt ein wartendes normales Spiel mit Bots bis zur Ziel-Spieleranzahl
  /// auf. Liest die aktuelle Spielerzahl neu (idempotent gegen Doppel-Tap
  /// oder zwei Clients, die gleichzeitig auf den Button tippen).
  Future<void> fillWithBots(String gameId, int targetPlayerCount) async {
    final snap = await _database.ref('games/$gameId/players').get();
    final current = snap.exists && snap.value is Map
        ? Map<String, dynamic>.from(snap.value as Map)
        : <String, dynamic>{};
    final needed = targetPlayerCount - current.length;
    if (needed <= 0) return;
    final existingBotIndices = current.keys
        .where((k) => k.startsWith('bot_'))
        .map((k) => int.tryParse(k.substring(4)) ?? -1)
        .toList();
    final nextIndex = existingBotIndices.isEmpty
        ? 0
        : (existingBotIndices.reduce((a, b) => a > b ? a : b) + 1);
    await addBotPlayers(gameId, needed, startIndex: nextIndex);
  }

  // --- Tutorial-Flag ------------------------------------------------------

  /// Wird von login_screen.dart während einer laufenden Registrierung
  /// gesetzt (VOR dem Auth-Aufruf) und nach Abschluss des users/$uid-
  /// Schreibvorgangs completet. Grund: FirebaseAuth.authStateChanges() kann
  /// feuern (und damit AuthGate → LobbyScreen auslösen), BEVOR der
  /// anschließende RTDB-Schreibvorgang mit hasSeenTutorial:false überhaupt
  /// abgeschickt ist — ein reiner hasSeenTutorial-Read direkt beim Lobby-
  /// Start würde den Key dann fälschlich als fehlend (= "schon gesehen")
  /// lesen. LobbyScreen wartet, falls gesetzt, auf dieses Future, bevor es
  /// den eigentlichen Tutorial-Check macht — für normale Logins (null)
  /// entsteht dadurch keine zusätzliche Wartezeit.
  static Completer<void>? pendingRegistration;

  Future<bool> hasSeenTutorial(String uid) async {
    final snap = await _database.ref('users/$uid/hasSeenTutorial').get();
    // Fehlender Key (Bestandskonto vor diesem Feature) zählt als "schon
    // gesehen" — nie rückwirkend aufzwingen.
    if (!snap.exists) return true;
    return snap.value == true;
  }

  Future<void> markTutorialSeen(String uid) {
    return _database.ref('users/$uid/hasSeenTutorial').set(true);
  }

  Future<String> getCurrentPlayerId(String gameId) async {
    final ref = _database.ref('games/$gameId/gameState/currentPlayerId');
    final snap = await ref.get();
    if (!snap.exists || snap.value == null) {
      throw Exception("currentPlayerId not found in the database");
    }
    return snap.value.toString();
  }

  Stream<String?> listenForCurrentPlayerUpdates(String gameId) {
    final ref = _database.ref('games/$gameId/gameState/currentPlayerId');
    return ref.onValue.map((ev) => (ev.snapshot.exists && ev.snapshot.value != null)
        ? ev.snapshot.value.toString()
        : null);
  }

  Future<void> notifyPlayersAboutGameStart(String gameId) async {
    final ref = _database.ref('games/$gameId/notifications');
    await ref.push().set({
      'type': 'gameStarted',
      'message': 'Das Spiel hat begonnen!',
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> setCurrentPlayer(String gameId, String userId) async {
    await _database.ref('games/$gameId/gameState').update({'currentPlayerId': userId});
  }

  /// Wirft eine [Exception], wenn das Spiel passwortgeschützt ist und
  /// [password] nicht passt. Bereits beigetretene Spieler (Reconnect/erneute
  /// Navigation ins eigene Spiel) werden nicht erneut geprüft.
  Future<void> _checkGamePassword(String gameId, String userId, String? password) async {
    final playersRef = _database.ref('games/$gameId/players');
    final alreadyJoined = (await playersRef.child(userId).get()).exists;
    if (alreadyJoined) return;

    final pwSnap = await _database.ref('games/$gameId/access/password').get();
    if (!pwSnap.exists) return; // öffentliches Spiel

    if (password == null || password != pwSnap.value.toString()) {
      throw Exception('Falsches Passwort.');
    }
  }

  Future<void> joinGame(String gameId, String userId, String userName, {String? password}) async {
    await _checkGamePassword(gameId, userId, password);
    final avatarUrl = resolveAvatarPath(await _fetchAvatarId(userId));
    final playersRef = _database.ref('games/$gameId/players/$userId');
    await playersRef.set({'name': userName, 'handCardIds': [], 'avatarUrl': avatarUrl});

    // Spieler in die Reihenfolge aufnehmen (falls nicht vorhanden)
    final orderRef = _database.ref('games/$gameId/gameState/playerOrder');
    final orderSnap = await orderRef.get();
    final order = orderSnap.exists && orderSnap.value is List
        ? List<String>.from((orderSnap.value as List).map((e) => e.toString()))
        : <String>[];
    if (!order.contains(userId)) {
      order.add(userId);
      await orderRef.set(order);
    }

    await _setCurrentGameWithPresence(userId, gameId);
  }

  /// Setzt currentGameId und registriert gleichzeitig eine `onDisconnect`-
  /// Regel: bricht die Verbindung ab (App gekillt, Netzwerk weg, Tab zu),
  /// ohne dass leaveGame() je aufgerufen wurde, löscht der Firebase-Server
  /// selbst dieses Feld — ohne das würde der "im Spiel"-Status auf dem
  /// Profil für immer hängen bleiben. Braucht keine Cloud Function, ist
  /// ein eingebautes RTDB-Feature.
  Future<void> _setCurrentGameWithPresence(String userId, String gameId) async {
    final ref = _database.ref('users/$userId/currentGameId');
    await ref.set(gameId);
    await ref.onDisconnect().remove();
  }

  Future<String> getCurrentUserName(String userId) async {
    final userRef = FirebaseDatabase.instance.ref('users/$userId');
    final snapshot = await userRef.get();
    return snapshot.exists ? snapshot.child('username').value.toString() : "Unbekannter Benutzer";
  }

  Future<GameCard> getCardById(String gameId, int cardId) async {
    final ref = _database.ref('games/$gameId/cards/$cardId');
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.value == null) {
      throw Exception('Card with ID $cardId not found');
    }
    return GameCard.fromMap(Map<String, dynamic>.from(snapshot.value as Map));
  }

  // ---------- Status / Finish ----------

  Future<void> updateGameStatus(String gameId) async {
    final gameRef = _database.ref('games/$gameId');
    final playersRef = gameRef.child('players');
    final snapshot = await playersRef.get();
    if (!snapshot.exists || snapshot.value == null) return;

    final raw = Map<String, dynamic>.from(snapshot.value as Map);
    final activePlayers = <String>[];
    final emptyHandPlayers = <String>[];

    for (final entry in raw.entries) {
      final cards = (entry.value is Map && entry.value['handCardIds'] is List)
          ? List.from(entry.value['handCardIds'] as List)
          : <dynamic>[];
      if (cards.isNotEmpty) {
        activePlayers.add(entry.key);
      } else {
        emptyHandPlayers.add(entry.key);
      }
    }

    for (final pid in emptyHandPlayers) {
      await markPlayerAsFinished(gameId, pid);
    }

    if (activePlayers.length == 1) {
      await endGame(gameId, activePlayers.first);
    }
  }

  Future<void> markPlayerAsFinished(String gameId, String playerId) async {
    final gameRef = _database.ref('games/$gameId');
    final playerRef = gameRef.child('players/$playerId');

    // Guard: only mark once
    final alreadySnap = await gameRef.child('finishedPlayers/$playerId').get();
    if (alreadySnap.exists) return;

    final ts = ServerValue.timestamp;
    await gameRef.child('finishedPlayers').child(playerId).set({'finishedAt': ts});
    // Store finishedAt in the player node too so fetchPlayers can read it
    await playerRef.update({'isActive': false, 'finishedAt': ts});
    await updatePlayerOrder(gameId);
  }

  Future<void> updatePlayerOrder(String gameId) async {
    final gameRef = _database.ref('games/$gameId');

    // Parallel reads instead of N sequential isActive reads
    final results = await Future.wait([
      gameRef.child('gameState/playerOrder').get(),
      gameRef.child('players').get(),
    ]);
    final orderSnap = results[0];
    final playersSnap = results[1];

    if (!orderSnap.exists || orderSnap.value == null) return;

    final raw = orderSnap.value;
    final currentOrder = raw is List
        ? List<String>.from(raw.map((e) => e.toString()))
        : <String>[];

    final activeIds = <String>{};
    if (playersSnap.exists && playersSnap.value is Map) {
      final map = Map<String, dynamic>.from(playersSnap.value as Map);
      for (final entry in map.entries) {
        if (entry.value is Map) {
          final isActive = (entry.value as Map)['isActive'];
          if (isActive != false) activeIds.add(entry.key.toString());
        }
      }
    }

    final filtered = currentOrder.where((id) => activeIds.contains(id)).toList();
    await gameRef.child('gameState/playerOrder').set(filtered);
  }

  Future<bool> canRestartGame(String gameId) async {
    final snap = await _database.ref('games/$gameId/players').get();
    if (!snap.exists || snap.value == null) return false;
    return (snap.value as Map).length >= 2;
  }

  Future<void> endGame(String gameId, String lastPlayerId) async {
    final gameRef = _database.ref('games/$gameId');

    // Mark the last remaining player as finished (they stayed longest = last place)
    await markPlayerAsFinished(gameId, lastPlayerId);

    await gameRef.child('gameState/state').set('finished');
    await gameRef.child('gameState/lastPlayerId').set(lastPlayerId);
    await notifyPlayersGameEnded(gameId);

    // Build placements from finishedPlayers (authoritative finishedAt timestamps)
    final finishedSnap = await gameRef.child('finishedPlayers').get();
    final players = await fetchPlayers(gameId);
    final nameMap = {for (final p in players) p.id: p.name};
    final avatarMap = {for (final p in players) p.id: p.avatarUrl};

    final isBotMap = {for (final p in players) p.id: p.isBot};
    final placements = <String, dynamic>{};
    if (finishedSnap.exists && finishedSnap.value is Map) {
      final finishedData = Map<String, dynamic>.from(finishedSnap.value as Map);
      finishedData.forEach((pid, data) {
        final ft = (data is Map) ? data['finishedAt'] : null;
        placements[pid] = {
          'name': nameMap[pid] ?? 'Unbekannter Spieler',
          'avatarUrl': avatarMap[pid] ?? '',
          'finishedAt': ft, // int (ms since epoch) from ServerValue.timestamp
          'isBot': isBotMap[pid] ?? false,
        };
      });
    }
    await gameRef.child('placements').set(placements);
    // Profil-Status ("im Spiel") wird bewusst NICHT hier für alle Spieler
    // gelöscht: die Security Rules erlauben nur Schreibzugriff auf die
    // eigene users/$uid, ein Client kann also nicht für andere Spieler
    // aufräumen. Jeder Client löscht stattdessen sein eigenes
    // currentGameId selbst in removePlayerFromFinishedGame().
  }

  Future<void> notifyPlayersGameEnded(String gameId) async {
    final ref = _database.ref('games/$gameId/notifications');
    await ref.push().set({
      'type': 'gameEnded',
      'message': 'Spiel ist beendet',
      'timestamp': ServerValue.timestamp,
    });
  }

  Stream<List<String>> getAvailableGames() {
    return _database
        .ref('games')
        .orderByChild('gameInfo/createdAt')
        .limitToLast(50)
        .onValue
        .map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) {
        return <String>[];
      }
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      return map.keys.map((e) => e.toString()).toList();
    });
  }

  Future<void> changeCurrentPlayer(String gameId, String nextPlayerId) async {
    // FIX: unter gameState schreiben
    await _database.ref('games/$gameId/gameState/currentPlayerId').set(nextPlayerId);
  }

  Future<String> _fetchUserName(String userId) async {
    final ref = _database.ref('users/$userId/username');
    final snap = await ref.get();
    return snap.exists ? snap.value.toString() : "Unbekannter Spieler";
  }

  Future<Map<String, dynamic>> getGameData(String gameId) async {
    final ref = _database.ref('games/$gameId');
    final snap = await ref.get();
    if (!snap.exists || snap.value == null) throw Exception("Spiel nicht gefunden");
    return Map<String, dynamic>.from(snap.value as Map);
  }

  // ---------- Registration / Login (optional) ----------

  Future<bool> registerUser(String username, String password) async {
    final userRef = _database.ref('usernames/$username');
    final exists = await userRef.get();
    if (exists.exists) return false;

    final cred = await _auth.createUserWithEmailAndPassword(
      email: "$username@yourapp.com",
      password: password,
    );
    final user = cred.user;
    if (user != null) {
      await _database.ref('users/${user.uid}').set({'username': username});
      await userRef.set(user.uid);
      return true;
    }
    return false;
  }

  Future<User?> loginUser(String username, String password) async {
    final uidSnap = await _database.ref('usernames/$username').get();
    if (!uidSnap.exists) return null;

    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: "$username@yourapp.com",
        password: password,
      );
      return cred.user;
    } catch (e) {
      print("Login Fehler: $e");
      return null;
    }
  }

  // ---------- User Profile / Avatar ----------

  Future<String?> _fetchAvatarId(String userId) async {
    final snap = await _database.ref('users/$userId/avatarId').get();
    return snap.exists ? snap.value?.toString() : null;
  }

  Future<void> setAvatar(String userId, String avatarId) async {
    await _database.ref('users/$userId/avatarId').set(avatarId);
  }

  /// Einmaliges Auslesen des Profils (Username, Avatar, aktuelles Spiel).
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final snap = await _database.ref('users/$userId').get();
    if (!snap.exists || snap.value == null) return null;
    return Map<String, dynamic>.from(snap.value as Map);
  }

  /// Live-Stream des Profils, z. B. für den Profil-Screen oder die
  /// Freundesliste (damit der "im Spiel"-Status in Echtzeit aktualisiert).
  Stream<Map<String, dynamic>?> getUserProfileStream(String userId) {
    return _database.ref('users/$userId').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return null;
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }

  /// Erneute Anmeldung vor dem Löschen des Kontos, falls Firebase
  /// "requires-recent-login" wirft (Sitzung zu alt für eine so sensible
  /// Aktion).
  Future<void> reauthenticate(String username, String password) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Nicht angemeldet.');
    final cred = EmailAuthProvider.credential(
      email: '$username@yourapp.com',
      password: password,
    );
    await user.reauthenticateWithCredential(cred);
  }

  /// Löscht das Konto vollständig: eigenes Profil, Usernamen-Reservierung,
  /// Einträge in fremden Freundeslisten/Anfragen (dort darf nur die eigene
  /// uid als Schlüssel entfernt werden — erlaubt laut Security Rules),
  /// verlässt ein laufendes Spiel falls nötig, und zuletzt den Auth-Account
  /// selbst. Kann `requires-recent-login` werfen — dann vorher
  /// [reauthenticate] aufrufen und erneut versuchen.
  Future<void> deleteAccount(String uid) async {
    final snap = await _database.ref('users/$uid').get();
    final data = snap.exists ? Map<String, dynamic>.from(snap.value as Map) : <String, dynamic>{};
    final username = data['username']?.toString();
    final currentGameId = data['currentGameId']?.toString();

    if (currentGameId != null && currentGameId.isNotEmpty) {
      try {
        await leaveGame(currentGameId, uid);
      } catch (_) {
        // Spiel evtl. schon beendet/gelöscht — für die Kontolöschung egal.
      }
    }

    final friends = data['friends'] is Map ? Map<String, dynamic>.from(data['friends'] as Map) : {};
    final requests = data['friendRequests'] is Map ? Map<String, dynamic>.from(data['friendRequests'] as Map) : {};
    final incoming = requests['incoming'] is Map ? Map<String, dynamic>.from(requests['incoming'] as Map) : {};
    final outgoing = requests['outgoing'] is Map ? Map<String, dynamic>.from(requests['outgoing'] as Map) : {};

    final cleanup = <String, dynamic>{};
    for (final otherUid in friends.keys) {
      cleanup['users/$otherUid/friends/$uid'] = null;
    }
    for (final fromUid in incoming.keys) {
      cleanup['users/$fromUid/friendRequests/outgoing/$uid'] = null;
    }
    for (final toUid in outgoing.keys) {
      cleanup['users/$toUid/friendRequests/incoming/$uid'] = null;
    }
    if (cleanup.isNotEmpty) {
      await _database.ref().update(cleanup);
    }

    if (username != null && username.isNotEmpty) {
      await _database.ref('usernames/$username').remove();
    }
    await _database.ref('users/$uid').remove();

    await _auth.currentUser?.delete();
  }

  // ---------- Freunde (gegenseitig: Anfrage + Bestätigung) ----------

  /// Sucht einen Nutzer über den bestehenden usernames/$username-Index.
  /// Gibt null zurück, wenn kein Treffer existiert.
  Future<String?> findUserByUsername(String username) async {
    final snap = await _database.ref('usernames/$username').get();
    return snap.exists ? snap.value.toString() : null;
  }

  Future<void> sendFriendRequest(String fromUid, String toUid) async {
    if (fromUid == toUid) return;
    final now = ServerValue.timestamp;
    await _database.ref().update({
      'users/$toUid/friendRequests/incoming/$fromUid': now,
      'users/$fromUid/friendRequests/outgoing/$toUid': now,
    });
  }

  Future<void> acceptFriendRequest(String uid, String fromUid) async {
    await _database.ref().update({
      'users/$uid/friendRequests/incoming/$fromUid': null,
      'users/$fromUid/friendRequests/outgoing/$uid': null,
      'users/$uid/friends/$fromUid': true,
      'users/$fromUid/friends/$uid': true,
    });
  }

  Future<void> declineFriendRequest(String uid, String fromUid) async {
    await _database.ref().update({
      'users/$uid/friendRequests/incoming/$fromUid': null,
      'users/$fromUid/friendRequests/outgoing/$uid': null,
    });
  }

  Future<void> removeFriend(String uid, String otherUid) async {
    await _database.ref().update({
      'users/$uid/friends/$otherUid': null,
      'users/$otherUid/friends/$uid': null,
    });
  }

  /// Liste der Freundes-UIDs (Keys der friends-Map) als Live-Stream.
  Stream<List<String>> getFriendsStream(String uid) {
    return _database.ref('users/$uid/friends').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <String>[];
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      return map.keys.map((e) => e.toString()).toList();
    });
  }

  /// Eingehende Freundschaftsanfragen (UIDs der Absender) als Live-Stream.
  Stream<List<String>> getIncomingFriendRequestsStream(String uid) {
    return _database.ref('users/$uid/friendRequests/incoming').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <String>[];
      final map = Map<String, dynamic>.from(event.snapshot.value as Map);
      return map.keys.map((e) => e.toString()).toList();
    });
  }

  // ---------- Einladen & Teilen ----------

  /// Lädt einen Freund in ein eigenes (wartendes) Spiel ein. Ist das Spiel
  /// privat, wird das Passwort in die Einladung übernommen — der Einladende
  /// kennt es ja bereits, der Eingeladene muss es nicht erneut eintippen.
  Future<void> inviteFriendToGame(String gameId, String fromUid, String toUid) async {
    final metaSnap = await _database.ref('games/$gameId/meta').get();
    final meta = metaSnap.exists ? Map<String, dynamic>.from(metaSnap.value as Map) : {};
    final gameName = meta['name']?.toString() ?? 'Spiel';

    String? password;
    if (meta['isPrivate'] == true) {
      final pwSnap = await _database.ref('games/$gameId/access/password').get();
      if (pwSnap.exists) password = pwSnap.value.toString();
    }

    await _database.ref('users/$toUid/invites/$gameId').set({
      'fromUid': fromUid,
      'gameName': gameName,
      if (password != null) 'password': password,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> declineInvite(String uid, String gameId) async {
    await _database.ref('users/$uid/invites/$gameId').remove();
  }

  /// Live-Stream offener Einladungen `{gameId: {fromUid, gameName, timestamp}}`.
  Stream<Map<String, dynamic>> getInvitesStream(String uid) {
    return _database.ref('users/$uid/invites').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <String, dynamic>{};
      return Map<String, dynamic>.from(event.snapshot.value as Map);
    });
  }

  static const _joinCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // ohne 0/O, 1/I

  String _generateJoinCode() {
    final rnd = Random();
    return List.generate(6, (_) => _joinCodeChars[rnd.nextInt(_joinCodeChars.length)]).join();
  }

  /// Erzeugt einen eindeutigen Beitritts-Code für ein Spiel und legt den
  /// Reverse-Index an (gleiches Muster wie usernames/$username → uid).
  Future<String> assignJoinCode(String gameId) async {
    String code;
    DatabaseEvent existing;
    do {
      code = _generateJoinCode();
      existing = await _database.ref('joinCodes/$code').once();
    } while (existing.snapshot.exists);

    await _database.ref().update({
      'joinCodes/$code': gameId,
      'games/$gameId/meta/joinCode': code,
    });
    return code;
  }

  /// Löst einen Beitritts-Code zu einer gameId auf, oder null.
  Future<String?> resolveJoinCode(String code) async {
    final snap = await _database.ref('joinCodes/${code.toUpperCase()}').get();
    return snap.exists ? snap.value.toString() : null;
  }

  // ---------- Deck / Rundenfluss ----------

  Future<void> updateDeckInDatabase(String gameId, Deck deck) async {
    final deckRef = _database.ref('games/$gameId/gameState/deck');
    await deckRef.set(deck.cards.map((c) => c.id).toList());
  }

  /// ########################################################
  /// ## nextTurn (Alias, falls im Code benutzt)
  /// ########################################################
  Future<void> nextTurn(String gameId) => advanceToNextPlayer(gameId);

  Future<String> getNextPlayerId(String gameId) async {
    final ref = _database.ref('games/$gameId/gameState');
    final snap = await ref.get();
    if (!snap.exists) throw Exception('Spielzustand nicht gefunden');

    final data = Map<String, dynamic>.from(snap.value as Map);
    final order = List<String>.from((data['playerOrder'] as List).map((e) => e.toString()));
    final clockwise = (data['isClockwise'] ?? true) == true;
    final current = data['currentPlayerId'].toString();

    int idx = order.indexOf(current);
    if (idx < 0) throw Exception('Spieler nicht in playerOrder');

    final nextIdx = clockwise ? (idx + 1) % order.length : (idx - 1 + order.length) % order.length;
    return order[nextIdx];
  }

    /// Gibt eine Liste aller Spiele zurück mit Metadaten (z. B. Spielerzahl, Status)
  Future<List<Map<String, dynamic>>> getGamesMeta() async {
    final gamesRef = _database.ref('games');
    final snapshot = await gamesRef.get();

    if (!snapshot.exists || snapshot.value == null) return [];

    final gamesMap = Map<String, dynamic>.from(snapshot.value as Map);
    final result = <Map<String, dynamic>>[];

    for (final entry in gamesMap.entries) {
      final gameId = entry.key;
      final data = Map<String, dynamic>.from(entry.value as Map);

      final players = (data['players'] as Map?)?.length ?? 0;
      final state = data['gameState']?['state'] ?? 'waiting';
      final createdAt = data['gameInfo']?['createdAt'];

      result.add({
        'id': gameId,
        'playerCount': players,
        'state': state,
        'createdAt': createdAt,
      });
    }

    return result;
  }

  Future<GameMeta> getGameMeta(String gameId) async {
    final ref = _database.ref('games/$gameId');
    final snap = await ref.get();

    if (!snap.exists || snap.value == null) {
      throw Exception("Spiel $gameId nicht gefunden");
    }

    final raw = Map<String, dynamic>.from(snap.value as Map);

    // Extrahiere Daten aus mehreren Knoten
    final metaMap = Map<String, dynamic>.from(raw['meta'] ?? {});
    final stateMap = Map<String, dynamic>.from(raw['gameState'] ?? {});
    final playersMap =
        Map<String, dynamic>.from(raw['players'] ?? {});

    final createdAt = (raw['gameInfo']?['createdAt'] is int)
        ? raw['gameInfo']['createdAt'] as int
        : DateTime.now().millisecondsSinceEpoch;

    final endedAt = stateMap['endedAt'] is int ? stateMap['endedAt'] as int : null;

    return GameMeta(
      id: gameId,
      name: metaMap['name'] ?? 'Unbenanntes Spiel',
      state: stateMap['state'] ?? 'waiting',
      playerIds: playersMap.keys.cast<String>().toList(),
      createdAt: createdAt,
      endedAt: endedAt,
    );
  }


  // Stream-Version für Live-Lobby. Begrenzt auf die 50 zuletzt erstellten
  // Spiele (wie das bereits vorhandene getAvailableGames()) — vorher wurde
  // bei jeder Änderung der KOMPLETTE games-Knoten an jeden Lobby-Client neu
  // übertragen, unbegrenzt wachsend mit jedem je erstellten Spiel.
Stream<List<GameMeta>> getGamesMetaStream() {
  return _database
      .ref('games')
      .orderByChild('gameInfo/createdAt')
      .limitToLast(50)
      .onValue
      .map((event) {
    if (!event.snapshot.exists || event.snapshot.value == null) return [];
    final map = Map<String, dynamic>.from(event.snapshot.value as Map);
    return map.entries
        .where((e) => e.value is Map)
        .map((e) => GameMeta.fromMap(e.key, Map<String, dynamic>.from(e.value as Map)))
        .toList();
  });
}
  
  /// Spieler verlässt das Spiel.
  /// - Wenn Spiel läuft und dadurch < 2 Spieler übrig: Spiel beenden + Placements schreiben
  /// - Sonst: Spieler aus /players + playerOrder entfernen, ggf. Zug weitergeben
  Future<void> leaveGame(String gameId, String playerId) async {
    final gameRef    = _database.ref('games/$gameId');
    final playersRef = gameRef.child('players');
    final stateRef   = gameRef.child('gameState');

    // Read state BEFORE removing player (we still need name/avatar for placements)
    final results = await Future.wait([
      stateRef.child('state').get(),
      stateRef.child('currentPlayerId').get(),
    ]);
    final state = (results[0].value ?? '').toString();
    final currentTurnId = (results[1].value ?? '').toString();

    // Fix playerOrder (player still in /players so _loadValidPlayerOrder finds them)
    final order = await _loadValidPlayerOrder(gameId);
    order.removeWhere((id) => id == playerId);

    if (state == 'in progress' && order.length < 2) {
      // Build placements while player is still in /players
      await _endGameWithLeave(gameId, playerId, order);
      // Now remove the leaving player
      await playersRef.child(playerId).remove();
      return;
    }

    // Normal leave: Spieler entfernen + playerOrder reparieren + (falls
    // nötig) den Zug weiterschalten — als EIN atomarer Mehrpfad-
    // Schreibvorgang, nicht als separate Future.wait-Aufrufe. Grund: die
    // $gameId-Schreibfreigabe hängt an players/{auth.uid}.exists(); sobald
    // players/$playerId separat entfernt wurde, erfüllt der EIGENE Client
    // diese Bedingung nicht mehr und jeder NACHFOLGENDE Schreibzugriff
    // (playerOrder, currentPlayerId, ...) schlägt mit PERMISSION_DENIED
    // fehl. Ein einziges update() wird dagegen als Ganzes gegen den
    // Zustand VOR dem Schreibvorgang geprüft (players/$playerId existiert
    // zu dem Zeitpunkt noch) — exakt das Muster, das advanceToNextPlayer
    // bereits nutzt, um trotz .write:false auf currentPlayerId schreiben
    // zu können.
    final updates = <String, Object?>{
      'players/$playerId': null,
      'gameState/playerOrder': order,
    };
    if (currentTurnId == playerId && order.isNotEmpty) {
      updates['gameState/currentPlayerId'] = order.first;
      updates['gameState/turn'] = ServerValue.increment(1);
      updates['gameState/remainingTime'] = 20;
    }
    await gameRef.update(_sanitizeUpdateMap(updates));
    await _database.ref('users/$playerId/currentGameId').remove();
  }

  /// Beendet das Spiel weil ein Spieler gegangen ist: schreibt Placements,
  /// setzt state = finished. Der verbleibende Spieler gewinnt.
  Future<void> _endGameWithLeave(
    String gameId,
    String leavingPlayerId,
    List<String> remainingIds,
  ) async {
    final gameRef = _database.ref('games/$gameId');
    final players = await fetchPlayers(gameId); // leaving player still in /players
    final nameMap   = {for (final p in players) p.id: p.name};
    final avatarMap = {for (final p in players) p.id: p.avatarUrl};
    final isBotMap  = {for (final p in players) p.id: p.isBot};

    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = <String, dynamic>{};

    // Remaining players won (earlier finishedAt = better rank)
    for (var i = 0; i < remainingIds.length; i++) {
      final pid = remainingIds[i];
      final ts  = now + i;
      batch['finishedPlayers/$pid']    = {'finishedAt': ts};
      batch['players/$pid/isActive']   = false;
      batch['players/$pid/finishedAt'] = ts;
      batch['placements/$pid'] = {
        'name':       nameMap[pid]   ?? 'Unbekannter Spieler',
        'avatarUrl':  avatarMap[pid] ?? 'lib/images/man.png',
        'finishedAt': ts,
        'isBot':      isBotMap[pid]  ?? false,
      };
    }

    // Leaving player is last (larger finishedAt = worse rank)
    final leavingTs = now + remainingIds.length + 1000;
    batch['finishedPlayers/$leavingPlayerId']    = {'finishedAt': leavingTs};
    batch['players/$leavingPlayerId/isActive']   = false;
    batch['players/$leavingPlayerId/finishedAt'] = leavingTs;
    batch['placements/$leavingPlayerId'] = {
      'name':       nameMap[leavingPlayerId]   ?? 'Unbekannter Spieler',
      'avatarUrl':  avatarMap[leavingPlayerId] ?? 'lib/images/man.png',
      'finishedAt': leavingTs,
      'isBot':      isBotMap[leavingPlayerId]  ?? false,
    };

    batch['gameState/state']           = 'finished';
    batch['gameState/currentPlayerId'] = null;
    batch['gameState/playerOrder']     = remainingIds;

    await gameRef.update(batch);

    // Nur die eigene currentGameId kann hier geräumt werden (Security
    // Rules erlauben nur Schreibzugriff auf die eigene users/$uid) —
    // _endGameWithLeave läuft auf dem Client des Verlassenden, dessen
    // eigene uid ist also `leavingPlayerId`. Die verbleibenden Spieler
    // räumen ihr eigenes currentGameId über removePlayerFromFinishedGame()
    // auf, sobald sie den GameOverScreen verlassen.
    await _database.ref('users/$leavingPlayerId/currentGameId').remove();
  }

  /// Entfernt den eigenen Spieler aus dem /players-Knoten eines beendeten Spiels
  /// und räumt den eigenen "im Spiel"-Profilstatus auf.
  /// Wird aufgerufen wenn der Spieler die Lobby betritt (nach GameOverScreen).
  Future<void> removePlayerFromFinishedGame(String gameId, String playerId) async {
    await _database.ref('games/$gameId/players/$playerId').remove();
    await _database.ref('users/$playerId/currentGameId').remove();
  }


    /// Löscht ein Spiel (z. B. aus der Lobby heraus)
  Future<void> deleteGame(String gameId) async {
    final gameRef = _database.ref('games/$gameId');
    await gameRef.remove();
  }

// Prüft, ob Spieler schon in einem laufenden Spiel ist (beendete Spiele werden ignoriert)
// Zwei kleine, gezielte Reads statt eines Downloads des kompletten
// games-Knotens bei jedem Versuch, ein neues Spiel zu erstellen.
// users/$uid/currentGameId (Phase 1 der Lobby-Social-Features) trägt
// bereits genau diese Information; der zweite Read prüft nur noch, ob das
// referenzierte Spiel nicht doch schon (z. B. durch onDisconnect-Latenz)
// beendet ist.
Future<bool> isPlayerAlreadyInGame(String playerId) async {
  final gameIdSnap = await _database.ref('users/$playerId/currentGameId').get();
  final gameId = gameIdSnap.value?.toString();
  if (gameId == null || gameId.isEmpty) return false;

  final stateSnap = await _database.ref('games/$gameId/gameState/state').get();
  final state = stateSnap.value?.toString();
  return state != null && state != 'finished';
}



  Future<void> toggleGameDirection(String gameId) async {
    final ref = _database.ref('games/$gameId/gameState');
    final snap = await ref.get();
    if (!snap.exists || snap.value == null) {
      print('Keine Daten im GameState vorhanden.');
      return;
    }
    final data = Map<String, dynamic>.from(snap.value as Map);
    final clockwise = (data['isClockwise'] ?? true) == true;
    await ref.update({'isClockwise': !clockwise});
  }

  Stream<GameData> getGameUpdates(String gameId) {
    return _database.ref('games/$gameId').onValue.map((e) => GameData.fromSnapshot(e.snapshot));
  }

  Map<String, GameData> gameDataCache = {};

  Future<GameData?> getCachedGameData(String gameId) async {
    if (gameDataCache.containsKey(gameId)) return gameDataCache[gameId];
    final snap = await _database.ref('games/$gameId').get();
    final data = GameData.fromSnapshot(snap);
    gameDataCache[gameId] = data;
    return data;
  }

  Future<void> dealCards(String gameId, int cardsPerPlayer) async {
    final gameRef = _database.ref('games/$gameId');
    final deckRef = gameRef.child('gameState/deck');
    final playersRef = gameRef.child('players');

    final deckSnapshot = await deckRef.get();
    if (!deckSnapshot.exists || deckSnapshot.value == null) return;

    var deckCardIds = List<int>.from((deckSnapshot.value as List).map((e) => int.parse(e.toString())));
    final playersSnapshot = await playersRef.get();
    if (!playersSnapshot.exists || playersSnapshot.value == null) return;

    final playersData = Map<String, dynamic>.from(playersSnapshot.value as Map);
    if (deckCardIds.length < playersData.length * cardsPerPlayer) return;

    final updates = <String, dynamic>{};
    for (final pid in playersData.keys) {
      final drawn = <int>[];
      for (int i = 0; i < cardsPerPlayer; i++) {
        drawn.add(deckCardIds.removeLast());
      }
      updates['players/$pid/handCardIds'] = drawn;
    }
    updates['gameState/deck'] = deckCardIds;

    await gameRef.update(updates);
  }

  // --- Mic-Check/Drop ---

  Future<bool> hasMicChecked(String gameId, String playerId) async {
    final snap = await _database.ref('games/$gameId/gameState/micChecks/$playerId').get();
    return snap.exists && (snap.value == true);
  }

  Future<bool> hasMicDropped(String gameId, String playerId) async {
    final snap = await _database.ref('games/$gameId/gameState/micDrops/$playerId').get();
    return snap.exists && (snap.value == true);
  }

  Future<void> drawCardForCurrentPlayer(String gameId, String playerId) async {
    final deckRef = _database.ref('games/$gameId/gameState/deck');
    final handRef = _database.ref('games/$gameId/players/$playerId/handCardIds');

    int? drawn;
    final result = await deckRef.runTransaction((current) {
      if (current == null) return Transaction.abort();
      final ids = List<int>.from((current as List).map((e) => int.parse(e.toString())));
      if (ids.isEmpty) return Transaction.abort();
      drawn = ids.removeLast();
      return Transaction.success(ids);
    });

    if (!result.committed || drawn == null) return;

    await handRef.runTransaction((current) {
      final hand = current == null
          ? <int>[]
          : List<int>.from((current as List).map((e) => int.parse(e.toString())));
      hand.add(drawn!);
      return Transaction.success(hand);
    });
  }

  Future<void> discardCard(String gameId, String playerId, GameCard card) async {
    final discardRef = _database.ref('games/$gameId/gameState/discardPile');
    final snap = await discardRef.get();

    final pile = (snap.exists && snap.value is List)
        ? (snap.value as List)
            .map((e) => GameCard.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <GameCard>[];

    pile.add(card);
    await discardRef.set(pile.map((c) => c.toMap()).toList());
  }

  // ---------- Aktionen / Reaktionen ----------

  Future<void> performDealAction(BuildContext context, String gameId, String currentPlayerId) async {
    final targetPlayerId =
        await GameController.instance.selectTargetPlayer(context, gameId, currentPlayerId);
    if (targetPlayerId == null || currentPlayerId == targetPlayerId) return;

    await tradeHands(gameId, currentPlayerId, targetPlayerId);
  }

  Future<void> performDealActionNoReaction(
      String gameId, String currentPlayerId, String targetPlayerId) async {
    if (currentPlayerId == targetPlayerId) return;
    await tradeHands(gameId, currentPlayerId, targetPlayerId);
  }

  Future<void> updateCounters(String gameId, int deucesCount, int inYoFaceCount) async {
    await _database.ref('games/$gameId/counters').set({
      'deucesCounter': deucesCount,
      'inYoFaceCounter': inYoFaceCount,
    });
  }

  Future<void> applyPenaltiesAndResetCounters(String gameId, String targetPlayerId) async {
    final countersRef = _database.ref('games/$gameId/counters');
    final snap = await countersRef.get();
    final data = (snap.value as Map?)?.cast<String, dynamic>() ?? {};

    final deuces = (data['deucesCounter'] as int?) ?? 0;
    final inyo = (data['inYoFaceCounter'] as int?) ?? 0;
    final total = deuces * 2 + inyo * 5;

    if (total > 0) {
      await forcePlayerDrawCards(gameId, targetPlayerId, total);
    }
    await updateCounters(gameId, 0, 0);
  }

  Future<void> applyPenalty(String gameId, String targetPlayerId, int count) async {
    await forcePlayerDrawCards(gameId, targetPlayerId, count);
  }

  /// Wird aufgerufen, wenn der Zielspieler NICHT reagiert
  Future<void> handleUnansweredReaction(String gameId) async {
    final reactionRef = _database.ref('games/$gameId/reactions');

    final snapshot = await reactionRef.get();
    if (!snapshot.exists || snapshot.value == null) return;

    final data = Map<String, dynamic>.from(snapshot.value as Map);
    final sourceId = data['sourcePlayerId']?.toString();
    final targetId = data['targetPlayerId']?.toString();
    final rawChain = (data['reactionChain'] ?? data['chain'] ?? []) as List;

    final chain = rawChain
        .map((m) => GameCard.fromMap(Map<String, dynamic>.from(m as Map)))
        .whereType<ActionCard>()
        .toList();

    if (sourceId == null || targetId == null || chain.isEmpty) {
      await reactionRef.remove();
      return;
    }

    final lastCard = chain.last;

    // Wer bekommt die Strafe?
    late String penaltyReceiver;
    if (lastCard.actionType == ActionType.payback) {
      // Payback gibt Strafe an vorher angepeilten Spieler zurück
      penaltyReceiver = (data['penaltyTarget']?.toString()) ?? sourceId;
    } else if (lastCard.actionType == ActionType.deuces ||
        lastCard.actionType == ActionType.inYoFace) {
      // Zielspieler, der NICHT reagieren konnte
      penaltyReceiver = targetId;
    } else {
      // Deal/Snitch etc.: keine Stapel-Strafen → nur Aufräumen
      await reactionRef.remove();
      return;
    }

    // Strafen aus Kettenlänge berechnen
    final deucesCount = chain.where((c) => c.actionType == ActionType.deuces).length;
    final inYoCount = chain.where((c) => c.actionType == ActionType.inYoFace).length;
    final totalPenalty = deucesCount * 2 + inYoCount * 5;

    if (totalPenalty > 0) {
      await forcePlayerDrawCards(gameId, penaltyReceiver, totalPenalty);
    }

    // Bei Deuces / InYoFace: der nächste Spieler nach dem Bestraften ist dran (Skip)
    if (lastCard.actionType == ActionType.deuces || lastCard.actionType == ActionType.inYoFace) {
      await skipNextPlayer(gameId);
    } else {
      await nextTurn(gameId);
    }

    await updateCounters(gameId, 0, 0);
    await reactionRef.remove();
  }



/// ########################################################
/// ## advanceToNextPlayer
/// ########################################################
/// Dreht den Zug auf den nächsten Spieler weiter.
/// - Überspringt Spieler, die nicht (mehr) existieren.
/// - Schreibt **niemals** eine leere ID.
/// - Beendet das Spiel sauber, wenn <2 Spieler übrig sind.
/// - Erhöht den Turn-Counter atomar.
/// - Räumt optionale Mic-Flags des vorherigen Spielers auf.
Future<void> advanceToNextPlayer(String gameId) async {
  final gameRef   = _database.ref('games/$gameId');
  final stateRef  = gameRef.child('gameState');

  final stateSnap = await stateRef.get();
  final stateData = stateSnap.exists && stateSnap.value is Map
      ? Map<String, dynamic>.from(stateSnap.value as Map)
      : <String, dynamic>{};

  final currentId   = (stateData['currentPlayerId'] ?? '').toString().trim();
  final turn        = (stateData['turn'] is int) ? (stateData['turn'] as int) : 0;
  final isClockwise = (stateData['isClockwise'] ?? true) == true;

  // Extract playerOrder directly from the already-loaded stateSnap (avoids 2 extra reads)
  final rawOrder = stateData['playerOrder'];
  List<String> order = [];
  if (rawOrder is List) {
    order = rawOrder.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  } else if (rawOrder is Map) {
    order = rawOrder.values.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  if (order.isEmpty) {
    order = await _loadValidPlayerOrder(gameId);
  }

  // Falls nicht genügend Spieler -> Game beenden
  if (order.length < 2) {
    await stateRef.update(_sanitizeUpdateMap({
      'state': 'finished',
      'currentPlayerId': null,
    }));
    return;
  }

  // Fallback, wenn currentId fehlt oder nicht in order
  String nextId;
  if (currentId.isEmpty || !order.contains(currentId)) {
    nextId = order.first;
  } else {
    final i = order.indexOf(currentId);
    nextId = isClockwise
        ? order[(i + 1) % order.length]
        : order[(i - 1 + order.length) % order.length];
  }

  // Sicherheitscheck: niemals leere IDs schreiben
  if (nextId.trim().isEmpty) {
    // Versuche irgendeine valide ID zu wählen
    nextId = order.firstWhere((id) => id.trim().isNotEmpty, orElse: () => '');
  }

  if (nextId.isEmpty) {
    // Wenn hier noch immer leer: beende das Spiel als Schutzmaßnahme
    await stateRef.update(_sanitizeUpdateMap({
      'state': 'finished',
      'currentPlayerId': null,
    }));
    return;
  }

  // Optional: Mic-Status des alten Spielers zurücksetzen (nur sein Flag)
  // (Wenn du die gesamte /gameState/mic löschen willst, lösch einfach den Knoten.)
  final updates = <String, Object?>{
    'gameState/currentPlayerId': nextId,
    'gameState/turn'          : turn + 1,      // alternativ: ServerValue.increment(1)
    'gameState/remainingTime' : 20,
    'gameState/mic/$currentId': null,          // altes Mic-Flag weg
  };

  await gameRef.update(_sanitizeUpdateMap(updates));
}

  Future<void> revealSnitchCard(String gameId, String targetId, int cardId, String sourceId) async {
    await _database
        .ref('games/$gameId/snitchReveal/$targetId')
        .set({'cardId': cardId, 'sourceId': sourceId, 'timestamp': ServerValue.timestamp});
  }

  Future<void> triggerSnitchActionFirebase(
    String gameId,
    String currentPlayerId,
    String targetPlayerId,
    int snitchCardId,
  ) async {
    final snitchRef = _database.ref('games/$gameId/snitchActions/$currentPlayerId');
    await snitchRef.set({
      'currentPlayerId': currentPlayerId,
      'targetPlayerId': targetPlayerId,
      'snitchCardId': snitchCardId,
      'actionRequired': true,
      'timestamp': ServerValue.timestamp,
    });
  }

  Future<void> jumpInCard(String gameId, String playerId, GameCard card) async {
    final gameRef = _database.ref('games/$gameId');
    final discardRef = gameRef.child('gameState/discardPile');
    final handRef = gameRef.child('players/$playerId/handCardIds');

    final discardSnap = await discardRef.get();
    final pile = discardSnap.exists
        ? (discardSnap.value as List)
            .map((e) => GameCard.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList()
        : <GameCard>[];

    final top = pile.isNotEmpty ? pile.last : null;
    if (top is NumberCard &&
        card is NumberCard &&
        top.number == card.number &&
        top.color == card.color) {
      pile.add(card);
      await discardRef.set(pile.map((c) => c.toMap()).toList());

      final handSnap = await handRef.get();
      final hand = handSnap.exists ? List<int>.from((handSnap.value as List).map((e) => int.parse(e.toString()))) : <int>[];
      hand.remove(card.id);
      await handRef.set(hand);
    } else {
      await forcePlayerDrawCards(gameId, playerId, 2);
    }
  }

  Future<void> notifyCurrentPlayerToExecuteSnitchAction(
    String gameId,
    String currentPlayerId,
    String targetPlayerId,
    GameCard snitchCard,
  ) async {
    try {
      final gameRef = FirebaseDatabase.instance.ref('games/$gameId');
      await gameRef.child('snitchAction').set({
        'currentPlayerId': currentPlayerId,
        'targetPlayerId': targetPlayerId,
        'snitchCard': snitchCard.toMap(),
      });
    } catch (e) {
      print('Error notifying current player to execute snitch action: $e');
    }
  }

  Future<void> handleActionCardEffect(
    BuildContext? context,
    ActionCard card,
    String gameId,
    String currentPlayerId,
    String targetPlayerId,
  ) async {
    try {
      switch (card.actionType) {
        case ActionType.fiveO:
          await avoidPenalties(gameId, currentPlayerId);
          await updateCounters(gameId, 0, 0);
          await nextTurn(gameId);
          break;

        case ActionType.deuces:
        case ActionType.inYoFace:
          await applyPenaltiesAndResetCounters(gameId, targetPlayerId);
          await skipNextPlayer(gameId); // Skip nach Strafe
          break;

        case ActionType.payback:
          await toggleGameDirection(gameId);
          await advanceToNextPlayer(gameId);
          break;

        case ActionType.busted:
          await skipNextPlayer(gameId);
          break;

        case ActionType.pimpSlap:
          await forceAllOtherPlayersDrawCards(gameId, 3);
          await nextTurn(gameId);
          break;

        case ActionType.deal:
          if (context != null) {
            await tradeHands(gameId, currentPlayerId, targetPlayerId);
          }
          await nextTurn(gameId);
          break;

        case ActionType.snitch:
          if (context != null) {
            await notifyCurrentPlayerToExecuteSnitchAction(
              gameId, currentPlayerId, targetPlayerId, card,
            );
          }
          await nextTurn(gameId);
          break;
      }
    } finally {
      // Reaktionsknoten sicher entfernen
      await _database.ref('games/$gameId/reactions').remove();
    }
  }

  Future<void> playCard(
    BuildContext context,
    String gameId,
    String playerId,
    GameCard card, {
    // Für Bot-Züge: ersetzt den Ziel-Auswahl- bzw. Tausch/Aufdecken-Dialog,
    // der sonst über GameController.instance auf dem BuildContext geöffnet
    // würde — ein Bot-Zug darf nie einen Dialog auf einem fremden
    // Bildschirm öffnen. Menschliche Aufrufer übergeben nichts, dann läuft
    // es exakt wie bisher über die Dialoge.
    Future<String?> Function()? resolveTarget,
    Future<void> Function(String source, String target, ActionCard card)?
        resolveSnitchChoice,
  }) async {
    final gameRef = _database.ref('games/$gameId');
    final discardRef = gameRef.child('gameState/discardPile');
    final playerRef = gameRef.child('players/$playerId/handCardIds');
    final countersRef = gameRef.child('counters');

    // Parallel reads — discard pile and hand are independent
    final snapResults = await Future.wait([discardRef.get(), playerRef.get()]);
    final discardSnap = snapResults[0];
    final handSnap    = snapResults[1];

    List<GameCard> parseDiscardPile(Object? raw) {
      if (raw == null) return [];
      final Iterable<dynamic> items =
          raw is List ? raw : (raw is Map ? raw.values : const []);
      return items
          .map((e) => GameCard.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    final discardPile = parseDiscardPile(discardSnap.exists ? discardSnap.value : null);

    List<int> parseHandIds(Object? raw) {
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => int.parse(e.toString())).toList();
      if (raw is Map) return raw.values.map((e) => int.parse(e.toString())).toList();
      return [];
    }
    final handIds = parseHandIds(handSnap.exists ? handSnap.value : null);

    final lastCard = discardPile.isNotEmpty ? discardPile.last : null;

    // Legal?
    if (lastCard != null && !card.canPlayOnTopOf(lastCard)) {
      await penalty(gameId, playerId);
      return;
    }

    // Batch: discard + hand removal in one round-trip
    discardPile.add(card);
    handIds.remove(card.id);
    await gameRef.update({
      'gameState/discardPile': discardPile.map((c) => c.toMap()).toList(),
      'players/$playerId/handCardIds': handIds,
    });

    // Mic-Check VOR Status: verhindert Strafkarten nach bereits gesetztem 'finished'
    final isDone = await handleMicChecksAndDrop(gameId, playerId);
    if (isDone) await updateGameStatus(gameId);

    // Zahlenkarte → nächster Spieler
    if (card is! ActionCard) {
      await nextTurn(gameId);
      return;
    }

    final action = card;

    // Deal/Snitch haben Sonderziel (wird im Controller per Dialog gewählt)
    if (action.actionType == ActionType.deal || action.actionType == ActionType.snitch) {
      final String? target;
      if (resolveTarget != null) {
        target = await resolveTarget();
      } else {
        // ignore: use_build_context_synchronously
        target = await GameController.instance.selectTargetPlayer(context, gameId, playerId);
      }
      if (target == null || target == playerId) {
        await nextTurn(gameId);
        return;
      }

      final reactables = await getReactableCards(gameId, target, action);
      if (reactables.isNotEmpty) {
        await setReactions(gameId, target, reactables, action, playerId);
        return;
      }

      if (action.actionType == ActionType.snitch) {
        // Show swap/reveal dialog directly on source device; performSnitchAction handles turn advancement
        if (resolveSnitchChoice != null) {
          await resolveSnitchChoice(playerId, target, action);
        } else {
          await GameController.instance.performSnitchAction(gameId, playerId, target, action);
        }
        return;
      }

      // ignore: use_build_context_synchronously
      await handleActionCardEffect(context, action, gameId, playerId, target);
      final isDoneAfterAction = await handleMicChecksAndDrop(gameId, playerId);
      if (isDoneAfterAction) await updateGameStatus(gameId);
      return;
    }

    // Counter für Deuces / InYoFace
    final ctrSnap = await countersRef.get();
    var deucesCounter = (ctrSnap.value as Map?)?['deucesCounter'] ?? 0;
    var inYoFaceCounter = (ctrSnap.value as Map?)?['inYoFaceCounter'] ?? 0;

    // Payback ohne Kette → sofortiger Effekt
    if (action.actionType == ActionType.payback && deucesCounter == 0 && inYoFaceCounter == 0) {
      // ignore: use_build_context_synchronously
      await handleActionCardEffect(context, action, gameId, playerId, '');
      return;
    }

    if (action.actionType == ActionType.deuces) {
      deucesCounter++;
      await updateCounters(gameId, deucesCounter, inYoFaceCounter);
    } else if (action.actionType == ActionType.inYoFace) {
      inYoFaceCounter++;
      await updateCounters(gameId, deucesCounter, inYoFaceCounter);
    }

    // Reaktionsabfrage an den relevanten Zielspieler
    final nextPlayerId = action.actionType == ActionType.payback
        ? await getPreviousPlayerId(gameId)
        : await getNextPlayerId(gameId);

    final reactable = await getReactableCards(gameId, nextPlayerId, action);
    if (reactable.isNotEmpty) {
      await setReactions(gameId, nextPlayerId, reactable, action, playerId);
      return;
    } else {
      // ignore: use_build_context_synchronously
      await handleActionCardEffect(context, action, gameId, playerId, nextPlayerId);
      return;
    }
  }

  Future<bool> handleMicChecksAndDrop(String gameId, String playerId) async {
    final hand = await getPlayerCards(gameId, playerId);
    final count = hand.length;

    if (count == 1) {
      final micSnap = await _database.ref('games/$gameId/gameState/mic/$playerId').get();
      if (!(micSnap.exists && micSnap.value == 'check')) {
        // Return the just-played card + 2 penalty cards
        await _returnTopDiscardToHand(gameId, playerId);
        await forcePlayerDrawCards(gameId, playerId, 2);
      }
      return false;
    }

    if (count == 0) {
      final micSnap = await _database.ref('games/$gameId/gameState/mic/$playerId').get();
      if (micSnap.exists && micSnap.value == 'drop') {
        await markPlayerAsFinished(gameId, playerId);
        return true;
      } else {
        // Return the just-played card + 2 penalty cards
        await _returnTopDiscardToHand(gameId, playerId);
        await forcePlayerDrawCards(gameId, playerId, 2);
        return false;
      }
    }

    return false;
  }

  /// Nimmt die oberste Karte vom Ablagestapel und legt sie zurück in die Hand des Spielers.
  Future<void> _returnTopDiscardToHand(String gameId, String playerId) async {
    final gameRef    = _database.ref('games/$gameId');
    final discardRef = gameRef.child('gameState/discardPile');
    final handRef    = gameRef.child('players/$playerId/handCardIds');

    final results     = await Future.wait([discardRef.get(), handRef.get()]);
    final discardSnap = results[0];
    final handSnap    = results[1];

    if (!discardSnap.exists || discardSnap.value == null) return;

    // Parse discard pile (List or Map)
    final rawPile = discardSnap.value;
    List<dynamic> pileList;
    if (rawPile is List) {
      pileList = List.from(rawPile);
    } else if (rawPile is Map) {
      pileList = rawPile.values.toList();
    } else {
      return;
    }
    if (pileList.isEmpty) return;

    // Top card → back to hand
    final topCardMap = pileList.removeLast() as Map;
    final topCard    = GameCard.fromMap(Map<String, dynamic>.from(topCardMap));

    // Parse hand (List or Map)
    final rawHand = handSnap.exists ? handSnap.value : null;
    List<int> handIds;
    if (rawHand is List) {
      handIds = rawHand.map((e) => int.parse(e.toString())).toList();
    } else if (rawHand is Map) {
      handIds = rawHand.values.map((e) => int.parse(e.toString())).toList();
    } else {
      handIds = [];
    }
    handIds.add(topCard.id);

    await gameRef.update({
      'gameState/discardPile': pileList,
      'players/$playerId/handCardIds': handIds,
    });
  }

  Future<void> markMicCheck(String gameId, String playerId) {
    return _database.ref('games/$gameId/gameState/mic/$playerId').set('check');
    // (Die alten Pfade micChecks/micDrops werden nicht mehr verwendet)
  }

  Future<void> markMicDrop(String gameId, String playerId) {
    return _database.ref('games/$gameId/gameState/mic/$playerId').set('drop');
  }

  Future<String?> getMicStatus(String gameId, String playerId) async {
    final snap = await _database.ref('games/$gameId/gameState/mic/$playerId').get();
    return snap.exists ? snap.value?.toString() : null;
  }

  /// Schickt eine Emoji-Reaktion an alle Mitspieler. Bewusst nur ein fest
  /// vorgegebenes Emoji statt freiem Text — verhindert unangemessene
  /// Kommentare, ohne dass die Interaktion zwischen Spielern ganz fehlt.
  Future<void> sendEmojiReaction(String gameId, String senderId, String emoji) {
    return _database.ref('games/$gameId/gameState/emojiPing').set({
      'senderId': senderId,
      'emoji': emoji,
      'ts': ServerValue.timestamp,
    });
  }

  Future<void> continueReactionChain(
    String gameId,
    String reactingPlayerId,
    ActionCard reactionCard,
  ) async {
    final ref = _database.ref('games/$gameId/reactions');
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.value == null) return;

    final data = Map<String, dynamic>.from(snapshot.value as Map);

    final prevRaw = (data['reactionChain'] as List?) ?? (data['chain'] as List?) ?? [];
    final previous = prevRaw
        .map((m) => GameCard.fromMap(Map<String, dynamic>.from(m as Map)))
        .whereType<ActionCard>()
        .toList();

    final chain = [...previous, reactionCard];

    // Parallel reads — hand and discard pile are independent
    final handRef    = _database.ref('games/$gameId/players/$reactingPlayerId/handCardIds');
    final discardRef = _database.ref('games/$gameId/gameState/discardPile');
    final snapPair   = await Future.wait([handRef.get(), discardRef.get()]);
    final handSnap    = snapPair[0];
    final discardSnap = snapPair[1];

    List<int> parseRawIds(Object? raw) {
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => int.parse(e.toString())).toList();
      if (raw is Map) return raw.values.map((e) => int.parse(e.toString())).toList();
      return [];
    }
    final hand = parseRawIds(handSnap.exists ? handSnap.value : null);
    hand.remove(reactionCard.id);

    List<GameCard> parseRawPile(Object? raw) {
      if (raw == null) return [];
      final Iterable<dynamic> items = raw is List ? raw : (raw is Map ? raw.values : const []);
      return items.map((e) => GameCard.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    }
    final pile = parseRawPile(discardSnap.exists ? discardSnap.value : null);
    pile.add(reactionCard);

    // Batch hand removal + discard update
    await _database.ref('games/$gameId').update({
      'players/$reactingPlayerId/handCardIds': hand,
      'gameState/discardPile': pile.map((c) => c.toMap()).toList(),
    });

    // Five-O cancels the entire penalty chain immediately
    if (reactionCard.actionType == ActionType.fiveO) {
      await updateCounters(gameId, 0, 0);
      await ref.remove();
      // gameState/currentPlayerId is never updated when a reaction is first
      // offered (setReactions only writes the reactions node), so it can
      // still point at the original source player here. Pin it to the
      // player who just reacted before advancing, otherwise
      // advanceToNextPlayer resumes from the source and hands the turn
      // right back to the reactor instead of the player after them.
      await _database.ref('games/$gameId/gameState/currentPlayerId').set(reactingPlayerId);
      await advanceToNextPlayer(gameId);
      return;
    }

    // Nächstes Ziel (Payback → zurück an Source)
    final nextTarget = reactionCard.actionType == ActionType.payback
        ? data['sourcePlayerId'].toString()
        : await getNextPlayerRelativeTo(gameId, reactingPlayerId);

    final hasDeucesBefore = previous.any((c) => c.actionType == ActionType.deuces);

    // Reaktionskarten sammeln
    List<GameCard> newReactables;
    if (reactionCard.actionType == ActionType.payback && !hasDeucesBefore) {
      newReactables = [];
    } else if (reactionCard.actionType == ActionType.payback && hasDeucesBefore) {
      final handIds = await getPlayerHandCardIds(gameId, nextTarget);
      final cards = await Future.wait(handIds.map((id) => getCardById(gameId, id)));
      newReactables = cards.whereType<ActionCard>().where((c) => c.canRespondWith(reactionCard)).toList();
    } else {
      newReactables = await getReactableCards(gameId, nextTarget, reactionCard);
    }

    final newRid = DateTime.now().millisecondsSinceEpoch.toString();

    if (newReactables.isNotEmpty) {
      final updates = {
        'reactionId': newRid,
        'sourcePlayerId': reactingPlayerId,
        'targetPlayerId': nextTarget,
        'reactableCards': newReactables.map((c) => c.toMap()).toList(),
        'handled': false,
        'reactionChain': chain.map((c) => c.toMap()).toList(),
      };

      if (reactionCard.actionType == ActionType.payback && data['penaltyTarget'] == null) {
        updates['penaltyTarget'] = data['sourcePlayerId'].toString();
      }

      await ref.set(updates);
      await _database.ref('games/$gameId/gameState/currentPlayerId').set(nextTarget);
    } else {
      // Ende der Kette — Strafen direkt aus der Kettle zählen (alle Karten, nicht nur die letzte)
      final deucesCount = chain.where((c) => c.actionType == ActionType.deuces).length;
      final inYoCount   = chain.where((c) => c.actionType == ActionType.inYoFace).length;
      final total = deucesCount * 2 + inYoCount * 5;

      String penaltyReceiver;
      if (reactionCard.actionType == ActionType.payback) {
        await toggleGameDirection(gameId);
        penaltyReceiver = (data['penaltyTarget']?.toString()) ?? data['sourcePlayerId'].toString();
      } else {
        penaltyReceiver = await getNextPlayerRelativeTo(gameId, reactingPlayerId);
      }

      // Counter immer zurücksetzen — egal ob Strafen anfallen oder nicht
      await updateCounters(gameId, 0, 0);

      if (total > 0) {
        await forcePlayerDrawCards(gameId, penaltyReceiver, total);
        final after = await getNextPlayerRelativeTo(gameId, penaltyReceiver);
        await _database.ref('games/$gameId/gameState/currentPlayerId').set(after);
      } else {
        // Same stale-currentPlayerId issue as the Five-O branch above:
        // pin it to the reactor before advancing.
        await _database.ref('games/$gameId/gameState/currentPlayerId').set(reactingPlayerId);
        await advanceToNextPlayer(gameId);
      }

      await ref.remove();
    }
  }

  Future<String> getNextPlayerRelativeTo(String gameId, String? fromPlayerId) async {
    final ref = _database.ref('games/$gameId/gameState');
    final snap = await ref.get();
    if (!snap.exists || fromPlayerId == null) throw Exception("Fehlender Spielstatus oder Zielspieler.");

    final data = Map<String, dynamic>.from(snap.value as Map);
    final order = List<String>.from((data['playerOrder'] as List).map((e) => e.toString()));
    final clockwise = (data['isClockwise'] ?? true) == true;

    int index = order.indexOf(fromPlayerId);
    if (index == -1) throw Exception("Spieler nicht gefunden");

    final nextIndex = clockwise ? (index + 1) % order.length : (index - 1 + order.length) % order.length;
    return order[nextIndex];
  }

  Future<List<GameCard>> getPlayerCards(String gameId, String playerId) async {
    final ids = await getPlayerHandCardIds(gameId, playerId);
    if (ids.isEmpty) return [];
    final results = await Future.wait(ids.map((id) async {
      try {
        return await getCardById(gameId, id);
      } catch (_) {
        return null;
      }
    }));
    return results.whereType<GameCard>().toList();
  }

  Future<String> getPreviousPlayerId(String gameId) async {
    final ref = _database.ref('games/$gameId/gameState');
    final snap = await ref.get();
    if (!snap.exists || snap.value == null) throw Exception('Spielzustand nicht gefunden');

    final data = Map<String, dynamic>.from(snap.value as Map);
    final order = List<String>.from((data['playerOrder'] as List).map((e) => e.toString()));
    final clockwise = (data['isClockwise'] ?? true) == true;
    final current = data['currentPlayerId'].toString();

    final idx = order.indexOf(current);
    final prevIdx = clockwise ? (idx - 1 + order.length) % order.length : (idx + 1) % order.length;
    return order[prevIdx];
  }

  Future<void> penalty(String gameId, String playerId) async {
    await forcePlayerDrawCards(gameId, playerId, 2);
    await nextTurn(gameId);
  }

  Future<void> setTargetPlayer(String gameId, String targetPlayerId) async {
    await _database.ref('games/$gameId/targetPlayerId').set(targetPlayerId);
  }

  Future<void> setReactions(
    String gameId,
    String targetPlayerId,
    List<GameCard> reactableCards,
    ActionCard playedCard,
    String sourcePlayerId,
  ) async {
    final ref = _database.ref('games/$gameId/reactions');
    final reactionId = DateTime.now().millisecondsSinceEpoch.toString();

    await ref.set({
      'reactionId': reactionId,
      'sourcePlayerId': sourcePlayerId,
      'targetPlayerId': targetPlayerId,
      'reactableCards': reactableCards.map((c) => c.toMap()).toList(),
      'handled': false,
      'reactionChain': [playedCard.toMap()],
    });
  }

  Future<List<GameCard>> getReactableCards(String gameId, String playerId, ActionCard playedCard) async {
    final handCardIds = await getPlayerHandCardIds(gameId, playerId);
    final cards = await Future.wait(handCardIds.map((id) => getCardById(gameId, id)));

    return cards.where((card) {
      if (card is! ActionCard) return false;
      if (playedCard.actionType == ActionType.payback && card.actionType == ActionType.inYoFace) {
        return false; // Payback darf NICHT auf InYoFace reagieren
      }
      return card.canRespondWith(playedCard);
    }).toList();
  }

  Future<List<int>> getPlayerHandCardIds(String gameId, String playerId) async {
    final snap = await _database.ref('games/$gameId/players/$playerId/handCardIds').get();
    if (!snap.exists || snap.value == null) return [];
    final raw = snap.value;
    Iterable<dynamic> items;
    if (raw is List) {
      items = raw;
    } else if (raw is Map) {
      items = raw.values;
    } else {
      return [];
    }
    return items.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
  }

  Future<void> performPaybackAction(String gameId) async {
    final previousPlayerId = await getPreviousPlayerId(gameId);
    await setPenaltyTarget(gameId, previousPlayerId);
    await toggleGameDirection(gameId);
  }

  Future<void> setPenaltyTarget(String gameId, String playerId) async {
    await _database.ref('games/$gameId/reactions/penaltyTarget').set(playerId);
  }

  Future<void> avoidPenalties(String gameId, String playerId) async {
    await updateCounters(gameId, 0, 0);
    await _database.ref('games/$gameId/reactions').remove();
  }

  Future<void> tradeHands(String gameId, String playerOneId, String playerTwoId) async {
    final gameRef = _database.ref('games/$gameId');

    final results = await Future.wait([
      gameRef.child('players/$playerOneId/handCardIds').get(),
      gameRef.child('players/$playerTwoId/handCardIds').get(),
    ]);

    List<int> parseIds(Object? raw) {
      if (raw == null) return [];
      if (raw is List) return raw.map((e) => int.parse(e.toString())).toList();
      if (raw is Map) return raw.values.map((e) => int.parse(e.toString())).toList();
      return [];
    }

    final handOne = parseIds(results[0].exists ? results[0].value : null);
    final handTwo = parseIds(results[1].exists ? results[1].value : null);

    await gameRef.update({
      'players/$playerOneId/handCardIds': handTwo,
      'players/$playerTwoId/handCardIds': handOne,
    });
  }

  Future<void> skipNextPlayer(String gameId) async {
    final stateRef = _database.ref('games/$gameId/gameState');
    final snap = await stateRef.get();
    if (!snap.exists || snap.value == null) return;

    final data = Map<String, dynamic>.from(snap.value as Map);
    final order = List<String>.from(
      (data['playerOrder'] as List? ?? []).map((e) => e.toString()),
    );
    final clockwise = (data['isClockwise'] ?? true) == true;
    final current = (data['currentPlayerId'] ?? '').toString();
    final turn = (data['turn'] is int) ? data['turn'] as int : 0;

    if (order.length < 2) return;
    final idx = order.indexOf(current);
    if (idx < 0) return;

    final skipIdx = clockwise
        ? (idx + 2) % order.length
        : (idx - 2 + order.length) % order.length;

    await stateRef.update(_sanitizeUpdateMap({
      'currentPlayerId': order[skipIdx],
      'turn': turn + 1,
      'remainingTime': 20,
    }));
  }

  Future<List<Player>> fetchPlayers(String gameId) async {
    final ref = _database.ref('games/$gameId/players');
    final snap = await ref.get();
    if (!snap.exists || snap.value == null) return [];
    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    final players = <Player>[];
    data.forEach((key, value) {
      players.add(Player.fromMap(Map<String, dynamic>.from(value as Map), key.toString()));
    });
    return players;
  }

  Future<void> swapHandCard(
    String gameId,
    String requestingPlayerId,
    String targetPlayerId,
    GameCard ownCard,
    GameCard targetCard,
  ) async {
    final gameRef = _database.ref('games/$gameId');

    final results = await Future.wait([
      gameRef.child('players/$requestingPlayerId/handCardIds').get(),
      gameRef.child('players/$targetPlayerId/handCardIds').get(),
    ]);
    if (!results[0].exists || !results[1].exists) throw Exception('Spielerdaten nicht gefunden');

    List<int> parseIds(Object? raw) {
      if (raw is List) return raw.map((e) => int.parse(e.toString())).toList();
      if (raw is Map) return raw.values.map((e) => int.parse(e.toString())).toList();
      return [];
    }

    final handOwn = parseIds(results[0].value);
    final handTar = parseIds(results[1].value);

    final iOwn = handOwn.indexOf(ownCard.id);
    final iTar = handTar.indexOf(targetCard.id);
    if (iOwn == -1 || iTar == -1) throw Exception('Karten nicht in Spielerhand gefunden');

    handOwn[iOwn] = targetCard.id;
    handTar[iTar] = ownCard.id;

    await gameRef.update({
      'players/$requestingPlayerId/handCardIds': handOwn,
      'players/$targetPlayerId/handCardIds': handTar,
    });
  }

  Future<void> forceNextPlayerDrawCards(String gameId, int numberOfCards, String currentPlayerId) async {
    final gameRef = _database.ref('games/$gameId');
    final deckRef = gameRef.child('gameState/deck');
    final playersRef = gameRef.child('players');

    final deckSnapshot = await deckRef.get();
    if (!deckSnapshot.exists || deckSnapshot.value == null) return;

    var deckCardIds = List<int>.from((deckSnapshot.value as List).map((e) => int.parse(e.toString())));
    if (deckCardIds.length < numberOfCards) return;

    final nextPlayerId = await getNextPlayerId(gameId);
    final nextHandRef = playersRef.child(nextPlayerId).child('handCardIds');

    final handSnapshot = await nextHandRef.get();
    final nextHand = handSnapshot.exists && handSnapshot.value != null
        ? List<int>.from((handSnapshot.value as List).map((e) => int.parse(e.toString())))
        : <int>[];

    final drawn = <int>[];
    for (int i = 0; i < numberOfCards; i++) {
      drawn.add(deckCardIds.removeLast());
    }
    nextHand.addAll(drawn);

    await deckRef.set(deckCardIds);
    await nextHandRef.set(nextHand);
  }

  Future<void> forcePlayerDrawCards(String gameId, String playerId, int numberOfCards) async {
    // Skip penalty for players who have already finished
    final activeSnap = await _database.ref('games/$gameId/players/$playerId/isActive').get();
    if (activeSnap.exists && activeSnap.value == false) return;

    final deckRef = _database.ref('games/$gameId/gameState/deck');
    final handRef = _database.ref('games/$gameId/players/$playerId/handCardIds');

    List<int>? drawn;
    await deckRef.runTransaction((current) {
      if (current == null) return Transaction.abort();
      final ids = List<int>.from((current as List).map((e) => int.parse(e.toString())));
      final count = min(numberOfCards, ids.length);
      if (count == 0) return Transaction.abort();
      drawn = ids.sublist(ids.length - count);
      ids.removeRange(ids.length - count, ids.length);
      return Transaction.success(ids);
    });

    if (drawn == null || drawn!.isEmpty) return;
    final toAdd = List<int>.unmodifiable(drawn!);

    await handRef.runTransaction((current) {
      final hand = current == null
          ? <int>[]
          : List<int>.from((current as List).map((e) => int.parse(e.toString())));
      hand.addAll(toAdd);
      return Transaction.success(hand);
    });
  }

  Future<void> forceAllOtherPlayersDrawCards(String gameId, int numberOfCards) async {
    final gameRef = _database.ref('games/$gameId');
    final deckRef = gameRef.child('gameState/deck');
    final playersRef = gameRef.child('players');
    final currentRef = gameRef.child('gameState/currentPlayerId');

    final currentPlayerId = (await currentRef.get()).value.toString();
    final deckSnapshot = await deckRef.get();
    if (!deckSnapshot.exists || deckSnapshot.value == null) return;

    var deckCardIds = List<int>.from((deckSnapshot.value as List).map((e) => int.parse(e.toString())));
    final playersSnapshot = await playersRef.get();
    if (!playersSnapshot.exists || playersSnapshot.value == null) return;

    final batch = <String, dynamic>{};
    for (final entry in (playersSnapshot.value as Map).entries) {
      final pid = entry.key.toString();
      if (pid == currentPlayerId) continue;

      final playerHand = List<int>.from(
        (entry.value['handCardIds'] as List?)?.map((e) => int.parse(e.toString())) ?? <int>[],
      );
      for (int i = 0; i < numberOfCards && deckCardIds.isNotEmpty; i++) {
        playerHand.add(deckCardIds.removeLast());
      }
      batch['players/$pid/handCardIds'] = playerHand;
    }
    batch['gameState/deck'] = deckCardIds;

    await gameRef.update(batch);
  }
}
