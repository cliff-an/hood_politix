import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hp_card_game/models/firebase_service.dart';
class DeckWidget extends StatelessWidget {
  final bool isEnabled;
  final String gameId;

  const DeckWidget({
    super.key,
    required this.isEnabled,
    required this.gameId,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (isEnabled) {
          FirebaseService.instance.drawCardForCurrentPlayer(gameId, FirebaseAuth.instance.currentUser!.uid);

          FirebaseService.instance.advanceToNextPlayer(gameId);

          FirebaseService.instance.nextTurn(gameId);

        }
      },
      child: Container(
        width: 100,
        height: 150,
        decoration: BoxDecoration(
          image: const DecorationImage(
            image: AssetImage('lib/images/back_card.png'), // Stelle sicher, dass der Pfad stimmt
            fit: BoxFit.cover,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}