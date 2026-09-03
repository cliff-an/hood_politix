import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_card.dart';
import '../models/card_image_factory.dart';
class DiscardFanned extends StatefulWidget {
  /// Der Ablagestapel (neueste Karte am Ende)
  final List<GameCard> pile;

  /// Breite einer Karte im Stapel
  final double cardWidth;

  /// Anzahl der Karten, die maximal im Fächer angezeigt werden
  final int maxFanCount;

  const DiscardFanned({
    super.key,
    required this.pile,
    required this.cardWidth,
    this.maxFanCount = 5,
  });

  @override
  State<DiscardFanned> createState() => _DiscardFannedState();
}

class _DiscardFannedState extends State<DiscardFanned>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Wie viele Karten wir fächern (bis maxFanCount oder Stapelgröße)
    final displayCount = min(widget.maxFanCount, widget.pile.length);

    return SizedBox(
      width: widget.cardWidth + widget.cardWidth * 0.07 * displayCount,
      height: widget.cardWidth * 1.5 + widget.cardWidth * 0.07 * displayCount,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Fächer-Effekt: die letzten displayCount Karten mit Offset zeichnen
          for (int i = 0; i < displayCount; i++)
            Positioned(
              left: i * widget.cardWidth * 0.07,
              top: -i * widget.cardWidth * 0.07,
              child: Image.asset(
                CardImageFactory.getCardImagePath(
                  widget.pile[widget.pile.length - 1 - i],
                ),
                width: widget.cardWidth,
                height: widget.cardWidth * 1.5,
                fit: BoxFit.cover,
              ),
            ),

          // Pfeil nach oben
          Positioned(
            top: -widget.cardWidth * 0.4,
            child: ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.2).animate(
                CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
              ),
              child: Icon(
                Icons.arrow_drop_up,
                size: widget.cardWidth * 0.7,
                color: Colors.green,
                shadows: [
                  Shadow(blurRadius: 8, color: Colors.greenAccent)
                ],
              ),
            ),
          ),

          // Pfeil nach unten
          Positioned(
            bottom: -widget.cardWidth * 0.4,
            child: ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.2).animate(
                CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
              ),
              child: Icon(
                Icons.arrow_drop_down,
                size: widget.cardWidth * 0.7,
                color: Colors.green,
                shadows: [
                  Shadow(blurRadius: 8, color: Colors.greenAccent)
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
