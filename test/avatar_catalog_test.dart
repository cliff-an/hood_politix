import 'package:flutter_test/flutter_test.dart';
import 'package:hp_card_game/models/avatar_catalog.dart';

void main() {
  test('resolveAvatarPath findet einen bekannten Katalog-Eintrag', () {
    final option = avatarCatalog.first;
    expect(resolveAvatarPath(option.id), option.assetPath);
  });

  test('resolveAvatarPath fällt auf den Platzhalter zurück', () {
    expect(resolveAvatarPath(null), defaultAvatarPath);
    expect(resolveAvatarPath(''), defaultAvatarPath);
    expect(resolveAvatarPath('nicht_im_katalog'), defaultAvatarPath);
  });

  test('jede Katalog-ID ist eindeutig', () {
    final ids = avatarCatalog.map((a) => a.id).toList();
    expect(ids.toSet().length, ids.length);
  });
}
