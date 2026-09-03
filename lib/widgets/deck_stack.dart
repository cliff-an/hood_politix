import 'package:flutter/material.dart';

class DeckStack extends StatefulWidget {
  final double cardWidth;
  final Widget child; // z.B. AnimatedDeck
  const DeckStack({
    super.key,
    required this.cardWidth,
    required this.child,
  });

  @override
  State<DeckStack> createState() => _DeckStackState();
}

class _DeckStackState extends State<DeckStack>
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
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        widget.child, // Dein AnimatedDeck oder Image.asset

        // Pfeil oben
        Positioned(
          top: -widget.cardWidth * 0.6,
          child: ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.2)
                .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
            child: Icon(Icons.arrow_drop_up,
                size: widget.cardWidth * 0.5, color: Colors.orangeAccent),
          ),
        ),

        // Pfeil unten
        Positioned(
          bottom: -widget.cardWidth * 0.6,
          child: ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.2)
                .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
            child: Icon(Icons.arrow_drop_down,
                size: widget.cardWidth * 0.5, color: Colors.orangeAccent),
          ),
        ),
      ],
    );
  }
}
