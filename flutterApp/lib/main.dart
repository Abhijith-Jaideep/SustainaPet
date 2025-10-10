// lib/main.dart
import 'package:carbon_pawprint/screens/socials_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/quest_screen.dart';
import 'screens/login_screen.dart';
import 'screens/grocery_scanner.dart';
import 'screens/intro_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SustainaPetApp());
}

class SustainaPetApp extends StatelessWidget {
  const SustainaPetApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Yellow & cream palette
    const cream = Color(0xFFFFF7DA);
    const yellow = Color(0xFFFFC107);
    const yellowTint = Color(0xFFFFE082);

    return MaterialApp(
      title: 'SustainaPet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Poppins',
        colorScheme: ColorScheme.fromSeed(
          seedColor: yellow,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: cream,
        appBarTheme: const AppBarTheme(
          backgroundColor: yellow,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: yellow,
          selectedItemColor: Colors.black87,
          unselectedItemColor: Colors.black54,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.black54,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: Colors.black87, width: 2),
          ),
        ),
        cardColor: Colors.white,
        dividerColor: yellowTint,
        useMaterial3: true,
      ),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  Widget? _startPage;

  @override
  void initState() {
    super.initState();
    _decideStart();
  }

  Future<void> _decideStart() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (!mounted) return;

    if (userId == null) {
      // Show Intro first; when finished, show Login in-place; then MainNavigation.
      setState(() {
        _startPage = IntroScreen(
          onFinished: () async {
            if (!mounted) return;
            setState(() {
              _startPage = LoginScreen(
                onLoginSuccess: () {
                  if (!mounted) return;
                  setState(() => _startPage = const MainNavigation());
                },
              );
            });
          },
        );
      });
    } else {
      setState(() => _startPage = const MainNavigation());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _startPage ?? const EcoLoader();
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    DashboardScreen(),
    QuestScreen(),
    GroceryScannerScreen(),
    SocialsScreen()
  ];

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Dashboard"),
          BottomNavigationBarItem(icon: Icon(Icons.task), label: "Quests"),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: "Grocery Scanner"),
          BottomNavigationBarItem(icon: Icon(Icons.groups_2), label: "Socials")
        ],
      ),
    );
  }
}

/* ---------- Cute eco-pet loader shown while we init ---------- */
class EcoLoader extends StatelessWidget {
  const EcoLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFF7DA),
      body: SafeArea(
        child: Center(child: _LoaderArt()),
      ),
    );
  }
}

class _LoaderArt extends StatefulWidget {
  const _LoaderArt();

  @override
  State<_LoaderArt> createState() => _LoaderArtState();
}

class _LoaderArtState extends State<_LoaderArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 0.95, end: 1.05).animate(
            CurvedAnimation(parent: _c, curve: Curves.easeInOut),
          ),
          child: Image.asset(
            'assets/app_icon/icon_1024.png', // your eco-pet icon
            width: 120,
            height: 120,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'warming up your eco-pet…',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
        ),
      ],
    );
  }
}
