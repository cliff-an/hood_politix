// widgets/reveal_card_dialog.dart

import 'package:flutter/material.dart';
import '../models/game_card.dart';
import '../models/card_image_factory.dart'; // <<< neu

class RevealCardDialog extends StatelessWidget {
  final List<GameCard> targetCards;
  final Future<void> Function(GameCard) onCardRevealed;

  const RevealCardDialog({
    required this.targetCards,
    required this.onCardRevealed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Karte zeigen'),
      content: SingleChildScrollView(
        child: Column(
          children: targetCards.map((card) {
            final imagePath = CardImageFactory.getCardImagePath(card);
            return ListTile(
              leading: Image.asset(
                imagePath,
                width: 48,
                height: 72,
                fit: BoxFit.contain,
              ),
              title: Text(card.toString()),
              onTap: () => onCardRevealed(card),
            );
          }).toList(),
        ),
      ),
    );
  }
}
