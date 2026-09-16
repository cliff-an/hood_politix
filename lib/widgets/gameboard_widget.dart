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
import '../screens/lobby_screen.dart';
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

  // Emoji-Reaktionen: fliegen kurz über dem Avatar des Senders hoch und
  // blenden aus. Nur eine feste, moderierte Auswahl (siehe _quickEmojis) —
  // bewusst kein Freitext-Chat, damit unangemessene Kommentare gar nicht
  // erst möglich sind.
  late final AnimationController _emojiBubbleCtrl;
  late final Animation<double> _emojiBubbleOpacity;
  late final Animation<Offset> _emojiBubbleRise;
  int _seenEmojiSeq = -1;
  String? _emojiBubbleText;
  Offset? _emojiBubblePos;

  static const List<String> _quickEmojis = [
    '😂', '😮', '😡', '👍', '👎', '🔥', '😱', '🤔', '💀', '🎉', '👀', '🙏',
  ];

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

    // Emoji-Bubble: poppt kurz hoch, steigt leicht auf, blendet aus.
    _emojiBubbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _emojiBubbleOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_emojiBubbleCtrl);
    _emojiBubbleRise = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, -0.9),
    ).animate(CurvedAnimation(parent: _emojiBubbleCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _popCtrl.dispose();
    _directionCtrl.dispose();
    _reactionFlashCtrl.dispose();
    _emojiBubbleCtrl.dispose();
    super.dispose();
  }

  Future<void> _showEmojiPicker(BuildContext context, String gameId, String myId) async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: _quickEmojis
                .map(
                  (e) => InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => Navigator.of(ctx).pop(e),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(e, style: const TextStyle(fontSize: 30)),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
    if (emoji != null) {
      await FirebaseService.instance.sendEmojiReaction(gameId, myId, emoji);
    }
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

    // Neue Emoji-Reaktion gemeldet -> Bubble über dem Avatar des Senders
    // anstoßen (Position wird weiter unten beim Layout der Avatare befüllt,
    // deshalb hier nur den Seq-Stand + Emoji merken; die genaue Position
    // wird unten anhand von avatarPositions aufgelöst).
    final pendingEmojiSeq = ctrl.emojiSeq != _seenEmojiSeq && ctrl.lastEmoji != null
        ? ctrl.emojiSeq
        : null;

    final size = MediaQuery.of(context).size;

    final shortestSide = min(size.width, size.height);
    final isLandscape = size.width > size.height;
    final cardW = (isLandscape ? shortestSide * 0.11 : shortestSide * 0.10)
        .clamp(48.0, 80.0);
    const edgeM = 16.0;

    // WICHTIG: MediaQuery.size ist in logischen Pixeln (dp), NICHT den
    // physischen Pixeln eines Screenshots. Ein reales Telefon im
    // Querformat hat oft nur ~350-450dp Höhe (z. B. Pixel 4a: 1080px bei
    // devicePixelRatio 2.75 -> ~393dp) — deutlich weniger, als cardW
    // allein (unten bei 48 gedeckelt) vermuten lässt. Avatar-Kreise,
    // Puls-Ringe und Abzeichen waren bisher mit festen dp-Werten codiert,
    // die für ein "großzügiges" Display kalibriert waren; auf einem
    // realen Telefon blieb dadurch schlicht nicht genug Höhe für Header +
    // Gegner-Bogen + Tischmitte + eigenen Avatar + Hand übrig — DESHALB
    // landete der eigene Avatar mitten im Ring, unabhängig von dessen
    // Größe. vScale schrumpft alle Avatar-Größen (nicht nur deren
    // Position) proportional zur tatsächlich verfügbaren Höhe.
    final vScale = (size.height / 500.0).clamp(0.55, 1.0);

    // Feste Avatar-Größen, EINMAL hier definiert und unten sowohl bei der
    // Ring-Platzbudget-Berechnung als auch beim tatsächlichen Rendern der
    // Avatare wiederverwendet (nie zwei getrennte Zahlen für dieselbe
    // Sache) — genau das Auseinanderlaufen zweier unabhängig gepflegter
    // Konstanten für ein und dieselbe Box war die Ursache dafür, dass der
    // eigene Avatar trotz mehrerer "Fixes" weiter in den Ring hineinragte.
    final oppAvatarBoxSize = 40.0 * vScale;
    final ownAvatarBoxSize = 48.0 * vScale;
    final ownAvatarBadgeAllowance = 20.0 * vScale;

    if (ctrl.currentPlayerId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Widget> layers = [];

    // Hintergrund
    layers.add(Positioned.fill(
      child: Image.asset('lib/images/background.png', fit: BoxFit.cover),
    ));
    // Leichte Abdunkelung zu den Rändern hin — wie auf dem Login-Screen.
    // Kaschiert nebenbei die Übergänge im seitlich gespiegelt erweiterten
    // Hintergrundbild und sorgt für mehr Kontrast zu den UI-Elementen.
    layers.add(const Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.05,
              colors: [Colors.transparent, Colors.black45],
            ),
          ),
        ),
      ),
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
                  // ERST den Controller (Zug-Timer, BotGameDriver, alle
                  // Firebase-Listener) abbauen, DANN leaveGame aufrufen —
                  // nicht umgekehrt. leaveGame entfernt uns aus players/,
                  // und danach hat dieser Client keine Schreibrechte mehr
                  // auf das Spiel. Lief der Controller noch, konnte einer
                  // seiner Listener (z. B. der Zug-Timer oder — als
                  // gewählter Anführer — der BotGameDriver) durch genau
                  // diesen Schreibzugriff selbst nochmal ausgelöst werden
                  // und mit PERMISSION_DENIED scheitern.
                  if (GameController.hasInstance) {
                    GameController.instance.dispose();
                  }
                  await svc.leaveGame(widget.gameId, myId);
                  // Kein Navigator.pop(): GameScreen wird nur per
                  // pushReplacement erreicht, der Verlaufsstapel hat also
                  // keinen vorherigen Eintrag zum Zurückspringen — pop()
                  // führte hier zu einem weißen Screen. Stattdessen wie
                  // beim "Zur Lobby"-Button in GameOverScreen direkt zur
                  // Lobby navigieren.
                  navigator.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => LobbyScreen(userId: myId)),
                    (_) => false,
                  );
                },
              ),
            ],
          );
        },
      ),
    ));

    // Karten-Positionen — dieselbe Breite wie die Handkarten (siehe
    // cardWidth weiter unten bei PersistentPlayerHandWidget), damit Deck,
    // Ablagestapel und Handkarten gleich groß wirken.
    final stackW = cardW.clamp(24.0, 48.0);

    // Vertikales Platzbudget: erst berechnen, WO die Gegner- und die
    // eigene Avatar-Zone tatsächlich enden/beginnen (auf Basis derselben
    // Größen, die unten beim Rendern verwendet werden — siehe
    // oppAvatarBoxSize/ownAvatarBoxSize oben), dann Deck/Ablage/Ring
    // MITTIG in die verbleibende Lücke setzen, statt sie unabhängig davon
    // auf eine feste Bildschirmmitte (0.5) zu legen. Eine feste Mitte
    // ignoriert, dass Kopf- und Handbereich unterschiedlich viel Platz
    // brauchen, und genau das ließ auf kurzen Querformat-Bildschirmen
    // (z. B. Pixel 4a: ~393dp Höhe) beide Avatar-Zonen bis übers Zentrum
    // hinausreichen.
    final baseY = size.height * 0.30;
    final arcLift = size.height * 0.15;
    // Header-Höhe: edgeM + IconButton (48px) + Platz für bis zu zwei
    // gestapelte Badges (aktueller Spieler + Countdown) — begrenzt, wie
    // weit der Bogen-Gegner nach oben gezogen werden darf (siehe
    // Opponents-Schleife unten), muss hier also für den ungünstigsten
    // Fall genauso berücksichtigt werden. Bewusst NICHT mit vScale
    // geschrumpft: Text/Icon-Mindestgrößen sind fix, nicht die Ursache
    // des Platzproblems.
    const headerBottom = edgeM + 56.0;
    const minY = headerBottom + 8;
    // Tatsächliche Gegner-Spalte (von oben nach unten): Mini-Kartenreihe
    // (~30) + Abstand (4*vScale) + Avatar-Box (oppAvatarBoxSize) + Name
    // (~14) + "Am Zug"-Badge (~14, nur wenn dieser Gegner am Zug ist —
    // worst case also mitgerechnet). Die Avatar-Box wird an ihrem
    // MITTELPUNKT positioniert (siehe "top: y - cardW/2" unten in der
    // Opponents-Schleife), ihr sichtbarer oberer Rand liegt also um
    // cardW/2 HÖHER als y — deshalb hier abgezogen, sonst würde die Zone
    // künstlich zu tief angesetzt.
    final avatarClearance = 58.0 + 4.0 * vScale + oppAvatarBoxSize - cardW / 2;
    final oppAvatarBottom = max(baseY - arcLift, minY) + avatarClearance;
    // Untere Zone: der eigene Avatar sitzt NICHT mehr oberhalb der Hand,
    // sondern seitlich daneben (siehe unten bei "Eigener Avatar") — braucht
    // hier also keinen eigenen Platz mehr. Einzige verbleibende Grenze ist
    // die Hand selbst: Sie fächert sich leicht auf (siehe
    // PersistentPlayerHandWidget._buildFan, "height = cardW*1.5 + 32" —
    // die mittlere Karte reicht bis ganz an die Oberkante dieser Zone),
    // plus ein kleiner Sicherheitsabstand zum Ring.
    const handFanAllowance = 32.0;
    const ringToHandGap = 12.0;
    final handZoneTop =
        size.height - (edgeM + cardW * 1.5 + handFanAllowance + ringToHandGap);
    final ringMargin = 10.0 * vScale;
    final verticalCenterY = (oppAvatarBottom + handZoneTop) / 2;
    final deckCenter = Offset(size.width * 0.4, verticalCenterY);
    final discCenter = Offset(size.width * 0.6, verticalCenterY);
    // Richtungsanzeige: rotierender Pfeilring zwischen Deck und
    // Ablagestapel, spiegelt bei Gegenuhrzeigersinn (Payback-Karte). Dunkle
    // Scheibe dahinter, sonst geht das Orange im bunten Hintergrundbild unter.
    final tableCenter = Offset((deckCenter.dx + discCenter.dx) / 2, deckCenter.dy);
    final maxRingRadiusForAvatars = min(
      tableCenter.dy - oppAvatarBottom,
      handZoneTop - tableCenter.dy,
    ) - ringMargin;
    // Kein hoher fester Mindestradius mehr (der frühere 48px-Boden
    // erzwang auf engen Bildschirmen einen Ring, der größer war als der
    // tatsächlich sichere Platz — und überlappte dadurch trotz negativem
    // maxRingRadiusForAvatars die Avatare). 16px ist nur ein Notanker
    // gegen einen unsichtbaren Ring, kein Zielwert.
    final ringSize = min(
      (discCenter.dx - deckCenter.dx) + stackW * 1.25,
      max(16.0, maxRingRadiusForAvatars) * 2,
    );
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
                      child: SizedBox(
                        width: ringSize * 0.7,
                        height: ringSize * 0.7,
                        child: CustomPaint(
                          painter: _CircularArrowPainter(
                            color: directionColor,
                            strokeWidth: ringSize * 0.7 * 0.1,
                          ),
                        ),
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

    // Ablagestapel — gleiche Kartenbreite wie Deck/Handkarten (cardWidth,
    // Höhe = cardWidth * 1.5), statt der vorherigen festen 150x180px, die
    // auf den meisten Bildschirmen deutlich größer als Deck/Hand wirkten.
    layers.add(Positioned(
      key: _discardKey,
      left: discCenter.dx - stackW / 2,
      top: discCenter.dy - stackW * 0.6,
      child: DragTargetWidget(
        gameId: widget.gameId,
        topCard: ctrl.topCardOfDiscardPile,
        isEnabled: isTurn,
        currentPlayerId: myId,
        cardWidth: stackW,
        onCardDropped: (_) async {},
      ),
    ));

    // Gegner-Avatare — auf einem Bogen über dem Tisch, wie am runden Tisch
    // sitzend. Bei genau einem Gegner bewusst mittig (klassisches
    // 1-gegen-1-Layout). Ab zwei Gegnern werden sie entlang eines Halbkreis-
    // Bogens verteilt: die äußeren sitzen auf gleicher Höhe wie früher, die
    // mittleren werden nach oben gezogen. Das vermeidet automatisch, dass
    // bei ungerader Gegnerzahl einer exakt auf x=50% landet — genau dort,
    // wo der eigene Avatar samt Zug-Ring sitzt (siehe tableCenter unten) —,
    // weil dieser mittlere Gegner stattdessen am höchsten Punkt des Bogens
    // sitzt und so am weitesten vom eigenen Avatar entfernt ist.
    final opponents = ctrl.players.where((p) => p.id != myId).toList();
    // headerBottom/minY/baseY/arcLift werden schon oben bei der
    // Ring-Größenberechnung gebraucht (siehe dort) und deshalb nicht hier
    // neu deklariert.
    // Avatar-Positionen je Spieler merken, damit Emoji-Reaktionen (siehe
    // unten) an der richtigen Stelle auftauchen können.
    final Map<String, Offset> avatarPositions = {};
    for (var i = 0; i < opponents.length; i++) {
      final double x;
      final double y;
      if (opponents.length == 1) {
        x = size.width / 2;
        y = baseY < minY ? minY : baseY;
      } else {
        const marginX = 0.08;
        final t = i / (opponents.length - 1); // 0..1, links nach rechts
        final theta = pi - t * pi; // pi..0, schwenkt über den Scheitel
        final radiusX = size.width * (0.5 - marginX);
        x = size.width * 0.5 + radiusX * cos(theta);
        final rawY = baseY - arcLift * sin(theta);
        y = rawY < minY ? minY : rawY;
      }
      final opp = opponents[i];
      avatarPositions[opp.id] = Offset(x, y);

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
                  SizedBox(height: 4 * vScale),
                  // Glow + feste Umrandung, wenn dieser Gegner am Zug ist
                  if (ctrl.currentPlayerId == opp.id)
                    SizedBox(
                      width: oppAvatarBoxSize,
                      height: oppAvatarBoxSize,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Pulsierendes Glühen als zusätzlicher Blickfang
                          AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (_, __) {
                              final t = _pulseCtrl.value;
                              final d = (28.0 + 8.0 * t) * vScale;
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
                            width: 30 * vScale,
                            height: 30 * vScale,
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
                              radius: 13 * vScale,
                              backgroundImage: AssetImage(ctrl.playerAvatar(opp.id)),
                            ),
                          ),
                          if (opp.isBot)
                            const Positioned(
                              right: 2,
                              bottom: 2,
                              child: Text('🤖', style: TextStyle(fontSize: 14)),
                            ),
                        ],
                      ),
                    )
                  else
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 13 * vScale,
                          backgroundImage: AssetImage(ctrl.playerAvatar(opp.id)),
                        ),
                        if (opp.isBot)
                          const Positioned(
                            right: -2,
                            bottom: -2,
                            child: Text('🤖', style: TextStyle(fontSize: 14)),
                          ),
                      ],
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
        cardWidth: stackW,
        discardKey: _discardKey,
        isMyTurn: isTurn,
        maxVisible: 15,
      ),
    ));

    // Eigener Avatar — dieselbe feste Umrandung + Puls wie bei Gegnern
    // (vorher nur ein schwaches, animationsabhängiges Glühen ohne festen
    // Ring — dadurch stach der eigene Zug visuell schwächer heraus als der
    // der Gegner). Sitzt bewusst NEBEN der Hand (unten links), nicht mehr
    // MITTIG DARÜBER: die Handkarten fächern sich leicht auf (siehe
    // PersistentPlayerHandWidget._buildFan), die mittlere Karte reicht
    // dabei bis an die Oberkante der Hand-Zone — genau dort saß vorher der
    // eigene Avatar zentriert und überlappte deshalb mit ihr. Seitlich
    // davon reicht selbst bei maximal vielen Handkarten keine Karte hin
    // (Fächer-Öffnungswinkel ist auf 45° begrenzt, siehe dort).
    final ownBoxW = ownAvatarBoxSize;
    final ownBoxH = ownAvatarBoxSize + ownAvatarBadgeAllowance;
    final ownBottomOffset = edgeM + (cardW * 1.5 - ownBoxH) / 2;
    avatarPositions[myId] = Offset(
      edgeM + ownBoxW / 2,
      size.height - ownBottomOffset - ownBoxH / 2,
    );
    layers.add(
      Positioned(
        bottom: ownBottomOffset,
        left: edgeM,
        child: isTurn
            // Kein umschließender SizedBox(width: ownBoxW) mehr um die
            // ganze Column: das zwang auch das "Du bist dran"-Badge auf
            // die schmale Avatar-Kreis-Breite, wodurch der Text auf zwei
            // Zeilen umbrach und über den unten fest zugewiesenen Platz
            // hinausragte (RenderFlex-Overflow). Ohne Breitenzwang darf
            // das Badge so breit werden, wie sein Text braucht — genau
            // wie beim Gegner-Pendant ("Am Zug"), das nie in eine feste
            // Box gezwungen wurde.
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    SizedBox(
                      width: ownBoxW,
                      height: ownBoxW,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Pulsierendes Glühen als zusätzlicher Blickfang
                          AnimatedBuilder(
                            animation: _pulseCtrl,
                            builder: (_, __) {
                              final t = _pulseCtrl.value; // 0.0 → 1.0 → 0.0
                              final d = (34.0 + 10.0 * t) * vScale;
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
                            width: 36 * vScale,
                            height: 36 * vScale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.orangeAccent, width: 3.5),
                              boxShadow: const [
                                BoxShadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                            child: CircleAvatar(
                              radius: 16 * vScale,
                              backgroundImage: const AssetImage('lib/images/man.png'),
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
              )
            : CircleAvatar(
                radius: 16 * vScale,
                backgroundImage: const AssetImage('lib/images/man.png'),
              ),
      ),
    );

    // Emoji-Reaktion eines Spielers: Bubble über dessen Avatar anstoßen,
    // sobald sich dessen Position (Gegner oder man selbst) auflösen lässt.
    if (pendingEmojiSeq != null) {
      final pos = avatarPositions[ctrl.lastEmojiSenderId];
      if (pos != null) {
        _seenEmojiSeq = pendingEmojiSeq;
        final text = ctrl.lastEmoji!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _emojiBubbleText = text;
            _emojiBubblePos = pos;
          });
          _emojiBubbleCtrl.forward(from: 0);
        });
      }
    }
    if (_emojiBubbleText != null && _emojiBubblePos != null) {
      layers.add(
        Positioned(
          left: _emojiBubblePos!.dx - 22,
          top: _emojiBubblePos!.dy - 60,
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _emojiBubbleCtrl,
              builder: (_, child) => Opacity(
                opacity: _emojiBubbleOpacity.value,
                child: FractionalTranslation(
                  translation: _emojiBubbleRise.value,
                  child: child,
                ),
              ),
              child: Text(_emojiBubbleText!, style: const TextStyle(fontSize: 40)),
            ),
          ),
        ),
      );
    }

    // Emoji-Button links unten — feste, moderierte Auswahl statt Freitext,
    // damit Spieler ohne unangemessene Kommentare miteinander interagieren
    // können.
    layers.add(
      Positioned(
        bottom: cardW * 1.6 + 32,
        left: 16,
        child: FloatingActionButton.small(
          heroTag: 'emojiPicker',
          backgroundColor: Colors.black54,
          onPressed: () => _showEmojiPicker(context, widget.gameId, myId),
          child: const Text('😀', style: TextStyle(fontSize: 20)),
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

/// Zeichnet zwei kurze, dünne Pfeilbögen (Kreislauf-Symbol) für die
/// Richtungsanzeige: EIN durchgehender Bogen (fast ein voller Kreis) mit
/// EINER klaren Pfeilspitze am Ende — wie ein "Neu laden"/Rotations-Icon.
/// Die vorherige Version zeichnete zwei kurze 120°-Bögen mit 60°-Lücken:
/// bei typischer Ringgröße war der sichtbare "Schaft" vor jeder Spitze so
/// kurz, dass das Ganze eher wie zwei Klammern "( )" aussah als wie
/// Pfeile. Ein einzelner langer Bogen liest sich eindeutig als Pfeil, weil
/// Schaft und Spitze klar auseinanderzuhalten sind.
class _CircularArrowPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _CircularArrowPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - strokeWidth;
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      // butt statt round: strokeCap gilt für BEIDE Enden des Bogens, nicht
      // nur das Startende — ein rundes Ende an der Pfeilspitze-Seite fügt
      // dort einen kleinen runden "Klecks" direkt an der Spitze hinzu
      // (sichtbar als Ausbuchtung außerhalb des Dreiecks), statt dass die
      // Spitze sauber spitz zuläuft.
      ..strokeCap = StrokeCap.butt;
    final headPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    const startAngle = -pi / 2;
    // ~290° Bogen: fast ein voller Kreis, aber mit sichtbarer Lücke, damit
    // klar erkennbar bleibt, dass es sich um einen Pfeil und keinen
    // geschlossenen Ring handelt.
    const sweepAngle = 2 * pi * 0.8;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );

    final endAngle = startAngle + sweepAngle;
    final tip = center + Offset(cos(endAngle), sin(endAngle)) * radius;
    final travel = endAngle + pi / 2;
    final dir = Offset(cos(travel), sin(travel));
    final normal = Offset(-dir.dy, dir.dx);
    final headLen = strokeWidth * 3.6;
    final headWidth = strokeWidth * 3.0;
    final base = tip - dir * headLen;
    final p1 = base + normal * (headWidth / 2);
    final p2 = base - normal * (headWidth / 2);

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();
    canvas.drawPath(path, headPaint);
  }

  @override
  bool shouldRepaint(covariant _CircularArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
