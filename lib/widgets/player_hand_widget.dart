import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:hp_card_game/models/card_image_factory.dart';
import '../models/game_card.dart';
class PlayerHandWidget extends StatefulWidget {
  final String gameId;
  final String playerId;

  const PlayerHandWidget({
    super.key,
    required this.gameId,
    required this.playerId,
  });

  @override
  PlayerHandWidgetState createState() => PlayerHandWidgetState();
}

class PlayerHandWidgetState extends State<PlayerHandWidget> {
  List<GameCard> handCards = [];
  bool isLoading = true;
  String errorMessage = '';
  StreamSubscription? _handSubscription;
  int? draggingCardId;

  @override
  void initState() {
    super.initState();
    _loadHandCards();
    _listenForHandUpdates();
  }

  @override
  void dispose() {
    _handSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadHandCards() async {
    final playerRef = FirebaseDatabase.instance
        .ref('games/${widget.gameId}/players/${widget.playerId}/handCardIds');
    final snapshot = await playerRef.get();
    if (!snapshot.exists || snapshot.value == null) {
      setState(() {
        errorMessage = 'Keine Karten gefunden.';
        isLoading = false;
      });
      return;
    }
    final ids = List<int>.from(snapshot.value as List);
    _loadFullCardDetails(ids);
  }

  Future<void> _loadFullCardDetails(List<int> cardIds) async {
    final cards = <GameCard>[];
    for (var id in cardIds) {
      try {
        final cardSnap = await FirebaseDatabase.instance
            .ref('games/${widget.gameId}/cards/$id')
            .get();
        if (cardSnap.exists) {
          cards.add(GameCard.fromMap(
            Map<String, dynamic>.from(cardSnap.value as Map),
          ));
        }
      } catch (_) {}
    }
    setState(() {
      handCards = cards;
      isLoading = false;
      errorMessage = cards.isEmpty ? 'Keine Karten gefunden.' : '';
    });
  }

  void _listenForHandUpdates() {
    final playerRef = FirebaseDatabase.instance
        .ref('games/${widget.gameId}/players/${widget.playerId}/handCardIds');
    _handSubscription = playerRef.onValue.listen((event) {
      if (!mounted) return;
      if (!event.snapshot.exists || event.snapshot.value == null) {
        setState(() {
          handCards = [];
          errorMessage = 'Keine Karten gefunden.';
        });
      } else {
        final ids = List<int>.from(event.snapshot.value as List);
        _loadFullCardDetails(ids);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (errorMessage.isNotEmpty) return Center(child: Text(errorMessage));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Platz zwischen den Karten
        const double spacing = 8.0;
        final availableWidth = constraints.maxWidth;
        final count = handCards.length;

        // Je nach Anzahl schrumpfen die Karten bis max 100px
        final cardWidth = count > 0
            ? min(100.0, (availableWidth - spacing * (count + 1)) / count)
            : 100.0;

        return SizedBox(
          height: 150,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: spacing),
            itemCount: handCards.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                final card = handCards.removeAt(oldIndex);
                handCards.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, card);
              });
            },
            proxyDecorator: (child, index, animation) => child,
            itemBuilder: (context, index) {
              final card = handCards[index];
              return SizedBox(
                key: ValueKey(card.id),
                width: cardWidth,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Draggable<GameCard>(
                      data: card,
                      onDragStarted: () => setState(() => draggingCardId = card.id),
                      onDragEnd: (_) => setState(() => draggingCardId = null),
                      feedback: Material(
                        elevation: 6,
                        child: Image.asset(
                          CardImageFactory.getCardImagePath(card),
                          width: cardWidth * 1.25,
                          height: 150 * 1.25,
                          fit: BoxFit.cover,
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.4,
                        child: Image.asset(
                          CardImageFactory.getCardImagePath(card),
                          width: cardWidth,
                          height: 150,
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: Image.asset(
                        CardImageFactory.getCardImagePath(card),
                        width: cardWidth,
                        height: 150,
                        fit: BoxFit.cover,
                      ),
                    ),
                    // Sortier-Handle
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_handle, size: 20, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
