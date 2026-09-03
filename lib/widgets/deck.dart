import 'dart:math';

import 'package:hp_card_game/models/game_card.dart';
import 'package:hp_card_game/models/action_card.dart';
import 'package:hp_card_game/models/card_action_type.dart';
import 'package:hp_card_game/models/card_color.dart';
import 'package:hp_card_game/models/number_card.dart';
class Deck {
  final List<GameCard> _cards = [];

  Deck() {
    initializeDeck();
  }
 Deck.empty();
  List<GameCard> get cards => _cards;

  void initializeDeck() {
    _cards.clear(); // Sicherstellen, dass das Deck zu Beginn leer ist
    int id = 1; // Eindeutige ID für jede Karte

    for (var color in CardColor.values) {
      // Zahlenkarten
      for (int number = 1; number <= 10; number++) {
        // Annahme: Jede Zahl erscheint viermal pro Farbe im Deck
        _cards.add(NumberCard(color, id++, number));
        _cards.add(NumberCard(color, id++, number));
        _cards.add(NumberCard(color, id++, number));
        _cards.add(NumberCard(color, id++, number));
      }

      // Aktionskarten
      Map<ActionType, int> actionCardCounts = {
        ActionType.deal: 2,
        ActionType.busted: 2,
        ActionType.payback: 2,
        ActionType.deuces: 2,
        ActionType.inYoFace: 2,
        ActionType.snitch: 2,
        ActionType.pimpSlap: 2,
        ActionType.fiveO: 2,
      };

      actionCardCounts.forEach((type, count) {
        for (int i = 0; i < count; i++) {
          _cards.add(ActionCard(color, id++, type));
        }
      });
    }
    shuffle();
  }

  void updateWith(List<GameCard> newCards) {
  _cards.clear();
  _cards.addAll(newCards);
}


  void shuffle() {
    var rng = Random();
    for (int i = _cards.length - 1; i > 0; i--) {
      int n = rng.nextInt(i + 1);
      var temp = _cards[i];
      _cards[i] = _cards[n];
      _cards[n] = temp;
    }
  }

  Map<String, dynamic> toMap() {
    // Konvertiere jede Karte in deinem Deck zu einer Map und speichere diese in einer Liste
    List<Map<String, dynamic>> cardsMap = cards.map((card) => card.toMap()).toList();

    // Gebe eine Map zurück, die deine Liste von Karten-Maps enthält
    return {
      'cards': cardsMap,
    };
  }

  GameCard draw() {
    if (_cards.isNotEmpty) {
      return _cards.removeLast();
    } else {
      throw Exception('Der Kartenstapel ist leer.');
    }
  }

  List<GameCard> drawMultiple(int count) {
    List<GameCard> drawnCards = [];
    for (int i = 0; i < count && cards.isNotEmpty; i++) {
      drawnCards.add(cards.removeLast());
    }
    return drawnCards;
  }

  bool get isEmpty => _cards.isEmpty;

  

  void reset() {
    _cards.clear();
    initializeDeck(); // Erneutes Initialisieren des Decks
  }
}
