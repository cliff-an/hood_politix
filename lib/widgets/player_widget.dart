// Das PlayerWidget könnte so aussehen:
import 'package:flutter/material.dart';

class PlayerWidget extends StatelessWidget {
  final String playerId;
  final String playerName;
  final int cardCount;
  final bool isCurrentPlayer;

  const PlayerWidget({
    super.key,
    required this.playerId,
    required this.playerName,
    required this.cardCount,
    this.isCurrentPlayer = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isCurrentPlayer ? Colors.green : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(playerName, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(cardCount, (index) => const Icon(Icons.credit_card, size: 20)),
            ),
          ],
        ),
      ),
    );
  }
}