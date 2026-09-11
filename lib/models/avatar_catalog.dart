/// Feste, kuratierte Auswahl an Profil-Avataren.
///
/// Die Bilder unter `lib/images/avatars/` sind aktuell nur einfache
/// Platzhalter (farbige Silhouetten). Echte Charakterbilder können später
/// 1:1 unter denselben Dateinamen ersetzt werden — an [avatarCatalog] und
/// am restlichen Code ändert sich dadurch nichts.
class AvatarOption {
  final String id;
  final String assetPath;

  const AvatarOption(this.id, this.assetPath);
}

const List<AvatarOption> avatarCatalog = [
  AvatarOption('char_1', 'lib/images/avatars/char_1.png'),
  AvatarOption('char_2', 'lib/images/avatars/char_2.png'),
  AvatarOption('char_3', 'lib/images/avatars/char_3.png'),
  AvatarOption('char_4', 'lib/images/avatars/char_4.png'),
  AvatarOption('char_5', 'lib/images/avatars/char_5.png'),
  AvatarOption('char_6', 'lib/images/avatars/char_6.png'),
  AvatarOption('char_7', 'lib/images/avatars/char_7.png'),
  AvatarOption('char_8', 'lib/images/avatars/char_8.png'),
];

/// Fallback, falls kein Avatar gewählt wurde oder eine unbekannte
/// avatarId in der Datenbank steht.
const String defaultAvatarPath = 'lib/images/man.png';

/// Löst eine gespeicherte `avatarId` in einen Asset-Pfad auf.
String resolveAvatarPath(String? avatarId) {
  if (avatarId == null || avatarId.isEmpty) return defaultAvatarPath;
  for (final option in avatarCatalog) {
    if (option.id == avatarId) return option.assetPath;
  }
  return defaultAvatarPath;
}
