// ignore_for_file: use_build_context_synchronously

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_card.dart';

import '../models/card_image_factory.dart';
class CardWidget extends StatelessWidget {
  final GameCard? card; // Mach `card` zu einem optionalen Parameter
  final VoidCallback? onTap; // `onTap` könnte auch null sein, wenn keine Karte vorhanden ist
  final bool isSelected;

  const CardWidget({
    super.key,
    this.card, // Entferne 'required' und mache 'card' optional
    this.onTap, // Auch 'onTap' ist optional
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    // Wenn `card` null ist, zeige einen Platzhalter anstatt des echten Kartenbildes
    if (card == null) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 80.0,
          height: 120.0,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey), // Grauer Rahmen für den Platzhalter
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade200, // Grauer Hintergrund für den Platzhalter
          ),
          child: Center(
            child: Text('Keine Karte', style: TextStyle(color: Colors.grey.shade600)),
          ),
        ),
      );
    }

    // Wenn `card` nicht null ist, baue das Widget wie gewohnt
    String cardImagePath = CardImageFactory.getCardImagePath(card!); // Verwende `!` da wir wissen, dass `card` nicht null ist

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80.0,
        height: 120.0,
        decoration: BoxDecoration(
          border: isSelected
              ? Border.all(color: Colors.green, width: 3) // Grüner Rahmen, wenn ausgewählt
              : Border.all(color: Colors.transparent), // Transparenter Rahmen, wenn nicht ausgewählt
          borderRadius: BorderRadius.circular(8),
          image: DecorationImage(
            image: AssetImage(cardImagePath),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}


// Stelle sicher, dass FlipCard öffentlich ist, wenn sie als generischer Typ oder
// in öffentlichen APIs verwendet wird.
class FlipCard extends StatefulWidget {
  final String frontAsset;
  final String backAsset;

  // Stelle sicher, dass der Konstruktor öffentlich ist und optional einen Key akzeptiert
  const FlipCard({super.key, required this.frontAsset, required this.backAsset});

  @override
  // ignore: library_private_types_in_public_api
  _FlipCardState createState() => _FlipCardState();
}


class _FlipCardState extends State<FlipCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (_isFront) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
        _isFront = !_isFront;
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, child) {
          return Transform(
            transform: Matrix4.rotationY(_controller.value * pi),
            alignment: Alignment.center,
            child: _controller.value < 0.5 ? Image.asset(widget.frontAsset) : Image.asset(widget.backAsset),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }


}


class DraggableCard extends StatefulWidget {
  final GameCard card;
  final bool isDraggable;
  final VoidCallback? onTap;
  final String gameId;
  final String playerId;
  final Function(GameCard) onPlayCard;
  final GlobalKey<ScaffoldState> parentKey;

  const DraggableCard({
    super.key,
    required this.card,
    required this.gameId,
    required this.playerId,
    this.isDraggable = true,
    this.onTap,
    required this.onPlayCard,
    required this.parentKey,
  });

  @override
  State<DraggableCard> createState() => _DraggableCardState();
}

class _DraggableCardState extends State<DraggableCard> {
   bool _isDraggingEnabled = false;  // Status, ob Dragging aktiviert ist
  @override
  Widget build(BuildContext context) {
    return widget.isDraggable ? Draggable<GameCard>(
      data: widget.card,
      feedback: Material(
        elevation: 1.0,
        child: CardWidget(card: widget.card),
      ),
      childWhenDragging: Container(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: CardWidget(card: widget.card),
      ),
      onDragEnd: (details) async {
        if (details.wasAccepted) {
          widget.onPlayCard(widget.card);
        }
      },
    ) : GestureDetector(
       onTap: () {
        if (!_isDraggingEnabled) {
          widget.onPlayCard(widget.card);  // Spielt die Karte beim Tippen, wenn nicht im Dragging-Modus
        }
      },
      onLongPress: () {
        setState(() {
          _isDraggingEnabled = true;  // Aktiviert das Ziehen nach einem LongPress
        });
      },
    );
  }
}




