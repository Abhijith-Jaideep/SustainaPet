// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/ecopet.dart';
import '../api/base_url.dart';
import '../api/pawprint_api.dart';
import 'package:flutter/services.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PawprintApi api;
  int? _userId;
  String? _userName;
  Future<PetMood>? _futureMood = Future.value(PetMood.neutral);
  int _moodScore = 0;

  // NEW: control when the bubble appears
  bool _bubbleVisible = false;
  String? _lastFeelingText;

  @override
  void initState() {
    super.initState();
    api = PawprintApi(pickBaseUrl());
    _loadUserIdAndMood();
  }

  Future<void> _loadUserIdAndMood() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get('userId');
    int? uid;
    if (raw is int) {
      uid = raw;
    } else if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) {
        uid = parsed;
        await prefs.setInt('userId', parsed);
      }
    }
    if (!mounted) return;
    if (uid == null) {
      setState(() {
        _userId = null;
        _futureMood = Future.value(PetMood.neutral);
      });
      // Pet first → bubble later on first real draw
      _scheduleBubbleShow(delayMs: 220);
      return;
    }
    setState(() {
      _userId = uid;
      _futureMood = _fetchMood(uid!);
    });
  }

  Future<PetMood> _fetchMood(int userid) async {
    final dash = await api.getDashboard(userid);
    if (mounted) {
      _userName = dash.user.name;
      _moodScore = dash.user.ecopetmood.clamp(0, 100);
      setState(() {});
    }
    return petMoodFromScore(dash.user.ecopetmood);
  }

  String _greeting({String? withName}) {
    final h = DateTime.now().hour;
    String base = (h < 12) ? 'Good Morning' : (h < 17) ? 'Good Afternoon' : 'Good Evening';
    if (withName != null && withName.isNotEmpty) base = '$base, $withName';
    return '$base!';
  }

  Future<void> _resetUser(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User reset — restart app to re-onboard.')),
    );
  }

  Future<void> _devResetMoodToZero() async {
    if (_userId == null) return;
    try {
      await api.resetUserMood(_userId!, 0);
      if (!mounted) return;
      setState(() {
        _moodScore = 0;
        _futureMood = Future.value(PetMood.sad);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('EcoPet mood reset to 0 (Dev).')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reset mood: $e')),
      );
    }
  }

  // === NEW: small helper that reveals the bubble with a slight delay ===
  void _scheduleBubbleShow({int delayMs = 220}) {
    // hide immediately, then show after a short delay so the pet renders first
    if (mounted) {
      setState(() => _bubbleVisible = false);
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) setState(() => _bubbleVisible = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'reset_user') {
                await _resetUser(context);
                // Give the SnackBar a moment (optional), then exit.
                await Future.delayed(const Duration(milliseconds: 150));
                SystemNavigator.pop(); // exits the app (Android). No-op on iOS.
              } else if (v == 'reset_mood') {
                await _devResetMoodToZero();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'reset_mood', child: Text('Dev: Reset EcoPet Mood to 0')),
              PopupMenuItem(value: 'reset_user', child: Text('Dev: Reset User')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<PetMood>(
          future: _futureMood,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && _userId == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final mood = snap.data ?? PetMood.neutral;
            final clamped = _moodScore.clamp(0, 100);
            final feelingText = clamped < 31
                ? "I'm feeling sad..."
                : clamped < 61
                ? "I'm doing okay!"
                : clamped < 81
                ? "I'm feeling good!"
                : "I'm feeling great!";

            // When the text changes, re-run the staged show so pet appears first
            if (_lastFeelingText != feelingText) {
              _lastFeelingText = feelingText;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scheduleBubbleShow(delayMs: 250);
              });
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final petHeight = (constraints.maxHeight * 0.50).clamp(220.0, 420.0);
                final bubbleWidth = (constraints.maxWidth - 32).clamp(220.0, 360.0);
                const bubbleHeight = 120.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    // ✅ Even vertical distribution for ALL components
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Greeting (now participates in even spacing)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _greeting(withName: _userName),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      // Pet
                      SizedBox(
                        height: petHeight,
                        child: EcoPet(mood: mood, size: petHeight * 0.9),
                      ),

                      // Speech bubble (appears after pet, closer to pet)
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _bubbleVisible
                            ? Transform.translate(
                          key: ValueKey('bubble-visible-$feelingText'),
                          offset: const Offset(0, -12), // pull closer toward pet
                          child: SpeechCloudPop(
                            key: ValueKey(feelingText),
                            text: feelingText,
                            width: bubbleWidth,
                            height: bubbleHeight,
                          ),
                        )
                            : SizedBox(
                          key: const ValueKey('bubble-placeholder'),
                          height: bubbleHeight - 12, // reserve space to avoid jump
                        ),
                      ),

                      // Mood bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
                        child: _HorizontalMoodBar(score: clamped),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _HorizontalMoodBar extends StatelessWidget {
  final int score;
  const _HorizontalMoodBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100);
    final target = clamped / 100.0;
    final barColor = clamped < 31 ? Colors.red : clamped < 61 ? Colors.amber : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Happiness Level', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Container(height: 18, color: Colors.grey.shade300),
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(begin: 0.0, end: target),
                builder: (context, value, _) => FractionallySizedBox(
                  widthFactor: value,
                  child: Container(height: 18, color: barColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Animated rounded speech “box” with a centered TOP tail.
/// Paste this at the BOTTOM of lib/screens/home_screen.dart
class SpeechCloudPop extends StatefulWidget {
  final String text;
  final double width;
  final double height;
  final Duration duration;
  final Color color;
  final Color borderColor;

  const SpeechCloudPop({
    super.key,
    required this.text,
    required this.width,
    required this.height,
    this.duration = const Duration(milliseconds: 420),
    this.color = Colors.white,
    this.borderColor = const Color(0xFFE3E3E3),
  });

  @override
  State<SpeechCloudPop> createState() => _SpeechCloudPopState();
}

class _SpeechCloudPopState extends State<SpeechCloudPop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _scale = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    _fade  = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(covariant SpeechCloudPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    );

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: FadeTransition(
        opacity: _fade,
        child: ScaleTransition(
          scale: _scale,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Main rounded box
              Positioned.fill(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: widget.borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      widget.text,
                      textAlign: TextAlign.center,
                      style: textStyle,
                    ),
                  ),
                ),
              ),
              // Top-centered tail (points upward toward the pet)
              Positioned(
                top: -12,
                left: 0,
                right: 0,
                child: Center(
                  child: CustomPaint(
                    size: const Size(26, 14), // tail width x height
                    painter: _TopTailPainter(
                      fill: widget.color,
                      stroke: widget.borderColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopTailPainter extends CustomPainter {
  final Color fill;
  final Color stroke;

  _TopTailPainter({required this.fill, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Upward-pointing triangle
    final p = Path()
      ..moveTo(w / 2, 0)   // apex
      ..lineTo(w, h)       // bottom-right
      ..lineTo(0, h)       // bottom-left
      ..close();

    final paintFill = Paint()..color = fill;
    final paintStroke = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(p, paintFill);
    canvas.drawPath(p, paintStroke);
  }

  @override
  bool shouldRepaint(covariant _TopTailPainter old) =>
      old.fill != fill || old.stroke != stroke;
}
