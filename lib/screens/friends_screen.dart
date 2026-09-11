import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/avatar_catalog.dart';
import '../models/firebase_service.dart';
import 'profile_screen.dart';

/// Freundesliste, eingehende Anfragen und Suche nach Benutzername.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchCtrl = TextEditingController();
  String? _searchResultUid;
  String? _searchError;
  bool _searching = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(FirebaseService svc, String myUid) async {
    final username = _searchCtrl.text.trim();
    if (username.isEmpty) return;
    setState(() {
      _searching = true;
      _searchError = null;
      _searchResultUid = null;
    });
    final uid = await svc.findUserByUsername(username);
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (uid == null) {
        _searchError = 'Kein Nutzer mit diesem Namen gefunden.';
      } else if (uid == myUid) {
        _searchError = 'Das bist du selbst.';
      } else {
        _searchResultUid = uid;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.read<FirebaseService>();
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Freunde')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---- Suche ----
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Benutzername suchen',
                  ),
                  onSubmitted: (_) => _search(svc, myUid),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: _searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                onPressed: _searching ? null : () => _search(svc, myUid),
              ),
            ],
          ),
          if (_searchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_searchError!, style: const TextStyle(color: Colors.red)),
            ),
          if (_searchResultUid != null)
            _SearchResultTile(
              uid: _searchResultUid!,
              myUid: myUid,
              svc: svc,
              onHandled: () => setState(() => _searchResultUid = null),
            ),

          const Divider(height: 32),

          // ---- Eingehende Anfragen ----
          Text('Anfragen', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          StreamBuilder<List<String>>(
            stream: svc.getIncomingFriendRequestsStream(myUid),
            builder: (context, snap) {
              final incoming = snap.data ?? [];
              if (incoming.isEmpty) {
                return const Text('Keine offenen Anfragen.');
              }
              return Column(
                children: incoming
                    .map((fromUid) => _IncomingRequestTile(
                          fromUid: fromUid,
                          myUid: myUid,
                          svc: svc,
                        ))
                    .toList(),
              );
            },
          ),

          const Divider(height: 32),

          // ---- Freundesliste ----
          Text('Meine Freunde', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          StreamBuilder<List<String>>(
            stream: svc.getFriendsStream(myUid),
            builder: (context, snap) {
              final friends = snap.data ?? [];
              if (friends.isEmpty) {
                return const Text('Noch keine Freunde — oben suchen und anfragen.');
              }
              return Column(
                children: friends.map((uid) => _FriendTile(uid: uid, svc: svc)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final String uid;
  final String myUid;
  final FirebaseService svc;
  final VoidCallback onHandled;

  const _SearchResultTile({
    required this.uid,
    required this.myUid,
    required this.svc,
    required this.onHandled,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: svc.getUserProfile(uid),
      builder: (context, snap) {
        final profile = snap.data;
        if (profile == null) return const SizedBox.shrink();
        final name = profile['username']?.toString() ?? uid;
        final avatarPath = resolveAvatarPath(profile['avatarId']?.toString());
        final alreadyFriends = profile['friends'] is Map &&
            (profile['friends'] as Map).containsKey(myUid);
        return Card(
          child: ListTile(
            leading: CircleAvatar(backgroundImage: AssetImage(avatarPath)),
            title: Text(name),
            trailing: alreadyFriends
                ? const Text('Schon Freunde')
                : ElevatedButton(
                    onPressed: () async {
                      await svc.sendFriendRequest(myUid, uid);
                      onHandled();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Anfrage an $name gesendet.')),
                        );
                      }
                    },
                    child: const Text('Anfragen'),
                  ),
          ),
        );
      },
    );
  }
}

class _IncomingRequestTile extends StatelessWidget {
  final String fromUid;
  final String myUid;
  final FirebaseService svc;

  const _IncomingRequestTile({
    required this.fromUid,
    required this.myUid,
    required this.svc,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: svc.getUserProfile(fromUid),
      builder: (context, snap) {
        final name = snap.data?['username']?.toString() ?? '…';
        final avatarPath = resolveAvatarPath(snap.data?['avatarId']?.toString());
        return Card(
          child: ListTile(
            leading: CircleAvatar(backgroundImage: AssetImage(avatarPath)),
            title: Text(name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  tooltip: 'Annehmen',
                  onPressed: () => svc.acceptFriendRequest(myUid, fromUid),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  tooltip: 'Ablehnen',
                  onPressed: () => svc.declineFriendRequest(myUid, fromUid),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FriendTile extends StatelessWidget {
  final String uid;
  final FirebaseService svc;

  const _FriendTile({required this.uid, required this.svc});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: svc.getUserProfileStream(uid),
      builder: (context, snap) {
        final profile = snap.data;
        final name = profile?['username']?.toString() ?? '…';
        final avatarPath = resolveAvatarPath(profile?['avatarId']?.toString());
        final currentGameId = profile?['currentGameId']?.toString();
        final isInGame = currentGameId != null && currentGameId.isNotEmpty;
        return Card(
          child: ListTile(
            leading: CircleAvatar(backgroundImage: AssetImage(avatarPath)),
            title: Text(name),
            subtitle: Text(
              isInGame ? 'Ist im Spiel' : 'Nicht im Spiel',
              style: TextStyle(color: isInGame ? Colors.orange : Colors.green),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ProfileScreen(uid: uid)),
            ),
          ),
        );
      },
    );
  }
}
