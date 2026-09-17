import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_card.dart';
import '/models/firebase_service.dart';
import '/widgets/dialog_manager.dart';
import '../models/card_image_factory.dart';
import '../widgets/mic_action_button.dart';

/// Dialog, der erscheint, wenn ein Spieler auf eine Aktionskarte reagieren kann.
class ReactionDialog extends StatefulWidget {
  final List<GameCard> reactableCards;
  final Future<void> Function(GameCard) onCardSelected;
  final Future<void> Function() onNoReaction;
  /// Die zuletzt gespielte Karte, auf die reagiert werden kann/muss.
  final GameCard? previousCard;

  const ReactionDialog({
    super.key,
    required this.reactableCards,
    required this.onCardSelected,
    required this.onNoReaction,
    this.previousCard,
  });

  @override
  State<ReactionDialog> createState() => _ReactionDialogState();
}

class _ReactionDialogState extends State<ReactionDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;

  // 10-Sekunden-Reaktionsfenster: reagiert der Spieler nicht rechtzeitig,
  // läuft das Spiel automatisch ohne Reaktion weiter (wie ein expliziter
  // Tap auf "Keine Reaktion"). _resolved verhindert Doppelausführung, falls
  // der Timer genau in dem Moment abläuft, in dem der Spieler noch selbst
  // tippt.
  static const _timeoutSeconds = 10;
  int _remainingSeconds = _timeoutSeconds;
  Timer? _countdownTimer;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remainingSeconds--);
      if (_remainingSeconds <= 0) {
        t.cancel();
        _resolve(widget.onNoReaction);
      }
    });
  }

  Future<void> _resolve(Future<void> Function() action) async {
    if (_resolved) return;
    _resolved = true;
    _countdownTimer?.cancel();
    await action();
    if (mounted) DialogManager.closeDialog();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = FirebaseAuth.instance.currentUser!.uid;
    final gameId = DialogManager.currentGameId!; // sicheres Game-Id-Handling
    final reactableCards = widget.reactableCards;
    final previousCard = widget.previousCard;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Reaktion wählen'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${_remainingSeconds}s',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ---- Zuvor gespielte Karte, auf die reagiert wird — pulsiert,
            // damit sofort klar ist, worauf gerade reagiert werden muss.
            if (previousCard != null) ...[
              Text(
                'Gespielte Karte:',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _glowCtrl,
                    builder: (_, child) {
                      final t = _glowCtrl.value;
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF0A65C).withValues(alpha: 0.35 + 0.35 * t),
                              blurRadius: 6 + 10 * t,
                              spreadRadius: 1 + 2 * t,
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        CardImageFactory.getCardImagePath(previousCard),
                        width: 54,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    previousCard.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 24),
            ],

            // ---- Auswahl der möglichen Reaktionskarten ----
            if (reactableCards.isNotEmpty)
              ...reactableCards.map(
                (card) => ListTile(
                  leading: Image.asset(
                    CardImageFactory.getCardImagePath(card),
                    width: 50,
                  ),
                  title: Text(card.toString()),
                  onTap: () => _resolve(() => widget.onCardSelected(card)),
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
          onPressed: () => _resolve(widget.onNoReaction),
        ),
      ],
    );
  }
}
