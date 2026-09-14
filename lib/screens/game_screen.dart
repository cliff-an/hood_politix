import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/avatar_catalog.dart';
import '../models/firebase_service.dart';
import '../models/game_controller.dart';
import '../widgets/gameboard_widget.dart';
import '../widgets/start_video_overlay.dart';
import 'game_over_screen.dart';

class GameScreen extends StatefulWidget {
  final String gameId;
  const GameScreen({super.key, required this.gameId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool isLoading = true;
  bool navigated = false;
  bool showStartVideo = false;
  bool _isFillingBots = false;

  @override
  void initState() {
    super.initState();
    _initialize();
    _listenForStartVideo();
    _listenToGameChanges();
  }

  /// Initialisiert den GameController und lädt den Spielzustand
  Future<void> _initialize() async {
    GameController.initializeInstance(widget.gameId, FirebaseService.instance);
    await GameController.instance.initializeGameIfNeeded();
    if (mounted) setState(() => isLoading = false);
  }

  /// Lauscht auf das Startvideo-Signal aus der DB
  void _listenForStartVideo() {
    FirebaseDatabase.instance
        .ref('games/${widget.gameId}/gameState/startVideo')
        .onValue
        .listen((event) {
      final val = event.snapshot.value;
      if (val == true && !showStartVideo) {
        setState(() => showStartVideo = true);
        Future.delayed(const Duration(seconds: 8), () {
          if (mounted) setState(() => showStartVideo = false);
        });
      }
    });
  }

  /// Lauscht auf Änderungen im Spielstatus
  void _listenToGameChanges() {
    // The StreamBuilder in build() handles state='finished' and playersCount<=1.
    // This listener handles placements arriving independently (belt-and-suspenders).
    FirebaseDatabase.instance
        .ref('games/${widget.gameId}/placements')
        .onValue
        .listen((event) {
      if (!mounted || !event.snapshot.exists) return;
      _navigateToGameOver();
    });
  }

  /// Navigiert zum GameOverScreen
  void _navigateToGameOver() {
    if (navigated) return;
    navigated = true;

    final ctrl = GameController.instance;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: ctrl,
          child: GameOverScreen(gameId: widget.gameId),
        ),
      ),
    );
  }

  /// Versucht, das Spiel zu starten
  Future<void> _tryStartGame() async {
    final players = await FirebaseService.instance.fetchPlayers(widget.gameId);
    if (!mounted) return;
    if (players.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mindestens 2 Spieler erforderlich!')),
      );
      return;
    }

    final shuffled = [...players]..shuffle();
    final startPlayer = shuffled.first;
    await FirebaseService.instance.startGame(widget.gameId, startPlayer.id);
  }

  /// Füllt den Warteraum bis zur in meta/targetPlayerCount hinterlegten
  /// Ziel-Spieleranzahl mit Bots auf. fillWithBots ist selbst idempotent
  /// (liest die aktuelle Spielerzahl neu) — der Guard hier verhindert nur
  /// unnötige Doppel-Aufrufe durch schnelles Doppel-Tippen.
  Future<void> _fillWithBots(int targetPlayerCount) async {
    if (_isFillingBots) return;
    setState(() => _isFillingBots = true);
    try {
      await FirebaseService.instance.fillWithBots(widget.gameId, targetPlayerCount);
    } finally {
      if (mounted) setState(() => _isFillingBots = false);
    }
  }

  /// Teilt den Beitritts-Code dieses Spiels über die native Share-Sheet.
  Future<void> _shareJoinCode(String gameId) async {
    final snap = await FirebaseDatabase.instance.ref('games/$gameId/meta/joinCode').get();
    final code = snap.exists ? snap.value.toString() : null;
    if (code == null) return;
    await SharePlus.instance.share(
      ShareParams(text: 'Spiel mir bei Hood Politix! Code: $code'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: null,
      body: Stack(
        children: [
          // Hintergrundbild
          Positioned.fill(
            child: Image.asset('lib/images/background.png', fit: BoxFit.cover),
          ),

          SafeArea(
            child: StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance
                  .ref('games/${widget.gameId}/players')
                  .onValue,
              builder: (ctx, playersSnap) {
                if (!playersSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final raw = playersSnap.data!.snapshot.value;
                final playersMap =
                    (raw is Map) ? raw.cast<String, dynamic>() : {};
                final playersCount = playersMap.length;

                return StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref('games/${widget.gameId}/gameState/state')
                      .onValue,
                  builder: (ctx2, stateSnap) {
                    if (!stateSnap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final state =
                        stateSnap.data!.snapshot.value?.toString() ?? '';

                    // 1️⃣ Spiel vorbei — warten bis placements geschrieben sind
                    if (state == 'finished') {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted || navigated) return;
                        // Wait for placements node (written by endGame / _endGameWithLeave)
                        await FirebaseDatabase.instance
                            .ref('games/${widget.gameId}/placements')
                            .onValue
                            .firstWhere((e) => e.snapshot.exists);
                        _navigateToGameOver();
                      });
                      return const SizedBox.shrink();
                    }

                    // 2️⃣ Spiel läuft, aber nur noch ≤1 Spieler aktiv
                    // (leaveGame setzt state=finished + placements, also hier auch warten)
                    if (state == 'in progress' && playersCount <= 1) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted || navigated) return;
                        await FirebaseDatabase.instance
                            .ref('games/${widget.gameId}/placements')
                            .onValue
                            .firstWhere((e) => e.snapshot.exists);
                        _navigateToGameOver();
                      });
                      return const SizedBox.shrink();
                    }

                    // 3️⃣ Spiel läuft normal
                    if (state == 'in progress') {
                      return ChangeNotifierProvider.value(
                        value: GameController.instance,
                        child: GameBoard(gameId: widget.gameId),
                      );
                    }

                    // 4️⃣ Wartezustand (noch nicht gestartet)
                    final names = playersMap.values
                        .map((v) => (v as Map)['name'] as String? ?? '—')
                        .toList();
                    final isBotFlags = playersMap.values
                        .map((v) => (v as Map)['isBot'] == true)
                        .toList();
                    final humanCount =
                        isBotFlags.where((isBot) => !isBot).length;
                    final canStart = names.length >= 2;

                    return StreamBuilder<DatabaseEvent>(
                      stream: FirebaseDatabase.instance
                          .ref('games/${widget.gameId}/meta')
                          .onValue,
                      builder: (ctx3, metaSnap) {
                        final metaRaw = metaSnap.data?.snapshot.value;
                        final metaMap = (metaRaw is Map)
                            ? metaRaw.cast<String, dynamic>()
                            : <String, dynamic>{};
                        final mode = metaMap['mode']?.toString() ?? 'normal';
                        final targetPlayerCount =
                            (metaMap['targetPlayerCount'] as num?)?.toInt();

                        // Bot-Auffüllen nur für normale Spiele mit gesetztem
                        // Ziel, solange noch Platz ist — und erst ab 2
                        // echten Menschen (der Block fehlt komplett, nicht
                        // nur deaktiviert, solange nur 1 Mensch da ist).
                        final showBotFill = mode == 'normal' &&
                            targetPlayerCount != null &&
                            playersMap.length < targetPlayerCount &&
                            humanCount >= 2;
                        final botsNeeded = targetPlayerCount != null
                            ? targetPlayerCount - playersMap.length
                            : 0;

                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text("Warte auf Spielstart…",
                                  style: TextStyle(fontSize: 16)),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                alignment: WrapAlignment.center,
                                children: List.generate(names.length, (i) {
                                  return Chip(
                                    avatar:
                                        isBotFlags[i] ? const Text('🤖') : null,
                                    label: Text(names[i]),
                                  );
                                }),
                              ),
                              if (showBotFill) ...[
                                const SizedBox(height: 16),
                                Text(
                                  '👥 $humanCount/$targetPlayerCount Spieler',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    const OutlinedButton(
                                      onPressed: null,
                                      child: Text('Auf echte Spieler warten'),
                                    ),
                                    ElevatedButton(
                                      onPressed: _isFillingBots
                                          ? null
                                          : () => _fillWithBots(targetPlayerCount),
                                      child: Text(
                                          'Mit $botsNeeded Bots starten'),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                alignment: WrapAlignment.center,
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.person_add),
                                    label: const Text('Freund einladen'),
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) =>
                                          _InviteFriendDialog(gameId: widget.gameId),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.share),
                                    label: const Text('Code teilen'),
                                    onPressed: () => _shareJoinCode(widget.gameId),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: canStart ? _tryStartGame : null,
                                child: Text('Spiel starten (${names.length})'),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // 5️⃣ Startvideo Overlay
          if (showStartVideo) const StartVideoOverlay(),
        ],
      ),
    );
  }
}

