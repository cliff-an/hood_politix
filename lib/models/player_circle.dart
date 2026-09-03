import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hp_card_game/models/player.dart';
class PlayerCircle extends StatelessWidget {
  final List<Player> players;              // ohne mich
  final String currentPlayerId;
  final Map<String,int> handCounts;        // aus Firebase
  final double radius;
  final String backImagePath;
  final Animation<double> currentPlayerPulse;

  const PlayerCircle({
    super.key,
    required this.players,
    required this.currentPlayerId,
    required this.handCounts,
    required this.radius,
    required this.backImagePath,
    required this.currentPlayerPulse,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2 + 40,
      height: radius * 2 + 40,
      child: Stack(
        children: List.generate(players.length, (i) {
          return _buildOne(context, players[i], i);
        }),
      ),
    );
  }

   Widget _buildOne(BuildContext ctx, Player p, int idx) {
    final n = players.length;
    // Winkel nur im oberen Halbkreis [-π .. 0]
    final angle = n < 2
        ? -pi/2
        : -pi + (idx / (n - 1)) * pi;
    final cx = radius + cos(angle)*radius;
    final cy = radius + sin(angle)*radius;
    final ortho = Offset(cos(angle), sin(angle));
    final count = (handCounts[p.id] ?? 0).clamp(0, 5);

    // Back-Card-Fächer, dabei jedes Bild zum Tisch hin rotieren:
    final backs = List.generate(count, (j) {
      final ofs = j * (radius*0.3 * 0.4);
      return Positioned(
        left: ortho.dx.sign * ofs,
        top:  ortho.dy.sign * ofs,
        child: Transform.rotate(
          angle: angle + pi/2,  // Karte zeigt zum Tisch-Mittelpunkt
          child: Image.asset(
            backImagePath,
            width: radius*0.3,
            height: radius*0.45,
            fit: BoxFit.cover,
          ),
        ),
      );
    });

    return Positioned(
      left: cx + 20,
      top:  cy + 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // die verdeckten Karten
          SizedBox(
            width: radius*0.3 + (count-1)*(radius*0.3*0.4),
            height: radius*0.45,
            child: Stack(children: backs),
          ),
          const SizedBox(height: 4),
          // Avatar bleibt so wie gehabt …
        ],
      ),
    );
  }
}