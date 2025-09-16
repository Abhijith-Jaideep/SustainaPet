// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
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

  static const String onboardingRoute = '/onboarding'; // <-- set this to your onboarding route

  @override
  void initState() {
    super.initState();
    final base = pickBaseUrl();
    // ignore: avoid_print
    print('[Home] baseUrl: $base');
    api = PawprintApi(base);
    _loadUserIdAndMood();
  }

  Future<void> _loadUserIdAndMood() async {
    final prefs = await SharedPreferences.getInstance();

    // Read raw -> support int or string, migrate to int.
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
        // Corrupt value; clear it so onboarding can run cleanly.
        await prefs.remove('userId');
      }
    }

    if (!mounted) return;

    if (uid == null) {
      // ⚠️ DO NOT navigate to '/' if HomeScreen is on '/' — that loops forever.
      // Either render a panel or go to a DIFFERENT route:
      // WidgetsBinding.instance.addPostFrameCallback((_) {
      //   Navigator.of(context).pushReplacementNamed(onboardingRoute);
      // });
      setState(() {
        _userId = null;
        _futureMood = null;
      });
      return;
    }

    // Have a valid user id — fetch mood.
    setState(() {
      _userId = uid;
      _futureMood = _fetchMood(uid!);
    });
  }

  Future<PetMood> _fetchMood(int userid) async {
    // ignore: avoid_print
    print('[Home] fetching dashboard for userId=$userid');
    final dash = await api.getDashboard(userid);
    // ignore: avoid_print
    print('[Home] dashboard ok. ecopetmood=${dash.user.ecopetmood}');
    if (mounted) setState(() => _userName = dash.user.name);
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
    // Prefer sending to a distinct onboarding route:
    Navigator.of(context).pushReplacementNamed(onboardingRoute);
  }

  @override
  Widget build(BuildContext context) {
    // If we don't have a user yet, show a friendly panel instead of looping routes.
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
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed(onboardingRoute);
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

    // While mood is being fetched.
    if (_futureMood == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _greeting(withName: _userName), // ← use the name
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                "Let's check on your eco-journey",
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),

              // ---- EcoPet, backed by dashboard mood ----
              FutureBuilder<PetMood>(
                future: _futureMood,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Column(
                      children: [
                        const Icon(Icons.error_outline, size: 40, color: Colors.red),
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
                              setState(() => _futureMood = _fetchMood(id));
                            }
                          },
                          child: const Text("Retry"),
                        ),
                      ],
                    );
                  }
                  final mood = snap.data ?? PetMood.neutral;
                  return EcoPet(mood: mood);
                },
              ),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/dashboard'),
                icon: const Icon(Icons.bar_chart),
                label: const Text('Dashboard'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/quests'),
                icon: const Icon(Icons.emoji_events_outlined),
                label: const Text('Quest System'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                ),
              ),
              const SizedBox(height: 24),

              OutlinedButton.icon(
                onPressed: () => _resetUser(context),
                icon: const Icon(Icons.restart_alt),
                label: const Text("Reset User (Dev Only)"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
