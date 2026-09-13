import 'package:flutter/material.dart';
import 'package:hp_card_game/models/card_image_factory.dart';
import 'package:provider/provider.dart';
import '../models/game_controller.dart';
import '../models/firebase_service.dart';
import '../models/game_card.dart';
import '../models/number_card.dart';
class DragTargetWidget extends StatelessWidget {
  final String gameId;
  final GameCard? topCard;
  final bool isEnabled;           // true = aktiver Spieler dran
  final String currentPlayerId;
  final Function(GameCard) onCardDropped;
  // Kartenbreite — gleiche Konvention wie AnimatedDeck/PlayerHand
  // (Höhe = cardWidth * 1.5), damit Ablagestapel, Deck und Handkarten
  // gleich groß wirken statt der vorherigen festen 150x180px.
  final double cardWidth;

  const DragTargetWidget({
    super.key,
    required this.gameId,
    required this.topCard,
    required this.isEnabled,
    required this.currentPlayerId,
    required this.onCardDropped,
    required this.cardWidth,
  });

  @override
  Widget build(BuildContext context) {
    final gameController = Provider.of<GameController>(context, listen: false);

    return Center(
      child: DragTarget<GameCard>(
        // ➊ Immer annehmen, aber wir unterscheiden in onAccept
        onWillAcceptWithDetails: (_) => true,

        // ➋ Wird immer aufgerufen, sobald Spieler etwas fallen lässt
        onAcceptWithDetails: (details) async {
          final GameCard card = details.data;

          if (isEnabled) {
            // playCard handles legality check and penalty internally
            await gameController.playCard(context, currentPlayerId, card);
          } else {
            // nicht am Zug → Jump-In-Logik wie vorher
            final isJumpIn = card is NumberCard
                && topCard is NumberCard;
                //&& (card).number == (topCard as NumberCard).number
                //&& card.color == topCard!.color;
            if (isJumpIn) {
              await FirebaseService.instance.jumpInCard(
                gameId,
                currentPlayerId,
                card,
              );
            }
          }

          onCardDropped(card);
        },

        builder: (ctx, candidateData, rejectedData) {
          final hovering = candidateData.isNotEmpty;
          return Container(
            width: cardWidth,
            height: cardWidth * 1.5,
            decoration: BoxDecoration(
              border: Border.all(
                color: hovering ? Colors.greenAccent : Colors.black,
                width: hovering ? 3 : 2,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: hovering
                  ? [
                      BoxShadow(
                        color: Colors.greenAccent.withValues(alpha: 0.75),
                        blurRadius: 20,
                        spreadRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                // Karte "poppt" beim Erscheinen rein statt sich einfach
                // ohne Übergang auszutauschen — macht sichtbar, welche
                // Karte gerade gespielt wurde (eigene, gegnerische oder
                // Reaktionskarte, alle laufen über denselben topCard-Wert).
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: topCard != null
                    ? Image.asset(
                        CardImageFactory.getCardImagePath(topCard!),
                        key: ValueKey(topCard!.id),
                      )
                    : const Center(
                        key: ValueKey('empty'),
                        child: Text(
                          "Ablegen",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}