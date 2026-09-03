// ignore_for_file: file_names
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hp_card_game/models/player.dart';

import 'game_card.dart';
class GameData {
  final String gameId;
  final List<Player> players;
  final String currentPlayerId;
  final List<int> deck;
  final List<GameCard> discardPile;
  final String gameState;
  final int turn;
  final String? targetPlayerId; // Ziel-Spieler für Reaktionen
  final List<GameCard>? reactableCards; // Reaktionsfähige Karten
  final bool isClockwise;  // Spielrichtung hinzugefügt
  final List<String> playerOrder;  // Spielerreihenfolge hinzugefügt

  GameData({
    required this.gameId,
    required this.players,
    required this.currentPlayerId,
    required this.deck,
    required this.discardPile,
    required this.gameState,
    required this.turn,
    required this.isClockwise,
    required this.playerOrder,
    this.targetPlayerId,
    this.reactableCards,
  });

  factory GameData.fromSnapshot(DataSnapshot snapshot) {
      if (snapshot.value == null) {
    throw Exception('Snapshot value is null');
  }

     Map<String, dynamic> value = Map<String, dynamic>.from(snapshot.value as Map);
    List<Player> players = []; // Logik zum Parsen der Spieler
    List<int> deckIds = []; // Logik zum Parsen des Decks
    List<GameCard> discardPile = []; // Logik zum Parsen des Ablagestapels
    String gameState = 'waiting for players'; // Standardwert für gameState
    int turn = 0; // Standardwert für turn
    String? targetPlayerId;
    List<GameCard>? reactableCards;
    bool isClockwise = value['gameState']['isClockwise'] ?? true;  // Standardwert ist true
    List<String> playerOrder = List<String>.from(value['gameState']['playerOrder'] ?? []);

    if (value['targetPlayerId'] != null) {
      targetPlayerId = value['targetPlayerId'];
    }
    if (value['reactableCards'] != null) {
      reactableCards = (value['reactableCards'] as List).map((data) => GameCard.fromMap(data)).toList();
    }

    // Beispiel für das Parsen der Spieler
    if (value['players'] != null) {
      Map<String, dynamic> playersData = value['players'];
      players = playersData.entries.map((entry) => Player.fromMap(entry.value, entry.key)).toList();
    }

    // Beispiel für das Parsen des Decks
    if (value['gameState']['deck'] is List) {
    // Extrahieren Sie die IDs und konvertieren Sie sie in GameCard-Objekte, falls nötig
    deckIds = List<int>.from(value['gameState']['deck']);
  }

    // Beispiel für das Parsen des Ablagestapels
    if (value.containsKey('gameState') && value['gameState'].containsKey('discardPile')) {
      List<dynamic> discardPileData = value['gameState']['discardPile'];
      discardPile = discardPileData.map((data) => GameCard.fromMap(data)).toList();
    }

    // Parsen des currentPlayerId
    String currentPlayerId = '';
    if (value['gameState'] != null && value['gameState']['currentPlayerId'] != null) {
      currentPlayerId = value['gameState']['currentPlayerId'].toString();
      debugPrint('Current Player ID raw value: ${value['gameState']['currentPlayerId']}');
      debugPrint('Converted Current Player ID: $currentPlayerId');

    }

    // Parsen von gameState und turn
    if (value.containsKey('gameState')) {
      gameState = value['gameState']['state'] ?? gameState;
      turn = int.tryParse(value['gameState']['turn'].toString()) ?? turn;
    }

    return GameData(
      gameId: snapshot.key ?? '',
      players: players,
      currentPlayerId: currentPlayerId,
      deck: deckIds,
      discardPile: discardPile,
      gameState: gameState,
      turn: turn,
      targetPlayerId: targetPlayerId,
      reactableCards: reactableCards,
      isClockwise: isClockwise,
      playerOrder: playerOrder,
    );
  }
}

