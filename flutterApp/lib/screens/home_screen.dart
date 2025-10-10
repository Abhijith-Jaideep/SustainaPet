// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/ecopet.dart';
import '../api/base_url.dart';
import '../api/pawprint_api.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PawprintApi api;
  int? _userId;
  String? _userName;

  // Initialize with a safe default so the UI renders immediately.
  Future<PetMood>? _futureMood = Future.value(PetMood.neutral);
  int _moodScore = 0; // 0..100

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
        // Keep the neutral placeholder mood so the screen still renders.
        _futureMood = Future.value(PetMood.neutral);
      });
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
      setState(() {}); // updates header + bar immediately
    }
    return petMoodFromScore(dash.user.ecopetmood);
  }

  String _greeting({String? withName}) {
    final h = DateTime.now().hour;
    String base =
    (h < 12) ? 'Good Morning' : (h < 17) ? 'Good Afternoon' : 'Good Evening';
    if (withName != null && withName.isNotEmpty) base = '$base, $withName';
    return '$base!';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: SafeArea(
        child: FutureBuilder<PetMood>(
          future: _futureMood,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && _userId == null) {
              // Only show spinner if we truly have no user and are still figuring it out
              return const Center(child: CircularProgressIndicator());
            }

            // Use neutral until we get a real mood.
            final mood = snap.data ?? PetMood.neutral;
            final clamped = _moodScore.clamp(0, 100);
            final feelingText = clamped < 31
                ? "I'm feeling sad..."
                : clamped < 61
                ? "I'm doing okay!"
                : clamped < 81
                ? "I'm feeling good!"
                : "I'm feeling great!";

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Greeting header (kept)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          _greeting(withName: _userName),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ====== EcoPet Frame (fills width) ======
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      image: const DecorationImage(
                        // Make sure this exists in assets and is in pubspec.yaml
                        image: AssetImage('assets/ecopet_bg.png'),
                        fit: BoxFit.cover,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(18),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final isNarrow = c.maxWidth < 520;
                          final double petHeight = isNarrow ? 300 : 340;

                          final pet = SizedBox(
                            height: petHeight,
                            // Give EcoPet clear constraints and center it.
                            child: Center(child: EcoPet(mood: mood)),
                          );

                          final bubble = _SpeechBubble(
                            text: feelingText,
                            tailOnLeft: !isNarrow, // left tail in wide layout
                          );

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (isNarrow) ...[
                                pet,
                                const SizedBox(height: 12),
                                bubble,
                              ] else ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Pet
                                    Expanded(flex: 3, child: pet),
                                    const SizedBox(width: 20),
                                    // Speech bubble
                                    Expanded(flex: 4, child: bubble),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 20),
                              _HorizontalMoodBar(score: clamped),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Horizontal mood (happiness) bar with white border
class _HorizontalMoodBar extends StatelessWidget {
  final int score;
  const _HorizontalMoodBar({required this.score});

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100);
    final pct = clamped / 100.0;
    final barColor =
    clamped < 31 ? Colors.red : clamped < 61 ? Colors.amber : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Happiness Level',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),

        // Outer white bordered capsule
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white, width: 2), // white border
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Track
                Container(height: 22, color: Colors.grey.shade300),
                // Fill
                FractionallySizedBox(
                  widthFactor: pct,
                  child: Container(height: 22, color: barColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Speech bubble for EcoPet's mood message
class _SpeechBubble extends StatelessWidget {
  final String text;
  final bool tailOnLeft;
  const _SpeechBubble({required this.text, this.tailOnLeft = true});

  @override
  Widget build(BuildContext context) {
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );

    final tail = CustomPaint(
      size: const Size(16, 12),
      painter: _TrianglePainter(
        color: Colors.white,
        strokeColor: Colors.grey.shade300,
        pointLeft: tailOnLeft,
      ),
    );

    return Row(
      children: tailOnLeft
          ? [tail, const SizedBox(width: 6), Expanded(child: bubble)]
          : [Expanded(child: bubble), const SizedBox(width: 6), tail],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  final Color strokeColor;
  final bool pointLeft;
  _TrianglePainter({
    required this.color,
    required this.strokeColor,
    this.pointLeft = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke;
    final path = Path();
    if (pointLeft) {
      path.moveTo(0, size.height / 2);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, size.height / 2);
      path.lineTo(0, 0);
      path.lineTo(0, size.height);
    }
    path.close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) => false;
}
