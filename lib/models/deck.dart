import 'dart:math';

import 'action_card.dart';
import 'card_action_type.dart';
import 'card_color.dart';
import 'game_card.dart';
import 'number_card.dart';

class Deck {
  final List<GameCard> _cards = [];

  Deck() {
    initializeDeck();
  }
 Deck.empty();
  List<GameCard> get cards => _cards;

  /// Wie ein normales, zufällig gemischtes Deck — nur dass sichergestellt
  /// wird, dass unter den obersten [topWindow] Karten (deckt die
  /// Start-Hände + die ersten paar Zieh-Aktionen ab; Karten werden vom
  /// Ende der Liste gezogen, s. [draw]) mindestens [minActionCards]
  /// Aktionskarten liegen. Für den Tutorial-Modus, damit Aktionskarten
  /// früh im Spiel auftauchen, ohne eine feste Kartenreihenfolge
  /// vorzuschreiben — der Rest bleibt komplett zufällig.
  factory Deck.shuffledWithActionBias({int topWindow = 28, int minActionCards = 10}) {
    final deck = Deck();
    final cards = deck._cards;
    final n = cards.length;
    final windowStart = (n - topWindow).clamp(0, n);
    final rng = Random();

    int countActionInWindow() =>
        cards.sublist(windowStart).whereType<ActionCard>().length;

    while (countActionInWindow() < minActionCards) {
      final actionIndicesBeforeWindow = [
        for (var i = 0; i < windowStart; i++)
          if (cards[i] is ActionCard) i,
      ];
      final numberIndicesInWindow = [
        for (var i = windowStart; i < n; i++)
          if (cards[i] is NumberCard) i,
      ];
      if (actionIndicesBeforeWindow.isEmpty || numberIndicesInWindow.isEmpty) {
        break; // nicht genug Material zum Tauschen — bleibt einfach zufällig
      }
      final fromIdx = actionIndicesBeforeWindow[rng.nextInt(actionIndicesBeforeWindow.length)];
      final toIdx = numberIndicesInWindow[rng.nextInt(numberIndicesInWindow.length)];
      final tmp = cards[fromIdx];
      cards[fromIdx] = cards[toIdx];
      cards[toIdx] = tmp;
    }
    return deck;
  }

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
