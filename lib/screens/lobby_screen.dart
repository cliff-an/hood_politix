import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/firebase_service.dart';
import '../models/game_meta.dart';
import '../models/game_controller.dart';
import 'friends_screen.dart';
import 'game_screen.dart';
import 'profile_screen.dart';
import 'rules_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String userId;
  const LobbyScreen({super.key, required this.userId});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  @override
  void initState() {
    super.initState();
    _maybeStartTutorial();
  }

  /// Startet das Tutorial automatisch beim allerersten Login — aber nie
  /// erneut. hasSeenTutorial liefert `true`, wenn der Key fehlt
  /// (Bestandskonten vor diesem Feature) ODER schon `true` gesetzt wurde,
  /// beide Fälle lösen hier bewusst nichts aus.
  Future<void> _maybeStartTutorial() async {
    // Direkt nach einer Registrierung kann dieser Screen schon gebaut
    // werden, bevor login_screen.dart den hasSeenTutorial:false-Schreib-
    // vorgang abgeschickt hat (siehe FirebaseService.pendingRegistration) —
    // erst darauf warten, sonst würde der Key fälschlich als fehlend (=
    // "schon gesehen") gelesen. Für normale Logins ist das Future null,
    // hier entsteht also keine zusätzliche Wartezeit.
    final pending = FirebaseService.pendingRegistration;
    if (pending != null) {
      await pending.future;
      FirebaseService.pendingRegistration = null;
    }
    if (!mounted) return;

    final svc = context.read<FirebaseService>();
    final alreadySeen = await svc.hasSeenTutorial(widget.userId);
    if (alreadySeen || !mounted) return;

    await _disposeControllerIfExists();
    final gameId = await svc.createTutorialGame(widget.userId);
    if (!mounted) return;

    final controller = GameController.initializeInstance(gameId, svc);
    await controller.initializeGameIfNeeded();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => GameScreen(gameId: gameId)),
    );
  }

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
  Future<void> _joinAndNavigate(BuildContext context, String gameId,
      {String? password}) async {
    final svc = context.read<FirebaseService>();
    await _disposeControllerIfExists();
    final userName = await svc.getCurrentUserName(widget.userId);

    await svc.joinGame(gameId, widget.userId, userName, password: password);

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
    if (!g.isPrivate || g.playerIds.contains(widget.userId)) {
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

  /// Startet ein Training (1 Mensch + [botCount] Bots), sofort spielbereit
  /// ohne Warteraum. Der Ersteller ist bereits durch createTrainingGame
  /// als Spieler eingetragen — im Unterschied zu _joinAndNavigate wird
  /// hier also kein zusätzlicher svc.joinGame(...) gebraucht.
  Future<void> _startTrainingGame(BuildContext context, int botCount) async {
    final svc = context.read<FirebaseService>();
    try {
      final alreadyInGame = await svc.isPlayerAlreadyInGame(widget.userId);
      if (!context.mounted) return;
      if (alreadyInGame) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Du bist bereits in einem laufenden Spiel.')),
        );
        return;
      }

      await _disposeControllerIfExists();
      final gameId = await svc.createTrainingGame(widget.userId, botCount);
      if (!context.mounted) return;

      final controller = GameController.initializeInstance(gameId, svc);
      await controller.initializeGameIfNeeded();

      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => GameScreen(gameId: gameId)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Training konnte nicht gestartet werden: $e')),
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
      // Die Tastatur gehört einem TextField in einem MODALEN Dialog (Name/
      // Passwort/Code), nicht dem Lobby-Screen selbst dahinter — ohne dies
      // versucht der Lobby-Body sich zu verkleinern, wenn die Tastatur
      // aufklappt, und läuft dabei über (BOTTOM OVERFLOWED), weil die feste
      // Button-Reihe (Training/Neues Spiel/Code) nicht mitschrumpfen kann.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text("Lobby"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book),
            tooltip: 'Regeln',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RulesScreen()),
            ),
          ),
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
                        final data =
                            Map<String, dynamic>.from(entry.value as Map);
                        final gameName =
                            data['gameName']?.toString() ?? 'Spiel';
                        final password = data['password']?.toString();
                        return Card(
                          color: Colors.orangeAccent.withValues(alpha: 0.9),
                          margin: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: ListTile(
                            leading: const Icon(Icons.mail),
                            title: Text('Einladung zu "$gameName"'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check,
                                      color: Colors.green),
                                  tooltip: 'Beitreten',
                                  onPressed: () async {
                                    await svc.declineInvite(userId, gameId);
                                    if (!context.mounted) return;
                                    try {
                                      await _joinAndNavigate(context, gameId,
                                          password: password);
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Beitritt fehlgeschlagen: $e')),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  tooltip: 'Ablehnen',
                                  onPressed: () =>
                                      svc.declineInvite(userId, gameId),
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
                    stream:
                        svc.getGamesMetaStream(), // jetzt als Stream-Version
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        // Der Logout-Button ruft FirebaseAuth.signOut() aus
                        // OHNE dass dieser Stream vorher beendet wird (ein
                        // StreamBuilder lässt sich nicht "von außen"
                        // canceln) — der bereits laufende Listener auf
                        // games/ bekommt dadurch kurzzeitig noch einen
                        // permission-denied-Push, BEVOR AuthGate reagiert
                        // und diesen Screen überhaupt abbaut. Kein echter
                        // Fehler für den Nutzer, nur ein Wettlauf beim
                        // Verlassen — also nichts anzeigen statt der
                        // rohen Fehlermeldung, AuthGate navigiert gleich
                        // sowieso zum Login-Screen.
                        if (FirebaseAuth.instance.currentUser == null) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        return Center(child: Text('Fehler: ${snap.error}'));
                      }

                      final now = DateTime.now().millisecondsSinceEpoch;
                      const endedExpiry = 5 * 60 * 1000;
                      const createdExpiry = 24 * 60 * 60 * 1000;

                      final visible = <GameMeta>[];
                      for (var g in snap.data ?? []) {
                        // ⏰ Abgelaufene Spiele werden für alle ausgeblendet,
                        // aber nur gelöscht, wenn der Viewer selbst Teilnehmer
                        // ist — die Security Rules erlauben ohnehin nur
                        // Teilnehmern das Löschen; ein Versuch bei fremden
                        // Spielen würde bei jedem Stream-Update erneut
                        // fehlschlagen und nichts bewirken außer
                        // Konsolenrauschen.
                        final isExpired = (g.endedAt != null &&
                                now - g.endedAt! > endedExpiry) ||
                            now - g.createdAt > createdExpiry;
                        if (isExpired) {
                          if (g.playerIds.contains(userId)) {
                            svc.deleteGame(g.id);
                          }
                          continue;
                        }

                        // Training-/Tutorial-Spiele sind nie öffentlich
                        // beitretbar — zusätzliche Absicherung neben dem
                        // ohnehin kurzen Zeitfenster vor startGame.
                        if (g.mode != 'normal') continue;

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
                  child: _JoinByCodeRow(
                      onJoin: (code) => _joinByCode(context, code)),
                ),

                // 🤖 Trainingsmodus — bewusst optisch sekundär (Outline),
                // kein gleichwertiger Hauptmodus, sondern Übung ohne
                // Mitspieler.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: OutlinedButton(
                    onPressed: () async {
                      final botCount = await showDialog<int>(
                        context: context,
                        builder: (_) => const _TrainingBotCountDialog(),
                      );
                      if (botCount == null) return;
                      if (!context.mounted) return;
                      await _startTrainingGame(context, botCount);
                    },
                    child: const Text('🤖 Gegen Computer (Training)'),
                  ),
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
                          targetPlayerCount: result.targetPlayerCount,
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
  final int targetPlayerCount;
  const _NewGameResult(this.name, this.password, this.targetPlayerCount);
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
  int _targetPlayerCount = 4;

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
      // Lässt den Inhalt notfalls scrollen statt zu überlaufen, wenn wenig
      // vertikaler Platz bleibt (z. B. sehr kleine Bildschirme).
      content: SingleChildScrollView(
        child: Column(
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
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Ziel-Spieleranzahl: $_targetPlayerCount'),
            ),
            Slider(
              value: _targetPlayerCount.toDouble(),
              min: 2,
              max: 6,
              divisions: 4,
              label: '$_targetPlayerCount',
              onChanged: (v) => setState(() => _targetPlayerCount = v.round()),
            ),
          ],
        ),
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
            Navigator.pop(
              context,
              _NewGameResult(
                  _nameCtrl.text.trim(), password, _targetPlayerCount),
            );
          },
          child: const Text('Erstellen'),
        ),
      ],
    );
  }
}

/// Wählt die Bot-Anzahl (1-5) für den Trainingsmodus.
class _TrainingBotCountDialog extends StatefulWidget {
  const _TrainingBotCountDialog();

  @override
  State<_TrainingBotCountDialog> createState() =>
      _TrainingBotCountDialogState();
}

class _TrainingBotCountDialogState extends State<_TrainingBotCountDialog> {
  int _botCount = 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gegen Computer üben'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_botCount Bot${_botCount == 1 ? '' : 's'}'),
          Slider(
            value: _botCount.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            label: '$_botCount',
            onChanged: (v) => setState(() => _botCount = v.round()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _botCount),
          child: const Text('Training starten'),
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
