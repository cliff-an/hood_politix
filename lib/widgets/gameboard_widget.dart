import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/card_image_factory.dart';
import '../models/firebase_service.dart';
import '../models/game_card.dart';
import '../models/game_controller.dart';
import '../models/game_meta.dart';
import 'drag_target_widget.dart';
import 'persistent_player_hand_widget.dart';
import 'mic_action_button.dart';
import 'animated_deck.dart';

class GameBoard extends StatefulWidget {
  final String gameId;
  const GameBoard({super.key, required this.gameId});

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard> with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _popCtrl;
  late final Animation<double> _popAnim;
  late final AnimationController _directionCtrl;
  late final AnimationController _reactionFlashCtrl;
  late final Animation<double> _reactionFlashOpacity;
  late final Animation<double> _reactionFlashScale;
  final GlobalKey _discardKey = GlobalKey();
  int _lastHandCount = 0;
  late Future<GameMeta> _gameMetaFuture;

  // Öffentliche Reaktions-Animation (für alle Spieler sichtbar, nicht nur
  // den, der reagieren muss) — welche Karte gerade aufblitzt + welchen
  // reactionFlashSeq-Stand vom GameController wir schon gezeigt haben.
  GameCard? _flashCard;
  int _seenReactionFlashSeq = -1;

