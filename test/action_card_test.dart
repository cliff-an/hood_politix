import 'package:flutter_test/flutter_test.dart';
import 'package:hp_card_game/models/action_card.dart';
import 'package:hp_card_game/models/card_action_type.dart';
import 'package:hp_card_game/models/card_color.dart';

ActionCard card(ActionType type, [CardColor color = CardColor.green]) =>
    ActionCard(color, 0, type);

void main() {
  group('canRespondWith — wer darf auf eine gespielte Aktionskarte reagieren', () {
    // Regressionstest für den Zug-Reihenfolge-Bug aus 535ec4f: Five-O muss
    // auf Deuces reagieren dürfen, unabhängig von der Farbe.
    test('Five-O darf immer auf Deuces reagieren', () {
      expect(card(ActionType.fiveO, CardColor.purple)
          .canRespondWith(card(ActionType.deuces, CardColor.green)), isTrue);
    });

    test('Deuces darf auf Deuces reagieren (Kette verlängern)', () {
      expect(card(ActionType.deuces).canRespondWith(card(ActionType.deuces)), isTrue);
    });

    test('Payback darf nur mit gleicher Farbe auf Deuces reagieren', () {
      expect(
        card(ActionType.payback, CardColor.green)
            .canRespondWith(card(ActionType.deuces, CardColor.green)),
        isTrue,
      );
      expect(
        card(ActionType.payback, CardColor.purple)
            .canRespondWith(card(ActionType.deuces, CardColor.green)),
        isFalse,
      );
    });

    test('Payback darf farbunabhängig auf Payback reagieren', () {
      expect(
        card(ActionType.payback, CardColor.yellow)
            .canRespondWith(card(ActionType.payback, CardColor.orange)),
        isTrue,
      );
    });

    test('Auf Deal/Snitch darf nur mit Five-O reagiert werden', () {
      expect(card(ActionType.fiveO).canRespondWith(card(ActionType.deal)), isTrue);
      expect(card(ActionType.fiveO).canRespondWith(card(ActionType.snitch)), isTrue);
      expect(card(ActionType.deuces).canRespondWith(card(ActionType.deal)), isFalse);
    });

    test('Busted/Pimp Slap haben keine Reaktionsmöglichkeit', () {
      expect(card(ActionType.fiveO).canRespondWith(card(ActionType.busted)), isFalse);
      expect(card(ActionType.fiveO).canRespondWith(card(ActionType.pimpSlap)), isFalse);
    });
  });

  group('canPlayOnTopOf — welche Karten dürfen normal gespielt werden', () {
    test('Deuces braucht gleiche Farbe oder gleichen Typ', () {
      final discard = card(ActionType.deuces, CardColor.green);
      // gleicher Typ (deuces), Farbe egal -> erlaubt
      expect(card(ActionType.deuces, CardColor.purple).canPlayOnTopOf(discard), isTrue);
      // gleiche Farbe, anderer (aber ebenfalls farbgebundener) Typ -> erlaubt
      expect(card(ActionType.busted, CardColor.green).canPlayOnTopOf(discard), isTrue);
      // weder Typ noch Farbe passen -> nicht erlaubt
      expect(card(ActionType.busted, CardColor.purple).canPlayOnTopOf(discard), isFalse);
    });

    test('Five-O/InYoFace/PimpSlap/Deal/Snitch sind farbunabhängig immer spielbar', () {
      final discard = card(ActionType.deuces, CardColor.purple);
      for (final t in [
        ActionType.fiveO,
        ActionType.inYoFace,
        ActionType.pimpSlap,
        ActionType.deal,
        ActionType.snitch,
      ]) {
        expect(card(t, CardColor.yellow).canPlayOnTopOf(discard), isTrue, reason: t.name);
      }
    });
  });
}
