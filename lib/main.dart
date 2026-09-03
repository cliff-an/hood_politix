
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:hp_card_game/widgets/dialog_manager.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'auth_gate.dart';
import 'models/firebase_service.dart';
import 'widgets/player_hand_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 🌄 Vollbildmodus aktivieren
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // 📱 Nur Landscape erlauben
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 🚀 Firebase initialisieren
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') rethrow;
  }

  // ignore: deprecated_member_use
  await FirebaseAppCheck.instance.activate(
    // ignore: deprecated_member_use
    androidProvider: kDebugMode
        ? AndroidProvider.debug
        : AndroidProvider.playIntegrity,
    // ignore: deprecated_member_use
    appleProvider: kDebugMode
        ? AppleProvider.debug
        : AppleProvider.appAttest,
    // ignore: deprecated_member_use
    webProvider: ReCaptchaV3Provider('6LdbsPwqAAAAAB5jY6gkbAhoujuMmCixsf7ktWyr'),
  );




  // 🏁 App starten
  runApp(const MyGameApp());
}


class MyGameApp extends StatelessWidget {
  const MyGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<FirebaseService>(
          create: (_) => FirebaseService.instance,
        ),
        Provider(create: (_) => PlayerHandWidgetState()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Hood Politix',
        theme: ThemeData(primarySwatch: Colors.blue),
        builder: (context, child) {
        DialogManager.setRootContext(context); // ✅ hier setzen
    return child!;
  },
        home: const AuthGate(), // kümmert sich um Login & Navigation
      ),
    );
  }
}
