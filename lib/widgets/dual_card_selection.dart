import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_card.dart';
import '../models/card_image_factory.dart';

/// Dialog für Snitch-Aktion (Karten tauschen)
/// Zeigt die Handkarten beider Spieler und erlaubt das Auswählen je einer Karte.
class DualCardSelectDialog extends StatefulWidget {
  final List<GameCard> currentPlayerCards;
  final List<GameCard> targetPlayerCards;
  final Function(GameCard? currentPlayerCard, GameCard? targetPlayerCard)
      onCardsSelected;
  final String currentPlayerName;
  final String targetPlayerName;

  const DualCardSelectDialog({
    super.key,
    required this.currentPlayerCards,
    required this.targetPlayerCards,
    required this.onCardsSelected,
    required this.currentPlayerName,
    required this.targetPlayerName,
  });

  @override
  State<DualCardSelectDialog> createState() => _DualCardSelectDialogState();
}

class _DualCardSelectDialogState extends State<DualCardSelectDialog> {
  GameCard? _selectedCurrentPlayerCard;
  GameCard? _selectedTargetPlayerCard;

  Widget _buildCardItem(GameCard card, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.green : Colors.transparent,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Image.asset(
          CardImageFactory.getCardImagePath(card),
          width: 80,
          height: 110,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Wähle Karten zum Tauschen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.currentPlayerName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.currentPlayerCards
                    .map(
                      (card) => _buildCardItem(
                        card,
                        card == _selectedCurrentPlayerCard,
                        () => setState(() {
                          _selectedCurrentPlayerCard = card;
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.targetPlayerName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: widget.targetPlayerCards
                    .map(
                      (card) => _buildCardItem(
                        card,
                        card == _selectedTargetPlayerCard,
                        () => setState(() {
                          _selectedTargetPlayerCard = card;
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_selectedCurrentPlayerCard != null &&
                _selectedTargetPlayerCard != null) {
              widget.onCardsSelected(
                _selectedCurrentPlayerCard,
                _selectedTargetPlayerCard,
              );
              Navigator.of(context).pop();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bitte wähle je eine Karte für beide Spieler.'),
                ),
              );
            }
          },
          child: const Text('Bestätigen'),
        ),
      ],
    );
  }
}
