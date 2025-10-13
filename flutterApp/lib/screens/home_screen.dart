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
              } else if (v == 'reset_mood') {
                await _devResetMoodToZero();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'reset_mood',
                child: Text('Dev: Reset EcoPet Mood to 0'),
              ),
              PopupMenuItem(
                value: 'reset_user',
                child: Text('Dev: Reset User'),
              ),
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

            return Column(
              children: [
                // Greeting
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _greeting(withName: _userName),
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),

                // Main section
                Expanded(
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/eco_pet/ecopet_bg.png'),
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Even bigger pet
                        final petHeight =
                        (constraints.maxHeight * 0.75).clamp(300.0, 600.0);

                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Large EcoPet
                            SizedBox(
                              height: petHeight,
                              child: Center(child: EcoPet(mood: mood)),
                            ),

                            const SizedBox(height: 8),

                            // White bubble for message only
                            Container(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              margin: const EdgeInsets.symmetric(horizontal: 32),
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
                                feelingText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Happiness bar directly on background
                            Padding(
                              padding:
                              const EdgeInsets.symmetric(horizontal: 32.0),
                              child: _HorizontalMoodBar(score: clamped),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
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

    final barColor = clamped < 31
        ? Colors.red
        : clamped < 61
        ? Colors.amber
        : Colors.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Happiness Level',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),

        // Track + animated fill
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Container(height: 22, color: Colors.grey.shade300),
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeOutCubic,
                tween: Tween<double>(begin: 0.0, end: target),
                builder: (context, value, _) {
                  return FractionallySizedBox(
                    widthFactor: value,
                    child: Container(height: 22, color: barColor),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
