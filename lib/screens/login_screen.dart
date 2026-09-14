import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/avatar_catalog.dart';
import '../models/firebase_service.dart';

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

  // Stummer Endlos-Loop desselben Clips, der schon beim Spielstart gezeigt
  // wird (siehe StartVideoOverlay) — ersetzt das bisher komplett statische,
  // stark abgedunkelte Hintergrundbild auf dem allerersten Bildschirm.
  VideoPlayerController? _bgVideo;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.asset('lib/vids/HP_video.mp4');
    controller
        .initialize()
        .then((_) {
          if (!mounted) {
            controller.dispose();
            return;
          }
          controller
            ..setLooping(true)
            ..setVolume(0)
            ..play();
          setState(() => _bgVideo = controller);
        })
        .catchError((_) {
          // Kein Video verfügbar (z. B. Web ohne Codec-Support) -> das
          // statische Hintergrundbild bleibt einfach sichtbar.
          controller.dispose();
        });
  }

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

    // Siehe FirebaseService.pendingRegistration: muss VOR dem Auth-Aufruf
    // gesetzt sein, da authStateChanges() (und damit AuthGate → LobbyScreen)
    // schon feuern kann, bevor der hasSeenTutorial-Schreibvorgang unten
    // überhaupt abgeschickt ist.
    final registrationDone = Completer<void>();
    FirebaseService.pendingRegistration = registrationDone;

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
        // Nur NEUE Konten bekommen das Tutorial automatisch angeboten —
        // fehlt der Key (Bestandskonten vor diesem Feature), gilt das als
        // "schon gesehen" (siehe FirebaseService.hasSeenTutorial).
        'hasSeenTutorial': false,
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
      if (!registrationDone.isCompleted) registrationDone.complete();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _bgVideo?.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFF0A65C), width: 2),
      ),
    );
  }

  Widget _branding(double logoSize) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(logoSize * 0.21),
          child: Image.asset('lib/images/logo.png', width: logoSize, height: logoSize),
        ),
        const SizedBox(height: 12),
        Text(
          'HOOD POLITIX',
          style: TextStyle(
            color: Colors.white,
            fontSize: logoSize > 100 ? 26 : 20,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            shadows: const [Shadow(blurRadius: 12, color: Colors.black87)],
          ),
        ),
      ],
    );
  }

  Widget _formCard() {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Willkommen zurück',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _usernameController,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Benutzername', Icons.person_outline),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _passwordController,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration('Passwort', Icons.lock_outline),
            obscureText: true,
            onSubmitted: (_) => _signIn(),
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(color: Color(0xFFF0A65C)),
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE0722C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _signIn,
                child: const Text('Anmelden', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _showRegisterDialog,
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFF0A65C)),
              child: const Text('Neues Konto registrieren'),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Statisches Bild bleibt als unterste Ebene erhalten — Fallback,
          // solange das Video lädt (oder falls es z. B. im Web am
          // Codec-Support scheitert), damit nie ein leerer/schwarzer
          // Bildschirm aufblitzt.
          Image.asset('lib/images/background.png', fit: BoxFit.cover),
          if (_bgVideo != null && _bgVideo!.value.isInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _bgVideo!.value.size.width,
                  height: _bgVideo!.value.size.height,
                  child: VideoPlayer(_bgVideo!),
                ),
              ),
            ),
          // Abdunkeln für Lesbarkeit, stärker an den Rändern — deutlich
          // leichter als zuvor (black38/87), sonst verschluckt es genau
          // die Farbe/Bewegung, die das Video eigentlich bringen soll.
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.1,
                colors: [Colors.black12, Colors.black54],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                // Nebeneinander, wenn Platz da ist (normales Querformat);
                // untereinander auf schmalen Fenstern/Splitscreen, damit
                // nichts über den Rand hinausläuft.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 560;
                    if (wide) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _branding(132),
                          const SizedBox(width: 56),
                          _formCard(),
                        ],
                      );
                    }
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _branding(88),
                        const SizedBox(height: 20),
                        _formCard(),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
