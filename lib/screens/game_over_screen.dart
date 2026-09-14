import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/firebase_service.dart';
import '../models/game_controller.dart';
import 'lobby_screen.dart';

class GameOverScreen extends StatelessWidget {
  final String gameId;
  const GameOverScreen({super.key, required this.gameId});

  /// Lädt Platzierungen + Spielmodus (für den Tutorial-Hinweis) parallel.
  Future<(Map<String, Map<String, dynamic>>, String)> _loadGameOverData() async {
    final results = await Future.wait([
      FirebaseDatabase.instance.ref('games/$gameId/placements').get(),
      FirebaseDatabase.instance.ref('games/$gameId/meta/mode').get(),
    ]);
    final placementsSnap = results[0];
    final modeSnap = results[1];

    final placements = <String, Map<String, dynamic>>{};
    if (placementsSnap.exists && placementsSnap.value != null) {
      final raw = Map<String, dynamic>.from(placementsSnap.value as Map);
      raw.forEach((pid, data) {
        placements[pid] = Map<String, dynamic>.from(data as Map);
      });
    }

    return (placements, modeSnap.value?.toString() ?? 'normal');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Spiel beendet'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'lib/images/background_3.jpg',
              fit: BoxFit.cover,
            ),
          ),
          const Positioned.fill(
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
          ),
          SafeArea(
            child: FutureBuilder<(Map<String, Map<String, dynamic>>, String)>(
              future: _loadGameOverData(),
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Fehler beim Laden: ${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final (placements, mode) =
                    snap.data ?? (<String, Map<String, dynamic>>{}, 'normal');
                final sorted = placements.entries
                    .where((e) => e.value.containsKey('finishedAt'))
                    .toList()
                  ..sort((a, b) {
                    final ta = (a.value['finishedAt'] as num?)?.toInt() ?? 9999999999;
                    final tb = (b.value['finishedAt'] as num?)?.toInt() ?? 9999999999;
                    return ta.compareTo(tb);
                  });

                final winner =
                    sorted.isNotEmpty ? sorted.first.value['name'] : null;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  child: Column(
                    children: [
                      if (winner != null) ...[
                        Text(
                          '🎉 Herzlichen Glückwunsch, $winner! 🎉',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (mode == 'tutorial') ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Das war das Tutorial! Du kennst jetzt alle Grundlagen — '
                            'ab hier kannst du mit echten Spielern loslegen.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      Expanded(
                        child: ListView.builder(
                          itemCount: sorted.length,
                          itemBuilder: (ctx, i) {
                            final data = sorted[i].value;
                            final name =
                                data['name'] ?? 'Unbekannter Spieler';
                            final avatar =
                                data['avatarUrl'] ?? 'lib/images/man.png';
                            final isBot = data['isBot'] == true;
                            return Card(
                              color: Colors.black.withValues(alpha: 0.5),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: AssetImage(avatar),
                                ),
                                title: Text(
                                  '${i + 1}. $name',
                                  style: const TextStyle(
                                    color:
                                        Color.fromARGB(255, 236, 162, 1),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                trailing: isBot ? const Text('🤖') : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.home),
                            label: const Text('Zur Lobby'),
                            onPressed: () async {
                              final userId =
                                  FirebaseAuth.instance.currentUser!.uid;
                              await FirebaseService.instance
                                  .removePlayerFromFinishedGame(gameId, userId);
                              if (GameController.hasInstance) {
                                GameController.instance.dispose();
                              }
                              if (context.mounted) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => LobbyScreen(userId: userId),
                                  ),
                                  (_) => false,
                                );
                              }
                            },
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.logout),
                            label: const Text('Abmelden'),
                            onPressed: () async {
                              final userId =
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (userId != null) {
                                await FirebaseService.instance
                                    .removePlayerFromFinishedGame(gameId, userId);
                              }
                              if (GameController.hasInstance) {
                                GameController.instance.dispose();
                              }
                              await FirebaseAuth.instance.signOut();
                              if (context.mounted) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) => const _LoggedOutScreen(),
                                  ),
                                  (_) => false,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Platzhalter-Screen nach Logout (optional schöner Splash oder LoginScreen)
class _LoggedOutScreen extends StatelessWidget {
  const _LoggedOutScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Erfolgreich abgemeldet',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
