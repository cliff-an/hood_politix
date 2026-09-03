import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
class StartVideoOverlay extends StatefulWidget {
  const StartVideoOverlay({super.key});

  @override
  State<StartVideoOverlay> createState() => _StartVideoOverlayState();
}

class _StartVideoOverlayState extends State<StartVideoOverlay> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('lib/vids/HP_video.mp4')
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_controller.value.isInitialized)
          SizedBox.expand(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller)))),
        
      ],
    );
  }
}
