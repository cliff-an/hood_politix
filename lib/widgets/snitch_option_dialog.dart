// widgets/snitch_option_dialog.dart

import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_card.dart';

enum SnitchChoice { swap, reveal }

class SnitchOptionDialog extends StatelessWidget {
  final void Function(SnitchChoice choice) onChosen;
  const SnitchOptionDialog({ required this.onChosen, super.key, required Future<Null> Function(int cardId) onReveal, required Future<Null> Function(GameCard myCard, GameCard targetCard) onSwap });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Snitch-Aktion'),
      content: const Text('Möchtest du eine Karte tauschen oder eine Karte des Gegners zeigen?'),
      actions: [
        TextButton(
          onPressed: () {
            onChosen(SnitchChoice.reveal);
            // kein pop(): Dialog bleibt offen, bis nachfolgender Dialog geschlossen wird
          },
          child: const Text('Karte zeigen'),
        ),
        TextButton(
          onPressed: () {
            onChosen(SnitchChoice.swap);
          },
          child: const Text('Karte tauschen'),
        ),
      ],
    );
  }
}
