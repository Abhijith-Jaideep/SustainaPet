// lib/screens/intro_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

/// One-time intro for SustainaPet.
/// Shown by RootPage on first launch (when 'seen_intro' is false).
class IntroScreen extends StatelessWidget {
  final Future<void> Function()? onFinished; // RootPage passes this
  const IntroScreen({super.key, this.onFinished});

  @override
  Widget build(BuildContext context) {
    const cream = Color(0xFFFFF7DA);
    const yellow = Color(0xFFFFC107);

    return Scaffold(
      backgroundColor: cream,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // ===== Top: scrollable content (includes the video under badges) =====
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            color: Colors.white,
                            child: Center(
                              child: Image.asset(
                                'assets/splash/splash-600x600.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Welcome to SustainaPet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Welcome to SustainaPet, Your Eco Buddy!'
                          ' Scan receipts, complete eco quests'
                          ' and watch your pet grow happier as your footprint goes down.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _FeatureChips(),
                    const SizedBox(height: 12),

                    // ===== Intro video placed directly below the badges, responsive size =====
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: const _IntroVideo(
                          assetPath: 'assets/intro_video/introductory.mov',
                          fallbackImage: 'assets/splash/splash-600x600.png',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ===== Get Started button anchored at the bottom =====
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.pets_rounded),
                  label: const Text(
                    'Get Started',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: yellow,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('seen_intro', true);

                    if (onFinished != null) {
                      await onFinished!();
                    } else {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight video player area with overlay controls.
/// Autoplays, loops, and falls back to an image if the video fails.
/// Responsive sizing: keeps aspect ratio, caps width, avoids oversizing.
class _IntroVideo extends StatefulWidget {
  final String assetPath;
  final String fallbackImage;
  const _IntroVideo({
    required this.assetPath,
    required this.fallbackImage,
  });

  @override
  State<_IntroVideo> createState() => _IntroVideoState();
}

class _IntroVideoState extends State<_IntroVideo> {
  VideoPlayerController? _controller;
  bool _failed = false; // if asset missing or init fails
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final c = VideoPlayerController.asset(widget.assetPath);
      _controller = c;
      await c.initialize();
      c.setLooping(true);
      await c.setVolume(_muted ? 0.0 : 1.0);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    final newMuted = !_muted;
    setState(() => _muted = newMuted);
    await c.setVolume(newMuted ? 0.0 : 1.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Image.asset(
            widget.fallbackImage,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // Responsive, capped size: keeps aspect ratio and avoids being too wide
    return Stack(
      alignment: Alignment.center,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = math.min(constraints.maxWidth, 560.0); // tweak cap if you like
            final aspect = c.value.aspectRatio > 0 ? c.value.aspectRatio : (16 / 9);

            return Center(
              child: SizedBox(
                width: maxWidth,
                child: AspectRatio(
                  aspectRatio: aspect,
                  child: VideoPlayer(c),
                ),
              ),
            );
          },
        ),

        // Tap to play/pause
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _togglePlay,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
          ),
        ),

        // Big play overlay when paused
        if (!c.value.isPlaying)
          Container(
            color: Colors.black26,
            child: const Icon(Icons.play_circle_fill, size: 72, color: Colors.white),
          ),

        // Bottom-right controls (mute & play/pause)
        Positioned(
          right: 8,
          bottom: 8,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: c.value.isPlaying ? 'Pause' : 'Play',
                  onPressed: _togglePlay,
                  icon: Icon(
                    c.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: _muted ? 'Unmute' : 'Mute',
                  onPressed: _toggleMute,
                  icon: Icon(
                    _muted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureChips extends StatelessWidget {
  const _FeatureChips();

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE6E8EC)),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        _chip(Icons.eco_rounded, 'Track CO₂'),
        _chip(Icons.flag_circle_rounded, 'Eco Quests'),
        _chip(Icons.receipt_long_rounded, 'Scan Receipts'),
        _chip(Icons.favorite_rounded, 'Happy Eco-Pet'),
      ],
    );
  }
}
