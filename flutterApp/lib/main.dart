// lib/main.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/quest_screen.dart';
import 'screens/login_screen.dart';
import 'screens/grocery_scanner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CarbonPawprintApp());
}

class CarbonPawprintApp extends StatelessWidget {
  const CarbonPawprintApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Yellow & cream palette
    const cream = Color(0xFFFFF7DA);    
    const yellow = Color(0xFFFFC107);    
    const yellowTint = Color(0xFFFFE082);

    return MaterialApp(
      title: 'Carbon Pawprint',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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

        // 👇 Your Flutter expects TabBarThemeData
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.black54,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: Colors.black87, width: 2),
          ),
        ),

        cardColor: Colors.white,
        dividerColor: yellowTint,
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
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    if (!mounted) return;
    setState(() {
      _startPage = (userId == null)
          ? LoginScreen(
        onLoginSuccess: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
          );
        },
      )
          : const MainNavigation();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _startPage ??
        const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
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
    GroceryScannerScreen()
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

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
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: "Grocery Receipt")
        ],
      ),
    );
  }
}
