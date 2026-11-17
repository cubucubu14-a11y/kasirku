import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/setup_screen.dart';
import 'screens/main_navigation.dart';
import 'services/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
  // Inisialisasi SyncService setelah app ter-mount agar observer lifecycle aman.
  unawaited(SyncService.instance.initialize());
}

// Helper kecil agar tidak perlu import 'dart:async' hanya untuk unawaited.
void unawaited(Future<void> future) {}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Kasirku',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD32F2F)),
          useMaterial3: true,
          fontFamily: 'Roboto',
        ),
        home: const SplashScreen(),
      );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final kasir = prefs.getString('nama_kasir') ?? '';
    final cabang = prefs.getString('nama_cabang') ?? '';
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => kasir.isNotEmpty && cabang.isNotEmpty
            ? const MainNavigation()
            : const SetupScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
}
