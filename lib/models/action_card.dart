import 'package:hp_card_game/models/game_card.dart';

import 'card_action_type.dart';
import 'card_color.dart';
class ActionCard extends GameCard {
  final ActionType actionType;

  ActionCard(super.color, super.id, this.actionType);

  @override
  bool canPlayOnTopOf(GameCard card) {
      if (actionType == ActionType.inYoFace ||
          actionType == ActionType.fiveO ||
          actionType == ActionType.pimpSlap ||
          actionType == ActionType.deal ||
          actionType == ActionType.snitch) {
        // Diese Aktionskarten können auf jede Karte gelegt werden
        return true;
      } else if (actionType == ActionType.busted ||
                actionType == ActionType.deuces ||
                actionType == ActionType.payback) {
        // Busted, Deuces, und Payback müssen entweder die gleiche Farbe oder den gleichen Typ haben
        return color == card.color || (card is ActionCard && actionType == card.actionType);
      } else {
        // Fallback zur Basislogik
        return super.canPlayOnTopOf(card);
      }
    }

     // Methode zur Überprüfung möglicher Reaktionen
  bool canRespondWith(GameCard playedCard) {
  if (playedCard is! ActionCard) return false;

  switch (playedCard.actionType) {
    case ActionType.deuces:
      return actionType == ActionType.deuces
          || (actionType == ActionType.payback && color == playedCard.color)
          || actionType == ActionType.fiveO
          || actionType == ActionType.inYoFace;

    case ActionType.inYoFace:
      return actionType == ActionType.inYoFace
          || actionType == ActionType.fiveO;

    case ActionType.payback:
      return actionType == ActionType.payback // Farbe egal
          || actionType == ActionType.fiveO
          || actionType == ActionType.inYoFace;

    case ActionType.deal:
    case ActionType.snitch:
      return actionType == ActionType.fiveO;

    default:
      return false;
  }
}


  @override
  Map<String, dynamic> toMap() {
    return {
      'type': 'ActionCard',
      'color': color.toString().split('.').last,
      'id': id,
      'actionType': actionType.toString().split('.').last,
    };
  }

  @override
  String get imagePath => 'path/to/action/card/$color/${actionType.name}.png'; // Beispiel-Pfad

  static ActionCard fromMap(Map<String, dynamic> map) {
    // Wir nehmen an, dass die Überprüfung des Typs bereits in GameCard.fromMap durchgeführt wurde
    var color = CardColor.values.firstWhere(
      (c) => c.toString().split('.').last == map['color'],
      orElse: () => throw Exception('Unbekannte Farbe: ${map['color']}'),
    );
    var actionType = ActionType.values.firstWhere(
      (a) => a.toString().split('.').last == map['actionType'],
      orElse: () => throw Exception('Unbekannter Aktionstyp: ${map['actionType']}'),
    );
    var id = int.parse(map['id'].toString());
    return ActionCard(
      color,
      id,
      actionType,
    );
  }
    @override
  String toString() {
    // Gibt den ActionType und die Farbe der Karte als String zurück
    return "${actionType.name} ${color.name}";
  }
}
