import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hp_card_game/models/action_card.dart';
import 'package:hp_card_game/models/bot_engine.dart';
import 'package:hp_card_game/models/card_action_type.dart';
import 'package:hp_card_game/models/card_color.dart';
import 'package:hp_card_game/models/number_card.dart';

ActionCard action(ActionType type, [CardColor color = CardColor.green]) =>
    ActionCard(color, 0, type);
NumberCard number(int n, [CardColor color = CardColor.green]) =>
    NumberCard(color, 0, n);

void main() {
  group('BotEngine.chooseCardToPlay', () {
    test('leerer Ablagestapel -> erste Handkarte ist immer legal', () {
      final hand = [number(3, CardColor.purple), number(7)];
      expect(BotEngine.chooseCardToPlay(hand, null), hand.first);
    });

    test('leerer Ablagestapel + leere Hand -> null (muss ziehen)', () {
      expect(BotEngine.chooseCardToPlay([], null), isNull);
    });

    test('findet die erste legale Karte in Handreihenfolge', () {
      final top = number(5, CardColor.green);
      final hand = [
        number(9, CardColor.purple), // weder Zahl noch Farbe passt
        number(5, CardColor.yellow), // gleiche Zahl -> legal
        number(1, CardColor.green), // gleiche Farbe -> auch legal, aber später
      ];
      expect(BotEngine.chooseCardToPlay(hand, top), hand[1]);
    });

    test('keine Handkarte passt -> null (muss ziehen)', () {
      final top = number(5, CardColor.green);
      final hand = [number(9, CardColor.purple), number(2, CardColor.yellow)];
      expect(BotEngine.chooseCardToPlay(hand, top), isNull);
    });
  });

  group('BotEngine.chooseReaction', () {
    test('bevorzugt Five-O, auch wenn es nicht zuerst in der Liste steht', () {
      final reactable = [action(ActionType.deuces), action(ActionType.fiveO)];
      expect(BotEngine.chooseReaction(reactable)?.actionType, ActionType.fiveO);
    });

    test('ohne Five-O -> erste Karte in der Liste', () {
      final reactable = [action(ActionType.deuces), action(ActionType.payback)];
      expect(BotEngine.chooseReaction(reactable)?.actionType, ActionType.deuces);
    });

    test('leere Liste -> null (ablehnen/Strafe kassieren)', () {
      expect(BotEngine.chooseReaction([]), isNull);
    });
  });

  group('BotEngine.decideMicAction', () {
    test('2 Karten vor dem Ausspielen -> check (Hand geht auf 1)', () {
      expect(BotEngine.decideMicAction(2), BotMicAction.check);
    });

    test('1 Karte vor dem Ausspielen -> drop (Hand geht auf 0)', () {
      expect(BotEngine.decideMicAction(1), BotMicAction.drop);
    });

    test('0 oder 3+ Karten -> none', () {
      expect(BotEngine.decideMicAction(0), BotMicAction.none);
      expect(BotEngine.decideMicAction(3), BotMicAction.none);
      expect(BotEngine.decideMicAction(5), BotMicAction.none);
    });
  });

  group('BotEngine.chooseTarget', () {
    test('trifft nie sich selbst, auch über viele Wiederholungen (fester Seed)', () {
      final rng = Random(42);
      const self = 'bot_0';
      const others = ['human_1', 'bot_1', 'human_2'];
      for (var i = 0; i < 100; i++) {
        final target = BotEngine.chooseTarget(self, [self, ...others], rng);
        expect(target, isNotNull);
        expect(target, isNot(self));
        expect(others, contains(target));
      }
    });

    test('keine anderen Spieler -> null', () {
      expect(BotEngine.chooseTarget('bot_0', ['bot_0'], Random()), isNull);
      expect(BotEngine.chooseTarget('bot_0', [], Random()), isNull);
    });
  });
}
