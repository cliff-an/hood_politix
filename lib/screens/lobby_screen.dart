import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/firebase_service.dart';
import '../models/game_meta.dart';
import '../models/game_controller.dart';
import 'friends_screen.dart';
import 'game_screen.dart';
import 'profile_screen.dart';

class LobbyScreen extends StatelessWidget {
  final String userId;
  const LobbyScreen({super.key, required this.userId});

  /// Falls ein alter GameController aktiv ist → sauber beenden
  Future<void> _disposeControllerIfExists() async {
    if (GameController.hasInstance) {
      try {
        GameController.instance.dispose();
      } catch (e) {
        debugPrint("Fehler beim Dispose des Controllers: $e");
      }
    }
  }

  /// Spieler tritt einem bestehenden Spiel bei und navigiert weiter
  Future<void> _joinAndNavigate(BuildContext context, String gameId) async {
    final svc = context.read<FirebaseService>();
    await _disposeControllerIfExists();
    final userName = await svc.getCurrentUserName(userId);

    await svc.joinGame(gameId, userId, userName);

    // Controller initialisieren
    final controller = GameController.initializeInstance(gameId, svc);
    await controller.initializeGameIfNeeded();

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(gameId: gameId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<FirebaseService>();
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text("Lobby"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Freunde',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FriendsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Mein Profil',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen(uid: userId)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'lib/images/background_4.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<GameMeta>>(
                    stream: svc.getGamesMetaStream(), // jetzt als Stream-Version
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(child: Text('Fehler: ${snap.error}'));
                      }

                      final now = DateTime.now().millisecondsSinceEpoch;
                      const endedExpiry = 5 * 60 * 1000;
                      const createdExpiry = 24 * 60 * 60 * 1000;

                      final visible = <GameMeta>[];
                      for (var g in snap.data ?? []) {
                        // ⏰ Abgelaufene Spiele löschen
                        if (g.endedAt != null &&
                            now - g.endedAt! > endedExpiry) {
                          svc.deleteGame(g.id);
                          continue;
                        }

                        if (now - g.createdAt > createdExpiry) {
                          svc.deleteGame(g.id);
                          continue;
                        }

                        final isFinished =
                            g.endedAt != null || g.state == 'finished';
                        final isParticipant = g.playerIds.contains(userId);
                        final isWaiting = g.state == 'waiting' ||
                            g.state == 'waiting for players';
                        if ((isWaiting || isParticipant) && !isFinished) {
                          visible.add(g);
                        }
                      }

                      if (visible.isEmpty) {
                        return const Center(
                            child: Text("Keine verfügbaren Spiele."));
                      }

                      return ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (_, i) {
                          final g = visible[i];
                          return ListTile(
                            title: Text(
                              g.name,
                              style: const TextStyle(
                                  color: Color.fromARGB(255, 201, 181, 1)),
                            ),
                            subtitle: Text(
                              'Erstellt: ${DateTime.fromMillisecondsSinceEpoch(g.createdAt)}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color.fromARGB(179, 5, 3, 3)),
                            ),
                            onTap: () => _joinAndNavigate(context, g.id),
                          );
                        },
                      );
                    },
                  ),
                ),

                // ➕ Neues Spiel erstellen
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = await showDialog<String>(
                        context: context,
                        builder: (_) => const _NewGameNameDialog(),
                      );
                      if (name == null || name.trim().isEmpty) return;

                      try {
                        final alreadyInGame =
                            await svc.isPlayerAlreadyInGame(userId);
                        if (!context.mounted) return;
                        if (alreadyInGame) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Du bist bereits in einem laufenden Spiel.')),
                          );
                          return;
                        }

                        await _disposeControllerIfExists();
                        final newGameId =
                            await svc.createNewGame(name.trim(), userId);
                        if (!context.mounted) return;
                        await _joinAndNavigate(context, newGameId);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Erstellen fehlgeschlagen: $e')),
                        );
                      }
                    },
                    child: const Text('Neues Spiel erstellen'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog zur Eingabe des neuen Spielnamens
class _NewGameNameDialog extends StatefulWidget {
  const _NewGameNameDialog();

  @override
  State<_NewGameNameDialog> createState() => _NewGameNameDialogState();
}

class _NewGameNameDialogState extends State<_NewGameNameDialog> {
  final _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name für neues Spiel'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(hintText: 'z.B. Freitagabend'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('Erstellen'),
        ),
      ],
    );
  }
}
