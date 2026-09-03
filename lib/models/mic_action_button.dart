import 'package:flutter/material.dart';

class MicActionButton extends StatefulWidget {
  /// true = Mic Check, false = Mic Drop
  final bool isCheck;
  final VoidCallback onPressed;

  const MicActionButton({
    super.key,
    required this.isCheck,
    required this.onPressed,
  });

  @override
  State<MicActionButton> createState() => _MicActionButtonState();
}

class _MicActionButtonState extends State<MicActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    // Farbe und Icon je nach Mode
    final color = widget.isCheck ? Colors.cyanAccent : Colors.pinkAccent;
    final icon = widget.isCheck ? Icons.mic : Icons.mic_off;
    final label = widget.isCheck ? 'Mic Check' : 'Mic Drop';

    return AnimatedBuilder(
      animation: _glowCtrl,
      builder: (ctx, child) {
        final glow = 8 + 4 * _glowCtrl.value; // pulsierender Schatten
        return ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            foregroundColor: color, backgroundColor: Colors.black,
            shadowColor: color,
            elevation: glow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(icon, size: 24),
          label: Text(label, style: const TextStyle(fontSize: 16)),
          onPressed: widget.onPressed,
        );
      },
    );
  }
}
