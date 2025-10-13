// lib/screens/intro_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
            // scrollable content
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
                      'Scan receipts, complete eco quests'
                      'and watch your pet grow happier as your footprint goes down.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const _FeatureChips(),
                    const SizedBox(height: 20), // 👈 extra gap above button
                  ],
                ),
              ),
            ),

            // Button is lifted up (less bottom padding)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), // was 24
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
                      Navigator.of(context).maybePop();
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
