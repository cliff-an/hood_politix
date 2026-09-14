import 'package:flutter/material.dart';

/// Regel-Übersicht — direkt aus der Spiellogik abgeleitet (nicht aus dem
/// Poster abgetippt), damit hier nichts steht, was das Spiel tatsächlich
/// anders handhabt.
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFF0A65C);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Regeln'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('lib/images/background_3.jpg', fit: BoxFit.cover),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black54),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        'HOOD POLITIX',
                        style: TextStyle(
                          color: accent,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Ab 2 Spielern · Rauskommen ist die Mission',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _Section(
                  title: 'Ziel des Spiels',
                  accent: accent,
                  child: const Text(
                    'Wenn du aus der Hood kommst, teilst du den Traum vieler: groß '
                    'rauskommen und die Hood hinter dir lassen. "Rauskommen" ist auch '
                    'das Motto von Hood Politix — Cops, Snitches und einfach nur Pech '
                    'stehen dir dabei im Weg.\n\n'
                    'Das Ziel: so schnell wie möglich alle Karten aus deiner Hand loswerden.',
                    style: TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
                _Section(
                  title: 'Der Ablauf',
                  accent: accent,
                  child: const Text(
                    '• Jeder Spieler startet mit 5 Handkarten.\n'
                    '• Reihum wird eine Karte auf den Ablagestapel gelegt, die zur '
                    'obersten Karte passt: Zahlenkarten brauchen gleiche Farbe oder '
                    'gleiche Zahl, die meisten Aktionskarten sind farbunabhängig immer '
                    'spielbar.\n'
                    '• Kannst oder willst du nicht ablegen, ziehst du eine Karte vom Deck.\n'
                    '• Eine Payback-Karte dreht die Zugrichtung um.',
                    style: TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
                _Section(
                  title: 'Reinwerfen',
                  accent: accent,
                  child: const Text(
                    'Liegt eine Zahlenkarte mit exakt gleicher Farbe und Zahl wie die '
                    'oberste Ablagekarte in deiner Hand, darfst du sie sofort ablegen — '
                    'auch wenn du gerade nicht am Zug bist. Passt sie nicht exakt, gibt '
                    'es 2 Strafkarten.',
                    style: TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
                _Section(
                  title: 'Mic Check & Mic Drop',
                  accent: accent,
                  child: const Text(
                    'Bleibt dir nur noch 1 Karte übrig, musst du "Mic Check" drücken. '
                    'Spielst du deine letzte Karte, musst du vorher "Mic Drop" gedrückt '
                    'haben, um zu gewinnen. Vergisst du es, wandert die gerade gespielte '
                    'Karte zurück auf deine Hand — plus 2 Strafkarten obendrauf.',
                    style: TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
                _Section(
                  title: 'Straßenregeln',
                  accent: accent,
                  child: const Text(
                    '• Jeder spielt für sich — keine Tipps oder Absprachen unter Mitspielern.\n'
                    '• Bluffen und Ablenken ist erlaubt und Teil des Spiels.\n'
                    '• Für alles, was du deinen Mitspielern sagen willst: Die Emoji-Reaktionen '
                    'im Spiel (der 😀-Button) reichen völlig — kein Textchat, keine Beleidigungen.',
                    style: TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
                _Section(
                  title: 'Reagieren auf Aktionskarten',
                  accent: accent,
                  child: const Text(
                    'Auf manche Aktionskarten kannst du kontern, um die Strafe '
                    'weiterzugeben oder abzuwehren:\n'
                    '• Deuces → mit einer weiteren Deuces (Kette) oder mit Payback in '
                    'derselben Farbe.\n'
                    '• In Yo Face → mit einer weiteren In Yo Face.\n'
                    '• 5-0 hebt jede dieser Ketten sofort auf, egal wer dran ist.\n'
                    '• Deal und Snitch lassen sich nur mit 5-0 abwehren.\n'
                    '• Busted und Pimp Slap lassen sich gar nicht kontern.',
                    style: TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
                _Section(
                  title: 'Aktionskarten',
                  accent: accent,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _ActionCardRule(
                        assetPath: 'lib/images/fiveO_purple.png',
                        name: '5-0',
                        description: 'Hebt die Strafe einer anderen Aktionskarte sofort auf.',
                      ),
                      _ActionCardRule(
                        assetPath: 'lib/images/inYoFace_orange.png',
                        name: 'In Yo Face',
                        description: 'Der nächste Spieler muss 5 Karten ziehen.',
                      ),
                      _ActionCardRule(
                        assetPath: 'lib/images/deuces_green.png',
                        name: 'Deuces',
                        description: 'Der nächste Spieler muss 2 Karten ziehen.',
                      ),
                      _ActionCardRule(
                        assetPath: 'lib/images/snitch_yellow.png',
                        name: 'Snitch',
                        description: 'Tausche deine Handkarten mit einem Mitspieler deiner Wahl.',
                      ),
                      _ActionCardRule(
                        assetPath: 'lib/images/deal_purple.png',
                        name: 'Deal',
                        description: 'Tausche ALLE Handkarten mit einem Mitspieler deiner Wahl.',
                      ),
                      _ActionCardRule(
                        assetPath: 'lib/images/busted_orange.png',
                        name: 'Busted',
                        description: 'Der nächste Spieler setzt eine Runde aus.',
                      ),
                      _ActionCardRule(
                        assetPath: 'lib/images/payback_green.png',
                        name: 'Payback',
                        description: 'Dreht die Zugrichtung um und kann Strafen zurückgeben.',
                      ),
                      _ActionCardRule(
                        assetPath: 'lib/images/pimpSlap_yellow.png',
                        name: 'Pimp Slap',
                        description: 'Alle anderen Spieler müssen Karten ziehen.',
                      ),
                    ],
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

class _Section extends StatelessWidget {
  final String title;
  final Color accent;
  final Widget child;

  const _Section({required this.title, required this.accent, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ActionCardRule extends StatelessWidget {
  final String assetPath;
  final String name;
  final String description;

  const _ActionCardRule({
    required this.assetPath,
    required this.name,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(assetPath, width: 44),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white70, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
