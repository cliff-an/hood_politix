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
  Future<void> _joinAndNavigate(BuildContext context, String gameId, {String? password}) async {
    final svc = context.read<FirebaseService>();
    await _disposeControllerIfExists();
    final userName = await svc.getCurrentUserName(userId);

    await svc.joinGame(gameId, userId, userName, password: password);

    // Controller initialisieren
    final controller = GameController.initializeInstance(gameId, svc);
    await controller.initializeGameIfNeeded();

    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(gameId: gameId)),
      );
    }
  }

  /// Für private Spiele: fragt das Passwort ab, bevor beigetreten wird.
  /// Bereits beigetretene Spieler werden direkt durchgelassen (kein Prompt).
  Future<void> _joinPossiblyPrivate(BuildContext context, GameMeta g) async {
    if (!g.isPrivate || g.playerIds.contains(userId)) {
      await _joinAndNavigate(context, g.id);
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordPromptDialog(),
    );
    if (password == null) return; // abgebrochen
    if (!context.mounted) return;
    try {
      await _joinAndNavigate(context, g.id, password: password);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beitritt fehlgeschlagen: $e')),
      );
    }
  }

  /// Löst einen Beitritts-Code auf und tritt bei (fragt Passwort, falls nötig).
  Future<void> _joinByCode(BuildContext context, String code) async {
    final svc = context.read<FirebaseService>();
    final gameId = await svc.resolveJoinCode(code.trim());
    if (!context.mounted) return;
    if (gameId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kein Spiel mit diesem Code gefunden.')),
      );
      return;
    }
    try {
      final data = await svc.getGameData(gameId);
      final meta = GameMeta.fromMap(gameId, data);
      if (!context.mounted) return;
      await _joinPossiblyPrivate(context, meta);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Beitritt fehlgeschlagen: $e')),
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
                // 📨 Offene Einladungen
                StreamBuilder<Map<String, dynamic>>(
                  stream: svc.getInvitesStream(userId),
                  builder: (context, snap) {
                    final invites = snap.data ?? {};
                    if (invites.isEmpty) return const SizedBox.shrink();
                    return Column(
                      children: invites.entries.map((entry) {
                        final gameId = entry.key;
                        final data = Map<String, dynamic>.from(entry.value as Map);
                        final gameName = data['gameName']?.toString() ?? 'Spiel';
                        final password = data['password']?.toString();
                        return Card(
                          color: Colors.orangeAccent.withValues(alpha: 0.9),
                          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.mail),
                            title: Text('Einladung zu "$gameName"'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check, color: Colors.green),
                                  tooltip: 'Beitreten',
                                  onPressed: () async {
                                    await svc.declineInvite(userId, gameId);
                                    if (!context.mounted) return;
                                    try {
                                      await _joinAndNavigate(context, gameId, password: password);
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Beitritt fehlgeschlagen: $e')),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.red),
                                  tooltip: 'Ablehnen',
                                  onPressed: () => svc.declineInvite(userId, gameId),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
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
                            leading: g.isPrivate
                                ? const Icon(Icons.lock,
                                    color: Color.fromARGB(255, 201, 181, 1))
                                : null,
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
                            onTap: () => _joinPossiblyPrivate(context, g),
                          );
                        },
                      );
                    },
                  ),
                ),

                // 🔑 Mit Code beitreten
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _JoinByCodeRow(onJoin: (code) => _joinByCode(context, code)),
                ),

                // ➕ Neues Spiel erstellen
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ElevatedButton(
                    onPressed: () async {
                      final result = await showDialog<_NewGameResult>(
                        context: context,
                        builder: (_) => const _NewGameNameDialog(),
                      );
                      if (result == null || result.name.trim().isEmpty) return;

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
                        final newGameId = await svc.createNewGame(
                          result.name.trim(),
                          userId,
                          password: result.password,
                        );
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

/// Kompaktes Eingabefeld + Button, um per Beitritts-Code einem Spiel
/// beizutreten (Gegenstück zum "Code teilen"-Button im Warteraum).
class _JoinByCodeRow extends StatefulWidget {
  final void Function(String code) onJoin;
  const _JoinByCodeRow({required this.onJoin});

  @override
  State<_JoinByCodeRow> createState() => _JoinByCodeRowState();
}

class _JoinByCodeRowState extends State<_JoinByCodeRow> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'Code eingeben'),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) widget.onJoin(v.trim());
            },
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () {
            if (_ctrl.text.trim().isNotEmpty) widget.onJoin(_ctrl.text.trim());
          },
          child: const Text('Beitreten'),
        ),
      ],
    );
  }
}

class _NewGameResult {
  final String name;
  final String? password;
  const _NewGameResult(this.name, this.password);
}

/// Dialog zur Eingabe des neuen Spielnamens, optional mit Passwortschutz
class _NewGameNameDialog extends StatefulWidget {
  const _NewGameNameDialog();

  @override
  State<_NewGameNameDialog> createState() => _NewGameNameDialogState();
}

class _NewGameNameDialogState extends State<_NewGameNameDialog> {
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isPrivate = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name für neues Spiel'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(hintText: 'z.B. Freitagabend'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Privates Spiel'),
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
          ),
          if (_isPrivate)
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort'),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () {
            final password = _isPrivate ? _passwordCtrl.text.trim() : null;
            if (_isPrivate && (password == null || password.isEmpty)) return;
            Navigator.pop(context, _NewGameResult(_nameCtrl.text.trim(), password));
          },
          child: const Text('Erstellen'),
        ),
      ],
    );
  }
}

/// Fragt beim Beitritt zu einem privaten Spiel das Passwort ab.
class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog();

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Privates Spiel'),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Passwort'),
        onSubmitted: (_) => Navigator.pop(context, _ctrl.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Beitreten'),
        ),
      ],
    );
  }
}
