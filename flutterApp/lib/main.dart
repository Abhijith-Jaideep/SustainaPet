import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';

import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/quest_screen.dart';
import 'screens/login_screen.dart'; // <-- add the login page

void main() {
  runApp(const CarbonPawprintApp());
}

class CarbonPawprintApp extends StatefulWidget {
  const CarbonPawprintApp({super.key});

  @override
  State<CarbonPawprintApp> createState() => _CarbonPawprintAppState();
}

class _CarbonPawprintAppState extends State<CarbonPawprintApp> {
  Widget? _startPage;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("userId");

    setState(() {
      _startPage = (userId == null)
          ? LoginScreen(
        onLoginSuccess: () {
          setState(() => _startPage = const HomeScreen());
        },
      )
          : const HomeScreen();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carbon Pawprint',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      routes: {
        '/dashboard': (_) => const DashboardScreen(),
        '/quests': (_) => const QuestScreen(),
      },
      // Show loading spinner until _checkLoginStatus finishes
      home: _startPage ?? const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
