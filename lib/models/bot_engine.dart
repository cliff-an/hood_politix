import 'dart:math';

import 'action_card.dart';
import 'avatar_catalog.dart';
import 'card_action_type.dart';
import 'game_card.dart';

/// Feste Namen/Avatare für Bot-Spieler. Nutzt den bestehenden
/// [avatarCatalog] statt eigener Bilder.
class BotCatalog {
  static const List<String> _names = [
    'Bot Ost',
    'Bot West',
    'Bot Süd',
    'Bot Nord',
    'Bot Mitte',
  ];

  static String nameFor(int index) => _names[index % _names.length];

  static String avatarPathFor(int index) =>
      avatarCatalog[index % avatarCatalog.length].assetPath;
}

/// Was ein Bot vor/während seines Zugs bezüglich Mic Check/Drop tun soll.
enum BotMicAction { none, check, drop }

/// Reine, bewusst simple Entscheidungslogik für Bot-Spieler — kein
/// Firebase- oder BuildContext-Zugriff, dadurch einfach isoliert testbar.
/// Bots müssen nicht perfekt spielen, nur ein plausibles, faires Spiel
/// zeigen (siehe Plan "Bot-Gegner").
class BotEngine {
  BotEngine._();

  /// Erste legale Karte in Handreihenfolge. `topCard == null` (leerer
  /// Ablagestapel) ⇒ jede Karte ist legal. `null` Rückgabe ⇒ Bot muss ziehen.
  static GameCard? chooseCardToPlay(List<GameCard> hand, GameCard? topCard) {
    if (topCard == null) return hand.isEmpty ? null : hand.first;
    for (final card in hand) {
      if (card.canPlayOnTopOf(topCard)) return card;
    }
    return null;
  }

  /// Bevorzugt 5-0 (bricht die gesamte Straf-Kette sofort ab), sonst die
  /// erste legale Reaktion, sonst `null` (= ablehnen/Strafe kassieren).
  static ActionCard? chooseReaction(List<ActionCard> reactableCards) {
    if (reactableCards.isEmpty) return null;
    for (final card in reactableCards) {
      if (card.actionType == ActionType.fiveO) return card;
    }
    return reactableCards.first;
  }

  /// Zufälliges Ziel (Mensch oder Bot) für Deal/Snitch — keine Taktik.
  static String? chooseTarget(String selfId, List<String> otherPlayerIds, Random rng) {
    final candidates = otherPlayerIds.where((id) => id != selfId).toList();
    if (candidates.isEmpty) return null;
    return candidates[rng.nextInt(candidates.length)];
  }

  /// Snitch-Quelle: tauschen oder aufdecken — 50/50-Münzwurf.
  static bool chooseSnitchSwap(Random rng) => rng.nextBool();

  /// Muss VOR dem Ausspielen der Karte ausgewertet werden, die die Hand auf
  /// 1 oder 0 Karten bringt — handleMicChecksAndDrop bestraft einen
  /// fehlenden Status genauso wie bei einem menschlichen Spieler.
  static BotMicAction decideMicAction(int handCountBeforePlay) {
    if (handCountBeforePlay == 2) return BotMicAction.check;
    if (handCountBeforePlay == 1) return BotMicAction.drop;
    return BotMicAction.none;
  }

  /// "Bedenkzeit" vor einer Bot-Aktion, damit es sich nicht instant/robotisch
  /// anfühlt. Leicht randomisiert, damit mehrere Bots nicht im exakt
  /// gleichen Moment handeln.
  static Duration thinkDelay(Random rng, {int minMs = 900, int maxMs = 2400}) {
    final span = maxMs - minMs;
    final ms = span <= 0 ? minMs : minMs + rng.nextInt(span);
    return Duration(milliseconds: ms);
  }
}
