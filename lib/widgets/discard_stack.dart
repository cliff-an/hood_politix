// file: widgets/discard_stack.dart

import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_card.dart';
import '../models/card_image_factory.dart';
class DiscardStack extends StatefulWidget {
  final GameCard? topCard;
  final double cardWidth;

  const DiscardStack({
    super.key,
    required this.topCard,
    required this.cardWidth,
  });

  @override
  State<DiscardStack> createState() => _DiscardStackState();
}

class _DiscardStackState extends State<DiscardStack>
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
Widget build(BuildContext ctx) {
  // Definiere dir Breite/Höhe einmal
  final w = widget.cardWidth;
  final h = widget.cardWidth * 1.5;

  return SizedBox(
    width: w,
    height: h,
    child: Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (widget.topCard != null)
          Image.asset(
            CardImageFactory.getCardImagePath(widget.topCard!),
            width: w,
            height: h,
            fit: BoxFit.cover,
          ),

        // Pfeile links/rechts
        Positioned(
          left: -w * 0.6,
          child: ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.2)
                .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
            child: Icon(Icons.arrow_left, size: w * 0.5, color: Colors.greenAccent),
          ),
        ),
        Positioned(
          right: -w * 0.6,
          child: ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.2)
                .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
            child: Icon(Icons.arrow_right, size: w * 0.5, color: Colors.greenAccent),
          ),
        ),
      ],
    ),
  );
}
}