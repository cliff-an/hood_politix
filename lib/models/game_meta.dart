class GameMeta {
  final String id;
  final String name;
  final int createdAt;
  final int? endedAt;
  final List<String> playerIds;
  final String state; // ✅ HINZUGEFÜGT
  final bool isPrivate;
  final String? joinCode;

  /// 'normal' | 'training' | 'tutorial' — training/tutorial-Spiele werden
  /// aus der öffentlichen Lobby-Liste rausgefiltert.
  final String mode;

  /// Nur bei normalen Spielen gesetzt: Ziel-Spieleranzahl für die
  /// "X/Y Spieler" + "Mit N Bots starten"-Anzeige im Warteraum.
  final int? targetPlayerCount;

  GameMeta({
    required this.id,
    required this.name,
    required this.createdAt,
    this.endedAt,
    required this.playerIds,
    required this.state, // ✅ HINZUGEFÜGT
    this.isPrivate = false,
    this.joinCode,
    this.mode = 'normal',
    this.targetPlayerCount,
  });

  factory GameMeta.fromMap(String id, Map<String, dynamic> data) {
    final playersMap = Map<String, dynamic>.from(data['players'] ?? {});
    final playerIds = playersMap.keys.map((key) => key.toString()).toList();

    final gameState = Map<String, dynamic>.from(data['gameState'] ?? {});
    final state = gameState['state']?.toString() ?? 'unknown';

    final metaMap = data['meta'] is Map ? Map<String, dynamic>.from(data['meta'] as Map) : <String, dynamic>{};
    final gameInfoMap = data['gameInfo'] is Map ? Map<String, dynamic>.from(data['gameInfo'] as Map) : <String, dynamic>{};
    final createdAtRaw = gameInfoMap['createdAt'];
    final createdAt = createdAtRaw is int ? createdAtRaw : 0;
    final endedAtRaw = gameInfoMap['endedAt'];
    final endedAt = endedAtRaw is int ? endedAtRaw : null;

    return GameMeta(
      id: id,
      name: metaMap['name']?.toString() ?? 'Unbenanntes Spiel',
      createdAt: createdAt,
      endedAt: endedAt,
      playerIds: playerIds,
      state: state,
      isPrivate: metaMap['isPrivate'] == true,
      joinCode: metaMap['joinCode']?.toString(),
      mode: metaMap['mode']?.toString() ?? 'normal',
      targetPlayerCount: (metaMap['targetPlayerCount'] as num?)?.toInt(),
    );
  }
}
