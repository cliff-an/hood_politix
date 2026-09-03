import 'package:flutter/material.dart';

void showPimpSlapOverlay(BuildContext context) {
  // Initialisiere den OverlayEntry als null
  OverlayEntry? overlayEntry;

  // Overlay-Eintrag erzeugen
  overlayEntry = OverlayEntry(
    builder: (context) {
      // Animationscontroller für die Größenänderung
      AnimationController controller = AnimationController(
        duration: const Duration(seconds: 3),
        vsync: Navigator.of(context), // Benötigt einen TickerProvider
      );
      // Größenänderungsanimation
      Animation<double> sizeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(controller);

      controller.forward(); // Animation starten

      // Nach 3 Sekunden Overlay entfernen und Controller disposen
      controller.addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          overlayEntry?.remove();
          controller.dispose();
        }
      });

      return AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return Positioned(
            top: MediaQuery.of(context).size.height / 2 - (100 * sizeAnimation.value),
            left: MediaQuery.of(context).size.width / 2 - (100 * sizeAnimation.value),
            child: Opacity(
              opacity: sizeAnimation.value,
              child: Transform.scale(
                scale: sizeAnimation.value,
                child: Image.asset('assets/images/pimpslap.png'), // Pfad zu deinem Bild
              ),
            ),
          );
        },
      );
    },
  );

  // Overlay-Eintrag zum Overlay hinzufügen
  Overlay.of(context).insert(overlayEntry);
}
