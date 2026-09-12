import 'package:flutter_test/flutter_test.dart';
import 'package:hp_card_game/models/game_meta.dart';

void main() {
  test('GameMeta.fromMap liest ein vollständiges privates Spiel', () {
    final meta = GameMeta.fromMap('game1', {
      'meta': {'name': 'Freitagabend', 'isPrivate': true, 'joinCode': 'WAXJ43'},
      'players': {'uidA': {}, 'uidB': {}},
      'gameState': {'state': 'waiting for players'},
      'gameInfo': {'createdAt': 1000, 'endedAt': 2000},
    });

    expect(meta.id, 'game1');
    expect(meta.name, 'Freitagabend');
    expect(meta.isPrivate, isTrue);
    expect(meta.joinCode, 'WAXJ43');
    expect(meta.playerIds, containsAll(['uidA', 'uidB']));
    expect(meta.state, 'waiting for players');
    expect(meta.createdAt, 1000);
    expect(meta.endedAt, 2000);
  });

  test('GameMeta.fromMap ist robust gegen fehlende Felder (Default-Werte statt Absturz)', () {
    final meta = GameMeta.fromMap('game2', {});

    expect(meta.name, 'Unbenanntes Spiel');
    expect(meta.isPrivate, isFalse);
    expect(meta.joinCode, isNull);
    expect(meta.playerIds, isEmpty);
    expect(meta.state, 'unknown');
    expect(meta.createdAt, 0);
    expect(meta.endedAt, isNull);
  });

  test('ein öffentliches Spiel hat isPrivate=false ohne den Schlüssel explizit zu setzen', () {
    final meta = GameMeta.fromMap('game3', {
      'meta': {'name': 'Offene Runde'},
      'gameState': {'state': 'waiting'},
    });

    expect(meta.isPrivate, isFalse);
    expect(meta.joinCode, isNull);
  });
}
