import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_card.dart';
import '/models/firebase_service.dart';
import '/widgets/dialog_manager.dart';
import '../models/card_image_factory.dart';
import '../widgets/mic_action_button.dart';

/// Dialog, der erscheint, wenn ein Spieler auf eine Aktionskarte reagieren kann.
class ReactionDialog extends StatelessWidget {
  final List<GameCard> reactableCards;
  final Future<void> Function(GameCard) onCardSelected;
  final Future<void> Function() onNoReaction;

  const ReactionDialog({
    super.key,
    required this.reactableCards,
    required this.onCardSelected,
    required this.onNoReaction,
  });

  @override
  Widget build(BuildContext context) {
    final myId = FirebaseAuth.instance.currentUser!.uid;
    final gameId = DialogManager.currentGameId!; // sicheres Game-Id-Handling

    return AlertDialog(
      title: const Text('Reaktion wählen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- Auswahl der möglichen Reaktionskarten ----
            if (reactableCards.isNotEmpty)
              ...reactableCards.map(
                (card) => ListTile(
                  leading: Image.asset(
                    CardImageFactory.getCardImagePath(card),
                    width: 50,
                  ),
                  title: Text(card.toString()),
                  onTap: () async {
                    await onCardSelected(card);
                    DialogManager.closeDialog();
                  },
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Keine passende Reaktionskarte vorhanden.'),
              ),

            const SizedBox(height: 16),

            // ---- Mic-Button (Check/Drop) dynamisch anzeigen ----
            StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance
                  .ref('games/$gameId/players/$myId/handCardIds')
                  .onValue,
              builder: (ctx, handSnap) {
                final handList =
                    handSnap.data?.snapshot.value as List<dynamic>? ?? [];
                final cardCount = handList.length;

                return StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref('games/$gameId/gameState/mic/$myId')
                      .onValue,
                  builder: (ctx2, micSnap) {
                    final micStatus = micSnap.data?.snapshot.value as String?;

                    // Wenn Spieler 2 oder 1 Karten hat und noch kein Mic-Status gesetzt ist:
                    if ((cardCount == 2 || cardCount == 1) &&
                        micStatus == null) {
                      final isCheck = cardCount == 2;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: MicActionButton(
                          isCheck: isCheck,
                          onPressed: () {
                            if (isCheck) {
                              FirebaseService.instance
                                  .markMicCheck(gameId, myId);
                            } else {
                              FirebaseService.instance
                                  .markMicDrop(gameId, myId);
                            }
                          },
                        ),
                      );
                    }

                    return const SizedBox.shrink();
                  },
                );
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Keine Reaktion'),
          onPressed: () async {
            await onNoReaction();
            DialogManager.closeDialog();
          },
        ),
      ],
    );
  }
}
