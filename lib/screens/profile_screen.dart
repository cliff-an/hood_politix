import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/avatar_catalog.dart';
import '../models/firebase_service.dart';
import '../widgets/avatar_picker.dart';

/// Profil eines Nutzers: Avatar, Benutzername, Freundesanzahl, "im Spiel"-
/// Status. Für das eigene Profil (uid == aktueller Nutzer) ist der Avatar
/// bearbeitbar; für fremde Profile ist die Ansicht rein lesend.
class ProfileScreen extends StatelessWidget {
  final String uid;
  const ProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final svc = context.read<FirebaseService>();
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final isOwnProfile = uid == myUid;

    return Scaffold(
      appBar: AppBar(title: Text(isOwnProfile ? 'Mein Profil' : 'Profil')),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: svc.getUserProfileStream(uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snap.data;
          if (profile == null) {
            return const Center(child: Text('Profil nicht gefunden.'));
          }

          final username = profile['username']?.toString() ?? 'Unbekannt';
          final avatarId = profile['avatarId']?.toString();
          final avatarPath = resolveAvatarPath(avatarId);
          final currentGameId = profile['currentGameId']?.toString();
          final isInGame = currentGameId != null && currentGameId.isNotEmpty;
          final friends = profile['friends'] is Map
              ? Map<String, dynamic>.from(profile['friends'] as Map)
              : <String, dynamic>{};

          final requests = profile['friendRequests'] is Map
              ? Map<String, dynamic>.from(profile['friendRequests'] as Map)
              : <String, dynamic>{};
          final incoming = requests['incoming'] is Map
              ? Map<String, dynamic>.from(requests['incoming'] as Map)
              : <String, dynamic>{};
          final outgoing = requests['outgoing'] is Map
              ? Map<String, dynamic>.from(requests['outgoing'] as Map)
              : <String, dynamic>{};

          final isFriend = friends.containsKey(myUid);
          // Ich habe an diesen Nutzer angefragt (steht in dessen "incoming").
          final requestFromMe = incoming.containsKey(myUid);
          // Dieser Nutzer hat mich angefragt (steht in dessen "outgoing").
          final requestFromThem = outgoing.containsKey(myUid);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                GestureDetector(
                  onTap: isOwnProfile
                      ? () async {
                          final selected = await AvatarPicker.show(
                            context,
                            selectedId: avatarId,
                          );
                          if (selected != null) {
                            await svc.setAvatar(uid, selected);
                          }
                        }
                      : null,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 56,
                        backgroundImage: AssetImage(avatarPath),
                      ),
                      if (isOwnProfile)
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.black87,
                          child: Icon(Icons.edit, size: 16, color: Colors.white),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(username, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Chip(
                  avatar: Icon(
                    isInGame ? Icons.videogame_asset : Icons.check_circle_outline,
                    size: 18,
                    color: isInGame ? Colors.orange : Colors.green,
                  ),
                  label: Text(isInGame ? 'Ist im Spiel' : 'Nicht im Spiel'),
                ),
                if (!isOwnProfile) ...[
                  const SizedBox(height: 16),
                  if (isFriend)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.person_remove),
                      label: const Text('Freund entfernen'),
                      onPressed: () => svc.removeFriend(myUid, uid),
                    )
                  else if (requestFromThem)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Anfrage annehmen'),
                          onPressed: () => svc.acceptFriendRequest(myUid, uid),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => svc.declineFriendRequest(myUid, uid),
                          child: const Text('Ablehnen'),
                        ),
                      ],
                    )
                  else if (requestFromMe)
                    const OutlinedButton(
                      onPressed: null,
                      child: Text('Anfrage gesendet'),
                    )
                  else
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_add),
                      label: const Text('Freund hinzufügen'),
                      onPressed: () => svc.sendFriendRequest(myUid, uid),
                    ),
                ],
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Freunde (${friends.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 8),
                if (friends.isEmpty)
                  const Text('Noch keine Freunde.')
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: friends.keys.map((friendUid) {
                      return _FriendAvatar(uid: friendUid, svc: svc);
                    }).toList(),
                  ),
                if (isOwnProfile) ...[
                  const SizedBox(height: 48),
                  const Divider(),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text('Konto löschen', style: TextStyle(color: Colors.red)),
                    onPressed: () => _deleteAccountFlow(context, svc, uid, username),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bestätigungsdialog + Löschvorgang, inkl. Re-Authentifizierung falls
/// Firebase eine zu alte Sitzung für diese sensible Aktion ablehnt.
Future<void> _deleteAccountFlow(
  BuildContext context,
  FirebaseService svc,
  String uid,
  String username,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Konto wirklich löschen?'),
      content: const Text(
        'Dein Profil, deine Freundschaften und dein Zugang werden endgültig '
        'gelöscht. Das kann nicht rückgängig gemacht werden.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Endgültig löschen'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await svc.deleteAccount(uid);
    // AuthGate ist die Wurzel-Route (home:) und erkennt den fehlenden
    // Auth-Nutzer automatisch — zurückpoppen genügt, dann zeigt es von
    // selbst den Login-Screen statt des jetzt gelöschten Profils.
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  } on FirebaseAuthException catch (e) {
    if (!context.mounted) return;
    if (e.code != 'requires-recent-login') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: ${e.message ?? e.code}')),
      );
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _ReauthDialog(),
    );
    if (password == null || !context.mounted) return;
    try {
      await svc.reauthenticate(username, password);
      await svc.deleteAccount(uid);
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e2) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Löschen fehlgeschlagen: $e2')),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
      );
    }
  }
}

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog();

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort bestätigen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Deine Anmeldung ist zu alt für diese Aktion. Bitte Passwort erneut eingeben.'),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Passwort'),
            onSubmitted: (_) => Navigator.of(context).pop(_ctrl.text),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Bestätigen'),
        ),
      ],
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  final String uid;
  final FirebaseService svc;
  const _FriendAvatar({required this.uid, required this.svc});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: svc.getUserProfile(uid),
      builder: (context, snap) {
        final name = snap.data?['username']?.toString() ?? '…';
        final avatarPath = resolveAvatarPath(snap.data?['avatarId']?.toString());
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 24, backgroundImage: AssetImage(avatarPath)),
              const SizedBox(height: 4),
              Text(name, style: const TextStyle(fontSize: 11)),
            ],
          ),
        );
      },
    );
  }
}
