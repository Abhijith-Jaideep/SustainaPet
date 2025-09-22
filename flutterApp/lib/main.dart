// // lib/main.dart
// import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// import 'theme/app_theme.dart';
//
// import 'screens/home_screen.dart';
// import 'screens/dashboard_screen.dart';
// import 'screens/quest_screen.dart';
// import 'screens/login_screen.dart';
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   runApp(const CarbonPawprintApp());
// }
//
// class CarbonPawprintApp extends StatefulWidget {
//   const CarbonPawprintApp({super.key});
//
//   @override
//   State<CarbonPawprintApp> createState() => _CarbonPawprintAppState();
// }
//
// class _CarbonPawprintAppState extends State<CarbonPawprintApp> {
//   Widget? _startPage;
//
//   @override
//   void initState() {
//     super.initState();
//     _checkLoginStatus();
//   }
//
//   Future<void> _checkLoginStatus() async {
//     final prefs = await SharedPreferences.getInstance();
//
//     // Support both legacy string and current int storage.
//     final raw = prefs.get('userId'); // int | String | null
//     int? uid;
//     if (raw is int) {
//       uid = raw;
//     } else if (raw is String) {
//       final parsed = int.tryParse(raw);
//       if (parsed != null) {
//         uid = parsed;
//         await prefs.setInt('userId', parsed); // migrate to int
//       } else {
//         await prefs.remove('userId'); // corrupt -> clear
//       }
//     }
//
//     if (!mounted) return;
//     setState(() {
//       _startPage = (uid == null)
//           ? LoginScreen(
//         onLoginSuccess: () {
//           // We *flip to Home* once login writes a valid int userId.
//           setState(() => _startPage = const HomeScreen());
//         },
//       )
//           : const HomeScreen();
//     });
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Carbon Pawprint',
//       theme: AppTheme.light,
//       debugShowCheckedModeBanner: false,
//       routes: {
//         '/dashboard': (_) => const DashboardScreen(),
//         '/quests': (_) => const QuestScreen(),
//         // If you ever navigate to login manually:
//         '/login': (context) => LoginScreen(
//           onLoginSuccess: () {
//             // ✅ Option 1: use the route builder's context here
//             Navigator.of(context).pushReplacement(
//               MaterialPageRoute(builder: (_) => const HomeScreen()),
//             );
//           },
//         ),
//       },
//       // home: _startPage ??
//       //     const Scaffold(
//       //       body: Center(child: CircularProgressIndicator()),
//       //     ),
//       home: const DashboardScreen(),
//     );
//   }
// }

// lib/main.dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart'; // 确保 dashboard_screen.dart 在 lib/screens/

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dashboard Test',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: const DashboardScreen(), // 只显示 DashboardScreen
    );
  }
}



// class CarbonPawprintApp extends StatelessWidget {
//   const CarbonPawprintApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Carbon Pawprint',
//       theme: AppTheme.light,
//       debugShowCheckedModeBanner: false,
//       routes: {
//         '/dashboard': (_) => const DashboardScreen(),
//         '/quests': (_) => const QuestScreen(),
//         '/login': (_) => LoginScreen(
//           onLoginSuccess: () {
//             Navigator.of(context).pushReplacement(
//               MaterialPageRoute(builder: (_) => const HomeScreen()),
//             );
//           },
//         ),
//       },
//       home: const DashboardScreen(),
//     );
//   }
// }
