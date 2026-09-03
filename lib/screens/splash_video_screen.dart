import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '/screens/login_screen.dart';
class SplashVideoScreen extends StatefulWidget {
  const SplashVideoScreen({super.key});

  @override
  State<SplashVideoScreen> createState() => _SplashVideoScreenState();
}

class _SplashVideoScreenState extends State<SplashVideoScreen> {
  late VideoPlayerController _controller;
  bool _skipped = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset('lib/vids/What_is_Hood_Politix.mp4')
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        Future.delayed(const Duration(seconds: 25), _navigateToNext);
      });
  }

  void _navigateToNext() {
    if (_skipped) return;
    _skipped = true;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen()));
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
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Column(
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _navigateToNext,
                child: const Text("Überspringen"),
              )
            ],
          ),
        ),
      ],
    );
  }
}
