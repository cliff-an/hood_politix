// lib/widgets/persistent_player_hand_widget.dart
import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../models/game_card.dart';
import '../models/game_controller.dart';
import '../models/card_image_factory.dart';

typedef CardCallback = void Function(GameCard card);

/// Zeigt dauerhaft die Handkarten des Spielers unten im Spielfeld.
/// Unterstützt Drag&Drop, Pagination und Animation beim Ablegen.
class PersistentPlayerHandWidget extends StatefulWidget {
  final String gameId;
  final String playerId;
  final double cardWidth;
  final GlobalKey discardKey;
  final bool isMyTurn;

  /// Ob die Karten bei zu vielen Seitenweise angezeigt werden sollen.
  final bool paginate;

  /// Maximale Karten pro Seite (wenn paginate aktiv).
  final int maxVisible;

  const PersistentPlayerHandWidget({
    super.key,
    required this.gameId,
    required this.playerId,
    required this.cardWidth,
    required this.discardKey,
    required this.isMyTurn,
    this.paginate = false,
    this.maxVisible = 15,
  });

  @override
  State<PersistentPlayerHandWidget> createState() =>
      _PersistentPlayerHandWidgetState();
}

class _PersistentPlayerHandWidgetState extends State<PersistentPlayerHandWidget> {
  List<GameCard> handCards = [];
  bool isLoading = true;
  String errorMessage = '';
  late DatabaseReference _handRef;
  StreamSubscription<DatabaseEvent>? _handSub;
  int _page = 0;
  final Map<int, GameCard> _cardCache = {};

  @override
  void initState() {
    super.initState();
    _handRef = FirebaseDatabase.instance
        .ref('games/${widget.gameId}/players/${widget.playerId}/handCardIds');
    _handSub = _handRef.onValue.listen((event) => _loadHandFromSnapshot(event.snapshot));
  }

  @override
  void dispose() {
    _handSub?.cancel();
    super.dispose();
  }

  void _loadHandFromSnapshot(DataSnapshot snap) {
    List<int> ids = [];
    if (snap.exists && snap.value != null) {
      final raw = snap.value;
      Iterable<dynamic> items;
      if (raw is List) {
        items = raw;
      } else if (raw is Map) {
        items = raw.values;
      } else {
        items = const [];
      }
      ids = items.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
    }

    if (ids.isEmpty) {
      setState(() {
        isLoading = false;
        errorMessage = 'Keine Karten.';
        handCards = [];
      });
      return;
    }

    // Show cached cards immediately, then fetch missing ones
    final cached = ids.map((id) => _cardCache[id]).whereType<GameCard>().toList();
    if (cached.length == ids.length) {
      final pages = (cached.length / widget.maxVisible).ceil();
      if (_page >= pages && pages > 0) _page = pages - 1;
      setState(() {
        handCards = cached;
        isLoading = false;
        errorMessage = '';
      });
    } else {
      if (isLoading == false) {
        // Show what we have while fetching
        setState(() { handCards = cached; });
      }
      _loadCardsForIds(ids);
    }
  }

  Future<void> _loadCardsForIds(List<int> ids) async {
    final missing = ids.where((id) => !_cardCache.containsKey(id)).toList();
    await Future.wait(missing.map((id) async {
      final cs = await FirebaseDatabase.instance
          .ref('games/${widget.gameId}/cards/$id')
          .get();
      if (cs.exists && cs.value != null) {
        _cardCache[id] = GameCard.fromMap(Map<String, dynamic>.from(cs.value as Map));
      }
    }));

    final cards = ids.map((id) => _cardCache[id]).whereType<GameCard>().toList();
    final pages = (cards.length / widget.maxVisible).ceil();
    if (_page >= pages && pages > 0) _page = pages - 1;

    if (mounted) {
      setState(() {
        handCards = cards;
        isLoading = false;
        errorMessage = cards.isEmpty ? 'Keine Karten.' : '';
      });
    }
  }

  /// Animation einer Karte, die ins Ablagefeld fliegt.
  void _flyCardToDiscard(GameCard card, GlobalKey cardKey) {
    final overlay = Overlay.of(context);

    final startRb = cardKey.currentContext?.findRenderObject() as RenderBox?;
    final discardRb =
        widget.discardKey.currentContext?.findRenderObject() as RenderBox?;
    if (startRb == null || discardRb == null) return;

    final start = startRb.localToGlobal(Offset.zero);
    final end = discardRb.localToGlobal(Offset.zero);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => TweenAnimationBuilder<Offset>(
        tween: Tween(begin: start, end: end),
        duration: const Duration(milliseconds: 400),
        builder: (_, offset, __) {
          return Positioned(
            left: offset.dx,
            top: offset.dy,
            child: SizedBox(
              width: widget.cardWidth,
              height: widget.cardWidth * 1.5,
              child: Image.asset(
                CardImageFactory.getCardImagePath(card),
                fit: BoxFit.cover,
              ),
            ),
          );
        },
        onEnd: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }

  // --------------------------------------------------------------------------
  // ------------------------------- BUILD ------------------------------------
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        height: widget.cardWidth * 1.5 + 16,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (errorMessage.isNotEmpty) {
      return SizedBox(
        height: widget.cardWidth * 1.5 + 16,
        child: Center(child: Text(errorMessage)),
      );
    }

    if (widget.paginate && handCards.length > widget.maxVisible) {
      return _buildPaginatedHand();
    } else {
      return _buildFan(handCards);
    }
  }

