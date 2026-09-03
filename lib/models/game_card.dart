import 'package:hp_card_game/models/number_card.dart';

import 'action_card.dart';
import 'card_color.dart';
abstract class GameCard {
  final CardColor color;
  final int id; // Eine eindeutige ID für jede Karte

  GameCard(this.color, this.id);

  bool canPlayOnTopOf(GameCard card) {
    // Basislogik: Eine Karte kann auf eine andere Karte gelegt werden, wenn sie die gleiche Farbe hat
    return color == card.color;
  }

  Map<String, dynamic> toMap();

  String get imagePath; // Deklariere einen Getter für den Bildpfad

  // In GameCard als statische Methode
static GameCard back() {
  // Verwendet eine spezielle ID oder Farbe, um eine Rückseiten-Karte zu kennzeichnen
  return BackCard(); // Beispiel, wähle geeignete Werte
}

static GameCard blank() {
  // Verwendet eine spezielle ID oder Farbe, um eine Leer-Karte zu kennzeichnen
  return BackCard(); // Beispiel, wähle geeignete Werte
}

 static GameCard fromMap(Map<String, dynamic> map) {
  if (!map.containsKey('type')) {
    throw Exception('Kartentyp fehlt in Map: $map');
  }
  
  var type = map['type'];
  // Stellen Sie sicher, dass 'id' als int gelesen wird.
  var id = int.parse(map['id'].toString());
  
  if (type == 'NumberCard') {
    return NumberCard.fromMap(map..['id'] = id); // Stellen Sie sicher, dass die 'id' als int übergeben wird.
  } else if (type == 'ActionCard') {
    return ActionCard.fromMap(map..['id'] = id); // Stellen Sie sicher, dass die 'id' als int übergeben wird.
  } else {
    throw Exception('Unbekannter Karten-Typ: $type');
  }
}

  
}




// Neue Klasse BackCard, die von GameCard erbt
class BackCard extends GameCard {
  BackCard() : super(CardColor.green, -1);

  @override
  Map<String, dynamic> toMap() {
    // Diese Methode könnte leer sein, da BackCard nicht in Datenbank oder Ähnliches gespeichert wird.
    return {};
  }

  @override
  String get imagePath {
    // Pfad zum Bild der Rückseite der Karten
    return 'path/to/back/card/image.png';
  }
}
