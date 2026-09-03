import 'package:hp_card_game/models/number_card.dart';

import 'action_card.dart';
import 'game_card.dart';
class CardImageFactory {
  static String getCardImagePath(GameCard card) {
    String basePath = 'lib/images/';
    if(card is BackCard){
      return '$basePath/back_card.png';
    }

    if (card is NumberCard) {
      // Für NumberCards, z.B. "green_1.png"
      return '$basePath${card.color.name}_${card.number}.png';
    } else if (card is ActionCard) {
      // Für ActionCards, z.B. "busted_green.png"
      return '$basePath${card.actionType.name}_${card.color.name}.png';
    }


    // Standardbild, falls keines der obigen zutrifft
    return '$basePath/back_card.png';
  }
}
