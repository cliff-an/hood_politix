import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../models/avatar_catalog.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// 3-20 Zeichen, nur Buchstaben/Zahlen/"_"/"-" — verhindert u.a. Zeichen wie
/// ".", "#", "$", "[", "]", "/", die als Firebase-Realtime-Database-Key
/// verboten sind (sonst scheitert die usernames/-Reservierung mit einem
/// kryptischen Fehler statt einer verständlichen Meldung).
final RegExp _usernamePattern = RegExp(r'^[A-Za-z0-9_-]{3,20}$');

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  /// 1️⃣ Anmeldung
  Future<void> _signIn() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Benutzername und Passwort eingeben.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final email = '$username@yourapp.com';
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      // AuthGate übernimmt die Navigation zur Lobby automatisch
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'Benutzer nicht gefunden.';
          break;
        case 'wrong-password':
          message = 'Falsches Passwort.';
          break;
        case 'invalid-email':
          message = 'Ungültige Benutzerkennung.';
          break;
        case 'user-disabled':
          message = 'Dieser Benutzer ist deaktiviert.';
          break;
        default:
          message = 'Fehler: ${e.message}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unerwarteter Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 2️⃣ Registrierung
  Future<void> _showRegisterDialog() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Benutzername und Passwort eingeben.')),
      );
      return;
    }
    if (!_usernamePattern.hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Benutzername: 3-20 Zeichen, nur Buchstaben, Zahlen, "_" und "-".',
          ),
        ),
      );
      return;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwort muss mindestens 6 Zeichen haben.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    final db = FirebaseDatabase.instance.ref();

    try {
      // ▶️ 1) Prüfen, ob Username bereits vergeben
      final nameSnap = await db.child('usernames/$username').get();
      if (nameSnap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Benutzername bereits vergeben.')),
          );
        }
        return;
      }

      // ▶️ 2) Auth anlegen
      final email = '$username@yourapp.com';
      final cred  = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      final user  = cred.user!;
      final uid   = user.uid;

      // ▶️ 3) RTDB: Profil und Username-Index anlegen
      final defaultAvatar = avatarCatalog[Random().nextInt(avatarCatalog.length)];
      await db.child('users/$uid').set({
        'username': username,
        'createdAt': ServerValue.timestamp,
        'avatarId': defaultAvatar.id,
      });
      await db.child('usernames/$username').set(uid);

      // AuthGate übernimmt die Navigation zur Lobby automatisch
    } on FirebaseAuthException catch (e) {
      String message = e.message ?? 'Registrierungsfehler';
      if (e.code == 'email-already-in-use') {
        message = 'Dieser Benutzername ist bereits registriert.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unerwarteter Fehler: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login / Registrierung')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: 'Benutzername'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Passwort'),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const CircularProgressIndicator()
              else ...[
                ElevatedButton(
                  onPressed: _signIn,
                  child: const Text('Anmelden'),
                ),
                TextButton(
                  onPressed: _showRegisterDialog,
                  child: const Text('Registrieren'),
                ),
              ],
            ],
          ),
        ),
      ),

    );
  }
}
