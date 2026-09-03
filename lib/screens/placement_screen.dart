import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hp_card_game/models/firebase_service.dart';
import 'lobby_screen.dart';
import 'game_screen.dart';

class PlacementScreen extends StatelessWidget {
  final String gameId;
  final String userId;

  const PlacementScreen({
    super.key,
    required this.gameId,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    final firebaseService = context.read<FirebaseService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spielplatzierungen'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: firebaseService.getGameData(gameId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Fehler: ${snapshot.error}'));
                }

                final gameData = snapshot.data ?? {};
                if (gameData['placements'] == null) {
                  return const Center(
                      child: Text('Keine Platzierungen gefunden.'));
                }

                final raw =
                    Map<String, dynamic>.from(gameData['placements'] as Map);
                final placements = raw.entries
                    .map((e) =>
                        MapEntry(e.key, Map<String, dynamic>.from(e.value)))
                    .where((e) => e.value.containsKey('finishedAt'))
                    .toList()
                  ..sort((a, b) {
                    final ta = (a.value['finishedAt'] as num?)?.toInt() ?? 9999999999;
                    final tb = (b.value['finishedAt'] as num?)?.toInt() ?? 9999999999;
                    return ta.compareTo(tb);
                  });

                return ListView.builder(
                  itemCount: placements.length,
                  itemBuilder: (context, index) {
                    final data = placements[index].value;
                    final name = data['name'] ?? 'Spieler';
                    final avatar =
                        data['avatarUrl'] ?? 'lib/images/man.png';

                    return Card(
                      color: index == 0
                          ? Colors.amber.withValues(alpha: 0.3)
                          : Colors.black.withValues(alpha: 0.3),
                      child: ListTile(
                        leading:
                            CircleAvatar(backgroundImage: AssetImage(avatar)),
                        title: Text(
                          '$name',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text('Platz ${index + 1}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Spiel neu starten'),
              onPressed: () async {
                final canRestart =
                    await firebaseService.canRestartGame(gameId);
                if (!context.mounted) return;
                if (!canRestart) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Nicht genügend Spieler für einen Neustart.')),
                  );
                  return;
                }

                final newGameId =
                    await firebaseService.createNewGame('Neues Spiel', userId);
                if (context.mounted) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GameScreen(gameId: newGameId),
                    ),
                  );
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.home),
              label: const Text('Zurück zur Lobby'),
              onPressed: () {
                final uid = FirebaseAuth.instance.currentUser?.uid ?? userId;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => LobbyScreen(userId: uid),
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
