import 'package:flutter/material.dart';
import 'package:hp_card_game/models/firebase_service.dart';

/// Zeigt den Kartenstapel (Deck), von dem Spieler Karten ziehen.
/// Unterstützt eine Fly-Animation beim Ziehen.
class AnimatedDeck extends StatelessWidget {
  /// Callback, wenn der Spieler eine Karte ziehen darf (null = deaktiviert).
  final Future<void> Function()? onDraw;

  /// Breite der Karte (Layout-Anpassung).
  final double cardWidth;

  /// Pfad zum Kartenrücken-Bild.
  final String backImagePath;

  /// ID des aktuellen Spiels.
  final String gameId;

  const AnimatedDeck({
    super.key,
    required this.onDraw,
    required this.cardWidth,
    required this.backImagePath,
    required this.gameId,
  });

  // --------------------------------------------------------------------------
  // ----------------------- Öffentliche Animation-Hilfe ----------------------
  // --------------------------------------------------------------------------

  /// Startet eine Fluganimation von Deck → Spielerhand.
  /// Kann auch für Strafkarten / Ziehen-Animationen verwendet werden.
  static void flyCardToHand(
    BuildContext context,
    double cardWidth,
    String backImagePath,
  ) {
    final overlay = Overlay.of(context);

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final start = renderBox.localToGlobal(Offset.zero);
    final end = Offset(
      MediaQuery.of(context).size.width / 2 - cardWidth / 2,
      MediaQuery.of(context).size.height - cardWidth * 1.5 - 16,
    );

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => TweenAnimationBuilder<Offset>(
        tween: Tween(begin: start, end: end),
        duration: const Duration(milliseconds: 400),
        builder: (_, offset, __) {
          return Positioned(
            left: offset.dx,
            top: offset.dy,
            child: Image.asset(
              backImagePath,
              width: cardWidth,
              height: cardWidth * 1.5,
              fit: BoxFit.cover,
            ),
          );
        },
        onEnd: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }

  // --------------------------------------------------------------------------
  // -------------------------------- BUILD -----------------------------------
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onDraw != null
          ? () async {
              // Animierte Karte anzeigen
              flyCardToHand(context, cardWidth, backImagePath);

              // Benutzerdefinierte Callback (z. B. drawCard aus Controller)
              await onDraw!();

              // Nach dem Ziehen Zug an den nächsten Spieler übergeben
              try {
                // advanceToNextPlayer ersetzt nextTurn (je nach FirebaseService-Version)
                await FirebaseService.instance.advanceToNextPlayer(gameId);
              } catch (_) {
                // Fallback, falls nur nextTurn verfügbar ist
                await FirebaseService.instance.nextTurn(gameId);
              }
            }
          : null,
      child: SizedBox(
        width: cardWidth,
        height: cardWidth * 1.5,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.asset(
              backImagePath,
              width: cardWidth,
              height: cardWidth * 1.5,
              fit: BoxFit.cover,
            ),
          ],
        ),
      ),
    );
  }
}