  /// Erzeugt mehrere Seiten, wenn zu viele Karten vorhanden sind.
  Widget _buildPaginatedHand() {
    final total = handCards.length;
    final pages = (total / widget.maxVisible).ceil();
    final start = _page * widget.maxVisible;
    final end = min(start + widget.maxVisible, total);
    final pageCards = handCards.sublist(start, end);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFan(pageCards),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: _page > 0 ? () => setState(() => _page--) : null,
            ),
            Text('${_page + 1} / $pages',
                style: const TextStyle(color: Colors.white)),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: Colors.white),
              onPressed:
                  _page < pages - 1 ? () => setState(() => _page++) : null,
            ),
          ],
        ),
      ],
    );
  }

  /// Zeigt die Handkarten als leicht gefächerte Reihe unten.
  Widget _buildFan(List<GameCard> cards) {
    final count = cards.length;
    if (count == 0) return const SizedBox.shrink();

    final maxSpread = 45.0 * pi / 180;
    final step = count > 1 ? maxSpread / (count - 1) : 0.0;
    final startAng = -maxSpread / 2;
    final cardW = widget.cardWidth;
    final overlap = cardW * 0.6;
    final neededW = (count - 1) * overlap + cardW;
    final rawRadius = neededW / (2 * sin(maxSpread / 2));
    final screenW = MediaQuery.of(context).size.width;
    final maxRad = (screenW - cardW) / 2;
    final radius = rawRadius.clamp(cardW, maxRad);
    final height = cardW * 1.5 + 32;
    final cardH = cardW * 1.5;
    final maxDy = height - cardH;

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < count; i++)
            _buildCard(cards[i], startAng + step * i, radius,
                height: height, maxDy: maxDy),
        ],
      ),
    );
  }

  /// Einzelne Karte im Bogen platzieren.
  Widget _buildCard(
    GameCard card,
    double angle,
    double radius, {
    required double height,
    required double maxDy,
  }) {
    final screenW = MediaQuery.of(context).size.width;
    final cardW = widget.cardWidth;
    final dxRaw = radius * sin(angle);
    final dyRaw = radius * (1 - cos(angle));
    final dy = dyRaw.clamp(0.0, maxDy);
    final baseLeft = (screenW - cardW) / 2;
    final left = baseLeft + dxRaw;
    final cardKey = GlobalKey();

    return Positioned(
      left: left,
      top: dy,
      child: Transform.rotate(
        angle: angle,
        alignment: Alignment.bottomCenter,
        child: Draggable<GameCard>(
          data: card,
          feedback: _cardImage(card, scale: 1.2),
          childWhenDragging: Opacity(opacity: .3, child: _cardImage(card)),
          // Kein optimistisches Entfernen aus handCards mehr hier: ob die
          // Karte wirklich gespielt werden durfte, entscheidet der Server
          // (legaler Zug, legaler Jump-in) — bei einem illegalen Jump-in
          // (falsche Karte, nicht am Zug) bleibt sie in Firebase in der
          // Hand, oder bei einer Aktionskarte/leerem Ablagestapel wird
          // FirebaseService.jumpInCard gar nicht erst aufgerufen. Ein
          // Entfernen HIER, unabhängig vom Ergebnis, ließ die Karte dann
          // dauerhaft aus der lokalen Anzeige verschwinden, obwohl sie
          // laut Firebase noch in der Hand war. _handSub oben ist die
          // einzige Quelle der Wahrheit und aktualisiert handCards nach
          // jedem echten Schreibzugriff (inkl. der beiden Straf-Karten
          // bei einem ungültigen Jump-in) ohnehin selbst.
          child: GestureDetector(
            key: cardKey,
            onTap: () async {
              if (!widget.isMyTurn) return;
              _flyCardToDiscard(card, cardKey);
              // ignore: use_build_context_synchronously
              await GameController.instance.playCard(context, widget.playerId, card);
            },
            child: _cardImage(card),
          ),
        ),
      ),
    );
  }

  Widget _cardImage(GameCard card, {double scale = 1.0}) {
    return SizedBox(
      width: widget.cardWidth * scale,
      height: widget.cardWidth * 1.5 * scale,
      child: Image.asset(
        CardImageFactory.getCardImagePath(card),
        fit: BoxFit.cover,
      ),
    );
  }
}
