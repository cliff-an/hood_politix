import 'dart:math';
import 'package:flutter/material.dart';

/// Orientierung der Kartenanzeige
enum HandOrientation { horizontal, vertical, arc }

/// Zeigt die Handkarten eines Gegners (verdeckte Karten, Avatar, Name, Mic-Status)
class OpponentHandWidget extends StatelessWidget {
  final String avatarAsset;
  final String playerName;
  final int cardCount;
  final double cardWidth;
  final String backAsset;
  final bool isCurrent;
  final double avatarSize;
  final HandOrientation orientation;
  final int maxVisible;
  final bool micChecked;
  final bool micDropped;
  final double radius; // Nur für arc-Layout

  const OpponentHandWidget({
    super.key,
    required this.avatarAsset,
    required this.playerName,
    required this.cardCount,
    required this.cardWidth,
    this.backAsset = 'lib/images/back_card.png',
    this.isCurrent = false,
    this.avatarSize = 36,
    this.orientation = HandOrientation.horizontal,
    this.maxVisible = 15,
    this.micChecked = false,
    this.micDropped = false,
    this.radius = 60,
  });

  @override
  Widget build(BuildContext context) {
    if (cardCount <= 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAvatar(),
          const SizedBox(height: 4),
          Text(
            playerName,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    switch (orientation) {
      case HandOrientation.arc:
        return _buildArcLayout();
      case HandOrientation.vertical:
      case HandOrientation.horizontal:
        return _buildLinearLayout();
    }
  }

  /// ---- Lineares Layout (Reihe oder Spalte) ----
  Widget _buildLinearLayout() {
    final visible = cardCount.clamp(0, maxVisible);
    final overflow = cardCount > maxVisible ? cardCount - maxVisible : 0;

    final cards = List<Widget>.generate(visible, (_) {
      return Image.asset(
        backAsset,
        width: cardWidth,
        height: cardWidth * 1.5,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(),
      );
    });

    if (overflow > 0) {
      cards.add(
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            '+$overflow',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    final cardsWidget = orientation == HandOrientation.horizontal
        ? Row(mainAxisSize: MainAxisSize.min, children: cards)
        : Column(mainAxisSize: MainAxisSize.min, children: cards);

    final micStatus = _buildMicStatus();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (micStatus != null) ...[
          micStatus,
          const SizedBox(height: 4),
        ],
        cardsWidget,
        const SizedBox(height: 6),
        _buildAvatar(),
        Text(
          playerName,
          style: TextStyle(
            color: isCurrent ? Colors.cyanAccent : Colors.white70,
            fontSize: isCurrent ? 14 : 12,
            fontWeight: FontWeight.bold,
            shadows:
                isCurrent ? [const Shadow(color: Colors.cyanAccent, blurRadius: 4)] : null,
          ),
        ),
      ],
    );
  }

  /// ---- Halbkreis-Layout für Gegner oben am Tisch ----
  Widget _buildArcLayout() {
    final totalWidth = radius * 2 + cardWidth;
    final totalHeight = radius + cardWidth * 1.5 + avatarSize + 16;
    final maxSpread = pi / 3;
    final step = cardCount > 1 ? maxSpread / (cardCount - 1) : 0.0;
    const start = 0.0;

    return SizedBox(
      width: totalWidth,
      height: totalHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < cardCount; i++) _buildArcCard(i, start + step * i),
          Positioned(
            left: (totalWidth / 2) - avatarSize / 2,
            top: radius + (cardWidth * 1.5) / 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildAvatar(),
                const SizedBox(height: 4),
                Text(
                  playerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Eine Karte im Halbkreis positionieren
  Widget _buildArcCard(int index, double angle) {
    final dx = radius * cos(angle) + radius;
    final dy = radius * sin(angle) + radius;

    return Positioned(
      left: dx - cardWidth / 2,
      top: dy - (cardWidth * 1.5) / 2,
      child: Transform.rotate(
        angle: angle + pi / 2,
        alignment: Alignment.bottomCenter,
        child: Image.asset(
          backAsset,
          width: cardWidth,
          height: cardWidth * 1.5,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(),
        ),
      ),
    );
  }

  /// Mic-Status Widget
  Widget? _buildMicStatus() {
    if (!micChecked && !micDropped) return null;
    final color = micChecked ? Colors.greenAccent : Colors.redAccent;
    final text = micChecked ? 'Check' : 'Drop';
    final icon = micChecked ? Icons.check_circle : Icons.arrow_drop_down_circle;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// Avatar mit optionaler Markierung, wenn der Spieler am Zug ist
  Widget _buildAvatar() {
    return Container(
      width: avatarSize + (isCurrent ? 8 : 0),
      height: avatarSize + (isCurrent ? 8 : 0),
      decoration: isCurrent
          ? BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.8),
                  blurRadius: 12,
                  spreadRadius: 5,
                ),
              ],
            )
          : null,
      child: CircleAvatar(
        radius: avatarSize / 2,
        backgroundImage: AssetImage(avatarAsset),
      ),
    );
  }
}
