// lib/main.dart
import 'package:flutter/material.dart';
import 'auth_store.dart';
import 'pages/home_screen.dart';
import 'pages/login_page.dart';
import 'pages/signup_page.dart';
import 'pages/profile.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthStore.init();            // ← must be awaited so we know if a user is logged in
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // Make sure these routes point to the right widgets.
      routes: {
        '/login':   (_) => const LoginPage(),   // ← LOGIN PAGE, not a “Welcome/Continue” placeholder
        '/home':    (_) => const HomePage(),
        '/profile': (_) => const ProfilePage(),
        '/signup': (_) => const SignupPage(),
      },

      // Auth gate: if no user → LoginPage, else → HomePage
      home: ValueListenableBuilder<int?>(
        valueListenable: AuthStore.currentUserId,
        builder: (_, uid, __) => uid == null ? const LoginPage() : const HomePage(),
      ),
    );
  }
}
