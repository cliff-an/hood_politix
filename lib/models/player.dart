import 'package:hp_card_game/models/game_card.dart';

/// Repräsentiert einen Spieler innerhalb einer laufenden Game-Session.
class Player {
  /// Eindeutige Firebase-ID des Spielers.
  final String id;

  /// Anzeigename des Spielers.
  final String name;

  /// IDs der Karten in der Hand des Spielers.
  List<int> handCardIds;

  /// Optionales Avatar-Bild (URL oder Asset-Pfad).
  final String avatarUrl;

  /// Ob der Spieler das Spiel bereits beendet/gewonnen hat.
  bool hasWon;

  /// Zeitpunkt, wann der Spieler fertig wurde.
  final DateTime? finishedAt;

  Player({
    required this.id,
    required this.name,
    required this.handCardIds,
    this.avatarUrl = '',
    this.hasWon = false,
    this.finishedAt,
  });

  // ---------------------------------------------------------------------------
  // ----------------------------- Spiel-Hilfsmethoden -------------------------
  // ---------------------------------------------------------------------------

  /// Entfernt eine Karte aus der Hand (nachdem sie gespielt wurde).
  void removeCardFromHand(int cardId) => handCardIds.remove(cardId);

  /// Fügt eine Karte zur Hand hinzu (wenn sie gezogen wird).
  void addCardToHand(int cardId) => handCardIds.add(cardId);

  /// Prüft, ob eine Karte auf die aktuelle Ablage gespielt werden darf.
  bool canPlayCard(GameCard card, GameCard topDiscardCard) =>
      card.canPlayOnTopOf(topDiscardCard);

  /// Aktualisiert die gesamte Hand (z. B. nach Tausch-Aktionen).
  void updateHandCards(List<int> newHand) {
    handCardIds
      ..clear()
      ..addAll(newHand);
  }

  /// Kurze Aliase für Kartenereignisse (zur Konsistenz mit altem Code).
  void onCardPlayed(int cardId) => removeCardFromHand(cardId);
  void onCardDrawn(int cardId) => addCardToHand(cardId);

  // ---------------------------------------------------------------------------
  // -------------------------- Firebase-Serialisierung -----------------------
  // ---------------------------------------------------------------------------

  /// Konvertiert den Spieler in ein Firebase-kompatibles Map-Objekt.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'handCardIds': handCardIds,
      'avatarUrl': avatarUrl,
      'hasWon': hasWon,
      'finishedAt': finishedAt?.toIso8601String(),
    };
  }

  /// Erstellt ein [Player]-Objekt aus Firebase-/Realtime-Database-Daten.
  static Player fromMap(Map<String, dynamic> map, String id) {
    // Handkarten-IDs sicher parsen (egal ob int oder String in Firebase)
    final hand = <int>[];
    if (map['handCardIds'] is List) {
      for (final e in (map['handCardIds'] as List)) {
        final parsed = int.tryParse(e.toString());
        if (parsed != null) hand.add(parsed);
      }
    }

    // finishedAt kann int (msSinceEpoch) oder ISO-String sein
    DateTime? finishedAt;
    final raw = map['finishedAt'];
    if (raw is int) {
      finishedAt = DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw is String) {
      finishedAt = DateTime.tryParse(raw);
    }

    return Player(
      id: id,
      name: map['name'] as String? ?? 'Unbekannter Spieler',
      handCardIds: hand,
      avatarUrl: map['avatarUrl'] as String? ?? '',
      hasWon: map['hasWon'] == true,
      finishedAt: finishedAt,
    );
  }
}
