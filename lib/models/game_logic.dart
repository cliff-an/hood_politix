import 'package:hp_card_game/models/action_card.dart';
import 'package:hp_card_game/models/game_card.dart';

class GameLogic {
  static bool canRespondWith(ActionCard playedCard, GameCard responseCard) {
    // Implementieren Sie die Logik hier basierend auf den Spielregeln
    return responseCard is ActionCard &&
           responseCard.color == playedCard.color;  // Beispiellogik
  }
}
