// widgets/snitch_option_dialog.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hp_card_game/models/game_card.dart';

enum SnitchChoice { swap, reveal }

class SnitchOptionDialog extends StatefulWidget {
  final void Function(SnitchChoice choice) onChosen;
  const SnitchOptionDialog({ required this.onChosen, super.key, required Future<Null> Function(int cardId) onReveal, required Future<Null> Function(GameCard myCard, GameCard targetCard) onSwap });

  @override
  State<SnitchOptionDialog> createState() => _SnitchOptionDialogState();
}

class _SnitchOptionDialogState extends State<SnitchOptionDialog> {
  // Rein visuelle Anzeige — das tatsächliche 15-Sekunden-Zeitlimit für die
  // GESAMTE Snitch-Aktion (dieser Dialog + die nachfolgende Kartenwahl)
  // läuft schon außen in GameController.performSnitchAction, unabhängig
  // davon, was hier gerade angezeigt wird.
  static const _timeoutSeconds = 15;
  int _remainingSeconds = _timeoutSeconds;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _remainingSeconds <= 0) {
        t.cancel();
        return;
      }
      setState(() => _remainingSeconds--);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Snitch-Aktion'),
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
      content: const Text('Möchtest du eine Karte tauschen oder eine Karte des Gegners zeigen?'),
      actions: [
        TextButton(
          onPressed: () {
            widget.onChosen(SnitchChoice.reveal);
            // kein pop(): Dialog bleibt offen, bis nachfolgender Dialog geschlossen wird
          },
          child: const Text('Karte zeigen'),
        ),
        TextButton(
          onPressed: () {
            widget.onChosen(SnitchChoice.swap);
          },
          child: const Text('Karte tauschen'),
        ),
      ],
    );
  }
}
