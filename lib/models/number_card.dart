import 'package:hp_card_game/models/card_color.dart';

import 'action_card.dart';
import 'game_card.dart';
class NumberCard extends GameCard {
  final int number;
  String basePath = 'lib/images/';

  NumberCard(super.color, super.id, this.number);

  @override
  bool canPlayOnTopOf(GameCard card) {
  if (card is NumberCard) {
    return number == card.number || color == card.color;
  } else if (card is ActionCard) {
    // Prüft, ob die NumberCard auf ActionCards gelegt werden kann, basierend auf Farbübereinstimmung
    return color == card.color; // oder weitere spezifische Regeln
  }
  return false;
}

   @override
  Map<String, dynamic> toMap() {
    return {
      'type': 'NumberCard',
      'color': color.toString().split('.').last,
      'id': id,
      'number': number,
    };
  }

  @override
  String get imagePath => 'path/to/number/card/$color/$number.png'; // Beispiel-Pfad

  // In der NumberCard-Klasse
static NumberCard fromMap(Map<String, dynamic> map) {
    // Wir nehmen an, dass die Überprüfung des Typs bereits in GameCard.fromMap durchgeführt wurde
    var color = CardColor.values.firstWhere(
      (c) => c.toString().split('.').last == map['color'],
      orElse: () => throw Exception('Unbekannte Farbe: ${map['color']}'),
    );
    var id = int.parse(map['id'].toString());
    return NumberCard(
      color,
      id,
      map['number'],
    );
  }
   @override
  String toString() {
    // Gibt die Nummer und Farbe der Karte als String zurück
    return "$number ${color.name}";
  }
}
