// ignore_for_file: file_names
import 'package:flutter/material.dart';
import 'package:hp_card_game/widgets/card_widget.dart';

import '../models/game_card.dart';
class CustomReorderableList extends StatefulWidget {
  final List<GameCard> cards;
  const CustomReorderableList({super.key, required this.cards});

  @override
  State<CustomReorderableList> createState() => _CustomReorderableListState();
}

class _CustomReorderableListState extends State<CustomReorderableList> {
  late List<GameCard> _cards;

  @override
  void initState() {
    super.initState();
    _cards = widget.cards;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: _cards.length,
      itemBuilder: (context, index) {
        return LongPressDraggable<GameCard>(
          data: _cards[index],
          onDragStarted: () => debugPrint("Drag started"),
          onDraggableCanceled: (velocity, offset) {
            setState(() {
              // Hier könnte Logik zum Neuanordnen der Karten hinzugefügt werden
              debugPrint("Drag cancelled");
            });
          },
          feedback: Material(
            elevation: 4.0,
            child: CardWidget(card: _cards[index]),  // Ihr benutzerdefiniertes Kartenwidget
          ),
          childWhenDragging: Opacity(
            opacity: 0.5,
            child: CardWidget(card: _cards[index]),
          ),
          child: CardWidget(card: _cards[index]),
        );
      },
    );
  }
}
