// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/ecopet.dart';
import '../api/base_url.dart';
import '../api/pawprint_api.dart'; // PetMood + PawprintApi + petMoodFromScore

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PawprintApi api;

  int? _userId;
  String? _userName;

  Future<PetMood>? _futureMood;
  int _moodScore = 0; // 0..100 for the bar

  static const String onboardingRoute = '/onboarding';

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
        await prefs.setInt('userId', parsed); // migrate
      } else {
        await prefs.remove('userId'); // corrupt -> clear
      }
    }

    if (!mounted) return;

    if (uid == null) {
      setState(() {
        _userId = null;
        _futureMood = null;
      });
      return;
    }

    setState(() {
      _userId = uid!;
      _futureMood = _fetchMood(uid!);
    });
  }

  Future<PetMood> _fetchMood(int userid) async {
    final dash = await api.getDashboard(userid);
    if (mounted) {
      _userName = dash.user.name;
      _moodScore = dash.user.ecopetmood.clamp(0, 100);
      setState(() {}); // update username + mood bar
    }
    return petMoodFromScore(dash.user.ecopetmood);
  }

  String _greeting({String? withName}) {
    final h = DateTime.now().hour;
    String base = (h < 12)
        ? 'Good Morning'
        : (h < 17)
        ? 'Good Afternoon'
        : 'Good Evening';
    if (withName != null && withName.isNotEmpty) base = '$base, $withName';
    return '$base!';
  }

  Future<void> _resetUser(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('userName');

    // Exit the app completely
    SystemNavigator.pop();
  }

  Future<void> _devResetMoodToZero() async {
    if (_userId == null) return;
    try {
      await api.resetUserMood(_userId!, 0); // ✅ use resetUserMood here
      if (!mounted) return;
      setState(() {
        _moodScore = 0;
        _futureMood = Future.value(PetMood.sad); // reset EcoPet display
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
    if (_userId == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text(
                    'No user found on this device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context)
                          .pushReplacementNamed(onboardingRoute);
                    },
                    child: const Text('Go to Onboarding'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_futureMood == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'reset') {
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
                value: 'reset',
                child: Text('Reset User (Dev)'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final maxWidth = c.maxWidth;

            // Unified size so EcoPet and the bar are EXACTLY the same height
            final double petSize = maxWidth < 400 ? maxWidth * 0.9 : 360.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header text block, centered and tidy
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Text(
                          _greeting(withName: _userName),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Here's how your EcoPet is feeling today",
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Main content: EcoPet + vertical bar, same height, nicely aligned
                  FutureBuilder<PetMood>(
                    future: _futureMood,
                    builder: (context, snap) {
                      if (snap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Column(
                          children: [
                            const Icon(Icons.error_outline,
                                size: 40, color: Colors.red),
                            const SizedBox(height: 8),
                            Text(
                              "Failed to load EcoPet:\n${snap.error}",
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () {
                                final id = _userId;
                                if (id != null) {
                                  setState(() =>
                                  _futureMood = _fetchMood(id));
                                }
                              },
                              child: const Text("Retry"),
                            ),
                          ],
                        );
                      }

                      final mood = snap.data ?? PetMood.neutral;
                      final clamped = _moodScore.clamp(0, 100);

                      // Lock the row to a fixed height so both children match
                      return SizedBox(
                        height: petSize,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // EcoPet: fills available width, constrained to petSize height
                            Expanded(
                              child: Center(
                                child: SizedBox(
                                  height: petSize,
                                  child: EcoPet(mood: mood),
                                ),
                              ),
                            ),
                            const SizedBox(width: 18),

                            // Vertical mood bar: same height as the pet
                            _VerticalMoodBar(
                              score: clamped,
                              height: petSize,
                              width: 22,
                            ),
                          ],
                        ),
                      );
                    },
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

class _VerticalMoodBar extends StatelessWidget {
  final int score; // 0..100
  final double height;
  final double width;
  const _VerticalMoodBar({
    required this.score,
    required this.height,
    this.width = 18,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0, 100);
    final pct = clamped / 100.0;

    Color barColor;
    if (clamped < 31) {
      barColor = Colors.red;
    } else if (clamped < 61) {
      barColor = Colors.amber;
    } else {
      barColor = Colors.green;
    }

    return SizedBox(
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('100',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.grey)),
          // Bar
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              width: width,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(width),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: pct, // fill from bottom up
                  widthFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(width),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text('0',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            '$clamped / 100',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