  @override
  void initState() {
    super.initState();
    _gameMetaFuture = context.read<FirebaseService>().getGameMeta(widget.gameId);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _popCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _popAnim = CurvedAnimation(parent: _popCtrl, curve: Curves.elasticOut);

    // Langsame, endlose Drehung für den Richtungspfeil in der Tischmitte.
    _directionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // Reaktionskarte: schnell reinpoppen, kurz halten, ausblenden.
    _reactionFlashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _reactionFlashOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 33),
    ]).animate(_reactionFlashCtrl);
    _reactionFlashScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.4, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 30,
      ),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 12),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 58),
    ]).animate(_reactionFlashCtrl);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _popCtrl.dispose();
    _directionCtrl.dispose();
    _reactionFlashCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<FirebaseService>();
    final ctrl = context.watch<GameController>();
    final myId = FirebaseAuth.instance.currentUser!.uid;
    final isTurn = ctrl.currentPlayerId == myId;

    // Neue Reaktionskarte vom Controller gemeldet (für alle Spieler gleich,
    // nicht nur den, der reagieren musste) -> Flash-Animation anstoßen.
    if (ctrl.reactionFlashSeq != _seenReactionFlashSeq && ctrl.lastReactionCard != null) {
      _seenReactionFlashSeq = ctrl.reactionFlashSeq;
      final card = ctrl.lastReactionCard!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _flashCard = card);
        _reactionFlashCtrl.forward(from: 0);
      });
    }
    final size = MediaQuery.of(context).size;

    final shortestSide = min(size.width, size.height);
    final isLandscape = size.width > size.height;
    final cardW = (isLandscape ? shortestSide * 0.11 : shortestSide * 0.10)
        .clamp(48.0, 80.0);
    const edgeM = 16.0;

    if (ctrl.currentPlayerId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Widget> layers = [];

    // Hintergrund
    layers.add(Positioned.fill(
      child: Image.asset('lib/images/background.png', fit: BoxFit.cover),
    ));

    // Header: Titel + aktueller Spieler + Countdown + Leave-Button — alles in einer Zeile
    final currentPlayer = ctrl.players.where((p) => p.id == ctrl.currentPlayerId).firstOrNull;
    layers.add(Positioned(
      top: edgeM,
      left: edgeM,
      right: edgeM,
      child: FutureBuilder<GameMeta>(
        future: _gameMetaFuture,
        builder: (ctx, snap) {
          final gameName = snap.data?.name ?? '';
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Spielname links
              Expanded(
                child: Text(
                  gameName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(blurRadius: 4)],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Aktueller Spieler + Timer zentriert
              if (currentPlayer != null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                      decoration: BoxDecoration(
                        color: currentPlayer.id == myId
                            ? Colors.green.withValues(alpha: 0.85)
                            : Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        currentPlayer.id == myId
                            ? 'Du bist am Zug'
                            : '${currentPlayer.name} ist am Zug',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (ctrl.remainingTime > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${ctrl.remainingTime}s',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              // Leave-Button rechts
              IconButton(
                icon: const Icon(Icons.exit_to_app, color: Colors.white),
                tooltip: 'Spiel verlassen',
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  await svc.leaveGame(widget.gameId, myId);
                  navigator.pop();
                },
              ),
            ],
          );
        },
      ),
    ));

    // Karten-Positionen
    final stackW = cardW * 0.9;
    final deckCenter = Offset(size.width * 0.4, size.height * 0.5);
    final discCenter = Offset(size.width * 0.6, size.height * 0.5);

    // Richtungsanzeige: rotierender Doppelpfeilring zwischen Deck und
    // Ablagestapel, spiegelt bei Gegenuhrzeigersinn (Payback-Karte). Dunkle
    // Scheibe dahinter, sonst geht das Orange im bunten Hintergrundbild unter.
    final tableCenter = Offset((deckCenter.dx + discCenter.dx) / 2, deckCenter.dy);
    final ringSize = (discCenter.dx - deckCenter.dx) + stackW * 1.25;
    const directionColor = Color(0xFFFFA542);
    layers.add(Positioned(
      left: tableCenter.dx - ringSize / 2,
      top: tableCenter.dy - ringSize / 2,
      child: IgnorePointer(
        child: SizedBox(
          width: ringSize,
          height: ringSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Feste, dunkle Kontrastscheibe (dreht sich nicht mit)
              Container(
                width: ringSize * 0.94,
                height: ringSize * 0.94,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.42),
                  boxShadow: [
                    BoxShadow(
                      color: directionColor.withValues(alpha: 0.6),
                      blurRadius: 24,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              Transform(
                alignment: Alignment.center,
                transform: ctrl.isClockwise ? Matrix4.identity() : Matrix4.rotationY(pi),
                child: AnimatedBuilder(
                  animation: _directionCtrl,
                  builder: (_, __) {
                    return Transform.rotate(
                      angle: _directionCtrl.value * 2 * pi,
                      child: Icon(
                        Icons.autorenew,
                        size: ringSize * 0.8,
                        color: directionColor,
                        shadows: const [Shadow(blurRadius: 10, color: Colors.black87)],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ));

    // Reaktionskarte: blitzt kurz groß in der Tischmitte auf — über dem
    // Richtungspfeil, für alle Spieler gleichzeitig sichtbar, nicht nur in
    // einem privaten Dialog beim reagierenden Spieler.
    if (_flashCard != null) {
      final flashW = stackW * 1.7;
      layers.add(Positioned(
        left: tableCenter.dx - flashW / 2,
        top: tableCenter.dy - flashW * 0.65,
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _reactionFlashCtrl,
            builder: (_, child) => Opacity(
              opacity: _reactionFlashOpacity.value,
              child: Transform.scale(scale: _reactionFlashScale.value, child: child),
            ),
            child: Container(
              width: flashW,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(color: Color(0xFFFFA542), blurRadius: 32, spreadRadius: 4),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(CardImageFactory.getCardImagePath(_flashCard!)),
              ),
            ),
          ),
        ),
      ));
    }

    // Deck
    layers.add(Positioned(
      left: deckCenter.dx - stackW / 2,
      top: deckCenter.dy - stackW * 0.6,
      child: AnimatedDeck(
        onDraw: isTurn ? () async => ctrl.drawCard(myId) : null,
        cardWidth: stackW,
        backImagePath: 'lib/images/back_card.png',
        gameId: widget.gameId,
      ),
    ));

    // Ablagestapel
    layers.add(Positioned(
      key: _discardKey,
      left: discCenter.dx - stackW / 2,
      top: discCenter.dy - stackW * 0.6,
      child: SizedBox(
        width: stackW,
        height: stackW * 1.3,
        child: DragTargetWidget(
          gameId: widget.gameId,
          topCard: ctrl.topCardOfDiscardPile,
          isEnabled: isTurn,
          currentPlayerId: myId,
          onCardDropped: (_) async {},
        ),
      ),
    ));

    // Gegner-Avatare — feste Leiste im oberen Drittel, weg von Deck/Ablagestapel
    final opponents = ctrl.players.where((p) => p.id != myId).toList();
    for (var i = 0; i < opponents.length; i++) {
      final double x;
      if (opponents.length == 1) {
        x = size.width / 2;
      } else {
        final fraction = i / (opponents.length - 1);
        x = size.width * 0.12 + fraction * size.width * 0.76;
      }
      // Header-Höhe: edgeM + IconButton (48px) + etwas Abstand
      const headerBottom = edgeM + 56.0;
      final yRaw = size.height * 0.26;
      final y = yRaw < headerBottom + 8 ? headerBottom + 8 : yRaw;
      final opp = opponents[i];

      layers.add(
        StreamBuilder<DatabaseEvent>(
          stream: FirebaseService.instance.listenForPlayerHandUpdates(widget.gameId, opp.id),
          builder: (ctx, handSnap) {
            final handList = handSnap.data?.snapshot.value;
            final count = handList is List ? handList.length : 0;
            final visibleCards = count.clamp(0, 8);
            return Positioned(
              left: x - cardW / 2,
              top: y - cardW / 2,
              child: Column(
                children: [
                  // Mini stacked card backs + count badge
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (visibleCards > 0)
                        SizedBox(
                          width: visibleCards * 7.0 + 18,
                          height: 30,
                          child: Stack(
                            children: List.generate(
                              visibleCards,
                              (i) => Positioned(
                                left: i * 7.0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(3),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black45,
                                          blurRadius: 2,
                                          offset: Offset(1, 1)),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: Image.asset(
                                      'lib/images/back_card.png',
                                      width: 18,
                                      height: 26,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Text(
                          '$count',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Glow + feste Umrandung, wenn dieser Gegner am Zug ist
                  if (ctrl.currentPlayerId == opp.id)
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Pulsierendes Glühen als zusätzlicher Blickfang
                          AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (_, __) {
                              final t = _pulseCtrl.value;
                              final d = 48.0 + 16.0 * t;
                              return Container(
                                width: d,
                                height: d,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.orangeAccent
                                      .withValues(alpha: 0.55 - 0.30 * t),
                                ),
                              );
                            },
                          ),
                          // Feste, immer sichtbare Umrandung (unabhängig von der Animation)
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.orangeAccent,
                                width: 3.5,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black54,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 20,
                              backgroundImage: AssetImage(ctrl.playerAvatar(opp.id)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: AssetImage(ctrl.playerAvatar(opp.id)),
                    ),
                  Text(
                    opp.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      shadows: [Shadow(blurRadius: 2)],
                    ),
                  ),
                  if (ctrl.currentPlayerId == opp.id)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Am Zug',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    }

    // Eigene Hand
    layers.add(Positioned(
      left: 0,
      right: 0,
      bottom: edgeM,
      child: PersistentPlayerHandWidget(
        gameId: widget.gameId,
        playerId: myId,
        cardWidth: cardW.clamp(24.0, 48.0),
        discardKey: _discardKey,
        isMyTurn: isTurn,
        maxVisible: 15,
      ),
    ));

    // Eigener Avatar — dieselbe feste Umrandung + Puls wie bei Gegnern
    // (vorher nur ein schwaches, animationsabhängiges Glühen ohne festen
    // Ring — dadurch stach der eigene Zug visuell schwächer heraus als der
    // der Gegner).
    // Position centres a 84×104 Bereich (Ring + "Am Zug"-Badge darunter);
    // non-turn avatar (54px) uses same anchor
    layers.add(
      Positioned(
        bottom: edgeM + cardW * 1.5 + 40,
        left: size.width / 2 - 42,
        child: isTurn
            ? SizedBox(
                width: 84,
                height: 104,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Pulsierendes Glühen als zusätzlicher Blickfang
                          AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (_, __) {
                              final t = _pulseCtrl.value; // 0.0 → 1.0 → 0.0
                              final d = 58.0 + 22.0 * t;
                              return Container(
                                width: d,
                                height: d,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.orangeAccent
                                      .withValues(alpha: 0.55 - 0.30 * t),
                                ),
                              );
                            },
                          ),
                          // Feste, immer sichtbare Umrandung (unabhängig von der Animation)
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.orangeAccent, width: 3.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                            child: const CircleAvatar(
                              radius: 27,
                              backgroundImage: AssetImage('lib/images/man.png'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Du bist dran',
                        style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              )
            : const CircleAvatar(
                radius: 27,
                backgroundImage: AssetImage('lib/images/man.png'),
              ),
      ),
    );

    // MicButton rechts unten
    layers.add(
      Positioned(
        bottom: cardW * 1.6 + 32,
        right: 16,
        child: StreamBuilder<DatabaseEvent>(
          stream: FirebaseDatabase.instance
              .ref('games/${widget.gameId}/players/$myId/handCardIds')
              .onValue,
          builder: (ctx, handSnap) {
            final handList =
                handSnap.data?.snapshot.value as List<dynamic>? ?? [];
            final cardCount = handList.length;

            return StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance
                  .ref('games/${widget.gameId}/gameState/mic/$myId')
                  .onValue,
              builder: (ctx2, micSnap) {
                final micStatus = micSnap.data?.snapshot.value as String?;

                final showButton =
                    (micStatus == null && (cardCount == 1 || cardCount == 2));

                if (showButton) {
                  if (cardCount != _lastHandCount) {
                    WidgetsBinding.instance
                        .addPostFrameCallback((_) => _popCtrl.forward(from: 0));
                  }
                  _lastHandCount = cardCount;

                  return ScaleTransition(
                    scale: _popAnim,
                    child: MicActionButton(
                      isCheck: cardCount == 2,
                      onPressed: () {
                        if (cardCount == 2) {
                          FirebaseService.instance
                              .markMicCheck(widget.gameId, myId);
                        } else {
                          FirebaseService.instance
                              .markMicDrop(widget.gameId, myId);
                        }
                      },
                    ),
                  );
                }

                _lastHandCount = cardCount;
                return const SizedBox.shrink();
              },
            );
          },
        ),
      ),
    );

    return Stack(children: layers);
  }
}
