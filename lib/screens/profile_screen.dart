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
              ],
            ),
          );
        },
      ),
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
