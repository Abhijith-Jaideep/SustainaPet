// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/ecopet.dart';
import '../api/base_url.dart';
import '../api/pawprint_api.dart';
import 'package:flutter/services.dart';
import '../widgets/helper_icon.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _MoodBand { sad, neutral, happy }

class _HomeScreenState extends State<HomeScreen> {
  late final PawprintApi api;
  int? _userId;
  String? _userName;
  Future<PetMood>? _futureMood = Future.value(PetMood.neutral);
  int _moodScore = 0;

  // Bubble visibility + message cycling
  bool _bubbleVisible = false;
  String? _lastBubbleText;
  _MoodBand _activeBand = _MoodBand.neutral;
  final Map<_MoodBand, int> _msgIndexByBand = {
    _MoodBand.sad: 0,
    _MoodBand.neutral: 0,
    _MoodBand.happy: 0,
  };

  // 👈 “Tap me” hint lives inside the bubble & hides after first tap
  bool _showTapHint = true;

  // Message banks
  static const List<String> _neutralMsgs = [
    "Hey there! I’m your Eco-Pet. Let’s start making some small changes together!",
    "All good here… but we can do even better, right?",
    "Yaaawn… it’s been quiet here. Let’s try a quest and wake things up!",
  ];
  static const List<String> _sadMsgs = [
    "I’m feeling a bit down… maybe a little eco-action would cheer me up.",
    "It’s been quiet lately… the planet (and I) could use your help.",
    "Every small step helps. I believe in you.",
  ];
  static const List<String> _happyMsgs = [
    "I’m so proud of you! Together we’re creating positive change.",
    "You’re unstoppable!",
    "Woohoo! Let’s keep this green streak going strong.",
  ];

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
    String base =
    (h < 12) ? 'Good Morning' : (h < 17) ? 'Good Afternoon' : 'Good Evening';
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

  void _scheduleBubbleShow({int delayMs = 220}) {
    if (mounted) {
      setState(() => _bubbleVisible = false);
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) setState(() => _bubbleVisible = true);
      });
    }
  }

  _MoodBand _bandFromScore(int score) {
    if (score < 31) return _MoodBand.sad;
    if (score <= 60) return _MoodBand.neutral;
    return _MoodBand.happy;
  }

  String _currentMessageForBand(_MoodBand band) {
    final i = _msgIndexByBand[band] ?? 0;
    switch (band) {
      case _MoodBand.sad:
        return _sadMsgs[i % _sadMsgs.length];
      case _MoodBand.neutral:
        return _neutralMsgs[i % _neutralMsgs.length];
      case _MoodBand.happy:
        return _happyMsgs[i % _happyMsgs.length];
    }
  }

  void _cycleMessage(_MoodBand band) {
    setState(() {
      _msgIndexByBand[band] = ((_msgIndexByBand[band] ?? 0) + 1);
      _showTapHint = false; // hide the hint after first tap
    });
    _scheduleBubbleShow(delayMs: 120);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          HelpIcon(assetPath: 'assets/images/tutorial/home.jpg'),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'reset_user') {
                await _resetUser(context);
                await Future.delayed(const Duration(milliseconds: 150));
                SystemNavigator.pop(); // Android exit; no-op on iOS
              } else if (v == 'reset_mood') {
                await _devResetMoodToZero();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: 'reset_mood',
                  child: Text('Dev: Reset EcoPet Mood to 0')),
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

            final clamped = _moodScore.clamp(0, 100);
            final band = _bandFromScore(clamped);

            if (band != _activeBand) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _activeBand = band;
                });
                _scheduleBubbleShow(delayMs: 250);
              });
            }

            final feelingText = _currentMessageForBand(band);

            if (_lastBubbleText != feelingText) {
              _lastBubbleText = feelingText;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scheduleBubbleShow(delayMs: 200);
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
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Greeting
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _greeting(withName: _userName),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),

                      // Pet
                      SizedBox(
                        height: petHeight,
                        child: EcoPet(
                          mood: snap.data ?? PetMood.neutral,
                          size: petHeight * 0.9,
                        ),
                      ),

                      // Speech bubble (tap to cycle) — hint is inside
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _bubbleVisible
                            ? Transform.translate(
                          key: ValueKey('bubble-visible-$feelingText'),
                          offset: const Offset(0, -12),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _cycleMessage(band),
                            child: SpeechCloudPop(
                              key: ValueKey(feelingText),
                              text: feelingText,
                              width: bubbleWidth,
                              height: bubbleHeight,
                              showTapHint: _showTapHint,
                            ),
                          ),
                        )
                            : SizedBox(
                          key: const ValueKey('bubble-placeholder'),
                          height: bubbleHeight - 12,
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
    final barColor =
    clamped < 31 ? Colors.red : clamped < 61 ? Colors.amber : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Happiness Level',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
/// Now supports an inline “Tap me” hint inside the bubble.
class SpeechCloudPop extends StatefulWidget {
  final String text;
  final double width;
  final double height;
  final Duration duration;
  final Color color;
  final Color borderColor;
  final bool showTapHint;

  const SpeechCloudPop({
    super.key,
    required this.text,
    required this.width,
    required this.height,
    this.duration = const Duration(milliseconds: 420),
    this.color = Colors.white,
    this.borderColor = const Color(0xFFE3E3E3),
    this.showTapHint = false,
  });

  @override
  State<SpeechCloudPop> createState() => _SpeechCloudPopState();
}

class _SpeechCloudPopState extends State<SpeechCloudPop>
    with TickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  // pulse for the inline hint
  late final AnimationController _hintC;
  late final Animation<double> _hintOpacity;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    _scale = CurvedAnimation(parent: _c, curve: Curves.easeOutBack);
    _fade  = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.forward(from: 0);
    });

    _hintC = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _hintOpacity = Tween<double>(begin: 0.35, end: 1.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_hintC);

    if (widget.showTapHint && !_hintC.isAnimating) {
      _hintC.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant SpeechCloudPop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _c.forward(from: 0);

    if (oldWidget.showTapHint != widget.showTapHint) {
      if (widget.showTapHint) {
        if (!_hintC.isAnimating) _hintC.repeat(reverse: true);
      } else {
        _hintC.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _hintC.dispose();
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            widget.text,
                            textAlign: TextAlign.center,
                            style: textStyle,
                          ),
                        ),
                      ),
                      // Inline “Tap me” hint (inside bubble bottom)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: widget.showTapHint ? 1.0 : 0.0,
                        child: FadeTransition(
                          opacity: _hintOpacity,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.touch_app_outlined,
                                  size: 16, color: Colors.black54),
                              SizedBox(width: 6),
                              Text(
                                'Tap me',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Top-centered tail (points toward the pet)
              Positioned(
                top: -12,
                left: 0,
                right: 0,
                child: Center(
                  child: CustomPaint(
                    size: const Size(26, 14),
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

    final p = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h)
      ..lineTo(0, h)
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
