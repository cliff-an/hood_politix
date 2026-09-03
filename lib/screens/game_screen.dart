import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
                    final canStart = names.length >= 2;

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
                            children:
                                names.map((n) => Chip(label: Text(n))).toList(),
                          ),
                          const SizedBox(height: 20),
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
            ),
          ),

          // 5️⃣ Startvideo Overlay
          if (showStartVideo) const StartVideoOverlay(),
        ],
      ),
    );
  }
}