/// Zeigt die Freundesliste, um einen Freund direkt in dieses Spiel einzuladen.
class _InviteFriendDialog extends StatelessWidget {
  final String gameId;
  const _InviteFriendDialog({required this.gameId});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final svc = FirebaseService.instance;

    return AlertDialog(
      title: const Text('Freund einladen'),
      content: SizedBox(
        width: 320,
        child: StreamBuilder<List<String>>(
          stream: svc.getFriendsStream(myUid),
          builder: (context, snap) {
            final friends = snap.data ?? [];
            if (friends.isEmpty) {
              return const Text('Noch keine Freunde zum Einladen.');
            }
            return SizedBox(
              height: 300,
              child: ListView(
                shrinkWrap: true,
                children: friends.map((friendUid) {
                  return FutureBuilder<Map<String, dynamic>?>(
                    future: svc.getUserProfile(friendUid),
                    builder: (context, profileSnap) {
                      final name = profileSnap.data?['username']?.toString() ?? '…';
                      final avatarPath =
                          resolveAvatarPath(profileSnap.data?['avatarId']?.toString());
                      return ListTile(
                        leading: CircleAvatar(backgroundImage: AssetImage(avatarPath)),
                        title: Text(name),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            await svc.inviteFriendToGame(gameId, myUid, friendUid);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('$name eingeladen.')),
                              );
                            }
                          },
                          child: const Text('Einladen'),
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
      ],
    );
  }
}
